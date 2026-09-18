# Sona Comms PoC: Implementation Plan

Product intent lives in [PRODUCT.md](PRODUCT.md). The reasons behind decisions live in [adr/](adr/). This file is the **contract** between work packages (WPs).

## 1. How to use this plan

- You are given exactly one WP (§7). Do only that WP.
- **WP1 lands first.** WP2a, WP2b and WP2c then run **in parallel**, each on its own branch.
- After WP1, §3 to §6 are **frozen**: context APIs, PubSub topics, routes, seams, file ownership and UI vocabulary.
  - Only edit files your WP owns (§6.3).
  - If you need a change in a file you don't own, **stop and report the gap**. Do not edit it.
  - If you own a context, you may add functions. Never change the signature or semantics of a §3 function that another WP calls.
  - You may add new migration files, new test files, and new fixture modules under `test/support/fixtures/`. Never edit an existing migration or an existing file in `test/support/`.
- A WP is **done** when all three hold:
  1. its *Outcome* is demonstrated in the running app, verified with Tidewave (`project_eval`, `execute_sql_query`, `get_logs`);
  2. its listed tests exist and pass;
  3. `mix precommit` is clean, with no warnings.
- After all three WP2s are merged, the demo script (§8) is the acceptance check.

## 2. Domain model

### 2.1 Conventions

- bigint primary keys, to match `users`.
- `timestamps(type: :utc_datetime)` unless noted. Fields used for ordering or unread maths use `:utc_datetime_usec` ([ADR 0001](adr/0001-derived-conversations-materialised-participants.md)).
- Enums are `Ecto.Enum`, stored as strings.
- Chat schemas refer to Org tables with plain `field :venue_id, :id`, **not** `belongs_to` ([ADR 0002](adr/0002-org-chat-context-boundary.md)). Chat may `belongs_to` `SonaComms.Accounts.User`.
- Programmatic keys (`user_id`, `sender_id`, `conversation_id`, `organisation_id`, `created_by_id`) are never listed in `cast`.
- **A user belongs to at most one organisation** in this PoC. `Org.create_membership/2` rejects users who have active memberships in another organisation.
- Generate migrations with `mix ecto.gen.migration`.

### 2.2 Accounts (changed)

```elixir
# users: new column
field :name, :string            # NULL allowed, 1..80 chars

# SonaComms.Accounts.User.name_changeset/2 casts :name
# SonaComms.Accounts.register_user/1 accepts an optional "name"
# SonaComms.Accounts.display_name(user) returns name, or the email local part if name is nil
```

`SonaComms.Accounts.Scope` gains plain fields only. It never holds or references Org structs, so Accounts does not depend on Org ([ADR 0002](adr/0002-org-chat-context-boundary.md), [ADR 0003](adr/0003-membership-shape-and-roles.md)).

```elixir
defstruct user: nil, organisation_id: nil, admin?: false, system?: false

Scope.for_user(user)                  # unchanged (phx.gen.auth)
Scope.for_system(organisation_id)     # seeds/tests only: %Scope{organisation_id: id, system?: true}
Scope.admin?(scope)                   # reads the admin? flag; UI gating only
```

`organisation_id` and `admin?` are set by `Org.put_member_scope/1`, called from `SonaCommsWeb.OrgAuth`. Pages without that hook (`/users/settings`, `/no-access`) have an un-enriched scope, so admin-only nav links only show on member pages.

### 2.3 Org: `SonaComms.Org`

```elixir
# SonaComms.Org.Organisation  "organisations"
field :name, :string                          # NOT NULL
has_many :venues, Venue
timestamps(type: :utc_datetime)
```

```elixir
# SonaComms.Org.Venue  "venues"
belongs_to :organisation, Organisation        # NOT NULL
field :name, :string                          # NOT NULL
has_many :teams, Team
timestamps(type: :utc_datetime)

create unique_index(:venues, [:organisation_id, :name])
```

```elixir
# SonaComms.Org.Team  "teams"
belongs_to :venue, Venue                      # NOT NULL
field :name, :string                          # NOT NULL
timestamps(type: :utc_datetime)

create unique_index(:teams, [:venue_id, :name])
create unique_index(:teams, [:id, :venue_id]) # target of the memberships composite FK
```

```elixir
# SonaComms.Org.Membership  "memberships"
belongs_to :user, SonaComms.Accounts.User     # NOT NULL
belongs_to :venue, Venue                      # NOT NULL
belongs_to :team, Team                        # NULL = venue-level membership
field :role, Ecto.Enum, values: [:staff, :manager, :admin], default: :staff   # NOT NULL
field :ended_at, :utc_datetime                # NULL = active. Rows are never deleted.
timestamps(type: :utc_datetime)

# migration
add :team_id, references(:teams, with: [venue_id: :venue_id])   # team must belong to venue
create unique_index(:memberships, [:user_id, :venue_id, :team_id],
         where: "ended_at IS NULL", nulls_distinct: false,
         name: :memberships_one_active_per_slot)
create index(:memberships, [:venue_id], where: "ended_at IS NULL")
create index(:memberships, [:team_id], where: "ended_at IS NULL")
create index(:memberships, [:user_id])
create constraint(:memberships, :ended_after_start,
         check: "ended_at IS NULL OR ended_at >= inserted_at")
```

### 2.4 Chat: `SonaComms.Chat`

