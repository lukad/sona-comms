# 0005. Announcements and receipts

- Status: Accepted
- Date: 2026-09-15

## Context

[PRODUCT.md](../PRODUCT.md) scopes "announcements with acknowledgement (X of Y read)". In the demo, Alice posts an allergen announcement that everyone must read, Bob acknowledges it, and Alice sees the count update live. Alice "broadcasts to one or all sites". The open questions:

- where announcements live;
- how Y is defined, especially when people leave;
- how acknowledgement relates to ordinary unread tracking.

## Decision

- An announcement is a `Message` with `kind: :announcement`. It shares the table, the stream and the ordering with text messages.
- It is posted into **exactly one derived conversation** (`org`, `venue` or `team`). "All sites" means the org conversation. There is no fan-out to several conversations.
- Posting requires the author's participant row to have `can_announce` ([ADR 0003](0003-membership-shape-and-roles.md)). DMs and groups never allow announcements.
- **Snapshot receipts:** in the same transaction as the message, one `message_receipts` row is inserted for every active participant except the sender. **Y is the number of receipt rows; X is the number with `acknowledged_at` set.**
- Acknowledging sets `acknowledged_at` on the caller's own receipt. It is idempotent, and only people who hold a receipt can acknowledge.
- When a recipient leaves the conversation (including through offboarding), their **pending** receipt is deleted, so Y shrinks, while acknowledged receipts are kept. People who join later get no receipt: they can read the announcement but aren't counted in Y.
- **Unread is not a receipt.** Unread counts for every message kind come from `participants.last_read_at`. Receipts exist only for announcements and mean "explicitly acknowledged", not "seen".
- **Visibility:** the sender and participants with `can_announce` see "X of Y acknowledged" and the pending and acknowledged lists. Recipients see only their own state.
- Changes are pushed as `{:ack_updated, message_id, %{acknowledged: x, total: y}}` on `"conversation:<id>"` ([ADR 0006](0006-realtime-pubsub-contract.md)). `my_ack` differs per viewer, so receivers always refetch the message through `Chat.get_message/2` rather than rendering from a broadcast.
- **UI copy says "read"**, to match PRODUCT.md: the button is "I've read this", the summary "X of Y read", and the lists "Read" / "Not yet read". Code keeps `acknowledge` and receipts. The explicit button is what separates it from the automatic unread tracking.
- **Priority** (added 2026-09-18, after customer feedback that staff were overwhelmed by announcements): every announcement has a `priority` of `:low`, `:mid` (the default) or `:high`, and text messages have none. A check constraint enforces this. Pending `:high` announcements open a modal on the chat screens that can't be dismissed until the recipient has read them, one at a time. Every pending announcement also appears in the `/announcements` list, high first, then mid, then low. `Chat.list_pending_announcements/1` feeds both. The admin screens under `/org` don't block.

## Consequences

- The model is simple: one stream, one receipts table, and counts are a `COUNT` over an indexed column.
- Y always means "people who were asked and can still answer", so an announcement can reach 100% after offboarding.
- **Known limitation:** a new hire who joins after an allergen announcement is not asked to acknowledge it. A later iteration might add receipts on join for announcements that are still open.
- Sending to two specific venues means posting twice, or posting in the org conversation. Multi-target fan-out and an aggregated count are out of scope.
