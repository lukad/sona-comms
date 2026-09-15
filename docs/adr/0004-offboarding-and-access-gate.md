# 0004. Offboarding and the access gate

- Status: Accepted
- Date: 2026-09-15

## Context

The demo in [PRODUCT.md](../PRODUCT.md) ends with Charlie's contract ending: Alice removes their membership, and Charlie's open chats close and are no longer accessible. We have to decide three things:

- what happens to participant rows and history;
- whether DMs and ad-hoc groups are affected;
- how access is enforced, both on page load and live.

## Decision

**Data**

- Ending a membership sets `ended_at` and resyncs the affected org, venue and team conversations. The person leaves any derived conversation that no other active membership still backs.
- When the **last** active membership in the organisation ends, `Chat.revoke_org_access/2` also sets `left_at` on the person's `:dm` and `:group` participations in that organisation. Offboarding means losing access to *all* of the organisation's chat.
- Participants are **soft-removed** (`left_at`), never deleted. Messages stay, and other people still see the leaver's messages under their name.
- When someone leaves a conversation, their **pending** announcement receipts in it are deleted. Acknowledged receipts are kept ([ADR 0005](0005-announcements-and-receipts.md)).
- The user account is not deleted. The person can still log in, but they land on `/no-access`.
- **Rehire:** a new membership re-activates the same participant rows (`left_at = nil`, `last_read_at = now`). Previously visible history becomes visible again.

**Enforcement**

- Every Chat read and write checks for an active participant row. A leaver gets `{:error, :not_found}`, the same result as someone who never participated, so nothing leaks. **This database check is the real guard.**
- **Mount gate:** member LiveViews declare `on_mount {SonaCommsWeb.OrgAuth, :require_member}`, and org screens declare `on_mount {SonaCommsWeb.OrgAuth, :require_admin}`. The hook calls `Org.put_member_scope/1` and redirects users without an active membership to `/no-access`.
- These routes stay inside the **existing** `live_session :require_authenticated_user`, as AGENTS.md requires. We do not add a new membership-gated `live_session`, because `/users/settings` and `/no-access` share that session and must stay reachable for users without memberships.
- **Live kick:** when connected, `OrgAuth` subscribes to `"user:<id>:access"`. On `{:access_revoked, org_id}` it sends every open member LiveView to `/no-access` with a flash.
- **Ordering:** Org publishes `{:access_revoked, _}` before the `{:conversation_left, _}` events. PubSub delivers messages from one sender in order, and `push_navigate` ends the LiveView, so an offboarded user always lands on `/no-access`, never `/`. Losing a single conversation while staying in the organisation (for example, removed from a team) is handled by ChatLive on `{:conversation_left, id}`: it leaves the conversation if that is the one open.

## Consequences

- There is a full audit trail of who was in which conversation and when, and offboarding never destroys data.
- A rehired person sees messages posted while they were away. That is acceptable for the PoC, and a real product might hide the gap.
- The live kick is a UX guarantee layered on PubSub. If a broadcast is missed, the next action still fails the database check, so security doesn't depend on delivery.
- Each member LiveView must declare the `on_mount` itself. Forgetting it is a review finding, and the tests in `org_auth_test.exs` cover the gate.