```elixir
# SonaComms.Chat.Conversation  "conversations"
field :organisation_id, :id                   # NOT NULL, FK organisations
field :kind, Ecto.Enum, values: [:dm, :group, :team, :venue, :org]   # NOT NULL
field :title, :string                         # set by the creator (see below); NULL for dm
field :venue_id, :id                          # kind :venue only, FK venues
field :team_id, :id                           # kind :team only, FK teams
field :dm_key, :string                        # kind :dm only: "#{min_user_id}:#{max_user_id}"
field :created_by_id, :id                     # dm/group creator, FK users; NULL for derived
field :last_message_at, :utc_datetime_usec
has_many :participants, Participant
has_many :messages, Message
# virtual, set by list_conversations/1 and get_conversation/2
field :unread_count, :integer, virtual: true, default: 0
field :pending_ack_count, :integer, virtual: true, default: 0   # populated by WP2b
field :display_title, :string, virtual: true                    # title, or for a dm the other person's name
field :can_announce, :boolean, virtual: true, default: false    # current user's participant flag
timestamps(type: :utc_datetime)

create index(:conversations, [:organisation_id])
create unique_index(:conversations, [:organisation_id], where: "kind = 'org'",   name: :conversations_one_per_org)
create unique_index(:conversations, [:venue_id],        where: "kind = 'venue'", name: :conversations_one_per_venue)
create unique_index(:conversations, [:team_id],         where: "kind = 'team'",  name: :conversations_one_per_team)
create unique_index(:conversations, [:organisation_id, :dm_key], where: "kind = 'dm'", name: :conversations_one_dm_per_pair)
create constraint(:conversations, :conversation_shape, check: """
  (kind = 'org'   AND venue_id IS NULL     AND team_id IS NULL     AND dm_key IS NULL) OR
  (kind = 'venue' AND venue_id IS NOT NULL AND team_id IS NULL     AND dm_key IS NULL) OR
  (kind = 'team'  AND venue_id IS NULL     AND team_id IS NOT NULL AND dm_key IS NULL) OR
  (kind = 'group' AND venue_id IS NULL     AND team_id IS NULL     AND dm_key IS NULL) OR
  (kind = 'dm'    AND venue_id IS NULL     AND team_id IS NULL     AND dm_key IS NOT NULL)
""")
```

Titles are written once at creation:

| kind | title | example |
|---|---|---|
| org | organisation name | "Sona Hospitality Group" |
| venue | venue name | "Bristol" |
| team | `"#{venue.name} · #{team.name}"` (built by Org) | "Bristol · FOH" |
| group | name typed by the creator | "Saturday wedding crew" |
| dm | NULL; `display_title` is the other person's `Accounts.display_name/1` | "Bob" |

```elixir
# SonaComms.Chat.Participant  "conversation_participants"
belongs_to :conversation, Conversation        # NOT NULL, on_delete: :delete_all
belongs_to :user, SonaComms.Accounts.User     # NOT NULL
field :can_announce, :boolean, default: false # NOT NULL; derived kinds only, written by sync
field :last_read_at, :utc_datetime_usec       # NOT NULL; set to join time
field :left_at, :utc_datetime_usec            # NULL = active
timestamps(type: :utc_datetime)

create unique_index(:conversation_participants, [:conversation_id, :user_id])
create index(:conversation_participants, [:user_id], where: "left_at IS NULL")
```

```elixir
# SonaComms.Chat.Message  "messages"
belongs_to :conversation, Conversation        # NOT NULL, on_delete: :delete_all
belongs_to :sender, SonaComms.Accounts.User   # NOT NULL
field :kind, Ecto.Enum, values: [:text, :announcement], default: :text   # NOT NULL
field :body, :string                          # text column, NOT NULL, 1..4000 chars
field :priority, Ecto.Enum, values: [:low, :mid, :high]   # announcements only (check constraint), default :mid
# virtual, announcements only, per viewer, populated by WP2b
field :ack_count, :integer, virtual: true
field :recipient_count, :integer, virtual: true
field :my_ack, :any, virtual: true            # :pending | :acknowledged | nil (not a recipient)
timestamps(type: :utc_datetime_usec, updated_at: false)

create index(:messages, [:conversation_id, :inserted_at])
```

```elixir
# SonaComms.Chat.Receipt  "message_receipts" (kind :announcement messages only)
belongs_to :message, Message                  # NOT NULL, on_delete: :delete_all
belongs_to :user, SonaComms.Accounts.User     # NOT NULL
field :acknowledged_at, :utc_datetime_usec    # NULL = pending
timestamps(type: :utc_datetime_usec, updated_at: false)

create unique_index(:message_receipts, [:message_id, :user_id])
create index(:message_receipts, [:user_id], where: "acknowledged_at IS NULL")
```

### 2.5 Derivation rules

Participation in derived conversations is a pure function of **active** memberships ([ADR 0001](adr/0001-derived-conversations-materialised-participants.md), [ADR 0003](adr/0003-membership-shape-and-roles.md)).

| conversation | participants | `can_announce` |
|---|---|---|
| `:org` | users with any active membership in the org | holds an active `:admin` membership |
| `:venue` V | users with an active membership where `venue_id = V` | `:admin` membership at V, or `:manager` membership at V with `team_id IS NULL` |
| `:team` T | users with an active membership where `team_id = T` | `:manager` or `:admin` membership with `team_id = T` |
| `:dm`, `:group` | explicit; sync never touches them (only org revocation does) | always `false` |

Rules:

- Org computes `desired :: %{user_id => can_announce}` for a conversation and calls `Chat.sync_participants/2`. The sync is a full recompute:
  - it upserts desired users (a rejoining user gets `left_at = nil`, `last_read_at = now`);
  - it updates changed `can_announce` flags;
  - it sets `left_at = now` for active participants who are not desired.
- Sync runs inside the same `Repo.transact` as the membership change, with the conversation row locked `FOR UPDATE`. Broadcasts happen **after commit**.
- Triggers:
  - `create_membership` and `end_membership` resync the org, venue and (if set) team conversation of that membership;
  - `create_venue` by a user resyncs the new venue conversation after adding the creator's membership.
  - `create_team` adds nobody, so a new team conversation has no participants until someone is given a membership on that team.
- When a user's **last** active membership in the org ends, `Chat.revoke_org_access/2` also sets `left_at` on their `:dm` and `:group` participations in that org ([ADR 0004](adr/0004-offboarding-and-access-gate.md)).
- Leaving any conversation deletes the leaver's **pending** receipts in it. Acknowledged receipts are kept ([ADR 0005](adr/0005-announcements-and-receipts.md)).
- **Unread count** = messages in the conversation with `inserted_at > participant.last_read_at` and `sender_id != me`.

Seeded result:

| persona | conversations | can announce in |
|---|---|---|
| Alice (admin, venue-level at London, Manchester, Bristol) | org, London, Manchester, Bristol | all 4 |
| Bob (manager, London · Kitchen) | org, London, London · Kitchen | London · Kitchen |
| Charlie (staff, Bristol · FOH) | org, Bristol, Bristol · FOH | nowhere |

## 3. Context API contract

Caller-facing functions take `%Scope{}` first. LiveViews and controllers call **only** these functions (CLAUDE.md).

