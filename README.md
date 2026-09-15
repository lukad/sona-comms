# SonaComms

A PoC for an internal messaging app in hospitality businesses where group membership follows organizational structure rather than manual configuration.

An organization has venues, venues have teams, and staff have memberships. Conversations are created automatically for each org, venue, and team. Creating or removing memberships automatically adds or removes the member from the conversation group. Managers can post announcements that need to be explicitly acknowledged by recipients. Direct messages and ad-hoc groups are also supported.

Messages are delivered in real-time using via PubSub. See [`docs/PRODUCT.md`](docs/PRODUCT.md) for the product description and [`docs/adr/`](docs/adr/) for the architecture decisions.

## Run it

To start your Phoenix server:

- Run `mix setup` to install and setup dependencies
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

`mix setup` will seed the database with sample data needed for the demo. In development, you can visit [`localhost:4000/dev/switch-user`](http://localhost:4000/dev/switch-user) to switch between users.

## Demo

1. Log in as Alice (Admin) in one browser, Bob (head chef, Bristol) in another, and finally Charlie (staff, Bristol) in a third.
2. As Alice, post an announcement in the Bristol chat.
3. Bob's chat updates live; acknowledge it.
4. Alice's read count updates immediately.
5. As Alice, remove Charlie from the staff list, they instantly lose access.
