defmodule SonaComms.Org do
  @moduledoc """
  Organisations, venues, teams and memberships.

  Memberships are the source of truth for who is in the organisation's
  derived conversations. Every membership change resyncs the affected org,
  venue and team conversations through `SonaComms.Chat.sync_participants/2`
  inside the same transaction, and broadcasts after commit (ADR 0001).

  PubSub topics (ADR 0006):

    * `"user:<id>:access"` - `{:access_revoked, organisation_id}`
    * `"org:<id>"` - `{:org_changed, :venue | :team | :membership}`
  """

  import Ecto.Query, warn: false

  alias SonaComms.Accounts
  alias SonaComms.Accounts.{Scope, User}
  alias SonaComms.Chat
  alias SonaComms.Org.{Membership, Organisation, Team, Venue}
  alias SonaComms.Repo

  @pubsub SonaComms.PubSub
  @personas ~w(alice@sona.test bob@sona.test charlie@sona.test)

  ## Access

  @doc """
  Sets `organisation_id` and `admin?` on the scope from the user's active
  memberships. Returns `{:error, :no_access}` when there are none.
  """
  def put_member_scope(%Scope{user: %User{id: user_id}} = scope) do
    rows =
      Repo.all(
        from m in active_memberships(),
          join: v in assoc(m, :venue),
          where: m.user_id == ^user_id,
          order_by: [asc: m.inserted_at, asc: m.id],
          select: {v.organisation_id, m.role}
      )

    case rows do
      [] ->
        {:error, :no_access}

      [{org_id, _role} | _] ->
        admin? = Enum.any?(rows, &(&1 == {org_id, :admin}))
        {:ok, %{scope | organisation_id: org_id, admin?: admin?}}
    end
  end

  def put_member_scope(_scope), do: {:error, :no_access}

  @doc """
  Returns true if the scope's user holds an active `:admin` membership in the
  scope's organisation. Checks the database, never the scope's `admin?` flag.
  """
  def admin?(%Scope{user: %User{id: user_id}, organisation_id: org_id})
      when not is_nil(org_id) do
    Repo.exists?(
      from m in active_memberships(),
        join: v in assoc(m, :venue),
        where: m.user_id == ^user_id and m.role == ^:admin and v.organisation_id == ^org_id
    )
  end

  def admin?(_scope), do: false

  @doc "Subscribes to `\"user:<id>:access\"`."
  def subscribe_access(%Scope{user: %User{id: user_id}}) do
    Phoenix.PubSub.subscribe(@pubsub, access_topic(user_id))
  end

  @doc "Subscribes to `\"org:<organisation_id>\"`."
  def subscribe_org(%Scope{organisation_id: org_id}) when not is_nil(org_id) do
    Phoenix.PubSub.subscribe(@pubsub, org_topic(org_id))
  end

  ## Structure

  @doc """
  Lists the organisation's venues ordered by name, with teams preloaded,
  ordered by name. Each venue's and team's `member_count` is set to the
  number of distinct people with an active membership there.
  """
  def list_venues(%Scope{} = scope) do
    with :ok <- authorize(scope) do
      teams =
        from t in Team,
          left_join: m in Membership,
          on: m.team_id == t.id and is_nil(m.ended_at),
          group_by: t.id,
          order_by: t.name,
          select_merge: %{member_count: count(m.user_id, :distinct)}

      Repo.all(
        from v in Venue,
          left_join: m in Membership,
          on: m.venue_id == v.id and is_nil(m.ended_at),
          where: v.organisation_id == ^scope.organisation_id,
          group_by: v.id,
          order_by: v.name,
          select_merge: %{member_count: count(m.user_id, :distinct)},
          preload: [teams: ^teams]
      )
    end
  end

  @doc "Returns a changeset for the venue form."
  def change_venue(%Venue{} = venue, attrs \\ %{}) do
    Venue.changeset(venue, attrs)
  end

  @doc """
  Creates a venue and its conversation. When the scope has a user, that user
  also gets a venue-level `:admin` membership.
  """
  def create_venue(%Scope{} = scope, attrs) do
    with :ok <- authorize(scope),
         {:ok, {venue, events}} <- Repo.transact(fn -> insert_venue(scope, attrs) end) do
      Chat.broadcast(events)
      broadcast_org(scope.organisation_id, {:org_changed, :venue})
      {:ok, venue}
    end
  end

  defp insert_venue(scope, attrs) do
    venue = %Venue{organisation_id: scope.organisation_id}

    with {:ok, venue} <- venue |> Venue.changeset(attrs) |> Repo.insert(),
         {:ok, _conversation} <-
           Chat.create_derived_conversation(:venue, %{
             organisation_id: venue.organisation_id,
             venue_id: venue.id,
             title: venue.name
           }),
         {:ok, events} <- add_venue_creator(scope, venue) do
      {:ok, {venue, events}}
    end
  end

  defp add_venue_creator(%Scope{user: %User{id: user_id}}, venue) do
    Repo.insert!(%Membership{user_id: user_id, venue_id: venue.id, role: :admin})
    sync(:venue, venue.id)
  end

  defp add_venue_creator(%Scope{}, _venue), do: {:ok, []}

  @doc "Returns a changeset for the team form."
  def change_team(%Team{} = team, attrs \\ %{}) do
    Team.changeset(team, attrs)
  end

  @doc """
  Creates a team and its conversation, titled "Venue · Team". Nobody is added
  until someone is given a membership on the team.

  Returns `{:error, :not_found}` if the venue is outside the scope's organisation.
  """
  def create_team(%Scope{} = scope, venue_id, attrs) do
    with :ok <- authorize(scope),
         %Venue{} = venue <- get_venue(scope.organisation_id, venue_id) || {:error, :not_found},
         {:ok, team} <- Repo.transact(fn -> insert_team(venue, attrs) end) do
      broadcast_org(scope.organisation_id, {:org_changed, :team})
      {:ok, team}
    end
  end

  defp insert_team(venue, attrs) do
    with {:ok, team} <- %Team{venue_id: venue.id} |> Team.changeset(attrs) |> Repo.insert(),
         {:ok, _conversation} <-
           Chat.create_derived_conversation(:team, %{
             organisation_id: venue.organisation_id,
             team_id: team.id,
             title: "#{venue.name} · #{team.name}"
           }) do
      {:ok, team}
    end
  end

  defp get_venue(org_id, venue_id) do
    with {:ok, venue_id} <- cast_id(venue_id) do
      Repo.get_by(Venue, id: venue_id, organisation_id: org_id)
    else
      _ -> nil
    end
  end

  ## Memberships

  @doc """
  Lists the organisation's memberships with user, venue and team preloaded,
  ordered by venue, team and name.

  ## Options

    * `:venue_id` - only memberships at this venue
    * `:include_ended` - include ended memberships, defaults to false
  """
  def list_memberships(%Scope{} = scope, opts \\ []) do
    with :ok <- authorize(scope) do
      from(m in Membership,
        join: v in assoc(m, :venue),
        join: u in assoc(m, :user),
        left_join: t in assoc(m, :team),
        where: v.organisation_id == ^scope.organisation_id,
        order_by: [
          asc: v.name,
          asc_nulls_first: t.name,
          asc_nulls_last: u.name,
          asc: u.email,
          asc: m.inserted_at
        ],
        preload: [venue: v, user: u, team: t]
      )
      |> filter_venue(Keyword.get(opts, :venue_id))
      |> filter_ended(Keyword.get(opts, :include_ended, false))
      |> Repo.all()
    end
  end

  defp filter_venue(query, nil), do: query

  defp filter_venue(query, venue_id) do
    case cast_id(venue_id) do
      {:ok, venue_id} -> where(query, [m], m.venue_id == ^venue_id)
      _ -> where(query, [m], false)
    end
  end

  defp filter_ended(query, true), do: query
  defp filter_ended(query, false), do: where(query, [m], is_nil(m.ended_at))

  @doc """
  Returns a changeset for the membership form: email, name, venue_id,
  team_id and role.
  """
  def change_membership(attrs \\ %{}) do
    Membership.form_changeset(%Membership{}, attrs)
  end

  @doc """
  Creates a membership, finding or creating the user by email, and syncs the
  org, venue and team conversations.

  Returns a changeset error when the venue is outside the organisation, the
  team is outside the venue, the slot is already active, or the user has
  active memberships in another organisation.
  """
  def create_membership(%Scope{} = scope, attrs) do
    with :ok <- authorize(scope),
         {:ok, {membership, events}} <-
           Repo.transact(fn -> insert_membership(scope.organisation_id, attrs) end) do
      Chat.broadcast(events)
      broadcast_org(scope.organisation_id, {:org_changed, :membership})
      {:ok, membership}
    end
  end

  defp insert_membership(org_id, attrs) do
    changeset = attrs |> change_membership() |> validate_placement(org_id)

    with {:ok, _valid} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, user} <- find_or_register_user(changeset),
         {:ok, membership} <-
           changeset
           |> validate_single_organisation(user, org_id)
           |> Ecto.Changeset.put_change(:user_id, user.id)
           |> Repo.insert(),
         {:ok, events} <- sync_membership(org_id, membership) do
      {:ok, {Repo.preload(membership, [:user, :venue, :team]), events}}
    end
  end

  defp validate_placement(changeset, org_id) do
    venue_id = Ecto.Changeset.get_field(changeset, :venue_id)
    team_id = Ecto.Changeset.get_field(changeset, :team_id)

    cond do
      is_nil(venue_id) ->
        changeset

      not Repo.exists?(from v in Venue, where: v.id == ^venue_id and v.organisation_id == ^org_id) ->
        Ecto.Changeset.add_error(changeset, :venue_id, "is not part of this organisation")

      team_id &&
          not Repo.exists?(from t in Team, where: t.id == ^team_id and t.venue_id == ^venue_id) ->
        Ecto.Changeset.add_error(changeset, :team_id, "is not part of this venue")

      true ->
        changeset
    end
  end

  defp find_or_register_user(changeset) do
    email = Ecto.Changeset.get_field(changeset, :email)

    with nil <- Accounts.get_user_by_email(email),
         {:error, user_changeset} <-
           Accounts.register_user(%{
             email: email,
             name: Ecto.Changeset.get_field(changeset, :name)
           }) do
      changeset =
        Enum.reduce(user_changeset.errors, changeset, fn {field, {message, opts}}, acc ->
          Ecto.Changeset.add_error(acc, field, message, opts)
        end)

      {:error, %{changeset | action: :insert}}
    else
      %User{} = user -> {:ok, user}
      {:ok, %User{} = user} -> {:ok, user}
    end
  end

  defp validate_single_organisation(changeset, %User{id: user_id}, org_id) do
    elsewhere? =
      Repo.exists?(
        from m in active_memberships(),
          join: v in assoc(m, :venue),
          where: m.user_id == ^user_id and v.organisation_id != ^org_id
      )

    if elsewhere? do
      Ecto.Changeset.add_error(changeset, :email, "already works for another organisation")
    else
      changeset
    end
  end

  @doc """
  Ends a membership and resyncs its conversations. On the user's last active
  membership in the organisation it also revokes their DMs and group chats.

  After commit it broadcasts `{:access_revoked, org_id}` first (if revoked),
  then the Chat events, then `{:org_changed, :membership}`.
  """
  def end_membership(%Scope{} = scope, membership_id) do
    with :ok <- authorize(scope),
         {:ok, {membership, events, revoked?}} <-
           Repo.transact(fn -> close_membership(scope, membership_id) end) do
      if revoked?, do: broadcast_access_revoked(membership.user_id, scope.organisation_id)
      Chat.broadcast(events)
      broadcast_org(scope.organisation_id, {:org_changed, :membership})
      {:ok, membership}
    end
  end

  defp close_membership(%Scope{organisation_id: org_id} = scope, membership_id) do
    with {:ok, membership} <- lock_membership(org_id, membership_id),
         :ok <- ensure_active(membership),
         :ok <- ensure_not_own(scope, membership),
         {:ok, membership} <-
           membership |> Membership.end_changeset(DateTime.utc_now(:second)) |> Repo.update(),
         {:ok, events} <- sync_membership(org_id, membership) do
      membership = Repo.preload(membership, [:user, :venue, :team])

      if member?(membership.user_id, org_id) do
        {:ok, {membership, events, false}}
      else
        {:ok, revoke_events} = Chat.revoke_org_access(org_id, membership.user_id)
        {:ok, {membership, events ++ revoke_events, true}}
      end
    end
  end

  defp lock_membership(org_id, membership_id) do
    with {:ok, membership_id} <- cast_id(membership_id),
         %Membership{} = membership <-
           Repo.one(
             from m in Membership,
               join: v in assoc(m, :venue),
               where: m.id == ^membership_id and v.organisation_id == ^org_id,
               lock: "FOR UPDATE OF m0"
           ) do
      {:ok, membership}
    else
      _ -> {:error, :not_found}
    end
  end

  defp ensure_active(%Membership{ended_at: nil}), do: :ok
  defp ensure_active(%Membership{}), do: {:error, :already_ended}

  defp ensure_not_own(%Scope{user: %User{id: user_id}}, %Membership{user_id: user_id}),
    do: {:error, :cannot_end_own_membership}

  defp ensure_not_own(%Scope{}, %Membership{}), do: :ok

  defp member?(user_id, org_id) do
    Repo.exists?(
      from m in active_memberships(),
        join: v in assoc(m, :venue),
        where: m.user_id == ^user_id and v.organisation_id == ^org_id
    )
  end

  @doc """
  Lists active members of the scope's organisation except the scope's user,
  ordered by name.
  """
  def list_colleagues(%Scope{user: %User{id: user_id}, organisation_id: org_id})
      when not is_nil(org_id) do
    member_ids =
      from m in active_memberships(),
        join: v in assoc(m, :venue),
        where: v.organisation_id == ^org_id,
        select: m.user_id

    Repo.all(
      from u in User,
        where: u.id in subquery(member_ids) and u.id != ^user_id,
        order_by: [asc_nulls_last: u.name, asc: u.email]
    )
  end

  def list_colleagues(_scope), do: []

  ## Sync

  # Conversations are always locked in org -> venue -> team order, so
  # concurrent membership changes cannot deadlock.
  defp sync_membership(org_id, %Membership{venue_id: venue_id, team_id: team_id}) do
    events =
      [org: org_id, venue: venue_id, team: team_id]
      |> Enum.reject(fn {_kind, ref_id} -> is_nil(ref_id) end)
      |> Enum.flat_map(fn {kind, ref_id} ->
        {:ok, events} = sync(kind, ref_id)
        events
      end)

    {:ok, events}
  end

  # Locks the conversation first, then computes the desired participants, so
  # a concurrent change is seen once its transaction commits.
  defp sync(kind, ref_id) do
    conversation =
      Chat.get_derived_conversation(kind, ref_id) ||
        raise "no #{kind} conversation for #{ref_id}"

    Chat.sync_participants(conversation, desired_participants(kind, ref_id))
  end

  defp desired_participants(kind, ref_id) do
    kind
    |> active_memberships_for(ref_id)
    |> select([m], {m.user_id, m.role, m.team_id})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {user_id, role, team_id}, acc ->
      flag = can_announce?(kind, role, team_id)
      Map.update(acc, user_id, flag, &(&1 or flag))
    end)
  end

  defp active_memberships_for(:org, org_id) do
    from m in active_memberships(),
      join: v in assoc(m, :venue),
      where: v.organisation_id == ^org_id
  end

  defp active_memberships_for(:venue, venue_id),
    do: where(active_memberships(), [m], m.venue_id == ^venue_id)

  defp active_memberships_for(:team, team_id),
    do: where(active_memberships(), [m], m.team_id == ^team_id)

  # The role matrix, PLAN.md §2.5 and ADR 0003.
  defp can_announce?(:org, role, _team_id), do: role == :admin
  defp can_announce?(:venue, :admin, _team_id), do: true
  defp can_announce?(:venue, :manager, team_id), do: is_nil(team_id)
  defp can_announce?(:venue, _role, _team_id), do: false
  defp can_announce?(:team, role, _team_id), do: role in [:manager, :admin]

  defp active_memberships, do: from(m in Membership, where: is_nil(m.ended_at))

  ## Bootstrap and dev: no scope, never called from LiveViews

  @doc """
  Creates an organisation and its conversation. Seeds and tests only.
  """
  def create_organisation(attrs) do
    Repo.transact(fn ->
      with {:ok, organisation} <-
             %Organisation{} |> Organisation.changeset(attrs) |> Repo.insert(),
           {:ok, _conversation} <-
             Chat.create_derived_conversation(:org, %{
               organisation_id: organisation.id,
               title: organisation.name
             }) do
        {:ok, organisation}
      end
    end)
  end

  @doc """
  Lists every user with their active memberships (venue and team preloaded).
  Alice, Bob and Charlie come first. Dev user switcher only.
  """
  def directory do
    memberships =
      Repo.all(
        from m in active_memberships(),
          join: v in assoc(m, :venue),
          left_join: t in assoc(m, :team),
          order_by: [asc: v.name, asc_nulls_first: t.name],
          preload: [venue: v, team: t]
      )
      |> Enum.group_by(& &1.user_id)

    User
    |> Repo.all()
    |> Enum.map(&%{user: &1, memberships: Map.get(memberships, &1.id, [])})
    |> Enum.sort_by(fn %{user: user} ->
      {persona_rank(user), String.downcase(Accounts.display_name(user))}
    end)
  end

  defp persona_rank(%User{email: email}) do
    Enum.find_index(@personas, &(&1 == String.downcase(email))) || length(@personas)
  end

  ## Helpers

  defp authorize(%Scope{system?: true, organisation_id: org_id}) when not is_nil(org_id),
    do: :ok

  defp authorize(%Scope{} = scope) do
    if admin?(scope), do: :ok, else: {:error, :unauthorized}
  end

  defp access_topic(user_id), do: "user:#{user_id}:access"
  defp org_topic(org_id), do: "org:#{org_id}"

  defp broadcast_org(org_id, message),
    do: Phoenix.PubSub.broadcast(@pubsub, org_topic(org_id), message)

  defp broadcast_access_revoked(user_id, org_id),
    do: Phoenix.PubSub.broadcast(@pubsub, access_topic(user_id), {:access_revoked, org_id})

  defp cast_id(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