Exceptions: `change_*` form helpers and `unsubscribe_conversation/1` touch no data, so they take no scope. Bootstrap functions and those marked Org-only take no scope either, and are never called from LiveViews.

### 3.1 `SonaComms.Org` (written in WP1, owned by WP2c afterwards)

```elixir
# Access
put_member_scope(Scope.t()) :: {:ok, Scope.t()} | {:error, :no_access}
  # sets organisation_id and admin? from the user's active memberships
admin?(Scope.t()) :: boolean()                          # checks the DB, never the scope's admin? flag
subscribe_access(Scope.t()) :: :ok                      # "user:<id>:access"
subscribe_org(Scope.t()) :: :ok                         # "org:<organisation_id>"

# Structure: admin or system scope, otherwise {:error, :unauthorized}
list_venues(Scope.t()) :: [Venue.t()]
  # teams preloaded, ordered by name; each team has a virtual member count for "0 people"
change_venue(Venue.t(), map()) :: Ecto.Changeset.t()
create_venue(Scope.t(), map()) :: {:ok, Venue.t()} | {:error, :unauthorized | Ecto.Changeset.t()}
  # creates the venue conversation; if scope.user is set, also gives that user a venue-level :admin membership
change_team(Team.t(), map()) :: Ecto.Changeset.t()
create_team(Scope.t(), venue_id, map()) :: {:ok, Team.t()} | {:error, :unauthorized | :not_found | Ecto.Changeset.t()}
  # creates the team conversation titled "Venue · Team"; :not_found if the venue is outside the scope's org

# Memberships
list_memberships(Scope.t(), keyword()) :: [Membership.t()]
  # opts: venue_id: id, include_ended: false; user/venue/team preloaded; ordered by venue, team, name
change_membership(map()) :: Ecto.Changeset.t()          # form: email, name, venue_id, team_id, role
create_membership(Scope.t(), map()) :: {:ok, Membership.t()} | {:error, :unauthorized | Ecto.Changeset.t()}
  # finds or creates the user by email (Accounts.get_user_by_email/1, Accounts.register_user/1).
  # Changeset errors when: the venue is outside the org, the team is outside the venue, the slot is
  # already active, or the user has active memberships in another organisation. Then syncs conversations.
end_membership(Scope.t(), membership_id) ::
  {:ok, Membership.t()} | {:error, :unauthorized | :not_found | :already_ended | :cannot_end_own_membership}
  # :not_found for another org's membership. Sets ended_at and resyncs. On the last active membership it
  # also calls Chat.revoke_org_access/2. After commit it broadcasts {:access_revoked, org_id} FIRST,
  # then the Chat events, then {:org_changed, :membership}.
list_colleagues(Scope.t()) :: [User.t()]                # active org members except self, ordered by name

# Bootstrap and dev: no scope, never called from LiveViews
create_organisation(map()) :: {:ok, Organisation.t()}   # also creates the org conversation (seeds/tests)
directory() :: [%{user: User.t(), memberships: [Membership.t()]}]
  # dev switcher only: Alice, Bob, Charlie first; includes users with no active membership
```

### 3.2 `SonaComms.Chat`: core (WP1)

```elixir
list_conversations(Scope.t()) :: [Conversation.t()]
  # active participations only; virtuals set; ordered by kind (org, venue, team, group, dm),
  # then last_message_at desc
get_conversation(Scope.t(), id) :: {:ok, Conversation.t()} | {:error, :not_found}
  # not_found also when the user never participated or has left (no existence leak)
list_participants(Scope.t(), conversation_id) :: {:ok, [User.t()]} | {:error, :not_found}
list_messages(Scope.t(), conversation_id, keyword()) :: {:ok, [Message.t()]} | {:error, :not_found}
  # opts: limit: 50, before: DateTime; returned oldest to newest; sender preloaded
get_message(Scope.t(), message_id) :: {:ok, Message.t()} | {:error, :not_found}
  # sender preloaded; the caller must be an active participant. Announcement virtuals are nil until WP2b.
change_message(map()) :: Ecto.Changeset.t()
post_message(Scope.t(), conversation_id, map()) :: {:ok, Message.t()} | {:error, :not_found | Ecto.Changeset.t()}
  # kind :text; bumps conversation.last_message_at; broadcasts {:message_created, conversation_id, message_id}
mark_read(Scope.t(), conversation_id) :: :ok | {:error, :not_found}
  # broadcasts {:conversation_read, conversation_id} on "user:<id>"
start_dm(Scope.t(), other_user_id) :: {:ok, Conversation.t()} | {:error, :not_found}
  # find-or-create; both users must be active participants of the org conversation
  # (found via scope.organisation_id); self gives :not_found
create_group(Scope.t(), map()) :: {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  # %{"title" => _, "user_ids" => [_]}; creator is added; every user must be an active org member
leave_group(Scope.t(), conversation_id) :: :ok | {:error, :not_found | :not_leavable}
  # only kind :group; derived kinds and dms return :not_leavable
subscribe_user(Scope.t()) :: :ok                                     # "user:<id>"
subscribe_conversation(Scope.t(), conversation_id) :: :ok | {:error, :not_found}
unsubscribe_conversation(conversation_id) :: :ok

# Org-only: called inside Org's transaction. LiveViews never call these.
create_derived_conversation(:org | :venue | :team, map()) :: {:ok, Conversation.t()}
get_derived_conversation(:org | :venue | :team, ref_id) :: Conversation.t() | nil
sync_participants(Conversation.t(), %{user_id => boolean()}) :: {:ok, [event]}   # raises ArgumentError for :dm/:group
revoke_org_access(organisation_id, user_id) :: {:ok, [event]}
broadcast([event]) :: :ok                                             # call after commit
# event :: {:joined, conversation_id, user_id} | {:left, conversation_id, user_id}
#        | {:receipts_removed, conversation_id, [message_id]}
```

### 3.3 `SonaComms.Chat`: announcements (added by WP2b)

