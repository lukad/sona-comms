defmodule SonaCommsWeb.ChatLive.Announcements do
  @moduledoc """
  Announcement behaviour attached to `SonaCommsWeb.ChatLive`.

  WP1 stub, owned by WP2b: it only sets defaults. WP2b attaches the
  `:handle_event` and `:handle_info` hooks described in PLAN.md §6.1.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 3]

  @doc """
  Assigns the announcement defaults. Called from `ChatLive.mount/3`.
  """
  def attach(socket) do
    socket
    |> assign(:announcement_form, nil)
    |> assign(:receipt_summary, nil)
    |> stream(:pending_receipts, [])
    |> stream(:read_receipts, [])
  end

  @doc """
  Fills the modal assigns for `:announce` and `:receipts`. Called from
  `ChatLive.handle_params/3`.
  """
  def apply_action(socket, _live_action, _params), do: socket
end
