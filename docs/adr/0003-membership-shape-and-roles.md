# 0003. Membership shape and roles

- Status: Accepted
- Date: 2026-09-15

## Context

A membership is `(user, venue, team, role, ended_at)`. The personas in [PRODUCT.md](../PRODUCT.md) stretch that shape:

- **Alice**, ops manager, works across three venues and broadcasts to one or all of them.
- **Bob**, head chef, messages the London kitchen.
- **Charlie**, FOH in Bristol, sees Bristol and Bristol FOH.

We need to model who sits where and who may announce or administer, without introducing a separate permissions system.

## Decision

- **`venue_id` is required and `team_id` is optional.** A membership without a team is venue-level. Alice holds one venue-level membership per site. Nobody holds an org-level row: being in the organisation means holding at least one active membership.
- A team must belong to the membership's venue. A composite foreign key `(team_id, venue_id)` referencing `teams(id, venue_id)` enforces this.
- There is at most one active membership per `(user, venue, team)` slot, enforced by a partial unique index with `NULLS NOT DISTINCT`.
- Memberships are never deleted. Ending one sets `ended_at`. A role change means ending the membership and creating a new one, which keeps history.
- **Roles** are `:staff | :manager | :admin`:

  | | participates in | can announce in | can manage the org |
  |---|---|---|---|
  | staff | org + venue (+ team) | nowhere | no |
  | manager | org + venue (+ team) | the conversation of the venue (if `team_id` is NULL) or team the membership points at | no |
  | admin | org + venue (+ team) | org conversation, and the venue (and team, if set) conversation of the membership | yes |

- An **org admin** is anyone holding at least one active `:admin` membership in the organisation. Managing venues, teams and memberships is org-wide.
- **One organisation per user** in the PoC. `create_membership` rejects a user who has active memberships in another organisation, so `put_member_scope/1` always resolves a single `organisation_id`.
- **Bootstrap:** seeds and tests use `Scope.for_system(organisation_id)`, a scope with `system?: true` and no user, to create the first venues, teams and memberships through the normal context functions. No UI can build this scope.
- **Creating a venue as an admin** also creates that admin's venue-level `:admin` membership, so the new venue's conversation appears in their sidebar straight away.

## Consequences

- Alice has three membership rows. That is honest: she really does work at three sites. It also gives her exactly the org conversation plus three venue conversations.
- Admin rights are recorded per venue but act org-wide. That is a deliberate PoC simplification; a real product might want per-venue administration.
- Managers announce in the conversation of the level their membership sits at. Bob can announce to London Kitchen but not to all of London.
- `Scope.for_system/1` is a privileged construct. It must only appear in `priv/repo/seeds.exs` and `test/`.