```elixir
change_announcement(map()) :: Ecto.Changeset.t()
post_announcement(Scope.t(), conversation_id, map()) ::
  {:ok, Message.t()} | {:error, :not_found | :unauthorized | Ecto.Changeset.t()}
  # requires the participant's can_announce (so DMs and groups are always :unauthorized);
  # inserts receipts for all active participants except the sender
acknowledge(Scope.t(), message_id) :: {:ok, Receipt.t()} | {:error, :not_found}   # idempotent
list_receipts(Scope.t(), message_id) :: {:ok, [Receipt.t()]} | {:error, :not_found | :unauthorized}
  # :not_found for non-participants; :unauthorized unless sender or a can_announce participant; user preloaded
list_pending_announcements(Scope.t()) :: [Message.t()]
  # the user's unacknowledged receipts in active conversations; high, mid, low, then newest first;
  # sender and conversation preloaded (ADR 0005, priority)
# and: get_message/2, list_messages/3, get_conversation/2 and list_conversations/1 populate
#      ack_count, recipient_count, my_ack and pending_ack_count
# and: broadcast/1 turns {:receipts_removed, ...} into {:ack_updated, ...}
```

## 4. PubSub contract

Server: `SonaComms.PubSub`. Only contexts broadcast or subscribe. Broadcasts happen **after commit** ([ADR 0006](adr/0006-realtime-pubsub-contract.md)).

Payloads carry **ids only**. Receivers refetch through context functions, which re-check access and fill per-viewer fields such as `my_ack`.

| topic | message | published by | consumed by |
|---|---|---|---|
| `"conversation:<id>"` | `{:message_created, conversation_id, message_id}` | `Chat.post_message/3`, `Chat.post_announcement/3` | ChatLive: refetches with `Chat.get_message/2` for the open pane, and with `Chat.get_conversation/2` for the sidebar row |
| `"conversation:<id>"` | `{:ack_updated, message_id, %{acknowledged: n, total: n}}` | `Chat.acknowledge/2`, `Chat.broadcast/1` (WP2b) | `ChatLive.Announcements` hook |
| `"user:<id>"` | `{:conversation_joined, conversation_id}` / `{:conversation_left, conversation_id}` | `Chat.broadcast/1`, `create_group`, `start_dm` (other user, on create), `leave_group` | ChatLive |
| `"user:<id>"` | `{:conversation_read, conversation_id}` | `Chat.mark_read/2` | ChatLive (other tabs of the same user) |
| `"user:<id>:access"` | `{:access_revoked, organisation_id}` | `Org.end_membership/2` | `SonaCommsWeb.OrgAuth` hook (every member LiveView) |
| `"org:<id>"` | `{:org_changed, :venue \| :team \| :membership}` | `Org` writes | OrgLive.Index, OrgLive.Members |

**Ordering.** When ending a membership revokes access, `{:access_revoked, _}` is published **before** the `{:conversation_left, _}` events. PubSub delivers messages from one sender in order, and `push_navigate` ends the LiveView, so an offboarded user lands on `/no-access`, not `/`.

Every LiveView that subscribes defines a catch-all `handle_info/2`.

## 5. Routes

This is the complete `router.ex` after WP1. **It does not change after WP1.**

```elixir
# The generated `scope "/" … get "/", PageController, :home` block is REMOVED
# (along with PageController, PageHTML, home.html.heex and page_controller_test.exs).

if Application.compile_env(:sona_comms, :dev_routes) do
  import Phoenix.LiveDashboard.Router

  scope "/dev" do
    pipe_through :browser

    live_dashboard "/dashboard", metrics: SonaCommsWeb.Telemetry
    forward "/mailbox", Plug.Swoosh.MailboxPreview

    get "/switch-user", SonaCommsWeb.DevSessionController, :index
    post "/switch-user/:user_id", SonaCommsWeb.DevSessionController, :create
  end
end

scope "/", SonaCommsWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{SonaCommsWeb.UserAuth, :require_authenticated}] do
    live "/users/settings", UserLive.Settings, :edit
    live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

    # member-gated: on_mount {SonaCommsWeb.OrgAuth, :require_member} inside the module
    live "/", ChatLive, :index
    live "/c/:id", ChatLive, :show
    live "/c/:id/announce", ChatLive, :announce
    live "/c/:id/announcements/:message_id", ChatLive, :receipts
    live "/announcements", ChatLive, :announcements
    live "/new/dm", ChatLive, :new_dm
    live "/new/group", ChatLive, :new_group

    # admin-gated: on_mount {SonaCommsWeb.OrgAuth, :require_admin} inside the module
    live "/org", OrgLive.Index, :index
    live "/org/venues/new", OrgLive.Index, :new_venue
    live "/org/venues/:venue_id/teams/new", OrgLive.Index, :new_team
    live "/org/members", OrgLive.Members, :index          # ?venue_id= filter via handle_params
    live "/org/members/new", OrgLive.Members, :new

    # authenticated only: where users without an active membership land
    live "/no-access", NoAccessLive, :index
  end

  post "/users/update-password", UserSessionController, :update_password
end

scope "/", SonaCommsWeb do
  pipe_through [:browser]

  live_session :current_user,
    on_mount: [{SonaCommsWeb.UserAuth, :mount_current_scope}] do
    live "/users/register", UserLive.Registration, :new
    live "/users/log-in", UserLive.Login, :new
    live "/users/log-in/:token", UserLive.Confirmation, :new
  end

  post "/users/log-in", UserSessionController, :create
  delete "/users/log-out", UserSessionController, :delete
end
```

Why each route sits where it does:

- **Chat, Org and `/no-access` LiveViews** go in the existing `scope "/"` with `pipe_through [:browser, :require_authenticated_user]` and the **existing** `live_session :require_authenticated_user`.
  - They all need a logged-in user, and AGENTS.md requires authenticated LiveViews to live in that block.
  - Membership and admin checks are per-LiveView `on_mount` hooks, not a new `live_session`, because `/users/settings` and `/no-access` must stay reachable for users without memberships ([ADR 0004](adr/0004-offboarding-and-access-gate.md)).
- **`/`** is the app itself, so the PageController home is removed.
  - Unauthenticated visitors are redirected to `/users/log-in` by the `:require_authenticated_user` plug.
  - After a normal login, `UserAuth.signed_in_path/1` returns `/` for a logged-out conn.
  - `UserAuth.log_out_user/1` is changed to redirect to `/users/log-in`. Otherwise logging out would land on the now-protected `/` and show "Logged out" and "You must log in" together.
