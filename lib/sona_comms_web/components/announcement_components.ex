defmodule SonaCommsWeb.AnnouncementComponents do
  @moduledoc """
  Announcement components rendered by `SonaCommsWeb.ChatLive` (PLAN.md §6.1).

  The UI says "read" (ADR 0005): "I've read this", "X of Y read", and the
  "Read" / "Not yet read" lists. Code names such as acknowledge and receipt
  never appear in the copy.
  """
  use SonaCommsWeb, :html

  alias SonaComms.Accounts

  @doc """
  The header's "Announce" button. Renders only when the current user may
  announce in the conversation.
  """
  attr :conversation, :map, required: true

  def announce_button(assigns) do
    ~H"""
    <.link
      :if={@conversation.can_announce}
      id="announce-button"
      patch={~p"/c/#{@conversation.id}/announce"}
      class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-amber-300 bg-amber-50 px-3 py-1.5 text-sm font-medium text-amber-800 shadow-xs transition hover:-translate-y-px hover:border-amber-400 hover:bg-amber-100 hover:shadow-sm active:translate-y-0 dark:border-amber-400/30 dark:bg-amber-400/10 dark:text-amber-200 dark:hover:bg-amber-400/20"
    >
      <.icon name="hero-megaphone-mini" class="size-4" /> Announce
    </.link>
    """
  end

  @doc """
  An announcement card in the message stream.

  Recipients get "I've read this" (`#ack-<id>`), which turns into
  "Read at 14:02" (`#acked-<id>`). The sender and anyone who can announce in
  the conversation see "X of Y read" (`#ack-summary-<id>`), linking to the
  receipts modal.
  """
  attr :message, :map, required: true
  attr :conversation, :map, required: true
  attr :current_scope, :map, required: true

  def announcement_message(assigns) do
    assigns =
      assign(
        assigns,
        :show_summary?,
        assigns.message.sender_id == assigns.current_scope.user.id or
          assigns.conversation.can_announce
      )

    ~H"""
    <article
      id={"announcement-#{@message.id}"}
      class="relative overflow-hidden rounded-2xl border border-amber-200 bg-gradient-to-br from-amber-50 to-orange-50/40 shadow-sm dark:border-amber-400/25 dark:from-amber-400/10 dark:to-amber-400/5"
    >
      <div
        class={["absolute inset-y-0 left-0 w-1", priority_bar(@message.priority)]}
        aria-hidden="true"
      />
      <div class="py-4 pr-4 pl-5">
        <header class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
          <span class="inline-flex items-center gap-1 rounded-full bg-amber-400/20 px-2 py-0.5 font-semibold tracking-wide text-amber-800 uppercase dark:text-amber-200">
            <.icon name="hero-megaphone-micro" class="size-3.5" /> Announcement
          </span>
          <.priority_badge id={"announcement-#{@message.id}-priority"} priority={@message.priority} />
          <span class="font-medium text-base-content/80">
            {Accounts.display_name(@message.sender)}
          </span>
          <span class="text-base-content/50">
            <.local_time id={"announcement-#{@message.id}-at"} at={@message.inserted_at} />
          </span>
        </header>

        <p class="mt-2 text-[15px] leading-relaxed break-words whitespace-pre-line text-base-content">
          {@message.body}
        </p>

        <footer
          :if={@message.my_ack || @show_summary?}
          class="mt-3 flex flex-wrap items-center gap-3 border-t border-amber-200/80 pt-3 dark:border-amber-400/20"
        >
          <button
            :if={@message.my_ack == :pending}
            id={"ack-#{@message.id}"}
            type="button"
            phx-click="acknowledge"
            phx-value-id={@message.id}
            phx-disable-with="Saving…"
            class="inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-amber-500 px-4 py-1.5 text-sm font-semibold text-white shadow-sm ring-1 ring-amber-600/20 transition hover:-translate-y-px hover:bg-amber-600 hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-500 active:translate-y-0"
          >
            <.icon name="hero-check-mini" class="size-4" /> I've read this
          </button>

          <span
            :if={@message.my_ack == :acknowledged}
            id={"acked-#{@message.id}"}
            class="inline-flex items-center gap-1.5 text-sm font-medium text-emerald-700 motion-safe:animate-[fade-in_300ms_ease-out] dark:text-emerald-300"
          >
            <.icon name="hero-check-circle-mini" class="size-4" /> Read at
            <.local_time
              :if={@message.my_acknowledged_at}
              id={"acked-#{@message.id}-at"}
              at={@message.my_acknowledged_at}
            />
          </span>

          <.link
            :if={@show_summary?}
            id={"ack-summary-#{@message.id}"}
            patch={~p"/c/#{@message.conversation_id}/announcements/#{@message.id}"}
            class="group ml-auto inline-flex items-center gap-2.5 rounded-full px-2 py-1 text-sm text-base-content/70 transition hover:bg-amber-400/15 hover:text-base-content"
          >
            <.read_progress read={@message.ack_count} total={@message.recipient_count} />
            <span class="font-medium tabular-nums">
              {@message.ack_count} of {@message.recipient_count} read
            </span>
            <.icon
              name="hero-chevron-right-micro"
              class="size-4 opacity-50 transition group-hover:translate-x-0.5 group-hover:opacity-100"
            />
          </.link>
        </footer>
      </div>
    </article>
    """
  end

  @doc """
  The modal for `:announce` (`#announcement-form`) and `:receipts`
  (`#receipts-modal`, with the `#pending-receipts` and `#read-receipts`
  streams).
  """
  attr :live_action, :atom, required: true
  attr :conversation, :map, required: true
  attr :form, :any, default: nil
  attr :summary, :any, default: nil
  attr :pending_receipts, :any, required: true
  attr :read_receipts, :any, required: true

  def announcement_modal(%{live_action: :announce} = assigns) do
    ~H"""
    <.modal
      :if={@conversation && @form}
      id="announcement-modal"
      show
      on_cancel={JS.patch(~p"/c/#{@conversation.id}")}
    >
      <div class="flex items-start gap-3 pr-8">
        <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-amber-100 text-amber-700 dark:bg-amber-400/15 dark:text-amber-200">
          <.icon name="hero-megaphone" class="size-5" />
        </span>
        <div>
          <h2 id="announcement-modal-title" class="text-lg font-semibold tracking-tight">
            New announcement
          </h2>
          <p id="announcement-modal-description" class="mt-0.5 text-sm text-base-content/70">
            Everyone in
            <span class="font-medium text-base-content">{@conversation.display_title}</span>
            will be asked to confirm they've read it.
          </p>
        </div>
      </div>

      <.form
        for={@form}
        id="announcement-form"
        phx-change="validate_announcement"
        phx-submit="announce"
        class="mt-5"
      >
        <.input
          field={@form[:body]}
          type="textarea"
          rows="5"
          maxlength="4000"
          phx-debounce="300"
          placeholder="e.g. Allergen update: new sesame-containing supplier from Monday."
          class="w-full resize-y rounded-xl border border-base-300 bg-base-100 px-3.5 py-3 text-[15px] leading-relaxed shadow-xs transition outline-none placeholder:text-base-content/40 focus:border-amber-400 focus:ring-4 focus:ring-amber-400/20"
          error_class="border-error focus:border-error focus:ring-error/20"
        />
        <.priority_picker field={@form[:priority]} />
        <div class="mt-5 flex items-center justify-end gap-2">
          <.link
            patch={~p"/c/#{@conversation.id}"}
            class="rounded-full px-4 py-2 text-sm font-medium text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
          >
            Cancel
          </.link>
          <button
            type="submit"
            phx-disable-with="Sending…"
            class="inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-amber-500 px-5 py-2 text-sm font-semibold text-white shadow-sm ring-1 ring-amber-600/20 transition hover:-translate-y-px hover:bg-amber-600 hover:shadow-md active:translate-y-0"
          >
            <.icon name="hero-paper-airplane-mini" class="size-4" /> Send announcement
          </button>
        </div>
      </.form>
    </.modal>
    """
  end

  def announcement_modal(%{live_action: :receipts} = assigns) do
    ~H"""
    <.modal
      :if={@conversation && @summary}
      id="receipts-modal"
      show
      on_cancel={JS.patch(~p"/c/#{@conversation.id}")}
    >
      <div class="pr-8">
        <h2 id="receipts-modal-title" class="text-lg font-semibold tracking-tight">
          Who has read this
        </h2>
        <p
          id="receipts-modal-description"
          class="mt-1 line-clamp-2 text-sm text-base-content/70"
        >
          {@summary.message.body}
        </p>
      </div>

      <div
        id="receipts-summary"
        class="mt-4 flex items-center gap-4 rounded-xl bg-amber-50 px-4 py-3 dark:bg-amber-400/10"
      >
        <p class="text-sm text-base-content/70">
          <span class="text-2xl font-semibold text-base-content tabular-nums">
            {@summary.acknowledged}
          </span>
          of {@summary.total} read
        </p>
        <div class="flex-1">
          <.read_progress read={@summary.acknowledged} total={@summary.total} class="h-2 w-full" />
        </div>
      </div>

      <div class="mt-5 grid gap-5 sm:grid-cols-2">
        <section aria-labelledby="pending-receipts-heading">
          <h3
            id="pending-receipts-heading"
            class="mb-2 flex items-center gap-1.5 text-xs font-semibold tracking-wide text-base-content/60 uppercase"
          >
            <span class="size-1.5 rounded-full bg-amber-400" /> Not yet read
            <span class="tabular-nums">· {@summary.total - @summary.acknowledged}</span>
          </h3>
          <ul
            id="pending-receipts"
            phx-update="stream"
            class="max-h-72 space-y-0.5 overflow-y-auto pr-1"
          >
            <li
              id="pending-receipts-empty"
              class="hidden py-2 text-sm text-base-content/50 only:block"
            >
              Everyone has read it.
            </li>
            <li :for={{dom_id, receipt} <- @pending_receipts} id={dom_id}>
              <.person user={receipt.user} />
            </li>
          </ul>
        </section>

        <section aria-labelledby="read-receipts-heading">
          <h3
            id="read-receipts-heading"
            class="mb-2 flex items-center gap-1.5 text-xs font-semibold tracking-wide text-base-content/60 uppercase"
          >
            <span class="size-1.5 rounded-full bg-emerald-500" /> Read
            <span class="tabular-nums">· {@summary.acknowledged}</span>
          </h3>
          <ul id="read-receipts" phx-update="stream" class="max-h-72 space-y-0.5 overflow-y-auto pr-1">
            <li id="read-receipts-empty" class="hidden py-2 text-sm text-base-content/50 only:block">
              Nobody yet.
            </li>
            <li :for={{dom_id, receipt} <- @read_receipts} id={dom_id}>
              <.person user={receipt.user}>
                <.local_time
                  id={"#{dom_id}-at"}
                  at={receipt.acknowledged_at}
                  class="text-xs text-base-content/50 tabular-nums"
                />
              </.person>
            </li>
          </ul>
        </section>
      </div>
    </.modal>
    """
  end

  def announcement_modal(assigns), do: ~H""

  defp priorities, do: [:low, :mid, :high]

  attr :field, Phoenix.HTML.FormField, required: true

  defp priority_picker(assigns) do
    assigns = assign(assigns, :selected, to_string(assigns.field.value))

    ~H"""
    <fieldset id="announcement-priority" class="mt-4">
      <legend class="mb-2 text-sm font-medium text-base-content">Priority</legend>
      <div class="grid grid-cols-3 gap-2">
        <label
          :for={priority <- priorities()}
          for={"#{@field.id}-#{priority}"}
          class={[
            "flex cursor-pointer items-center justify-center gap-1.5 rounded-xl border px-3 py-2 text-sm font-medium transition duration-150 has-focus-visible:ring-4",
            if(@selected == to_string(priority),
              do: priority_selected(priority),
              else:
                "border-base-300 text-base-content/70 hover:border-base-content/30 hover:bg-base-200/60 hover:text-base-content"
            )
          ]}
        >
          <input
            type="radio"
            id={"#{@field.id}-#{priority}"}
            name={@field.name}
            value={priority}
            checked={@selected == to_string(priority)}
            class="sr-only"
          />
          <.icon name={priority_icon(priority)} class="size-4" />
          {priority_label(priority)}
        </label>
      </div>
      <p id="announcement-priority-help" class="mt-2 text-xs text-base-content/60">
        {priority_help(@selected)}
      </p>
    </fieldset>
    """
  end

  defp priority_selected(:low),
    do: "border-base-content/30 bg-base-200 text-base-content ring-base-content/10"

  defp priority_selected(:mid),
    do:
      "border-amber-400 bg-amber-50 text-amber-800 ring-amber-400/20 dark:bg-amber-400/10 dark:text-amber-200"

  defp priority_selected(:high),
    do:
      "border-red-400 bg-red-50 text-red-700 ring-red-400/20 dark:bg-red-400/10 dark:text-red-300"

  defp priority_help("low"), do: "No rush. It waits in everyone's announcements list."

  defp priority_help("high"),
    do: "Everyone has to read it before they can do anything else in the app."

  defp priority_help(_mid),
    do: "It waits in everyone's announcements list, above low priority ones."

  @doc """
  A "High", "Mid" or "Low priority" pill.
  """
  attr :priority, :atom, required: true
  attr :id, :string, default: nil

  def priority_badge(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold ring-1 ring-inset",
        priority_badge_class(@priority)
      ]}
    >
      <.icon name={priority_icon(@priority)} class="size-3.5" />
      {priority_label(@priority)} priority
    </span>
    """
  end

  defp priority_badge_class(:high),
    do: "bg-red-500/10 text-red-700 ring-red-500/25 dark:text-red-300"

  defp priority_badge_class(:low),
    do: "bg-base-content/5 text-base-content/60 ring-base-content/10"

  defp priority_badge_class(_mid),
    do: "bg-amber-400/15 text-amber-800 ring-amber-400/30 dark:text-amber-200"

  defp priority_bar(:high), do: "bg-red-500"
  defp priority_bar(:low), do: "bg-base-content/20"
  defp priority_bar(_mid), do: "bg-amber-400"

  defp priority_icon(:high), do: "hero-exclamation-triangle-micro"
  defp priority_icon(:low), do: "hero-arrow-down-micro"
  defp priority_icon(_mid), do: "hero-minus-micro"

  defp priority_label(:high), do: "High"
  defp priority_label(:low), do: "Low"
  defp priority_label(_mid), do: "Mid"

  @doc """
  The modal for a pending high priority announcement
  (`#urgent-announcement-modal`). It can't be dismissed: it goes away when
  "I've read this" (`#urgent-ack-<id>`) acknowledges it, and the next one
  takes its place.
  """
  attr :message, :map, required: true

  def urgent_announcement_modal(assigns) do
    ~H"""
    <.modal id="urgent-announcement-modal" show dismissible={false}>
      <div class="flex items-start gap-3">
        <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-red-100 text-red-600 dark:bg-red-400/15 dark:text-red-300">
          <.icon name="hero-exclamation-triangle" class="size-5" />
        </span>
        <div class="min-w-0">
          <h2 id="urgent-announcement-modal-title" class="text-lg font-semibold tracking-tight">
            Please read this now
          </h2>
          <p class="mt-0.5 text-sm text-base-content/70">
            High priority announcement from
            <span class="font-medium text-base-content">
              {Accounts.display_name(@message.sender)}
            </span>
            in <span class="font-medium text-base-content">{@message.conversation.title}</span>
          </p>
        </div>
      </div>

      <p
        id="urgent-announcement-modal-description"
        class="mt-5 max-h-80 overflow-y-auto rounded-xl border border-red-200 bg-red-50/60 px-4 py-3 text-[15px] leading-relaxed break-words whitespace-pre-line text-base-content dark:border-red-400/25 dark:bg-red-400/5"
      >
        {@message.body}
      </p>

      <div class="mt-5 flex items-center justify-between gap-3">
        <span class="text-xs text-base-content/50">
          Sent <.local_time id={"urgent-announcement-#{@message.id}-at"} at={@message.inserted_at} />
        </span>
        <button
          id={"urgent-ack-#{@message.id}"}
          type="button"
          phx-click="acknowledge"
          phx-value-id={@message.id}
          phx-disable-with="Saving…"
          class="inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-red-600 px-5 py-2 text-sm font-semibold text-white shadow-sm ring-1 ring-red-700/20 transition hover:-translate-y-px hover:bg-red-700 hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600 active:translate-y-0"
        >
          <.icon name="hero-check-mini" class="size-4" /> I've read this
        </button>
      </div>
    </.modal>
    """
  end

  @doc """
  The sidebar entry for the `:announcements` list (`#announcements-link`),
  with the number still to read (`#pending-announcements-count`).
  """
  attr :count, :integer, required: true
  attr :active, :boolean, default: false

  def announcements_link(assigns) do
    ~H"""
    <.link
      id="announcements-link"
      patch={~p"/announcements"}
      aria-current={@active && "page"}
      class={[
        "flex items-center gap-3 rounded-xl px-2.5 py-2 transition-colors duration-150",
        if(@active,
          do: "bg-primary/10 ring-1 ring-primary/15 ring-inset",
          else: "hover:bg-base-300/50"
        )
      ]}
    >
      <span
        aria-hidden="true"
        class="grid size-9 shrink-0 place-items-center rounded-xl bg-amber-400/15 text-amber-700 dark:text-amber-300"
      >
        <.icon name="hero-megaphone" class="size-[1.1rem]" />
      </span>
      <span class="min-w-0 flex-1">
        <span class={[
          "block truncate text-sm",
          if(@count > 0,
            do: "font-semibold text-base-content",
            else: "font-medium text-base-content/85"
          )
        ]}>
          Announcements
        </span>
        <span class="block truncate text-xs text-base-content/45">
          {if @count > 0, do: "Waiting for you to read", else: "You're all caught up"}
        </span>
      </span>
      <span
        :if={@count > 0}
        id="pending-announcements-count"
        aria-label={"#{@count} announcements to read"}
        class="grid h-5 min-w-5 place-items-center rounded-full bg-amber-500 px-1.5 text-[11px] font-bold text-white tabular-nums shadow-sm"
      >
        {@count}
      </span>
    </.link>
    """
  end

  @doc """
  The `:announcements` pane: every announcement the viewer still has to read
  (`#pending-announcements`), most urgent first, each with its own
  "I've read this" (`#list-ack-<id>`).
  """
  attr :count, :integer, required: true
  attr :announcements, :any, required: true, doc: "the `:pending_announcements` stream"

  def pending_announcements(assigns) do
    ~H"""
    <section id="announcements-pane" class="flex min-w-0 flex-1 flex-col bg-base-100">
      <header class="flex shrink-0 items-center gap-3 border-b border-base-300 px-3 py-2.5 sm:px-6">
        <.link
          patch={~p"/"}
          aria-label="Back to chats"
          class="-ml-1 grid size-8 place-items-center rounded-lg text-base-content/70 transition hover:bg-base-200 md:hidden"
        >
          <.icon name="hero-chevron-left" class="size-5" />
        </.link>
        <span class="grid size-9 shrink-0 place-items-center rounded-xl bg-amber-400/15 text-amber-700 dark:text-amber-300">
          <.icon name="hero-megaphone" class="size-[1.1rem]" />
        </span>
        <div class="min-w-0 flex-1">
          <h1 class="truncate leading-tight font-semibold">Announcements</h1>
          <p class="truncate text-xs text-base-content/55">
            {to_read_label(@count)}
          </p>
        </div>
      </header>

      <div class="min-h-0 flex-1 overflow-y-auto px-3 py-6 sm:px-6">
        <ul id="pending-announcements" phx-update="stream" class="mx-auto w-full max-w-3xl space-y-3">
          <li
            id="pending-announcements-empty"
            class="hidden flex-col items-center gap-2 py-16 text-center only:flex"
          >
            <span class="grid size-12 place-items-center rounded-2xl bg-emerald-500/10 text-emerald-600">
              <.icon name="hero-check-badge" class="size-6" />
            </span>
            <p class="text-sm font-medium">You're all caught up</p>
            <p class="text-sm text-base-content/55">New announcements will show up here.</p>
          </li>
          <li
            :for={{dom_id, message} <- @announcements}
            id={dom_id}
            class="motion-safe:animate-[fade-in_300ms_ease-out]"
          >
            <article class="relative overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm transition hover:shadow-md">
              <div
                class={["absolute inset-y-0 left-0 w-1", priority_bar(message.priority)]}
                aria-hidden="true"
              />
              <div class="py-4 pr-4 pl-5">
                <header class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
                  <.priority_badge priority={message.priority} />
                  <.link
                    id={"pending-announcement-link-#{message.id}"}
                    patch={~p"/c/#{message.conversation_id}"}
                    class="font-medium text-base-content/80 underline-offset-2 hover:text-base-content hover:underline"
                  >
                    {message.conversation.title}
                  </.link>
                  <span class="text-base-content/40">·</span>
                  <span class="text-base-content/60">{Accounts.display_name(message.sender)}</span>
                  <span class="text-base-content/50">
                    <.local_time
                      id={"pending-announcement-#{message.id}-at"}
                      at={message.inserted_at}
                    />
                  </span>
                </header>
                <p class="mt-2 text-[15px] leading-relaxed break-words whitespace-pre-line text-base-content">
                  {message.body}
                </p>
                <footer class="mt-3 flex items-center border-t border-base-200 pt-3">
                  <button
                    id={"list-ack-#{message.id}"}
                    type="button"
                    phx-click="acknowledge"
                    phx-value-id={message.id}
                    phx-disable-with="Saving…"
                    class="inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-amber-500 px-4 py-1.5 text-sm font-semibold text-white shadow-sm ring-1 ring-amber-600/20 transition hover:-translate-y-px hover:bg-amber-600 hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-500 active:translate-y-0"
                  >
                    <.icon name="hero-check-mini" class="size-4" /> I've read this
                  </button>
                </footer>
              </div>
            </article>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  defp to_read_label(0), do: "Nothing left to read"
  defp to_read_label(1), do: "1 to read"
  defp to_read_label(count), do: "#{count} to read"

  attr :user, :map, required: true
  slot :inner_block

  defp person(assigns) do
    assigns = assign(assigns, :name, Accounts.display_name(assigns.user))

    ~H"""
    <div class="flex items-center gap-2.5 rounded-lg px-2 py-1.5 transition hover:bg-base-200/70">
      <span
        class="grid size-7 shrink-0 place-items-center rounded-full bg-base-300 text-xs font-semibold text-base-content/70"
        aria-hidden="true"
      >
        {initials(@name)}
      </span>
      <span class="min-w-0 flex-1 truncate text-sm">{@name}</span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :read, :integer, required: true
  attr :total, :integer, required: true
  attr :class, :string, default: "h-1.5 w-16"

  defp read_progress(assigns) do
    assigns = assign(assigns, :percent, percent(assigns.read, assigns.total))

    ~H"""
    <span
      class={["block overflow-hidden rounded-full bg-amber-200/70 dark:bg-amber-400/20", @class]}
      role="progressbar"
      aria-valuemin="0"
      aria-valuemax={@total}
      aria-valuenow={@read}
      aria-label={"#{@read} of #{@total} read"}
    >
      <span
        class="block h-full rounded-full bg-amber-500 transition-[width] duration-500 ease-out"
        style={"width: #{@percent}%"}
      />
    </span>
    """
  end

  @doc false
  # A time rendered as HH:MM UTC on the server and swapped for the viewer's
  # local time by the hook ("Mon 14:02" when it isn't today).
  attr :id, :string, required: true
  attr :at, DateTime, required: true
  attr :class, :any, default: nil

  def local_time(assigns) do
    ~H"""
    <time
      id={@id}
      datetime={DateTime.to_iso8601(@at)}
      title={Calendar.strftime(@at, "%d %b %Y, %H:%M UTC")}
      phx-hook=".LocalTime"
      phx-update="ignore"
      class={@class}
    >
      {Calendar.strftime(@at, "%H:%M")}
    </time>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
      export default {
        mounted() {
          const at = new Date(this.el.getAttribute("datetime"))
          const time = at.toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"})
          const today = at.toDateString() === new Date().toDateString()
          const day = at.toLocaleDateString([], {weekday: "short", day: "numeric", month: "short"})
          this.el.textContent = today ? time : `${day}, ${time}`
          this.el.title = at.toLocaleString()
        }
      }
    </script>
    """
  end

  defp percent(_read, 0), do: 0
  defp percent(read, total), do: round(read * 100 / total)

  defp initials(name) do
    name
    |> String.split(~r/[\s._-]+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end
end
