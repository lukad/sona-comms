# 0007. Development user switcher

- Status: Accepted
- Date: 2026-09-15

## Context

[PRODUCT.md](../PRODUCT.md) scopes a "user switcher in development". The demo needs Alice, Bob and Charlie **at the same time**: Bob's tab updates live while Alice's count updates live. phx.gen.auth's magic-link login is too slow for demos. Session cookies are shared by every tab on the same host, so switching user in one tab would switch all of them.

## Decision

- `SonaCommsWeb.DevSessionController` gets two actions:
  - `index` (`GET /dev/switch-user`) lists `Org.directory/0`: Alice, Bob and Charlie first, then everyone grouped by venue and team with their role, including users with no active membership;
  - `create` (`POST /dev/switch-user/:user_id`) switches the user in three steps:
    1. if someone is already logged in on this host, it deletes their session token and broadcasts `"disconnect"` on their `live_socket_id`, exactly as `log_out_user/1` does, because `log_in_user/3` alone would leave the old user's LiveViews connected;
    2. it sets `:user_return_to` to `/`, because `signed_in_path/1` sends an already-logged-in conn to `/users/settings`;
    3. it calls `UserAuth.log_in_user/3`, the same code path as a real login.
- The routes live in the existing `if Application.compile_env(:sona_comms, :dev_routes)` `/dev` scope with `pipe_through :browser`. **They are not compiled into prod.** `config/test.exs` enables `dev_routes` so the controller can be tested.
- `Layouts.app` shows a "Switch user" link only when `dev_routes` is enabled.
- **Side-by-side personas use host-scoped cookies.** Open `alice.localhost:4000`, `bob.localhost:4000` and `charlie.localhost:4000`; browsers resolve `*.localhost` to loopback and keep a separate session cookie per host. The dev endpoint already has `check_origin: false`, so LiveView sockets connect from any of these hosts.
- The real login (email + password or magic link) is unchanged.

## Consequences

- The demo needs no extra browser profiles, and the switch uses production login code rather than a bypass.
- `Org.directory/0` is compiled into prod but only reachable from dev routes. It must not be called from anything else.
- Because `dev_routes` is enabled in the test env, the LiveDashboard and mailbox routes also exist in tests. That is harmless.
- Anyone who can reach a dev server can log in as anyone. That is acceptable for local development only, and dev binds to `127.0.0.1`.
