defmodule SonaCommsWeb.ChatLive.Announcements do
  @moduledoc """
  Announcement behaviour attached to `SonaCommsWeb.ChatLive` (PLAN.md §6.1).

  ChatLive has no announcement code of its own. `attach/1` assigns the modal
  defaults, loads the viewer's pending announcements and attaches two hooks:

    * `:handle_event` handles `"validate_announcement"`, `"announce"` and
      `"acknowledge"`, and halts;
    * `:handle_info` handles `{:ack_updated, message_id, counts}` and halts.
      It refetches the message with `Chat.get_message/2`, because `my_ack` is
      per viewer and never comes from the broadcast (ADR 0005), updates it in
      the `:messages` stream and refreshes the receipts modal if it's open.
      It also watches `{:message_created, ...}` and `{:conversation_left, _}`
      to keep the pending announcements current, and continues.

  Pending announcements (the viewer's unacknowledged receipts):

    * `@pending_announcement_count` - the sidebar's "Announcements" badge;
    * `@urgent_announcement` - the first pending `:high` one, shown in a modal
      the viewer can't dismiss until they've read it;
    * the `:pending_announcements` stream - the `:announcements` list.

  `apply_action/3` fills `@announcement_form` for `:announce`,
  `@receipt_summary` plus the `:pending_receipts` and `:read_receipts`
  streams for `:receipts`, and the `:pending_announcements` stream for
  `:announcements`.
  """
  use SonaCommsWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView

  alias SonaComms.Chat

  @events ["validate_announcement", "announce", "acknowledge"]

  @doc """
  Assigns the announcement defaults and attaches the hooks. Called from
  `ChatLive.mount/3`.
  """
  def attach(socket) do
    socket
    |> assign(:announcement_form, nil)
    |> assign(:receipt_summary, nil)
    |> stream(:pending_receipts, [])
    |> stream(:read_receipts, [])
    |> reload_pending()
    |> attach_hook(:announcement_events, :handle_event, &handle_event/3)
    |> attach_hook(:announcement_updates, :handle_info, &handle_info/2)
  end

  @doc """
  Fills the modal assigns for `:announce` and `:receipts` and the pending
  list for `:announcements`, and clears the modal assigns for other actions.
  Called from `ChatLive.handle_params/3` after it has assigned
  `@conversation`.
  """
  def apply_action(socket, live_action, params)
      when live_action in [:announce, :receipts] do
    case socket.assigns[:conversation] do
      # ChatLive is already navigating away when the conversation didn't load
      %{id: id} = conversation when is_map_key(params, "id") ->
        if to_string(id) == params["id"],
          do: open_modal(socket, live_action, conversation, params),
          else: socket

      _ ->
        socket
    end
  end

  # the stream is only rendered here, so it is refilled on every visit
  def apply_action(socket, :announcements, _params) do
    socket
    |> close_modals()
    |> reload_pending()
  end

  def apply_action(socket, _live_action, _params), do: close_modals(socket)

  defp close_modals(socket) do
    socket
    |> assign(:announcement_form, nil)
    |> assign(:receipt_summary, nil)
  end

  defp open_modal(socket, :announce, %{can_announce: true}, _params) do
    assign(socket, :announcement_form, to_form(Chat.change_announcement(), as: :message))
  end

  defp open_modal(socket, :announce, conversation, _params) do
    socket
    |> put_flash(:error, "You can't post announcements in this chat.")
    |> push_patch(to: ~p"/c/#{conversation.id}")
  end

  defp open_modal(socket, :receipts, conversation, %{"message_id" => message_id}) do
    case load_receipts(socket, conversation, message_id) do
      {:ok, socket} ->
        socket

      {:error, reason} ->
        socket
        |> put_flash(:error, receipts_error(reason))
        |> push_patch(to: ~p"/c/#{conversation.id}")
    end
  end

  defp receipts_error(:unauthorized),
    do: "Only the sender and whoever can announce here can see who has read it."

  defp receipts_error(:not_found), do: "That announcement isn't available."

  defp load_receipts(socket, %{id: conversation_id}, message_id) do
    scope = socket.assigns.current_scope

    with {:ok, %{conversation_id: ^conversation_id} = message} <-
           Chat.get_message(scope, message_id),
         {:ok, receipts} <- Chat.list_receipts(scope, message.id) do
      {read, pending} = Enum.split_with(receipts, & &1.acknowledged_at)
      summary = %{message: message, acknowledged: length(read), total: length(receipts)}

      {:ok,
       socket
       |> assign(:receipt_summary, summary)
       |> stream(:pending_receipts, pending, reset: true)
       |> stream(:read_receipts, read, reset: true)}
    else
      {:ok, _message_elsewhere} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Hooks

  defp handle_event("validate_announcement", %{"message" => params}, socket) do
    form = params |> Chat.change_announcement() |> to_form(action: :validate)
    {:halt, assign(socket, :announcement_form, form)}
  end

  defp handle_event(
         "announce",
         %{"message" => params},
         %{assigns: %{conversation: %{id: conversation_id}}} = socket
       ) do
    case Chat.post_announcement(socket.assigns.current_scope, conversation_id, params) do
      {:ok, message} ->
        {:halt,
         socket
         |> stream_insert(:messages, message)
         |> put_flash(:info, "Announcement sent.")
         |> push_patch(to: ~p"/c/#{conversation_id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:halt, assign(socket, :announcement_form, to_form(changeset, action: :insert))}

      {:error, _reason} ->
        {:halt,
         socket
         |> put_flash(:error, "You can't post announcements here any more.")
         |> push_patch(to: ~p"/c/#{conversation_id}")}
    end
  end

  defp handle_event("acknowledge", %{"id" => message_id}, socket) do
    case Chat.acknowledge(socket.assigns.current_scope, message_id) do
      {:ok, receipt} ->
        {:halt, refresh_message(socket, receipt.message_id)}

      {:error, :not_found} ->
        {:halt, put_flash(socket, :error, "That announcement isn't available any more.")}
    end
  end

  defp handle_event(event, _params, socket) when event in @events, do: {:halt, socket}
  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_info({:ack_updated, message_id, _counts}, socket),
    do: {:halt, refresh_message(socket, message_id)}

  # ChatLive renders the message; this only picks up a new announcement for us
  defp handle_info({:message_created, _conversation_id, message_id}, socket) do
    case Chat.get_message(socket.assigns.current_scope, message_id) do
      {:ok, %{my_ack: :pending}} -> {:cont, reload_pending(socket)}
      _other -> {:cont, socket}
    end
  end

  # leaving deletes our pending receipts there
  defp handle_info({:conversation_left, _conversation_id}, socket),
    do: {:cont, reload_pending(socket)}

  defp handle_info(_message, socket), do: {:cont, socket}

  # Refetches through Chat for the viewer's own my_ack, never from a broadcast
  defp refresh_message(socket, message_id) do
    case Chat.get_message(socket.assigns.current_scope, message_id) do
      {:ok, message} ->
        socket
        |> update_open_message(message)
        |> refresh_receipts(message)
        |> refresh_sidebar_row(message)
        |> refresh_pending(message)

      {:error, :not_found} ->
        refresh_pending(socket, %{id: message_id, my_ack: nil})
    end
  end

  # Only a pending announcement of ours that is no longer pending changes the list
  defp refresh_pending(socket, %{id: message_id, my_ack: my_ack}) do
    if my_ack != :pending and MapSet.member?(socket.assigns.pending_announcement_ids, message_id),
      do: reload_pending(socket),
      else: socket
  end

  defp reload_pending(socket) do
    pending = Chat.list_pending_announcements(socket.assigns.current_scope)

    socket
    |> assign(:pending_announcement_ids, MapSet.new(pending, & &1.id))
    |> assign(:pending_announcement_count, length(pending))
    |> assign(:urgent_announcement, Enum.find(pending, &(&1.priority == :high)))
    |> stream(:pending_announcements, pending, reset: true)
  end

  # update_only: an old announcement outside the loaded page mustn't be appended
  defp update_open_message(
         %{assigns: %{conversation: %{id: conversation_id}}} = socket,
         %{conversation_id: conversation_id} = message
       ),
       do: stream_insert(socket, :messages, message, update_only: true)

  defp update_open_message(socket, _message), do: socket

  defp refresh_receipts(
         %{
           assigns: %{
             live_action: :receipts,
             conversation: conversation,
             receipt_summary: %{message: %{id: message_id}}
           }
         } = socket,
         %{id: message_id}
       ) do
    case load_receipts(socket, conversation, message_id) do
      {:ok, socket} -> socket
      {:error, _reason} -> socket
    end
  end

  defp refresh_receipts(socket, _message), do: socket

  # Only the viewer's own acknowledgement changes their "1 announcement" pill
  defp refresh_sidebar_row(socket, %{my_ack: :acknowledged, conversation_id: conversation_id}) do
    case Chat.get_conversation(socket.assigns.current_scope, conversation_id) do
      {:ok, conversation} ->
        stream_insert(socket, :conversations, conversation, update_only: true)

      {:error, :not_found} ->
        socket
    end
  end

  defp refresh_sidebar_row(socket, _message), do: socket
end