- **Dev switcher** goes in the existing `/dev` scope inside `if dev_routes`, with `pipe_through :browser` only.
  - It is the login mechanism, so it can't require auth, and it is never compiled into prod ([ADR 0007](adr/0007-dev-user-switcher.md)).
  - `config/test.exs` sets `dev_routes: true` so the switcher can be tested.
- **Query params** (e.g. `/org/members?venue_id=3`) are allowed without router changes.

## 6. LiveView seams, DOM ids, ownership and vocabulary

### 6.1 Seams

WP2a (ChatLive), WP2b (announcements) and WP2c (org screens) never edit each other's files. The seams below are created by WP1 and must be preserved.

```elixir
# SonaCommsWeb.ChatLive (owned by WP2a)
on_mount {SonaCommsWeb.OrgAuth, :require_member}

def mount(_params, _session, socket) do
  {:ok, socket |> ... |> SonaCommsWeb.ChatLive.Announcements.attach()}
end

def handle_params(params, _uri, socket) do
  socket = ... # assigns @conversation for :show / :announce / :receipts
  {:noreply, SonaCommsWeb.ChatLive.Announcements.apply_action(socket, socket.assigns.live_action, params)}
end

# Every {:message_created, conversation_id, message_id} for the open conversation:
#   {:ok, msg} = Chat.get_message(scope, message_id)  ->  stream_insert(socket, :messages, msg)
# Never build a message from the broadcast. Per-viewer fields (my_ack) only come from get_message/2.
```

`SonaCommsWeb.ChatLive.Announcements` (owned by WP2b):

- `attach/1` assigns `announcement_form: nil` and `receipt_summary: nil`, initialises the streams `:pending_receipts` and `:read_receipts` (empty), then attaches hooks:
  - `:handle_event` for `"validate_announcement"`, `"announce"` and `"acknowledge"`, which returns `{:halt, socket}` for these events;
  - `:handle_info` for `{:ack_updated, message_id, _}`, which refetches with `Chat.get_message/2`, re-inserts the message into the `:messages` stream, re-streams the receipt lists if the receipts modal is open, and halts.
- `apply_action/3` fills `@announcement_form` for `:announce`, and `@receipt_summary` plus both receipt streams (`reset: true`) for `:receipts`. It is a no-op for other actions.

ChatLive template obligations (WP2a):

```heex
<AnnouncementComponents.announce_button conversation={@conversation} />   <%!-- in the header --%>

<div id="messages" phx-update="stream">
  <div :for={{dom_id, msg} <- @streams.messages} id={dom_id}>
    <AnnouncementComponents.announcement_message :if={msg.kind == :announcement}
      message={msg} conversation={@conversation} current_scope={@current_scope} />
    <%!-- WP2a renders msg.kind == :text --%>
  </div>
</div>

<AnnouncementComponents.announcement_modal :if={@live_action in [:announce, :receipts]}
  live_action={@live_action} conversation={@conversation}
  form={@announcement_form} summary={@receipt_summary}
  pending_receipts={@streams.pending_receipts} read_receipts={@streams.read_receipts} />
```

- Stream names are `:conversations` (sidebar) and `:messages`, using the default dom ids (`conversations-<id>`, `messages-<id>`).
- `conversation={@conversation}` lets the card read `can_announce`, so it can decide who sees "X of Y read".
- Access revocation is handled by `SonaCommsWeb.OrgAuth`, not ChatLive.
- Modals use `<.modal>` from `core_components.ex`, added by WP1.
- `Layouts.app` gets `attr :full_bleed, :boolean, default: false` for the chat's full-height layout.

**WP1's ChatLive stub is live enough for WP2b to test on its own branch.**

- `:index` streams `:conversations` with `#unread-<id>` and `#pending-acks-<id>` (when > 0).
- `:show` renders `#conversation-header` with the announce button, and `#messages` with the call sites above.
- `:show` subscribes to the open conversation and inserts on `{:message_created, _, _}` via `Chat.get_message/2`.
- The stub has no composer.

### 6.2 DOM ids (tests rely on these)

| WP | ids |
|---|---|
| WP1 | `#dev-users`, `#switch-to-<user_id>`, `#nav-dev-switch-user`, `#nav-org`, `#nav-staff`, `#no-access` |
| WP2a | `#conversations`, `#conversations-<id>`, `#unread-<conversation_id>`, `#pending-acks-<conversation_id>`, `#conversation-header`, `#messages`, `#messages-<id>`, `#message-form`, `#no-conversation-selected`, `#new-dm-form`, `#new-group-form`, `#leave-group` |
| WP2b | `#announce-button`, `#announcement-form`, `#ack-<message_id>` (button), `#acked-<message_id>`, `#ack-summary-<message_id>`, `#receipts-modal`, `#pending-receipts`, `#read-receipts`; for priority: `#announcement-priority`, `#urgent-announcement-modal`, `#urgent-ack-<message_id>`, `#announcements-link`, `#pending-announcements-count`, `#pending-announcements`, `#list-ack-<message_id>`, `#pending-announcement-link-<message_id>` |
| WP2c | `#venues`, `#venues-<id>`, `#new-venue-button`, `#venue-form`, `#new-team-<venue_id>`, `#team-form`, `#members`, `#members-<membership_id>`, `#member-venue-filter`, `#membership-form`, `#end-membership-<membership_id>` (confirmed with `data-confirm`) |

WP1 stubs already render `#conversations`, `#conversations-<id>`, `#unread-<id>`, `#pending-acks-<id>`, `#conversation-header` and `#messages`, so WP2a restyles them without renaming.

### 6.3 File ownership

| files | WP1 | after WP1 |
|---|---|---|
| `lib/sona_comms/org.ex`, `lib/sona_comms/org/*` | writes | **WP2c** |
| `lib/sona_comms/chat.ex`, `lib/sona_comms/chat/*` | writes | **WP2b** |
| `lib/sona_comms_web/live/chat_live.ex`, `components/chat_components.ex` | stub | **WP2a** |
| `lib/sona_comms_web/live/chat_live/announcements.ex`, `components/announcement_components.ex` | stub | **WP2b** |
| `lib/sona_comms_web/live/org_live/*`, `components/org_components.ex` | stub | **WP2c** |
| `router.ex`, `layouts.ex`, `core_components.ex`, `user_auth.ex`, `org_auth.ex`, `DevSessionController`, `NoAccessLive`, `accounts/*`, `assets/css/app.css`, `assets/js/app.js`, migrations, seeds, existing `test/support/**` | writes | frozen |

