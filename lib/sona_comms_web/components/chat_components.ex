defmodule SonaCommsWeb.ChatComponents do
  @moduledoc """
  Components for the chat screen: sidebar rows, avatars, message bubbles,
  the composer and the new-conversation pickers.

  Colocated hooks live next to the component that uses them:

    * `.LocalTime` - renders a `<time>` in the viewer's time zone
    * `.ScrollToBottom` - keeps the message pane pinned to the newest message
    * `.Composer` - Enter to send, Shift+Enter for a new line, auto-grow
    * `.PeopleFilter` - filters the people pickers as you type
  """
  use SonaCommsWeb, :html

  alias SonaComms.Accounts

  @avatar_colors [
    "bg-rose-500/15 text-rose-500",
    "bg-amber-500/15 text-amber-600",
    "bg-emerald-500/15 text-emerald-600",
    "bg-sky-500/15 text-sky-500",
    "bg-violet-500/15 text-violet-500",
    "bg-fuchsia-500/15 text-fuchsia-500",
    "bg-teal-500/15 text-teal-600",
    "bg-orange-500/15 text-orange-500"
  ]

  ## Sidebar

  @doc """
  A sidebar row, rendered inside a `:conversations` stream item that carries
  `data-kind`.

  Every row renders its section heading. CSS hides it when the previous row
  has the same kind, so headings stay right wherever a row is inserted.
  """
  attr :conversation, :map, required: true
  attr :active, :boolean, default: false

  def conversation_row(assigns) do
    ~H"""
    <p class={[
      "px-3 pt-4 pb-1.5 text-[11px] font-semibold tracking-wider text-base-content/45 uppercase",
      repeated_heading_class(@conversation.kind)
    ]}>
      {section_label(@conversation.kind)}
    </p>
    <.link
      patch={~p"/c/#{@conversation.id}"}
      aria-current={@active && "page"}
      class={[
        "flex items-center gap-3 rounded-xl px-2.5 py-2 transition-colors duration-150",
        if(@active,
          do: "bg-primary/10 ring-1 ring-primary/15 ring-inset",
          else: "hover:bg-base-300/50"
        )
      ]}
    >
      <.conversation_avatar conversation={@conversation} />
      <div class="min-w-0 flex-1">
        <div class="flex items-baseline gap-2">
          <span class={[
            "flex-1 truncate text-sm",
            if(@conversation.unread_count > 0,
              do: "font-semibold text-base-content",
              else: "font-medium text-base-content/85"
            )
          ]}>
            {@conversation.display_title}
          </span>
          <.local_time
            :if={@conversation.last_message_at}
            id={"conversation-time-#{@conversation.id}"}
            at={@conversation.last_message_at}
            format="short"
            class={[
              "shrink-0 text-[11px] tabular-nums",
              if(@conversation.unread_count > 0,
                do: "font-semibold text-primary",
                else: "text-base-content/45"
              )
            ]}
          />
        </div>
        <div class="mt-0.5 flex h-5 items-center gap-2">
          <span
            :if={@conversation.pending_ack_count > 0}
            id={"pending-acks-#{@conversation.id}"}
            class="inline-flex items-center gap-1 truncate rounded-full bg-warning/15 px-2 py-px text-[11px] font-semibold text-warning ring-1 ring-warning/30 ring-inset"
          >
            <.icon name="hero-megaphone-micro" class="size-3 shrink-0" />
            {announcements_label(@conversation.pending_ack_count)}
          </span>
          <span
            :if={@conversation.pending_ack_count == 0}
            class="truncate text-xs text-base-content/45"
          >
            {kind_label(@conversation.kind)}
          </span>
          <span class="flex-1" />
          <span
            :if={@conversation.unread_count > 0}
            id={"unread-#{@conversation.id}"}
            aria-label={"#{@conversation.unread_count} unread messages"}
            class="grid h-5 min-w-5 place-items-center rounded-full bg-primary px-1.5 text-[11px] font-bold text-primary-content tabular-nums shadow-sm"
          >
            {@conversation.unread_count}
          </span>
        </div>
      </div>
    </.link>
    """
  end

  # Literal class strings, so Tailwind generates them. A heading is hidden
  # when the row before it is of the same kind.
  defp repeated_heading_class(:org), do: "[[data-kind=org]+[data-kind=org]_&]:hidden"
  defp repeated_heading_class(:venue), do: "[[data-kind=venue]+[data-kind=venue]_&]:hidden"
  defp repeated_heading_class(:team), do: "[[data-kind=team]+[data-kind=team]_&]:hidden"
  defp repeated_heading_class(:group), do: "[[data-kind=group]+[data-kind=group]_&]:hidden"
  defp repeated_heading_class(:dm), do: "[[data-kind=dm]+[data-kind=dm]_&]:hidden"

  defp section_label(:org), do: "Organisation"
  defp section_label(:venue), do: "Venues"
  defp section_label(:team), do: "Teams"
  defp section_label(:group), do: "Group chats"
  defp section_label(:dm), do: "Direct messages"

  @doc "A short description of a conversation kind, for subtitles."
  def kind_label(:org), do: "Everyone"
  def kind_label(:venue), do: "Whole venue"
  def kind_label(:team), do: "Team"
  def kind_label(:group), do: "Group chat"
  def kind_label(:dm), do: "Direct message"

  defp announcements_label(1), do: "1 announcement"
  defp announcements_label(count), do: "#{count} announcements"

  ## Avatars

  @doc """
  The avatar of a conversation: an icon per derived kind or group, and the
  other person's initials for a DM.
  """
  attr :conversation, :map, required: true
  attr :class, :any, default: "size-9"

  def conversation_avatar(%{conversation: %{kind: :dm}} = assigns) do
    ~H"""
    <span
      aria-hidden="true"
      class={[
        "grid shrink-0 place-items-center rounded-full text-xs font-semibold",
        avatar_color(@conversation.display_title),
        @class
      ]}
    >
      {initials(@conversation.display_title)}
    </span>
    """
  end

  def conversation_avatar(assigns) do
    {icon, color} = kind_style(assigns.conversation.kind)
    assigns = assign(assigns, icon: icon, color: color)

    ~H"""
    <span
      aria-hidden="true"
      class={["grid shrink-0 place-items-center rounded-xl", @color, @class]}
    >
      <.icon name={@icon} class="size-[1.1rem]" />
    </span>
    """
  end

  defp kind_style(:org),
    do: {"hero-building-office-2", "bg-primary text-primary-content shadow-sm"}

  defp kind_style(:venue), do: {"hero-map-pin", "bg-info/15 text-info"}
  defp kind_style(:team), do: {"hero-users", "bg-success/15 text-success"}
  defp kind_style(:group), do: {"hero-chat-bubble-left-right", "bg-accent/15 text-accent"}

  @doc "A person's initials on a colour derived from their name."
  attr :user, :map, required: true
  attr :class, :any, default: "size-8 text-xs"

  def user_avatar(assigns) do
    assigns = assign(assigns, :name, Accounts.display_name(assigns.user))

    ~H"""
    <span
      aria-hidden="true"
      class={[
        "grid shrink-0 place-items-center rounded-full font-semibold",
        avatar_color(@name),
        @class
      ]}
    >
      {initials(@name)}
    </span>
    """
  end

  defp avatar_color(key),
    do: Enum.at(@avatar_colors, :erlang.phash2(key, length(@avatar_colors)))

  defp initials(nil), do: "?"

  defp initials(name) do
    name
    |> String.split(~r/[\s._-]+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  ## Time

  @doc """
  A `<time>` that the `.LocalTime` hook re-renders in the viewer's time zone.
  The server renders UTC until the hook mounts.

  `format="short"` shows the time today, the weekday this week and the date
  otherwise (sidebar). `format="message"` adds the time to the day.
  """
  attr :id, :string, required: true
  attr :at, DateTime, required: true
  attr :format, :string, default: "message", values: ~w(message short)
  attr :class, :any, default: nil

  def local_time(assigns) do
    ~H"""
    <time
      id={@id}
      datetime={DateTime.to_iso8601(@at)}
      data-format={@format}
      phx-hook=".LocalTime"
      class={@class}
    >
      {Calendar.strftime(@at, "%H:%M")}
    </time>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
      const DAY = 24 * 60 * 60 * 1000

      export default {
        mounted() { this.render() },
        updated() { this.render() },
        render() {
          const date = new Date(this.el.getAttribute("datetime"))
          if (Number.isNaN(date.getTime())) return

          const now = new Date()
          const time = date.toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"})
          const today = date.toDateString() === now.toDateString()
          const day = now - date < 6 * DAY
            ? date.toLocaleDateString([], {weekday: "short"})
            : date.toLocaleDateString([], {day: "numeric", month: "short"})

          const text = today ? time : (this.el.dataset.format === "short" ? day : day + " " + time)
          if (this.el.textContent !== text) this.el.textContent = text
          this.el.title = date.toLocaleString([], {dateStyle: "full", timeStyle: "short"})
        }
      }
    </script>
    """
  end

  ## Messages

  @doc """
  The scrolling message pane. Stays pinned to the newest message unless the
  reader has scrolled up, and always jumps down for your own messages and
  when another conversation opens.
  """
  attr :id, :string, required: true
  attr :conversation_id, :any, required: true
  slot :inner_block, required: true

  def message_scroller(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".ScrollToBottom"
      data-conversation-id={@conversation_id}
      class="min-h-0 flex-1 overflow-y-auto overscroll-contain"
    >
      <div class="flex min-h-full flex-col justify-end px-3 py-5 sm:px-6">
        {render_slot(@inner_block)}
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToBottom">
      export default {
        mounted() {
          this.conversationId = this.el.dataset.conversationId
          this.lastId = this.lastMessage()?.id
          this.pinned = true
          this.el.addEventListener("scroll", () => {
            this.pinned = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 96
          }, {passive: true})
          this.observer = new MutationObserver(() => this.onChange())
          this.observer.observe(this.el, {childList: true, subtree: true})
          this.toBottom()
        },
        updated() { this.onChange() },
        destroyed() { this.observer.disconnect() },
        lastMessage() { return this.el.querySelector("#messages > [data-mine]:last-child") },
        onChange() {
          const switched = this.el.dataset.conversationId !== this.conversationId
          const last = this.lastMessage()
          const newOwn = last && last.id !== this.lastId && last.dataset.mine === "true"
          this.conversationId = this.el.dataset.conversationId
          this.lastId = last?.id
          if (switched || newOwn || this.pinned) this.toBottom()
        },
        toBottom() {
          this.el.scrollTop = this.el.scrollHeight
          this.pinned = true
        }
      }
    </script>
    """
  end

  @doc "A text message. Your own messages sit on the right."
  attr :message, :map, required: true
  attr :mine, :boolean, default: false

  def message_bubble(assigns) do
    ~H"""
    <div
      class={["flex items-end gap-2.5", @mine && "flex-row-reverse"]}
      phx-mounted={
        JS.transition(
          {"ease-out duration-200", "opacity-0 translate-y-1", "opacity-100 translate-y-0"}
        )
      }
    >
      <.user_avatar :if={!@mine} user={@message.sender} class="mb-5 size-8 text-xs" />
      <div class={[
        "flex max-w-[80%] min-w-0 flex-col sm:max-w-[70%]",
        if(@mine, do: "items-end", else: "items-start")
      ]}>
        <p :if={!@mine} class="mb-1 px-1 text-xs font-medium text-base-content/60">
          {Accounts.display_name(@message.sender)}
        </p>
        <div
          phx-no-format
          class={[
            "rounded-2xl px-3.5 py-2 text-[15px] leading-relaxed break-words whitespace-pre-wrap shadow-xs",
            if(@mine,
              do: "rounded-br-md bg-primary text-primary-content",
              else: "rounded-bl-md bg-base-200 text-base-content"
            )
          ]}
        >{@message.body}</div>
        <.local_time
          id={"message-time-#{@message.id}"}
          at={@message.inserted_at}
          class="mt-1 px-1 text-[11px] text-base-content/40 tabular-nums"
        />
      </div>
    </div>
    """
  end

  ## Composer

  @doc """
  The message composer (`#message-form`). Enter sends, Shift+Enter adds a
  line. The server pushes `"composer:reset"` after a successful send.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :placeholder, :string, default: "Message"

  def composer(assigns) do
    ~H"""
    <.form
      for={@form}
      id="message-form"
      phx-submit="send_message"
      class="shrink-0 border-t border-base-300 bg-base-100/90 px-3 pt-3 pb-3 backdrop-blur sm:px-6"
    >
      <div class="mx-auto flex w-full max-w-3xl items-end gap-2 rounded-2xl border border-base-300 bg-base-200/50 py-1.5 pr-1.5 pl-4 transition duration-150 focus-within:border-primary/40 focus-within:bg-base-100 focus-within:ring-4 focus-within:ring-primary/10 [&>.fieldset]:mb-0 [&>.fieldset]:min-w-0 [&>.fieldset]:flex-1 [&>.fieldset]:p-0">
        <.input
          field={@form[:body]}
          type="textarea"
          id="message-body"
          rows="1"
          maxlength="4000"
          placeholder={@placeholder}
          aria-label="Message"
          autocomplete="off"
          phx-hook=".Composer"
          class="block max-h-40 w-full resize-none border-0 bg-transparent py-1.5 text-[15px] leading-relaxed outline-none placeholder:text-base-content/40"
        />
        <button
          type="submit"
          id="send-message"
          aria-label="Send message"
          class="grid size-9 shrink-0 cursor-pointer place-items-center rounded-xl bg-primary text-primary-content shadow-sm transition duration-150 hover:brightness-110 active:scale-95 phx-submit-loading:opacity-60"
        >
          <.icon name="hero-paper-airplane-solid" class="size-4" />
        </button>
      </div>
      <p class="mx-auto mt-1.5 hidden max-w-3xl px-1 text-[11px] text-base-content/40 md:block">
        <kbd class="font-sans font-semibold">Enter</kbd>
        to send · <kbd class="font-sans font-semibold">Shift + Enter</kbd>
        for a new line
      </p>
    </.form>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Composer">
      export default {
        mounted() {
          this.resize = () => {
            this.el.style.height = "auto"
            this.el.style.height = Math.min(this.el.scrollHeight, 160) + "px"
          }
          this.el.addEventListener("input", this.resize)
          this.el.addEventListener("keydown", event => {
            if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
            event.preventDefault()
            if (this.el.value.trim() !== "") this.el.form.requestSubmit()
          })
          this.handleEvent("composer:reset", () => {
            this.el.value = ""
            this.resize()
            if (window.matchMedia("(pointer: fine)").matches) this.el.focus()
          })
          this.resize()
        },
        updated() { this.resize() }
      }
    </script>
    """
  end

  ## New conversations

  @doc "The `/new/dm` picker (`#new-dm-form`): one click starts or reopens a DM."
  attr :colleagues, :any, required: true, doc: "the `:colleagues` stream"
  attr :on_cancel, JS, required: true

  def new_dm_modal(assigns) do
    ~H"""
    <.modal id="new-dm-modal" show on_cancel={@on_cancel}>
      <h2 id="new-dm-modal-title" class="text-lg font-semibold tracking-tight">New message</h2>
      <p id="new-dm-modal-description" class="mt-1 text-sm text-base-content/60">
        Message anyone in your organisation directly.
      </p>
      <.form for={%{}} id="new-dm-form" phx-submit="start_dm" class="mt-5">
        <.people_filter id="dm-people-filter" list="dm-people" />
        <ul id="dm-people" phx-update="stream" class="-mx-2 mt-3 max-h-80 overflow-y-auto">
          <li
            id="dm-people-empty"
            class="hidden px-3 py-8 text-center text-sm text-base-content/50 only:block"
          >
            Nobody else is here yet.
          </li>
          <li :for={{dom_id, user} <- @colleagues} id={dom_id} data-search={search_text(user)}>
            <button
              type="submit"
              id={"start-dm-#{user.id}"}
              name="user_id"
              value={user.id}
              class="group flex w-full cursor-pointer items-center gap-3 rounded-xl px-2 py-2 text-left transition duration-150 hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none"
            >
              <.user_avatar user={user} class="size-9 text-sm" />
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-medium">
                  {Accounts.display_name(user)}
                </span>
                <span class="block truncate text-xs text-base-content/50">{user.email}</span>
              </span>
              <.icon
                name="hero-chevron-right-mini"
                class="size-4 text-base-content/30 transition group-hover:translate-x-0.5 group-hover:text-base-content/60"
              />
            </button>
          </li>
        </ul>
      </.form>
    </.modal>
    """
  end

  @doc "The `/new/group` form (`#new-group-form`): a name and at least one person."
  attr :form, Phoenix.HTML.Form, required: true
  attr :colleagues, :any, required: true, doc: "the `:colleagues` stream"
  attr :on_cancel, JS, required: true

  def new_group_modal(assigns) do
    assigns =
      assign(
        assigns,
        :member_errors,
        Enum.map(assigns.form[:user_ids].errors, &translate_error/1)
      )

    ~H"""
    <.modal id="new-group-modal" show on_cancel={@on_cancel}>
      <h2 id="new-group-modal-title" class="text-lg font-semibold tracking-tight">
        New group chat
      </h2>
      <p id="new-group-modal-description" class="mt-1 text-sm text-base-content/60">
        For a shift, an event, or anything that doesn't fit a team.
      </p>
      <.form for={@form} id="new-group-form" phx-submit="create_group" class="mt-5 space-y-3">
        <.input
          field={@form[:title]}
          label="Name"
          placeholder="Saturday wedding crew"
          maxlength="80"
          autocomplete="off"
        />
        <fieldset>
          <legend class="mb-1.5 text-sm font-medium">People</legend>
          <.people_filter id="group-people-filter" list="group-people" />
          <ul id="group-people" phx-update="stream" class="-mx-2 mt-2 max-h-64 overflow-y-auto">
            <li
              id="group-people-empty"
              class="hidden px-3 py-8 text-center text-sm text-base-content/50 only:block"
            >
              Nobody else is here yet.
            </li>
            <li :for={{dom_id, user} <- @colleagues} id={dom_id} data-search={search_text(user)}>
              <label
                for={"group-member-#{user.id}"}
                class="flex cursor-pointer items-center gap-3 rounded-xl px-2 py-2 transition duration-150 hover:bg-base-200 has-checked:bg-primary/8"
              >
                <input
                  type="checkbox"
                  id={"group-member-#{user.id}"}
                  name={@form[:user_ids].name <> "[]"}
                  value={user.id}
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <.user_avatar user={user} class="size-8 text-xs" />
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-sm font-medium">
                    {Accounts.display_name(user)}
                  </span>
                  <span class="block truncate text-xs text-base-content/50">{user.email}</span>
                </span>
              </label>
            </li>
          </ul>
          <p
            :for={message <- @member_errors}
            class="mt-1.5 flex items-center gap-2 text-sm text-error"
          >
            <.icon name="hero-exclamation-circle" class="size-5" />
            {String.capitalize(message)}
          </p>
        </fieldset>
        <div class="flex justify-end gap-2 pt-2">
          <button
            type="button"
            class="btn btn-ghost"
            phx-click={JS.exec("data-cancel", to: "#new-group-modal")}
          >
            Cancel
          </button>
          <.button variant="primary" phx-disable-with="Creating…">Create group chat</.button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :id, :string, required: true
  attr :list, :string, required: true, doc: "the id of the list to filter"

  defp people_filter(assigns) do
    ~H"""
    <label class="flex items-center gap-2 rounded-xl border border-base-300 bg-base-200/40 px-3 py-2 transition duration-150 focus-within:border-primary/40 focus-within:bg-base-100 focus-within:ring-4 focus-within:ring-primary/10">
      <.icon name="hero-magnifying-glass-mini" class="size-4 text-base-content/40" />
      <input
        type="search"
        id={@id}
        data-list={"##{@list}"}
        phx-hook=".PeopleFilter"
        placeholder="Search people"
        aria-label="Search people"
        autocomplete="off"
        class="w-full bg-transparent text-sm outline-none placeholder:text-base-content/40"
      />
    </label>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PeopleFilter">
      export default {
        mounted() {
          this.el.addEventListener("input", () => this.filter())
          this.el.addEventListener("keydown", event => {
            if (event.key !== "Enter") return
            event.preventDefault()
            const visible = this.items().filter(item => !item.hidden)
            if (visible.length === 1) visible[0].querySelector("button, input")?.click()
          })
        },
        items() {
          return Array.from(document.querySelectorAll(this.el.dataset.list + " [data-search]"))
        },
        filter() {
          const query = this.el.value.trim().toLowerCase()
          this.items().forEach(item => {
            item.hidden = query !== "" && !item.dataset.search.includes(query)
          })
        }
      }
    </script>
    """
  end

  defp search_text(user),
    do: String.downcase("#{Accounts.display_name(user)} #{user.email}")
end
