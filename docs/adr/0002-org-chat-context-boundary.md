# 0002. One-way boundary: Org depends on Chat

- Status: Accepted
- Date: 2026-09-15

## Context

There are two contexts:

- `SonaComms.Org`: organisations, venues, teams, memberships.
- `SonaComms.Chat`: conversations, participants, messages, receipts.

Org has to create conversations and sync participants ([ADR 0001](0001-derived-conversations-materialised-participants.md)). Chat has two questions that look like Org questions:

- Who may post an announcement? That depends on the membership role.
- Who may be DMed or added to a group? Only active members of the same organisation.

If Chat called Org to answer them, the two contexts would depend on each other in a cycle.

## Decision

- **Org depends on Chat, never the reverse.** Nothing under `lib/sona_comms/chat*` references `SonaComms.Org`. Chat may depend on `SonaComms.Accounts`, which sits below both.
- Chat stores `organisation_id`, `venue_id` and `team_id` as plain `:id` fields with database foreign keys, **not** `belongs_to` to Org schemas.
- Org **compiles** roles into participant rows. `can_announce` is computed during sync from the role matrix ([ADR 0003](0003-membership-shape-and-roles.md)), so Chat checks its own row and never needs to know what a "manager" is.
- Chat treats the **active participants of the org conversation** as the set of organisation members. `start_dm/2` and `create_group/2` validate against it.
- Authorization reads the database at the moment of the call:
  - Chat checks participant rows (active, and `can_announce` where needed);
  - Org checks active memberships for admin rights (`Org.admin?/1`).

  `Scope` holds only plain values set by Org at mount (`organisation_id`, `admin?`). It never holds Org structs, so Accounts does not depend on Org. `admin?` is a cache for UI gating only (showing the admin nav links, for example) and is never trusted for writes.
- LiveViews and controllers call context functions only (CLAUDE.md). They never call `Repo` or build Ecto queries.

## Consequences

- Chat can be reasoned about and tested without Org semantics. Its tests build participants with fixtures.
- The reviewer can mechanically flag boundary violations, such as `SonaComms.Org` appearing in Chat or `Repo` appearing in `_web`.
- A role change only takes effect in chat after a resync. Org does that as part of every membership write, and a role change is modelled as ending one membership and creating another.
- The org conversation must always exist. It is created with the organisation, and a unique index guarantees one per organisation.
- A stale `Scope.admin?` can briefly show UI that the next action refuses. That is acceptable, because the database check is authoritative.