- WP2a needs no context changes: everything it calls is in §3.1 and §3.2.
- WP2s style with Tailwind classes and use colocated hooks, so none of them needs `app.css` or `app.js`.
- A shared component beyond `core_components.ex` goes in your own component module.

### 6.4 UI vocabulary

The user is a hospitality GM. Code names (membership, acknowledge, receipt) never appear in the UI.

| concept | UI copy |
|---|---|
| admin nav | "Venues & teams" (`/org`), "Staff" (`/org/members`) |
| org conversation | the organisation's name |
| team conversation | "Bristol · FOH" |
| ad-hoc groups / DMs (sidebar sections) | "Group chats" / "Direct messages" |
| unread badge | a count bubble, with `aria-label` "3 unread messages" |
| pending-acknowledgement badge | an amber megaphone pill: "1 announcement" |
| acknowledge button / done state | "I've read this" / "Read at 14:02" |
| announcement summary | "1 of 45 read" |
| receipts modal sections | "Read" / "Not yet read" |
| a person's job level | "Role": Staff, Manager, Admin |
| role help text (membership form) | Admin: "Posts announcements to the whole group and its venues. Manages venues, teams and staff." Manager: "Posts announcements to their team, or their venue if they have no team." Staff: "Chats only." |
| empty team option | "No team (whole venue)" |
| end membership | button "Remove from Bristol · FOH"; confirm "Charlie will lose access to Bristol · FOH chats. If this is their only venue or team, they lose access to all chats." |
| no access page | "You're not on any venue or team yet. Ask your manager to add you." |

## 7. Work packages

### WP1: Domain, seeds and dev login

**Outcome.** Run `mix ecto.reset && mix phx.server`. Open `/dev/switch-user` and choose Bob: `/` lists exactly his three conversations (Sona Hospitality Group, London, London · Kitchen) with unread counts. Switch to Charlie from the nav pill: you land on `/`, and `/org` redirects to `/`. Choose Alice: `/org` renders the stub and the nav shows "Venues & teams" and "Staff". Every rule in §2.5 is proven by context tests.

**Build**

- Migrations: `add_name_to_users`, `create_org_tables`, `create_chat_tables` (§2).
- Schemas and changesets for all eight Org and Chat schemas. Update `User`, `Accounts` and `Scope` (§2.2).
- `SonaComms.Org` in full (§3.1) and `SonaComms.Chat` core (§3.2), including sync, revocation, `get_message/2`, broadcasts, and the §4 ordering.
- `SonaCommsWeb.OrgAuth`:
  - `on_mount(:require_member)` calls `Org.put_member_scope/1`; on `:no_access` it redirects to `/no-access`. When connected it calls `Org.subscribe_access/1` and attaches a `:handle_info` hook that turns `{:access_revoked, _}` into a `push_navigate` to `/no-access` with a flash.
  - `on_mount(:require_admin)` does the member check, then `Org.admin?/1`, otherwise redirects to `/` with a flash.
- Router exactly as §5. Delete PageController and its template and test. Set `dev_routes: true` in `config/test.exs`.
- `UserAuth.log_out_user/1` redirects to `~p"/users/log-in"`. Update the logout assertions in `user_auth_test.exs` and `user_session_controller_test.exs`.
- Add `<.modal>` to `core_components.ex`: an overlay with a focus trap, Escape and click-away to close, `on_cancel` taking a `JS` command, and an `id` attr.
- `Layouts.app`:
  - replace the Phoenix boilerplate header with app nav: brand, Chat, `#nav-org` "Venues & teams" and `#nav-staff` "Staff" (both only when `Scope.admin?/1`), user name, Settings, Log out;
  - add a dev-only "Switch user" pill (`#nav-dev-switch-user`) shown when `dev_routes` is on;
  - add the `full_bleed` attr.
- `DevSessionController`:
  - `index` lists `Org.directory/0`, grouped by venue and team, with role, one button per user (`#switch-to-<id>`);
  - `create`, if someone is already logged in on this host, deletes their session token and broadcasts `"disconnect"` on their `live_socket_id` (exactly as `log_out_user/1` does);
  - it then `put_session(:user_return_to, ~p"/")` (otherwise `signed_in_path/1` sends an already-logged-in conn to Settings) and calls `UserAuth.log_in_user/3`.
- `NoAccessLive` (`#no-access`): the §6.4 copy and a log-out link.
- Stubs that satisfy §6.1:
  - `ChatLive` (live `:show` as described there; the other actions render the modal call site);
  - `ChatLive.Announcements` (`attach/1` and `apply_action/3` set defaults only);
  - `AnnouncementComponents` (plain markup);
  - `OrgLive.Index` and `OrgLive.Members` (heading only, with `:require_admin`).
- `priv/repo/seeds.exs`, using the contexts only and `Scope.for_system(org.id)`:
  - organisation "Sona Hospitality Group"; venues London, Manchester, Bristol; teams Kitchen, FOH and Bar in each venue;
  - 5 staff per team (1 manager + 4 staff), 45 in total, with deterministic names and `<first>@sona.test` emails;
  - Bob is London · Kitchen manager and Charlie is Bristol · FOH staff;
  - Alice gets a venue-level `:admin` membership at each venue;
  - a few sample messages (org welcome from Alice, a London · Kitchen thread, a Bristol · FOH thread);
  - on a non-empty DB, **`raise`** with a hint to run `mix ecto.reset` (never `System.halt`).
- Fixtures:
  - `SonaComms.OrgFixtures`: `organisation_fixture`, `venue_fixture`, `team_fixture`, `membership_fixture`, `member_scope_fixture/1`, and `demo_org_fixture/0`, which returns `%{org, london, bristol, kitchen, foh, alice, bob, charlie, conversations: %{org, london, kitchen, bristol, foh}}`;
  - `SonaComms.ChatFixtures`: `message_fixture`, `dm_fixture`, `group_fixture`, `receipt_fixture` (inserts directly).

**Tests**

