defmodule SonaCommsWeb.ChatLive do
  @moduledoc """
  The chat: a sidebar of conversations and the open conversation.

  WP1 stub, owned by WP2a. Keep the seams in PLAN.md §6.1: the
  `Announcements.attach/1` and `Announcements.apply_action/3` calls, the
  `:conversations` and `:messages` streams, and the announcement call sites.
  """
  use SonaCommsWeb, :live_view

  alias SonaComms.Accounts
  alias SonaComms.Chat
  alias SonaCommsWeb.AnnouncementComponents
  alias SonaCommsWeb.ChatLive.Announcements

  on_mount {SonaCommsWeb.OrgAuth, :require_member}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} full_bleed>
      <div class="flex h-full">
        <aside class="w-72 shrink-0 overflow-y-auto border-r border-base-300 bg-base-200/40">
          <ul id="conversations" phx-update="stream" class="space-y-0.5 p-2">
            <li :for={{dom_id, conversation} <- @streams.conversations} id={dom_id}>
              <.link
                patch={~p"/c/#{conversation.id}"}
                class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm transition hover:bg-base-300/60"
              >
                <span class="flex-1 truncate">{conversation.display_title}</span>
                <span
                  :if={conversation.pending_ack_count > 0}
                  id={"pending-acks-#{conversation.id}"}
                  class="badge badge-sm badge-warning"
                >
                  <.icon name="hero-megaphone-micro" class="size-3" />
                  {announcements_label(conversation.pending_ack_count)}
                </span>
                <span
                  :if={conversation.unread_count > 0}
                  id={"unread-#{conversation.id}"}
                  aria-label={"#{conversation.unread_count} unread messages"}
                  class="badge badge-sm badge-primary"
                >
                  {conversation.unread_count}
                </span>
              </.link>
            </li>
          </ul>
        </aside>

        <section :if={@conversation} class="flex min-w-0 flex-1 flex-col">
          <header
            id="conversation-header"
            class="flex items-center gap-3 border-b border-base-300 px-6 py-3"
          >
            <h1 class="flex-1 truncate font-semibold">{@conversation.display_title}</h1>
            <AnnouncementComponents.announce_button conversation={@conversation} />
          </header>

          <div id="messages" phx-update="stream" class="flex-1 space-y-3 overflow-y-auto px-6 py-4">
            <div :for={{dom_id, msg} <- @streams.messages} id={dom_id}>
              <AnnouncementComponents.announcement_message
                :if={msg.kind == :announcement}
                message={msg}
                conversation={@conversation}
                current_scope={@current_scope}
              />
              <div :if={msg.kind == :text} class="text-sm">
                <p class="font-medium">{Accounts.display_name(msg.sender)}</p>
                <p class="whitespace-pre-line">{msg.body}</p>
              </div>
            </div>
          </div>
        </section>
      </div>

      <AnnouncementComponents.announcement_modal
        :if={@live_action in [:announce, :receipts]}
        live_action={@live_action}
        conversation={@conversation}
        form={@announcement_form}
        summary={@receipt_summary}
        pending_receipts={@streams.pending_receipts}
        read_receipts={@streams.read_receipts}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Chat.subscribe_user(scope)

    {:ok,
     socket
     |> assign(:conversation, nil)
     |> stream(:conversations, Chat.list_conversations(scope))
     |> stream(:messages, [])
     |> Announcements.attach()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = open_conversation(socket, socket.assigns.live_action, params)
    {:noreply, Announcements.apply_action(socket, socket.assigns.live_action, params)}
  end

  defp open_conversation(socket, action, %{"id" => id})
       when action in [:show, :announce, :receipts] do
    case Chat.get_conversation(socket.assigns.current_scope, id) do
      {:ok, conversation} ->
        socket
        |> load_messages(conversation)
        |> assign(:conversation, conversation)
        |> assign(:page_title, conversation.display_title)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "That conversation isn't available.")
        |> push_navigate(to: ~p"/")
    end
  end

  defp open_conversation(socket, _action, _params) do
    socket
    |> close_conversation()
    |> assign(:conversation, nil)
    |> stream(:messages, [], reset: true)
  end

  # patching between :show, :announce and :receipts keeps the loaded messages
  defp load_messages(%{assigns: %{conversation: %{id: id}}} = socket, %{id: id}), do: socket

  defp load_messages(socket, conversation) do
    scope = socket.assigns.current_scope
    socket = close_conversation(socket)
    if connected?(socket), do: Chat.subscribe_conversation(scope, conversation.id)
    {:ok, messages} = Chat.list_messages(scope, conversation.id)
    stream(socket, :messages, messages, reset: true)
  end

  defp close_conversation(%{assigns: %{conversation: %{id: id}}} = socket) do
    Chat.unsubscribe_conversation(id)
    socket
  end

  defp close_conversation(socket), do: socket

  @impl true
  def handle_info(
        {:message_created, conversation_id, message_id},
        %{assigns: %{conversation: %{id: conversation_id}}} = socket
      ) do
    case Chat.get_message(socket.assigns.current_scope, message_id) do
      {:ok, message} -> {:noreply, stream_insert(socket, :messages, message)}
      {:error, :not_found} -> {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp announcements_label(1), do: "1 announcement"
  defp announcements_label(count), do: "#{count} announcements"
end
