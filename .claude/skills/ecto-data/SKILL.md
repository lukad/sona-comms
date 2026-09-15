---
name: ecto-data
description: "Load when editing lib/sona_comms/**, priv/repo/**, or on Ecto.Query / changeset errors."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

### phoenix

- [ecto](references/phoenix/ecto.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p phoenix -p ecto_sql
```

## Available Mix Tasks

- `mix compile.phoenix`
- `mix phx` - Prints Phoenix help information
- `mix phx.digest` - Digests and compresses static files
- `mix phx.digest.clean` - Removes old versions of static assets.
- `mix phx.gen` - Lists all available Phoenix generators
- `mix phx.gen.auth` - Generates authentication logic for a resource
- `mix phx.gen.auth.hashing_library`
- `mix phx.gen.auth.injector`
- `mix phx.gen.auth.migration`
- `mix phx.gen.cert` - Generates a self-signed certificate for HTTPS testing
- `mix phx.gen.channel` - Generates a Phoenix channel
- `mix phx.gen.context` - Generates a context with functions around an Ecto schema
- `mix phx.gen.embedded` - Generates an embedded Ecto schema file
- `mix phx.gen.html` - Generates context and controller for an HTML resource
- `mix phx.gen.json` - Generates context and controller for a JSON resource
- `mix phx.gen.live` - Generates LiveView, templates, and context for a resource
- `mix phx.gen.notifier` - Generates a notifier that delivers emails by default
- `mix phx.gen.presence` - Generates a Presence tracker
- `mix phx.gen.release` - Generates release files and optional Dockerfile for release-based deployments
- `mix phx.gen.schema` - Generates an Ecto schema and migration file
- `mix phx.gen.secret` - Generates a secret
- `mix phx.gen.socket` - Generates a Phoenix socket handler
- `mix phx.routes` - Prints all routes
- `mix phx.server` - Starts applications and their servers
- `mix ecto.dump` - Dumps the repository database structure
- `mix ecto.gen.migration` - Generates a new migration for the repo
- `mix ecto.load` - Loads previously dumped database structure
- `mix ecto.migrate` - Runs the repository migrations
- `mix ecto.migrations` - Displays the repository migration status
- `mix ecto.rollback` - Rolls back the repository migrations
<!-- usage-rules-skill-end -->
