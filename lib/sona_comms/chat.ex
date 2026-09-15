defmodule SonaComms.Chat do
  @moduledoc """
  Conversations, participants, messages and receipts.

  Every read and write checks for an active participant row
  (`left_at IS NULL`). Non-participants and leavers get `{:error, :not_found}`.

  Chat never depends on `SonaComms.Org` (ADR 0002). Participants of derived
  conversations (`:org`, `:venue`, `:team`) are written only by
  `sync_participants/2`, which only Org calls. Chat treats the active
  participants of the org conversation as the organisation's members.

  PubSub topics (ADR 0006):

    * `"conversation:<id>"` - `{:message_created, conversation_id, message_id}`,
      `{:ack_updated, message_id, %{acknowledged: n, total: n}}`
    * `"user:<id>"` - `{:conversation_joined, id}`, `{:conversation_left, id}`,
      `{:conversation_read, id}`
  """

  import Ecto.Query, warn: false

  alias SonaComms.Accounts
  alias SonaComms.Accounts.{Scope, User}
  alias SonaComms.Chat.{Conversation, Message, Participant, Receipt}
  alias SonaComms.Repo

  @pubsub SonaComms.PubSub
  @derived_kinds [:org, :venue, :team]

  ## Conversations

  @doc """
  Lists the conversations the user actively participates in, with
  `unread_count`, `display_title` and `can_announce` set.

  Ordered by kind (org, venue, team, group, dm), then most recent message.
  """
  def list_conversations(%Scope{user: %User{id: user_id}}) do
    user_id
    |> conversations_query()
    |> Repo.all()
    |> put_display_titles(user_id)
    |> put_pending_ack_counts(user_id)
  end

  @doc """
  Gets a conversation the user actively participates in.

  Returns `{:error, :not_found}` when it doesn't exist, or the user never
  participated or has left.
  """
  def get_conversation(%Scope{user: %User{id: user_id}}, id) do
    with {:ok, id} <- cast_id(id),
         %Conversation{} = conversation <-
           user_id |> conversations_query() |> where([c], c.id == ^id) |> Repo.one() do
      [conversation] =
        [conversation]
        |> put_display_titles(user_id)
        |> put_pending_ack_counts(user_id)

      {:ok, conversation}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_conversation(_scope, _id), do: {:error, :not_found}

  defp conversations_query(user_id) do
    from c in Conversation,
      join: p in Participant,
      on: p.conversation_id == c.id and p.user_id == ^user_id and is_nil(p.left_at),
      left_join: m in Message,
      on:
        m.conversation_id == c.id and m.inserted_at > p.last_read_at and
          m.sender_id != ^user_id,
      group_by: [c.id, p.id],
      order_by: [
        asc:
          fragment(
            "array_position(ARRAY['org','venue','team','group','dm']::varchar[], ?::varchar)",
            c.kind
          ),
        desc_nulls_last: c.last_message_at,
        asc: c.title,
        asc: c.id
      ],
      select: %{c | unread_count: count(m.id), can_announce: p.can_announce}
  end

  defp put_display_titles(conversations, user_id) do
    dm_ids = for %Conversation{kind: :dm, id: id} <- conversations, do: id
    others = dm_partners(dm_ids, user_id)

    Enum.map(conversations, fn
      %Conversation{kind: :dm} = conversation ->
        %{conversation | display_title: dm_title(others[conversation.id])}

      conversation ->
        %{conversation | display_title: conversation.title}
    end)
  end

  defp dm_partners([], _user_id), do: %{}

  defp dm_partners(dm_ids, user_id) do
    from(p in Participant,
      join: u in assoc(p, :user),
      where: p.conversation_id in ^dm_ids and p.user_id != ^user_id,
      select: {p.conversation_id, u}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp dm_title(nil), do: "Direct message"
  defp dm_title(%User{} = user), do: Accounts.display_name(user)

  @doc """
  Lists the active participants of a conversation, ordered by name.
  """
  def list_participants(%Scope{} = scope, conversation_id) do
    with {:ok, participant} <- fetch_participation(scope, conversation_id) do
      users =
        Repo.all(
          from u in User,
            join: p in Participant,
            on: p.user_id == u.id,
            where: p.conversation_id == ^participant.conversation_id and is_nil(p.left_at),
            order_by: [asc_nulls_last: u.name, asc: u.email]
        )

      {:ok, users}
    end
  end

  ## Messages

  @doc """
  Lists messages of a conversation, oldest to newest, with the sender preloaded.

  ## Options

    * `:limit` - the maximum number of messages, defaults to 50
    * `:before` - only messages inserted before this `DateTime`
  """
  def list_messages(%Scope{} = scope, conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    with {:ok, participant} <- fetch_participation(scope, conversation_id) do
      messages =
        from(m in Message,
          where: m.conversation_id == ^participant.conversation_id,
          order_by: [desc: m.inserted_at, desc: m.id],
          limit: ^limit,
          preload: :sender
        )
        |> messages_before(Keyword.get(opts, :before))
        |> Repo.all()
        |> Enum.reverse()
        |> put_announcement_fields(participant.user_id)

      {:ok, messages}
    end
  end

  defp messages_before(query, nil), do: query

  defp messages_before(query, %DateTime{} = before),
    do: where(query, [m], m.inserted_at < ^before)

  @doc """
  Gets a message with the sender preloaded. The caller must be an active
  participant of its conversation.
  """
  def get_message(%Scope{user: %User{id: user_id}}, message_id) do
    with {:ok, message_id} <- cast_id(message_id),
         %Message{} = message <-
           Repo.one(
             from m in Message,
               join: p in Participant,
               on:
                 p.conversation_id == m.conversation_id and p.user_id == ^user_id and
                   is_nil(p.left_at),
               where: m.id == ^message_id,
               preload: :sender
           ) do
      [message] = put_announcement_fields([message], user_id)
      {:ok, message}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_message(_scope, _message_id), do: {:error, :not_found}

  @doc """
  Returns a changeset for the message form.
  """
  def change_message(attrs \\ %{}) do
    Message.changeset(%Message{}, attrs)
  end

  @doc """
  Posts a text message, bumps the conversation's `last_message_at` and
  broadcasts `{:message_created, conversation_id, message_id}`.
  """
  def post_message(%Scope{} = scope, conversation_id, attrs) do
    with {:ok, participant} <- fetch_participation(scope, conversation_id),
         {:ok, message} <- insert_message(participant, :text, attrs) do
      broadcast_conversation(
        message.conversation_id,
        {:message_created, message.conversation_id, message.id}
      )

      {:ok, Repo.preload(message, :sender)}
    end
  end

  defp insert_message(%Participant{} = participant, kind, attrs) do
    Repo.transact(fn ->
      message = %Message{
        conversation_id: participant.conversation_id,
        sender_id: participant.user_id,
        kind: kind
      }

      with {:ok, message} <- message |> Message.changeset(attrs) |> Repo.insert() do
        Repo.update_all(
          from(c in Conversation,
            where: c.id == ^message.conversation_id,
            update: [
              set: [
                last_message_at:
                  fragment(
                    "GREATEST(?, ?)",
                    c.last_message_at,
                    type(^message.inserted_at, :utc_datetime_usec)
                  )
              ]
            ]
          ),
          []
        )

        {:ok, message}
      end
    end)
  end

  @doc """
  Marks the conversation as read for the user and broadcasts
  `{:conversation_read, conversation_id}` on `"user:<id>"`.
  """
  def mark_read(%Scope{} = scope, conversation_id) do
    with {:ok, participant} <- fetch_participation(scope, conversation_id) do
      Repo.update_all(from(p in Participant, where: p.id == ^participant.id),
        set: [last_read_at: DateTime.utc_now()]
      )

      broadcast_user(participant.user_id, {:conversation_read, participant.conversation_id})
    end
  end

  ## Announcements (ADR 0005)

  @doc """
  Returns a changeset for the announcement form.
  """
  def change_announcement(attrs \\ %{}) do
    Message.changeset(%Message{kind: :announcement}, attrs)
  end

  @doc """
  Posts an announcement and asks every other active participant to
  acknowledge it.

  Requires the participant's `can_announce`, so DMs and group chats always
  return `{:error, :unauthorized}`. Receipts are a snapshot: one per active
  participant except the sender, inserted in the same transaction. Broadcasts
  `{:message_created, conversation_id, message_id}` and returns the message
  as `get_message/2` does.
  """
  def post_announcement(%Scope{} = scope, conversation_id, attrs) do
    with {:ok, participant} <- fetch_participation(scope, conversation_id),
         {:ok, message} <- Repo.transact(fn -> insert_announcement(participant, attrs) end) do
      broadcast_conversation(
        message.conversation_id,
        {:message_created, message.conversation_id, message.id}
      )

      get_message(scope, message.id)
    end
  end

  # The lock serialises with sync_participants/2: a participant it removes
  # can't be left holding a receipt from an announcement committed after.
  defp insert_announcement(%Participant{} = participant, attrs) do
    lock_conversation!(participant.conversation_id)

    with :ok <- authorize_announcement(participant),
         {:ok, message} <- insert_message(participant, :announcement, attrs) do
      insert_receipts(message)
      {:ok, message}
    end
  end

  # Re-read under the lock: can_announce may have changed since the fetch
  defp authorize_announcement(%Participant{id: participant_id}) do
    if Repo.exists?(
         from p in Participant,
           where: p.id == ^participant_id and is_nil(p.left_at) and p.can_announce
       ) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp insert_receipts(%Message{} = message) do
    recipients =
      from p in Participant,
        where:
          p.conversation_id == ^message.conversation_id and is_nil(p.left_at) and
            p.user_id != ^message.sender_id,
        select: %{
          message_id: type(^message.id, :id),
          user_id: p.user_id,
          inserted_at: type(^message.inserted_at, :utc_datetime_usec)
        }

    Repo.insert_all(Receipt, recipients)
  end

  @doc """
  Acknowledges an announcement for the user ("I've read this").

  Idempotent: acknowledging again keeps the first time and broadcasts
  nothing. Returns `{:error, :not_found}` unless the user is an active
  participant holding a receipt for it. On change it broadcasts
  `{:ack_updated, message_id, %{acknowledged: n, total: n}}`.
  """
  def acknowledge(%Scope{user: %User{id: user_id}}, message_id) do
    with {:ok, message_id} <- cast_id(message_id),
         {%Receipt{} = receipt, conversation_id} <-
           Repo.one(
             from r in Receipt,
               join: m in assoc(r, :message),
               join: p in Participant,
               on:
                 p.conversation_id == m.conversation_id and p.user_id == r.user_id and
                   is_nil(p.left_at),
               where: r.message_id == ^message_id and r.user_id == ^user_id,
               select: {r, m.conversation_id}
           ) do
      acknowledge_receipt(receipt, conversation_id)
    else
      _ -> {:error, :not_found}
    end
  end

  def acknowledge(_scope, _message_id), do: {:error, :not_found}

  defp acknowledge_receipt(%Receipt{acknowledged_at: nil} = receipt, conversation_id) do
    # acknowledged_at IS NULL keeps the first time if two tabs race
    case Repo.update_all(
           from(r in Receipt,
             where: r.id == ^receipt.id and is_nil(r.acknowledged_at),
             select: r
           ),
           set: [acknowledged_at: DateTime.utc_now()]
         ) do
      {1, [receipt]} ->
        broadcast_ack_updated(conversation_id, [receipt.message_id])
        {:ok, receipt}

      {0, []} ->
        {:ok, Repo.reload!(receipt)}
    end
  end

  defp acknowledge_receipt(%Receipt{} = receipt, _conversation_id), do: {:ok, receipt}

  @doc """
  Lists an announcement's receipts with the user preloaded, ordered by name.

  Only the sender and participants who can announce in the conversation may
  see them. Other participants get `{:error, :unauthorized}`;
  non-participants get `{:error, :not_found}`, as do text messages.
  """
  def list_receipts(%Scope{user: %User{id: user_id}}, message_id) do
    with {:ok, message_id} <- cast_id(message_id),
         {%Message{} = message, %Participant{} = participant} <-
           Repo.one(
             from m in Message,
               join: p in Participant,
               on:
                 p.conversation_id == m.conversation_id and p.user_id == ^user_id and
                   is_nil(p.left_at),
               where: m.id == ^message_id and m.kind == ^:announcement,
               select: {m, p}
           ),
         :ok <- authorize_receipts(message, participant) do
      receipts =
        Repo.all(
          from r in Receipt,
            join: u in assoc(r, :user),
            where: r.message_id == ^message.id,
            order_by: [asc_nulls_last: u.name, asc: u.email],
            preload: [user: u]
        )

      {:ok, receipts}
    else
      {:error, :unauthorized} -> {:error, :unauthorized}
      _ -> {:error, :not_found}
    end
  end

  def list_receipts(_scope, _message_id), do: {:error, :not_found}

  defp authorize_receipts(%Message{sender_id: user_id}, %Participant{user_id: user_id}), do: :ok
  defp authorize_receipts(_message, %Participant{can_announce: true}), do: :ok
  defp authorize_receipts(_message, _participant), do: {:error, :unauthorized}

  # Sets ack_count, recipient_count, my_ack and my_acknowledged_at on
  # announcements, as seen by user_id. Text messages keep nil.
  defp put_announcement_fields(messages, user_id) do
    ids = for %Message{kind: :announcement, id: id} <- messages, do: id
    stats = announcement_stats(ids, user_id)

    Enum.map(messages, fn
      %Message{kind: :announcement, id: id} = message ->
        {acknowledged, total, mine, my_acknowledged_at} = Map.get(stats, id, {0, 0, 0, nil})

        %{
          message
          | ack_count: acknowledged,
            recipient_count: total,
            my_ack: my_ack(mine, my_acknowledged_at),
            my_acknowledged_at: my_acknowledged_at
        }

      message ->
        message
    end)
  end

  defp announcement_stats([], _user_id), do: %{}

  defp announcement_stats(message_ids, user_id) do
    from(r in Receipt,
      where: r.message_id in ^message_ids,
      group_by: r.message_id,
      select:
        {r.message_id,
         {count(r.acknowledged_at), count(r.id), filter(count(r.id), r.user_id == ^user_id),
          type(filter(max(r.acknowledged_at), r.user_id == ^user_id), :utc_datetime_usec)}}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp my_ack(0, _acknowledged_at), do: nil
  defp my_ack(_mine, nil), do: :pending
  defp my_ack(_mine, %DateTime{}), do: :acknowledged

  defp put_pending_ack_counts([], _user_id), do: []

  defp put_pending_ack_counts(conversations, user_id) do
    ids = Enum.map(conversations, & &1.id)

    counts =
      from(r in Receipt,
        join: m in assoc(r, :message),
        where: r.user_id == ^user_id and is_nil(r.acknowledged_at) and m.conversation_id in ^ids,
        group_by: m.conversation_id,
        select: {m.conversation_id, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(conversations, &%{&1 | pending_ack_count: Map.get(counts, &1.id, 0)})
  end

  defp broadcast_ack_updated(conversation_id, message_ids) do
    counts =
      from(r in Receipt,
        where: r.message_id in ^message_ids,
        group_by: r.message_id,
        select: {r.message_id, %{acknowledged: count(r.acknowledged_at), total: count(r.id)}}
      )
      |> Repo.all()
      |> Map.new()

    Enum.each(message_ids, fn message_id ->
      counts = Map.get(counts, message_id, %{acknowledged: 0, total: 0})
      broadcast_conversation(conversation_id, {:ack_updated, message_id, counts})
    end)
  end

  ## DMs and groups

  @doc """
  Finds or creates the DM between the user and `other_user_id`.

  Both must be active participants of the organisation's conversation.
  Returns `{:error, :not_found}` otherwise, and for yourself.
  """
  def start_dm(%Scope{user: %User{id: user_id}, organisation_id: org_id} = scope, other_user_id)
      when not is_nil(org_id) do
    with {:ok, other_id} when other_id != user_id <- cast_id(other_user_id),
         true <- org_members?(org_id, [user_id, other_id]),
         {:ok, {conversation_id, events}} <- find_or_create_dm(org_id, user_id, other_id) do
      broadcast(events)
      get_conversation(scope, conversation_id)
    else
      _ -> {:error, :not_found}
    end
  end

  def start_dm(_scope, _other_user_id), do: {:error, :not_found}

  defp find_or_create_dm(org_id, user_id, other_id) do
    dm_key = [user_id, other_id] |> Enum.sort() |> Enum.join(":")

    Repo.transact(fn ->
      existing =
        Repo.one(
          from c in Conversation,
            where: c.organisation_id == ^org_id and c.kind == ^:dm and c.dm_key == ^dm_key
        )

      conversation =
        existing ||
          %Conversation{
            organisation_id: org_id,
            kind: :dm,
            dm_key: dm_key,
            created_by_id: user_id
          }

      with {:ok, conversation} <- insert_if_new(conversation) do
        events =
          conversation.id
          |> join_participants(%{user_id => false, other_id => false}, DateTime.utc_now())
          |> Enum.reject(&match?({:joined, _, ^user_id}, &1))

        {:ok, {conversation.id, events}}
      end
    end)
  end

  defp insert_if_new(%Conversation{id: nil} = conversation),
    do: conversation |> Conversation.dm_changeset() |> Repo.insert()

  defp insert_if_new(%Conversation{} = conversation), do: {:ok, conversation}

  @doc """
  Creates a group chat from `%{"title" => _, "user_ids" => [_]}`.

  The creator is added. Every user must be an active member of the
  creator's organisation.
  """
  def create_group(%Scope{user: %User{id: user_id}, organisation_id: org_id} = scope, attrs) do
    changeset =
      %Conversation{kind: :group, organisation_id: org_id, created_by_id: user_id}
      |> Conversation.group_changeset(attrs)

    member_ids = Enum.uniq(Ecto.Changeset.get_field(changeset, :user_ids)) -- [user_id]

    changeset =
      changeset
      # forced: validate_length/3 skips unchanged fields, and [] is the default
      |> Ecto.Changeset.force_change(:user_ids, member_ids)
      |> Ecto.Changeset.validate_length(:user_ids, min: 1, message: "pick at least one person")
      |> validate_org_members(org_id, [user_id | member_ids])

    result =
      Repo.transact(fn ->
        with {:ok, conversation} <- Repo.insert(changeset) do
          flags = Map.new([user_id | member_ids], &{&1, false})
          {:ok, {conversation, join_participants(conversation.id, flags, DateTime.utc_now())}}
        end
      end)

    with {:ok, {conversation, events}} <- result do
      broadcast(events)
      get_conversation(scope, conversation.id)
    end
  end

  defp validate_org_members(changeset, org_id, user_ids) do
    if org_id && org_members?(org_id, user_ids) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :user_ids, "must all be in your organisation")
    end
  end

  @doc """
  Leaves a group chat. Derived conversations and DMs return
  `{:error, :not_leavable}`.
  """
  def leave_group(%Scope{} = scope, conversation_id) do
    with {:ok, participant} <- fetch_participation(scope, conversation_id) do
      case Repo.get!(Conversation, participant.conversation_id) do
        %Conversation{kind: :group} ->
          {:ok, events} =
            Repo.transact(fn ->
              {:ok,
               leave_participants(
                 participant.conversation_id,
                 [participant.user_id],
                 DateTime.utc_now()
               )}
            end)

          broadcast(events)

        %Conversation{} ->
          {:error, :not_leavable}
      end
    end
  end

  ## Subscriptions

  @doc "Subscribes to `\"user:<id>\"`."
  def subscribe_user(%Scope{user: %User{id: user_id}}) do
    Phoenix.PubSub.subscribe(@pubsub, user_topic(user_id))
  end

  @doc "Subscribes to `\"conversation:<id>\"`. Refuses non-participants."
  def subscribe_conversation(%Scope{} = scope, conversation_id) do
    with {:ok, participant} <- fetch_participation(scope, conversation_id) do
      Phoenix.PubSub.subscribe(@pubsub, conversation_topic(participant.conversation_id))
    end
  end

  @doc "Unsubscribes from `\"conversation:<id>\"`."
  def unsubscribe_conversation(conversation_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, conversation_topic(conversation_id))
  end

  ## Org-only: called inside Org's transaction. LiveViews never call these.

  @doc """
  Creates a derived conversation. Org-only.

  `attrs` has `:organisation_id` and `:title`, plus `:venue_id` for `:venue`
  and `:team_id` for `:team`.
  """
  def create_derived_conversation(kind, %{organisation_id: org_id} = attrs)
      when kind in @derived_kinds do
    %Conversation{
      kind: kind,
      organisation_id: org_id,
      venue_id: attrs[:venue_id],
      team_id: attrs[:team_id]
    }
    |> Conversation.derived_changeset(Map.take(attrs, [:title]))
    |> Repo.insert()
  end

  @doc """
  Gets the derived conversation of an organisation, venue or team, locking
  the row `FOR UPDATE`. Org-only; call it inside a transaction before
  computing the desired participants.
  """
  def get_derived_conversation(kind, ref_id) when kind in @derived_kinds do
    ref_field = %{org: :organisation_id, venue: :venue_id, team: :team_id}[kind]

    Repo.one(
      from c in Conversation,
        where: c.kind == ^kind and field(c, ^ref_field) == ^ref_id,
        lock: "FOR UPDATE"
    )
  end

  @doc """
  Makes the active participants of a derived conversation exactly `desired`,
  a map of `user_id => can_announce`. Org-only.

  Upserts desired users (rejoiners get `left_at = nil`, `last_read_at = now`),
  updates changed `can_announce` flags and sets `left_at` on everyone else,
  deleting their pending receipts. Returns the events to `broadcast/1` after
  commit. Raises for `:dm` and `:group`.
  """
  def sync_participants(%Conversation{kind: kind}, _desired) when kind in [:dm, :group] do
    raise ArgumentError, "sync_participants/2 only syncs derived conversations, got #{kind}"
  end

  def sync_participants(%Conversation{id: conversation_id}, desired) when is_map(desired) do
    now = DateTime.utc_now()
    lock_conversation!(conversation_id)

    active =
      Repo.all(
        from p in Participant,
          where: p.conversation_id == ^conversation_id and is_nil(p.left_at),
          select: {p.user_id, p.can_announce}
      )
      |> Map.new()

    joiners = Map.drop(desired, Map.keys(active))
    leavers = active |> Map.drop(Map.keys(desired)) |> Map.keys()

    flag_changes =
      for {user_id, flag} <- desired, Map.has_key?(active, user_id), active[user_id] != flag do
        {user_id, flag}
      end

    Enum.each([true, false], fn flag ->
      user_ids = for {user_id, ^flag} <- flag_changes, do: user_id
      update_can_announce(conversation_id, user_ids, flag, now)
    end)

    join_events = join_participants(conversation_id, joiners, now)
    leave_events = leave_participants(conversation_id, leavers, now)

    {:ok, join_events ++ leave_events}
  end

  @doc """
  Sets `left_at` on the user's `:dm` and `:group` participations in the
  organisation, deleting their pending receipts. Org-only; called when the
  user's last active membership ends.
  """
  def revoke_org_access(org_id, user_id) do
    conversation_ids =
      Repo.all(
        from p in Participant,
          join: c in assoc(p, :conversation),
          where:
            c.organisation_id == ^org_id and c.kind in ^[:dm, :group] and
              p.user_id == ^user_id and is_nil(p.left_at),
          select: c.id
      )

    now = DateTime.utc_now()
    {:ok, Enum.flat_map(conversation_ids, &leave_participants(&1, [user_id], now))}
  end

  @doc """
  Publishes events returned by `sync_participants/2` and
  `revoke_org_access/2`. Call after commit.

  `{:receipts_removed, conversation_id, message_ids}` becomes one
  `{:ack_updated, message_id, %{acknowledged: n, total: n}}` per message on
  `"conversation:<id>"`, with the counts after the removal.
  """
  def broadcast(events) when is_list(events) do
    Enum.each(events, &broadcast_event/1)
  end

  defp broadcast_event({:joined, conversation_id, user_id}),
    do: broadcast_user(user_id, {:conversation_joined, conversation_id})

  defp broadcast_event({:left, conversation_id, user_id}),
    do: broadcast_user(user_id, {:conversation_left, conversation_id})

  defp broadcast_event({:receipts_removed, conversation_id, message_ids}),
    do: broadcast_ack_updated(conversation_id, message_ids)

  ## Participants

  defp fetch_participation(%Scope{user: %User{id: user_id}}, conversation_id) do
    with {:ok, conversation_id} <- cast_id(conversation_id),
         %Participant{} = participant <-
           Repo.one(
             from p in Participant,
               where:
                 p.conversation_id == ^conversation_id and p.user_id == ^user_id and
                   is_nil(p.left_at)
           ) do
      {:ok, participant}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_participation(_scope, _conversation_id), do: {:error, :not_found}

  # Serialises participant sync and announcement snapshots per conversation
  defp lock_conversation!(conversation_id) do
    Repo.one!(
      from c in Conversation, where: c.id == ^conversation_id, lock: "FOR UPDATE", select: c.id
    )
  end

  defp org_members?(org_id, user_ids) do
    user_ids = Enum.uniq(user_ids)

    count =
      Repo.aggregate(
        from(p in Participant,
          join: c in assoc(p, :conversation),
          where:
            c.organisation_id == ^org_id and c.kind == ^:org and is_nil(p.left_at) and
              p.user_id in ^user_ids
        ),
        :count
      )

    count == length(user_ids)
  end

  # Activates `flags` (user_id => can_announce) in the conversation. Users who
  # already have an active row are left alone. Returns :joined events.
  defp join_participants(conversation_id, flags, now) do
    active =
      Repo.all(
        from p in Participant,
          where:
            p.conversation_id == ^conversation_id and p.user_id in ^Map.keys(flags) and
              is_nil(p.left_at),
          select: p.user_id
      )

    joiners = Map.drop(flags, active)
    timestamp = DateTime.truncate(now, :second)

    rows =
      for {user_id, can_announce} <- joiners do
        %{
          conversation_id: conversation_id,
          user_id: user_id,
          can_announce: can_announce,
          last_read_at: now,
          left_at: nil,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end

    Repo.insert_all(Participant, rows,
      on_conflict: {:replace, [:can_announce, :last_read_at, :left_at, :updated_at]},
      conflict_target: [:conversation_id, :user_id]
    )

    for {user_id, _} <- joiners, do: {:joined, conversation_id, user_id}
  end

  defp update_can_announce(_conversation_id, [], _flag, _now), do: :ok

  defp update_can_announce(conversation_id, user_ids, flag, now) do
    Repo.update_all(
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id in ^user_ids
      ),
      set: [can_announce: flag, updated_at: DateTime.truncate(now, :second)]
    )
  end

  # Sets left_at and deletes the leavers' pending receipts in the conversation.
  defp leave_participants(_conversation_id, [], _now), do: []

  defp leave_participants(conversation_id, user_ids, now) do
    Repo.update_all(
      from(p in Participant,
        where:
          p.conversation_id == ^conversation_id and p.user_id in ^user_ids and
            is_nil(p.left_at)
      ),
      set: [left_at: now, updated_at: DateTime.truncate(now, :second)]
    )

    {_, message_ids} =
      Repo.delete_all(
        from r in Receipt,
          join: m in Message,
          on: m.id == r.message_id,
          where:
            m.conversation_id == ^conversation_id and r.user_id in ^user_ids and
              is_nil(r.acknowledged_at),
          select: r.message_id
      )

    left_events = for user_id <- user_ids, do: {:left, conversation_id, user_id}

    case Enum.uniq(message_ids) do
      [] -> left_events
      message_ids -> left_events ++ [{:receipts_removed, conversation_id, message_ids}]
    end
  end

  ## PubSub

  defp user_topic(user_id), do: "user:#{user_id}"
  defp conversation_topic(conversation_id), do: "conversation:#{conversation_id}"

  defp broadcast_user(user_id, message),
    do: Phoenix.PubSub.broadcast(@pubsub, user_topic(user_id), message)

  defp broadcast_conversation(conversation_id, message),
    do: Phoenix.PubSub.broadcast(@pubsub, conversation_topic(conversation_id), message)

  defp cast_id(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
