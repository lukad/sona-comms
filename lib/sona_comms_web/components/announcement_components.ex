defmodule SonaCommsWeb.AnnouncementComponents do
  @moduledoc """
  Announcement components rendered by `SonaCommsWeb.ChatLive`.

  WP1 stub with plain markup, owned by WP2b.
  """
  use SonaCommsWeb, :html

  alias SonaComms.Accounts

  attr :conversation, :map, required: true

  def announce_button(assigns) do
    ~H"""
    <.link
      :if={@conversation.can_announce}
      id="announce-button"
      patch={~p"/c/#{@conversation.id}/announce"}
      class="btn btn-sm btn-soft btn-warning"
    >
      <.icon name="hero-megaphone" class="size-4" /> Announce
    </.link>
    """
  end

  attr :message, :map, required: true
  attr :conversation, :map, required: true
  attr :current_scope, :map, required: true

  def announcement_message(assigns) do
    ~H"""
    <article class="rounded-box border border-warning/40 bg-warning/10 p-4">
      <p class="mb-1 flex items-center gap-1.5 text-xs font-semibold tracking-wide text-warning uppercase">
        <.icon name="hero-megaphone-micro" class="size-3.5" />
        Announcement · {Accounts.display_name(@message.sender)}
      </p>
      <p class="text-sm whitespace-pre-line">{@message.body}</p>
    </article>
    """
  end

  attr :live_action, :atom, required: true
  attr :conversation, :map, required: true
  attr :form, :any, default: nil
  attr :summary, :any, default: nil
  attr :pending_receipts, :any, required: true
  attr :read_receipts, :any, required: true

  def announcement_modal(assigns) do
    ~H"""
    <.modal id="announcement-modal" show on_cancel={JS.patch(~p"/c/#{@conversation.id}")}>
      <h2 id="announcement-modal-title" class="text-lg font-semibold">
        {if @live_action == :announce, do: "New announcement", else: "Who has read this"}
      </h2>
      <p id="announcement-modal-description" class="mt-2 text-sm text-base-content/70">
        Coming soon.
      </p>
    </.modal>
    """
  end
end
