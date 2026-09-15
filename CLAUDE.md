@AGENTS.md
@docs/PRODUCT.md

- Read docs/PLAN.md and pick up only the work package you were given.
- Run `mix precommit` before reporting done. Never report done with warnings or failing tests.
- Use Tidewave (project_eval, execute_sql_query, get_logs) to verify behaviour in the running app instead of reasoning about it.
- Use `mix usage_rules.search_docs "<term>" -p <pkg>` before guessing an API.
- Contexts are the public API; LiveViews call context functions only.