- `test/sona_comms/org_test.exs`
  - Structure:
    - `create_organisation` creates exactly one org conversation;
    - `create_venue` creates one conversation, and a user-scoped `create_venue` adds the creator as a venue admin;
    - `create_team` creates a "Venue · Team" conversation with no participants;
    - `create_team` returns `:not_found` for another org's venue.
  - Authorization:
    - a non-admin scope gets `:unauthorized` on every structure and membership write;
    - an admin whose admin membership has ended, but whose scope still has `admin?: true`, is refused (the DB check wins).
  - `create_membership`:
    - with a team, it adds org, venue and team participation; without one, org and venue only;
    - it finds existing users by email and creates new ones;
    - it returns changeset errors for a duplicate active slot, a team from another venue, a venue from another org, and a user active in another org.
  - `can_announce`:
    - the §2.5 matrix holds for Alice, Bob and Charlie via `demo_org_fixture`, plus a venue-level manager and a team-level admin;
    - a role change (end one membership, create another) flips the flag.
  - `end_membership`:
    - ending one of two memberships removes only the conversation no longer backed;
    - ending the last one sets `left_at` in every derived, DM and group conversation;
    - it deletes pending receipts and keeps acknowledged ones;
    - it broadcasts `{:access_revoked, org_id}` on `user:<id>:access` **before** `{:conversation_left, _}` on `user:<id>`;
    - it returns `:not_found` for another org's membership, `:already_ended` twice, and `:cannot_end_own_membership` for your own.
  - Afterwards:
    - `put_member_scope` returns `:no_access`, and sets `organisation_id` and `admin?` for members;
    - rehire re-activates the same participant rows;
    - sync, `create_group`, `start_dm` and `leave_group` broadcast `{:conversation_joined}` / `{:conversation_left}` to the right `user:<id>` topics.
  - Queries:
    - `list_colleagues` excludes self and ended members;
    - `list_memberships` honours `venue_id:` and `include_ended:`.
- `test/sona_comms/chat_test.exs`
  - `list_conversations`: returns active participations only, in kind then recency order, with `display_title` (team label, DM other person).
  - Unread: counts others' messages, ignores your own, and resets on `mark_read`, which broadcasts `{:conversation_read, id}`.
  - Access:
    - `get_conversation`, `list_messages`, `get_message` and `post_message` return `:not_found` for non-participants and leavers;
    - `subscribe_conversation` refuses non-participants.
  - `list_messages` honours `limit:` and `before:`.
  - DMs and groups:
    - `start_dm` is idempotent in either direction and rejects non-members and self;
    - `create_group` validates its members;
    - `leave_group` works for groups and returns `:not_leavable` for derived conversations and DMs.
  - `sync_participants` raises for `:dm` and `:group`.
  - `post_message` broadcasts `{:message_created, conversation_id, message_id}`.
- `test/sona_comms/seeds_test.exs`
  - `Code.eval_file("priv/repo/seeds.exs")` produces:
    - 3 venues, 9 teams and 46 users;
    - 13 conversations with 46 org participants;
    - memberships and conversations for Alice, Bob and Charlie as in §2.5.
  - A second run raises.
- `test/sona_comms_web/controllers/dev_session_controller_test.exs`
  - `index` lists the personas;
  - `create` logs in and redirects to `/`;
  - while logged in as someone else, `create` still redirects to `/` and broadcasts `"disconnect"` on the previous `live_socket_id`.
- `test/sona_comms_web/org_auth_test.exs`
  - a member reaches `/`;
  - a user without memberships is redirected to `/no-access`;
  - non-admins are redirected from `/org`;
  - `#nav-org` shows for Alice and not for Bob or Charlie;
  - broadcasting `{:access_revoked, _}` pushes a connected `/` LiveView to `/no-access`.
- Existing phx.gen.auth tests stay green, with the updated logout redirects.

### WP2a: Chat UI

**Outcome.** In two persona tabs (`bob.localhost:4000` and a London · Kitchen colleague), Bob and his colleague chat live:

- sidebar unread badges update in real time;
- opening a conversation clears its badge;
- they can start a DM and create a group chat;
- leaving the group chat removes it from the sidebar.

**Build** (owns `chat_live.ex`, `chat_components.ex`)

- Full-bleed two-pane layout.
  - Sidebar (`:conversations` stream) has the sections Organisation, Venues, Teams, Group chats and Direct messages, with `#unread-<id>` and `#pending-acks-<id>` badges per §6.4.
  - Conversation pane (`:messages` stream) has a header with participant count and the §6.1 announce button slot, plus a composer (`#message-form`).
  - Responsive per AGENTS.md: on narrow screens, the sidebar shows at `/` and the pane at `/c/:id` with a back link.
- Subscriptions: `Chat.subscribe_user/1`, plus `Chat.subscribe_conversation/2` for every active conversation.
  - On `:message_created`: if the conversation is open, refetch the message with `Chat.get_message/2`, insert it and `mark_read`. Otherwise refetch the row with `Chat.get_conversation/2` and `stream_insert` it.
  - On `:conversation_joined`: subscribe and insert. On `:conversation_left`: unsubscribe and delete, and if it was open, `push_navigate` to `/` with the flash "You no longer have access to …".
  - On `:conversation_read`: clear the badge.
- `/new/dm` and `/new/group` modals (`<.modal>`) use `Org.list_colleagues/1`. `#leave-group` appears only for group chats.
- Colocated hooks allowed: scroll to bottom, Enter to send.

**Tests**

- `test/sona_comms_web/live/chat_live/index_test.exs`:
  - Bob sees `#conversations-<id>` for his three conversations and not Bristol's;
  - `#no-conversation-selected` shows at `/`.
- `test/sona_comms_web/live/chat_live/conversation_test.exs`:
  - `/c/:id` renders `#messages`;
  - submitting `#message-form` appends a message;
  - a second user's connected LiveView receives it live;
  - `#unread-<id>` increments on a LiveView where the conversation is not open and clears when opened;
  - a non-participant opening `/c/:id` is redirected to `/` with a flash;
  - ending the membership behind the open team conversation (user keeps another membership) navigates to `/`.
- `test/sona_comms_web/live/chat_live/new_conversation_test.exs`:
  - `#new-dm-form` creates or reuses a DM and navigates to it;
  - `#new-group-form` creates a group chat visible to its members;
  - `#leave-group` removes it.

### WP2b: Announcements and acknowledgements

**Outcome.** Demo steps 3 to 5 (§8) work live:

