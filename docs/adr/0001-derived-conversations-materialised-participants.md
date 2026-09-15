# 0001. Derived conversations with materialised participants

- Status: Accepted
- Date: 2026-09-15

## Context

The wedge in [PRODUCT.md](../PRODUCT.md) is that nobody administers org, venue or team conversations. Their participants follow from memberships `(user, venue, team, role, ended_at)`:

- creating a venue or team creates its conversation;
- adding a membership adds the person;
- ending it removes them.

We also need per-participant state (`last_read_at` for unread counts). DMs and ad-hoc groups need explicit participant lists anyway, and every read path needs a cheap, uniform access check.

Options considered:

1. **Compute on read.** Derive participants from memberships with a query or view on every access check. This gives one source of truth, but it has nowhere to keep per-user state, and DMs and groups need a second mechanism.
2. **Materialise participant rows, synced by domain code** when memberships change.
3. **Database triggers** that maintain participants. This hides logic from the application and is hard to test and evolve.

## Decision

We materialise participants (option 2).

- `conversation_participants` holds one row per `(conversation, user)` with `can_announce`, `last_read_at` and `left_at`. Every kind (`org`, `venue`, `team`, `group`, `dm`) uses the same table and the same access check: an active row, `left_at IS NULL`.
- For derived kinds (`org`, `venue`, `team`), participant rows are written **only** by `Chat.sync_participants/2`, and only `SonaComms.Org` calls it. Chat exposes no add or remove function for derived kinds, and `leave_group/2` refuses them.
- Sync is a **full, idempotent recompute** for one conversation. Org computes the desired `%{user_id => can_announce}` from active memberships (rules in PLAN.md §2.5), and the sync:
  - upserts desired users (a rejoining user gets `left_at = nil`, `last_read_at = now`);
  - updates changed flags;
  - sets `left_at = now` on the rest.
- Sync runs inside the same `Repo.transact` as the membership write, with the conversation row locked `FOR UPDATE` to serialise concurrent changes. PubSub broadcasts happen after commit.
- `last_read_at`, `left_at`, `messages.inserted_at` and `acknowledged_at` are `utc_datetime_usec`. Second precision would miscount unread messages posted in the same second as a read.

## Consequences

- Access checks, unread counts and sidebar listings are simple indexed queries on one table, whatever the conversation kind.
- Membership history (`ended_at`) and participation history (`left_at`) are both kept, and a rehire re-activates the existing rows.
- The same fact is stored in two places: memberships are the truth and participants are the projection. Every membership change **must** go through `SonaComms.Org`. Any other writer is a bug, and the reviewer flags it.
- Because the sync is idempotent, drift can be repaired by re-running it for any conversation.
- Each sync costs O(members of the conversation). That is trivial at PoC scale (46 users). Large organisations would need an incremental sync for the org conversation.
