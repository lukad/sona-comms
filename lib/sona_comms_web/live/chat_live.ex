defmodule SonaCommsWeb.ChatLive do
  @moduledoc """
  The chat: a sidebar of conversations and the open conversation.

  Keeps the seams in PLAN.md §6.1: the `Announcements.attach/1` and
  `Announcements.apply_action/3` calls, the `:conversations` and `:messages`
  streams, and the announcement call sites.

  Realtime (ADR 0006): subscribes to `"user:<id>"` and to every active
  conversation, and refetches through `SonaComms.Chat` on every event.

  `@sidebar` mirrors the order of the `:conversations` stream on the client
  (ids and sort keys only), so a row whose recency changes can be moved to
  its place within its section.
  """
  use SonaCommsWeb, :live_view

  alias SonaComms.Chat
  alias SonaComms.Org
  alias SonaCommsWeb.AnnouncementComponents
  alias SonaCommsWeb.ChatComponents
  alias SonaCommsWeb.ChatLive.Announcements

  on_mount {SonaCommsWeb.OrgAuth, :require_member}

  @kind_rank %{org: 0, venue: 1, team: 2, group: 3, dm: 4}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} full_bleed>
      <div class="flex h-full">
        <aside class={[
          "w-full shrink-0 flex-col border-r border-base-300 bg-base-200/50 md:flex md:w-80",
          if(@conversation, do: "hidden", else: "flex")
        ]}>
          <div class="flex items-center gap-1 px-4 pt-4 pb-1">
            <h2 class="flex-1 text-base font-semibold tracking-tight">Chats</h2>
            <.link
              id="new-dm-button"
              patch={~p"/new/dm"}
              title="New message"
              aria-label="New message"
              class="grid size-8 place-items-center rounded-lg text-base-content/70 transition hover:bg-base-300/60 hover:text-base-content"
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </.link>
            <.link
              id="new-group-button"
              patch={~p"/new/group"}
              title="New group chat"
              aria-label="New group chat"
              class="grid size-8 place-items-center rounded-lg text-base-content/70 transition hover:bg-base-300/60 hover:text-base-content"
            >
              <.icon name="hero-user-group" class="size-5" />
            </.link>
          </div>

          <ul
            id="conversations"
            phx-update="stream"
            class="min-h-0 flex-1 space-y-0.5 overflow-y-auto px-2 pb-4"
          >
            <li
              :for={{dom_id, conversation} <- @streams.conversations}
              id={dom_id}
              data-kind={conversation.kind}
            >
              <ChatComponents.conversation_row
                conversation={conversation}
                active={open?(@conversation, conversation)}
              />
            </li>
          </ul>
        </aside>

        <section :if={@conversation} class="flex min-w-0 flex-1 flex-col bg-base-100">
          <header
            id="conversation-header"
            class="flex shrink-0 items-center gap-3 border-b border-base-300 px-3 py-2.5 sm:px-6"
          >
            <.link
              patch={~p"/"}
              aria-label="Back to chats"
              class="-ml-1 grid size-8 place-items-center rounded-lg text-base-content/70 transition hover:bg-base-200 md:hidden"
            >
              <.icon name="hero-chevron-left" class="size-5" />
            </.link>
            <ChatComponents.conversation_avatar conversation={@conversation} />
            <div class="min-w-0 flex-1">
              <h1 class="truncate leading-tight font-semibold">{@conversation.display_title}</h1>
              <p id="participant-count" class="truncate text-xs text-base-content/55">
                {ChatComponents.kind_label(@conversation.kind)} · {people_label(@participant_count)}
              </p>
            </div>
            <AnnouncementComponents.announce_button conversation={@conversation} />
            <button
              :if={@conversation.kind == :group}
              id="leave-group"
              type="button"
              phx-click="leave_group"
              data-confirm={"Leave #{@conversation.display_title}? You'll stop getting its messages."}
              class="btn btn-ghost btn-sm text-base-content/70 hover:text-error"
            >
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
              <span class="hidden sm:inline">Leave</span>
            </button>
          </header>

          <ChatComponents.message_scroller id="message-scroller" conversation_id={@conversation.id}>
            <div id="messages" phx-update="stream" class="mx-auto w-full max-w-3xl space-y-4">
              <div
                id="messages-empty"
                class="hidden flex-col items-center gap-2 py-16 text-center only:flex"
              >
                <span class="grid size-12 place-items-center rounded-2xl bg-base-200 text-base-content/40">
                  <.icon name="hero-chat-bubble-left-ellipsis" class="size-6" />
                </span>
                <p class="text-sm font-medium">No messages yet</p>
                <p class="text-sm text-base-content/55">Say hello to get things started.</p>
              </div>
              <div
                :for={{dom_id, msg} <- @streams.messages}
                id={dom_id}
                data-mine={"#{msg.sender_id == @current_scope.user.id}"}
              >
                <AnnouncementComponents.announcement_message
                  :if={msg.kind == :announcement}
                  message={msg}
                  conversation={@conversation}
                  current_scope={@current_scope}
                />
                <ChatComponents.message_bubble
                  :if={msg.kind == :text}
                  message={msg}
                  mine={msg.sender_id == @current_scope.user.id}
                />
              </div>
            </div>
          </ChatComponents.message_scroller>

          <ChatComponents.composer
            form={@message_form}
            placeholder={"Message #{@conversation.display_title}"}
          />
        </section>

        <section
          :if={!@conversation}
          id="no-conversation-selected"
          class="hidden flex-1 flex-col items-center justify-center gap-3 p-8 text-center md:flex"
        >
          <span class="grid size-16 place-items-center rounded-3xl bg-primary/10 text-primary">
            <.icon name="hero-chat-bubble-left-right" class="size-8" />
          </span>
          <h1 class="mt-2 text-lg font-semibold tracking-tight">Pick a conversation</h1>
          <p class="max-w-sm text-sm text-base-content/60">
            Your venue and team chats are on the left, and you're added automatically.
            Start a direct message or a group chat any time.
          </p>
          <div class="mt-3 flex gap-2">
            <.link patch={~p"/new/dm"} class="btn btn-sm btn-primary">
              <.icon name="hero-pencil-square-mini" class="size-4" /> New message
            </.link>
            <.link patch={~p"/new/group"} class="btn btn-sm btn-ghost">
              <.icon name="hero-user-group-mini" class="size-4" /> New group chat
            </.link>
          </div>
        </section>
      </div>

      <AnnouncementComponents.announcement_modal
        :if={@conversation && @live_action in [:announce, :receipts]}
        live_action={@live_action}
        conversation={@conversation}
        form={@announcement_form}
        summary={@receipt_summary}
        pending_receipts={@streams.pending_receipts}
        read_receipts={@streams.read_receipts}
      />

      <ChatComponents.new_dm_modal
        :if={@live_action == :new_dm}
        colleagues={@streams.colleagues}
        on_cancel={JS.patch(return_path(@conversation))}
      />

      <ChatComponents.new_group_modal
        :if={@live_action == :new_group}
        form={@group_form}
        colleagues={@streams.colleagues}
        on_cancel={JS.patch(return_path(@conversation))}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    conversations = Chat.list_conversations(socket.assigns.current_scope)

    socket =
      socket
      |> assign(:conversation, nil)
      |> assign(:participant_count, 0)
      |> assign(:message_form, to_form(Chat.change_message()))
      |> assign(:group_form, nil)
      |> assign(:sidebar, Enum.map(conversations, &sidebar_entry/1))
      |> assign(:subscribed, MapSet.new())
      |> stream(:conversations, conversations)
      |> stream(:messages, [])
      |> stream(:colleagues, [])
      |> subscribe(conversations)
      # attached before Announcements, whose {:ack_updated, ...} hook halts
      |> attach_hook(:sidebar_acks, :handle_info, &refresh_open_row_on_ack/2)
      |> Announcements.attach()

    {:ok, socket}
  end

  defp subscribe(socket, conversations) do
    if connected?(socket) do
      :ok = Chat.subscribe_user(socket.assigns.current_scope)
      Enum.reduce(conversations, socket, &watch(&2, &1.id))
    else
      socket
    end
  end

  # Subscribes to a conversation once; `@subscribed` keeps it idempotent.
  defp watch(socket, conversation_id) do
    cond do
      not connected?(socket) ->
        socket

      MapSet.member?(socket.assigns.subscribed, conversation_id) ->
        socket

      Chat.subscribe_conversation(socket.assigns.current_scope, conversation_id) == :ok ->
        update(socket, :subscribed, &MapSet.put(&1, conversation_id))

      true ->
        socket
    end
  end

  defp unwatch(socket, conversation_id) do
    Chat.unsubscribe_conversation(conversation_id)
    update(socket, :subscribed, &MapSet.delete(&1, conversation_id))
  end

  @impl true
  def handle_params(params, _uri, socket) do
    action = socket.assigns.live_action

    case apply_action(socket, action, params) do
      {:ok, socket} -> {:noreply, Announcements.apply_action(socket, action, params)}
      {:not_found, socket} -> {:noreply, socket}
    end
  end

  defp apply_action(socket, action, %{"id" => id})
       when action in [:show, :announce, :receipts] do
    case Chat.get_conversation(socket.assigns.current_scope, id) do
      {:ok, conversation} ->
        {:ok, open_conversation(socket, conversation)}

      {:error, :not_found} ->
        socket =
          socket
          |> put_flash(:error, "That conversation isn't available.")
          |> push_navigate(to: ~p"/")

        {:not_found, socket}
    end
  end

  defp apply_action(socket, :index, _params) do
    {:ok, socket |> close_conversation() |> assign(:page_title, "Chat")}
  end

  # The new-conversation modals keep the open conversation behind them.
  defp apply_action(socket, :new_dm, _params) do
    socket =
      socket
      |> assign(:page_title, "New message")
      |> stream(:colleagues, Org.list_colleagues(socket.assigns.current_scope), reset: true)

    {:ok, socket}
  end

  defp apply_action(socket, :new_group, _params) do
    socket =
      socket
      |> assign(:page_title, "New group chat")
      |> assign(:group_form, to_form(%{"title" => "", "user_ids" => []}, as: :group))
      |> stream(:colleagues, Org.list_colleagues(socket.assigns.current_scope), reset: true)

    {:ok, socket}
  end

  defp open_conversation(socket, conversation) do
    previous = socket.assigns.conversation
    conversation = read_conversation(socket, conversation)

    socket
    |> load_conversation(previous, conversation)
    |> assign(:conversation, conversation)
    |> assign(:page_title, conversation.display_title)
    |> refresh_previous_row(previous, conversation)
    |> put_row(conversation)
  end

  # patching between :show, :announce and :receipts keeps the loaded messages
  defp load_conversation(socket, %{id: id}, %{id: id}), do: socket

  defp load_conversation(socket, _previous, conversation) do
    scope = socket.assigns.current_scope
    {:ok, messages} = Chat.list_messages(scope, conversation.id)
    {:ok, participants} = Chat.list_participants(scope, conversation.id)

    socket
    |> assign(:participant_count, length(participants))
    |> assign(:message_form, to_form(Chat.change_message()))
    |> stream(:messages, messages, reset: true)
    |> push_event("composer:reset", %{})
  end

  # Opening a conversation clears its badge. Only once connected, so the
  # dead render doesn't mark it read on its own.
  defp read_conversation(socket, %{unread_count: count} = conversation) when count > 0 do
    if connected?(socket) do
      :ok = Chat.mark_read(socket.assigns.current_scope, conversation.id)
      %{conversation | unread_count: 0}
    else
      conversation
    end
  end

  defp read_conversation(_socket, conversation), do: conversation

  defp close_conversation(%{assigns: %{conversation: nil}} = socket), do: socket

  defp close_conversation(socket) do
    previous = socket.assigns.conversation

    socket
    |> assign(:conversation, nil)
    |> stream(:messages, [], reset: true)
    |> refresh_row(previous.id)
  end

  # re-renders the previously open row so it loses its highlight
  defp refresh_previous_row(socket, %{id: id}, %{id: id}), do: socket
  defp refresh_previous_row(socket, nil, _conversation), do: socket
  defp refresh_previous_row(socket, previous, _conversation), do: refresh_row(socket, previous.id)

  @impl true
  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    case String.trim(body) do
      "" -> {:noreply, socket}
      body -> {:noreply, post_message(socket, body)}
    end
  end

  def handle_event("start_dm", %{"user_id" => user_id}, socket) do
    case Chat.start_dm(socket.assigns.current_scope, user_id) do
      {:ok, conversation} ->
        {:noreply, show_new_conversation(socket, conversation)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "You can't message that person.")}
    end
  end

  # Enter in the search box with no single match
  def handle_event("start_dm", _params, socket), do: {:noreply, socket}

  def handle_event("create_group", %{"group" => params}, socket) do
    case Chat.create_group(socket.assigns.current_scope, params) do
      {:ok, conversation} ->
        {:noreply, show_new_conversation(socket, conversation)}

      {:error, changeset} ->
        {:noreply, assign(socket, :group_form, to_form(changeset, as: :group))}
    end
  end

  def handle_event("leave_group", _params, socket) do
    %{current_scope: scope, conversation: conversation} = socket.assigns

    case Chat.leave_group(scope, conversation.id) do
      :ok ->
        socket =
          socket
          |> forget_conversation(conversation.id)
          |> assign(:conversation, nil)
          |> put_flash(:info, "You left #{conversation.display_title}.")
          |> push_patch(to: ~p"/")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "You can't leave this conversation.")}
    end
  end

  defp post_message(socket, body) do
    %{current_scope: scope, conversation: conversation} = socket.assigns

    case Chat.post_message(scope, conversation.id, %{"body" => body}) do
      # the message arrives through {:message_created, ...} like everyone else's
      {:ok, _message} ->
        socket
        |> assign(:message_form, to_form(Chat.change_message()))
        |> push_event("composer:reset", %{})

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, :message_form, to_form(changeset))

      {:error, :not_found} ->
        put_flash(socket, :error, "You can't post in this conversation any more.")
    end
  end

  defp show_new_conversation(socket, conversation) do
    socket
    |> watch(conversation.id)
    |> put_row(conversation)
    |> push_patch(to: ~p"/c/#{conversation.id}")
  end

  @impl true
  def handle_info(
        {:message_created, conversation_id, message_id},
        %{assigns: %{conversation: %{id: conversation_id}}} = socket
      ) do
    case Chat.get_message(socket.assigns.current_scope, message_id) do
      {:ok, message} ->
        {:noreply, socket |> stream_insert(:messages, message) |> read_new_message(message)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_info({:message_created, conversation_id, _message_id}, socket),
    do: {:noreply, refresh_row(socket, conversation_id)}

  def handle_info({:conversation_joined, conversation_id}, socket),
    do: {:noreply, socket |> watch(conversation_id) |> refresh_row(conversation_id)}

  def handle_info({:conversation_left, conversation_id}, socket) do
    socket = forget_conversation(socket, conversation_id)

    case socket.assigns.conversation do
      %{id: ^conversation_id} = conversation ->
        socket =
          socket
          |> put_flash(:error, "You no longer have access to #{conversation.display_title}.")
          |> push_navigate(to: ~p"/")

        {:noreply, socket}

      _other ->
        {:noreply, socket}
    end
  end

  # another tab of this user read it
  def handle_info({:conversation_read, conversation_id}, socket),
    do: {:noreply, refresh_row(socket, conversation_id)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # Someone else's message in the open conversation is read on arrival; the
  # {:conversation_read, _} broadcast then refreshes the row. Your own
  # messages leave the unread count alone, so refresh the row directly.
  defp read_new_message(socket, message) do
    scope = socket.assigns.current_scope

    if message.sender_id == scope.user.id do
      refresh_row(socket, message.conversation_id)
    else
      :ok = Chat.mark_read(scope, message.conversation_id)
      socket
    end
  end

  # Acknowledging an announcement changes the open row's pending count.
  defp refresh_open_row_on_ack(
         {:ack_updated, _message_id, _counts},
         %{assigns: %{conversation: %{id: id}}} = socket
       ),
       do: {:cont, refresh_row(socket, id)}

  defp refresh_open_row_on_ack(_message, socket), do: {:cont, socket}

  ## Sidebar

  defp refresh_row(socket, conversation_id) do
    case Chat.get_conversation(socket.assigns.current_scope, conversation_id) do
      {:ok, conversation} -> put_row(socket, conversation)
      {:error, :not_found} -> socket
    end
  end

  # Inserts or updates a row, moving it when its position changes.
  defp put_row(socket, conversation) do
    conversation = keep_read(socket, conversation)
    entry = sidebar_entry(conversation)
    old_index = Enum.find_index(socket.assigns.sidebar, &(&1.id == entry.id))
    rest = Enum.reject(socket.assigns.sidebar, &(&1.id == entry.id))
    index = Enum.find_index(rest, &(&1.key > entry.key)) || length(rest)
    socket = assign(socket, :sidebar, List.insert_at(rest, index, entry))
    at = if index == length(rest), do: -1, else: index

    cond do
      old_index == index ->
        stream_insert(socket, :conversations, conversation)

      is_nil(old_index) ->
        stream_insert(socket, :conversations, conversation, at: at)

      true ->
        socket
        |> stream_delete(:conversations, conversation)
        |> stream_insert(:conversations, conversation, at: at)
    end
  end

  # The open conversation is read on arrival; a refetch racing mark_read
  # must not flash a badge on it.
  defp keep_read(%{assigns: %{conversation: %{id: id}}}, %{id: id} = conversation),
    do: %{conversation | unread_count: 0}

  defp keep_read(_socket, conversation), do: conversation

  defp forget_conversation(socket, conversation_id) do
    socket
    |> unwatch(conversation_id)
    |> update(:sidebar, fn sidebar -> Enum.reject(sidebar, &(&1.id == conversation_id)) end)
    |> stream_delete_by_dom_id(:conversations, "conversations-#{conversation_id}")
  end

  # Mirrors Chat.list_conversations/1: kind, then most recent message
  # (never-messaged last), then title, then id.
  defp sidebar_entry(conversation) do
    recency =
      if conversation.last_message_at,
        do: -DateTime.to_unix(conversation.last_message_at, :microsecond),
        else: :never

    key =
      {@kind_rank[conversation.kind], recency, is_nil(conversation.title), conversation.title,
       conversation.id}

    %{id: conversation.id, key: key}
  end

  defp open?(%{id: id}, %{id: id}), do: true
  defp open?(_open, _conversation), do: false

  defp return_path(nil), do: ~p"/"
  defp return_path(conversation), do: ~p"/c/#{conversation.id}"

  defp people_label(1), do: "1 person"
  defp people_label(count), do: "#{count} people"
end