- Alice posts an allergen announcement to the org conversation;
- Bob's tab shows it with "I've read this" and a pending badge;
- Bob clicks it;
- Alice's "1 of 45 read" updates without reload;
- the receipts modal lists who hasn't read it.

**Build** (owns `chat.ex`, `chat/*`, `chat_live/announcements.ex`, `announcement_components.ex`)

- §3.3 functions:
  - receipts are inserted with `Repo.insert_all` in the post transaction;
  - acknowledgements are idempotent via `acknowledged_at IS NULL`;
  - per-viewer announcement virtuals and `pending_ack_count` are populated in every read function;
  - `{:receipts_removed, …}` becomes `{:ack_updated, …}`.
- Components (copy per §6.4):
  - `announce_button` (`#announce-button`, only when `conversation.can_announce`);
  - `announcement_message`, a visually distinct card that shows:
    - for recipients: `#ack-<id>`, or `#acked-<id>` with time;
    - for the sender and announcers (`message.sender_id == scope.user.id or conversation.can_announce`): `#ack-summary-<id>`, which links to the receipts route;
  - `announcement_modal` (`<.modal>`) with `#announcement-form` for `:announce`, and `#receipts-modal` with the `#pending-receipts` and `#read-receipts` streams for `:receipts`.
- The Announcements hook per §6.1.

**Tests**

- `test/sona_comms/chat/announcements_test.exs`
  - `post_announcement`:
    - staff, and team-level managers posting in their venue or org conversation, get `:unauthorized`;
    - posting in a DM or group chat gets `:unauthorized`;
    - Bob can post in London · Kitchen, and a venue-level manager can post in their venue conversation;
    - Alice's org announcement creates 45 receipts, none for her.
  - `acknowledge`: idempotent; non-recipients get `:not_found`.
  - `list_receipts`: `:not_found` for non-participants, `:unauthorized` for staff.
  - Late joiners: someone who joins after posting has `my_ack: nil` and isn't counted.
  - `pending_ack_count` is set in `list_conversations` and `get_conversation`.
  - Offboarding: `Org.end_membership` on a pending recipient drops the total from 45 to 44 and broadcasts `{:ack_updated, _, %{total: 44}}`, while an acknowledged recipient stays counted.
- `test/sona_comms_web/live/chat_live/announcements_test.exs`
  - Alice submits `#announcement-form` on `/c/:org/announce`.
  - Bob's connected LiveView on `/c/:org` shows `#ack-<id>` live; clicking it swaps to `#acked-<id>`.
  - Alice's LiveView `#ack-summary-<id>` updates to "1 of 45 read" live.
  - `/c/:org/announcements/:id` shows `#pending-receipts` and `#read-receipts`.
  - Bob's freshly mounted `/` shows `#pending-acks-<org_id>`.
  - Charlie has no `#announce-button`, and Bob has it only in London · Kitchen.

### WP2c: Org lifecycle

**Outcome.** Demo step 6 (§8):

- Alice opens Staff, filters to Bristol and removes Charlie;
- Charlie's open tab is pushed to `/no-access`, and every `/c/:id` stays inaccessible to them;
- Alice creates a venue and sees its conversation appear in her sidebar;
- she adds a team, which shows "0 people" until staff are added to it.

**Build** (owns `org.ex`, `org/*`, `org_live/*`, `org_components.ex`, copy per §6.4)

- `OrgLive.Index` ("Venues & teams"):
  - venues with their teams and people counts (`#venues` stream);
  - a create-venue modal (`#venue-form`);
  - create-team (`#new-team-<venue_id>` opens `#team-form`).
- `OrgLive.Members` ("Staff"):
  - `#members` stream with name, venue, team and role;
  - `#member-venue-filter` patches `?venue_id=`;
  - `/org/members/new` holds `#membership-form`, whose team select depends on the chosen venue (`phx-change`), with role help text and "No team (whole venue)";
  - `#end-membership-<id>` uses `data-confirm` with the §6.4 copy.
- Both screens subscribe via `Org.subscribe_org/1` and re-stream on `{:org_changed, _}`.

**Tests**

- `test/sona_comms_web/live/org_live/index_test.exs`:
  - admin sees `#venues`;
  - `#venue-form` creates a venue, its conversation exists, and Alice holds a membership there;
  - `#team-form` creates a team whose conversation exists with no participants;
  - Bob and Charlie are redirected away from `/org`.
- `test/sona_comms_web/live/org_live/members_test.exs`:
  - `#member-venue-filter` narrows `#members`;
  - `#membership-form` with a new email creates the user, the membership and their participations;
  - an invalid team or venue combination shows errors;
  - `#end-membership-<id>` removes the row.
- `test/sona_comms_web/live/offboarding_test.exs`:
  - Charlie is connected on `/c/:foh`;
  - Alice ends Charlie's membership through the Staff LiveView;
  - Charlie's LiveView redirects to `/no-access` (not `/`), and a fresh `live(conn, "/c/:foh")` redirects to `/no-access`.

## 8. Demo script (post-merge acceptance)

1. `mix ecto.reset && mix phx.server`
2. Open three tabs. Session cookies are per host, so each tab keeps its own user ([ADR 0007](adr/0007-dev-user-switcher.md)):
   - `http://alice.localhost:4000/dev/switch-user`: choose Alice.
   - `http://bob.localhost:4000/dev/switch-user`: choose Bob.
   - `http://charlie.localhost:4000/dev/switch-user`: choose Charlie, then open **Bristol · FOH**.
3. **Alice**: open **Sona Hospitality Group**, click **Announce**, and post "Allergen update: new sesame-containing supplier from Monday. Read the updated allergen matrix before your next shift." The card shows **0 of 45 read**.
4. **Bob**: without a reload, the org conversation gets a "1 announcement" pill and the card appears with **I've read this**. Click it.
5. **Alice**: the card updates live to **1 of 45 read**. Clicking it shows 44 under **Not yet read**.
6. **Alice**: open **Staff**, filter to **Bristol**, and click **Remove from Bristol · FOH** on Charlie's row (their only venue or team). Confirm.
7. **Charlie**: the tab is pushed to **No access** live. Visiting `/` or any `/c/:id` stays on No access.
8. **Alice**: the announcement now reads **1 of 44 read** (Charlie's pending receipt was dropped).
