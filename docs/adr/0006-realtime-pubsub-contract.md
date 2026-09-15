# 0006. Realtime PubSub contract

- Status: Accepted
- Date: 2026-09-15

## Context

The scope includes live messages, live unread counts, live acknowledgement counts and a live offboarding kick. WP2a, WP2b and WP2c are built in parallel, so topic names and payloads must be agreed up front.

## Decision

- Use `Phoenix.PubSub` (`SonaComms.PubSub`). Only contexts call `broadcast` or `subscribe`, through functions such as `Chat.subscribe_conversation/2` and `Org.subscribe_access/1`. LiveViews never name topics themselves.
- Topics:

  | topic | messages |
  |---|---|
  | `"conversation:<id>"` | `{:message_created, conversation_id, message_id}`, `{:ack_updated, message_id, %{acknowledged: x, total: y}}` |
  | `"user:<id>"` | `{:conversation_joined, id}`, `{:conversation_left, id}`, `{:conversation_read, id}` |
  | `"user:<id>:access"` | `{:access_revoked, organisation_id}` |
  | `"org:<id>"` | `{:org_changed, :venue \| :team \| :membership}` |

- Broadcast **only after the transaction commits**. Inside a transaction, contexts collect events (for example, `sync_participants/2` returns `[event]`) and publish them once the transaction has succeeded.
- When one action emits several events, Org publishes `{:access_revoked, _}` before the Chat participation events. Each subscriber receives them in that order ([ADR 0004](0004-offboarding-and-access-gate.md)).
- Payloads carry **ids only**. Receivers refetch through context functions, for example `Chat.get_message/2` on `:message_created`. The refetch re-checks access and fills per-viewer fields, such as an announcement's `my_ack`, which a single broadcast payload could not carry.
- `subscribe_conversation/2` refuses non-participants.
- ChatLive subscribes to `"user:<id>"` and to `"conversation:<id>"` for every active conversation. It subscribes on `:conversation_joined` and unsubscribes on `:conversation_left`.
- `OrgAuth` alone subscribes to `"user:<id>:access"`, so every member LiveView gets the kick without handling it itself.
- Every subscribing LiveView has a catch-all `handle_info/2`.

## Consequences

- WP2 packages can be built and tested in isolation. Tests subscribe and `assert_receive` on these exact tuples.
- A user in N conversations holds N subscriptions. That is fine at PoC scale (at most about 10). At real scale we would fan out new-message notifications to `"user:<id>"` at write time instead.
- Every viewer runs one extra query per new message. That is fine at PoC scale.
- No content travels over PubSub, so a stale subscription after removal leaks nothing: the refetch returns `:not_found`.
- PubSub works across nodes (`dns_cluster` is already a dependency), so nothing assumes a single node.
