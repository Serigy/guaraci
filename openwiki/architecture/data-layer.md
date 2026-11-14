---
type: "Reference"
title: "Data Layer"
openwiki_generated: true
---


# Data Layer

Guaraci's data layer is a layered stack that provides database access without ever concatenating user input into SQL. It runs from a thin prepared-statement wrapper (`db`) down to a concrete SQLite driver, with a fluent query builder and a model registry (`Dataware`) on top that can generate CRUD routes automatically.

## Module stack

| Layer | Module | Role |
| --- | --- | --- |
| Wrapper | `src/db.lua` | Prepared-statement gateway, SQL validation, transactions |
| Driver | `src/sqlite_driver.lua` | lsqlite3 binding |
| Builder | `src/query_builder.lua` | Fluent query construction and execution |
| Registry | `src/dataware.lua` | Model registry and schema DSL |
| CRUD | `src/auto_crud.lua` | Route generator for models |
| Tenancy | `src/dataware_tenancy.lua` | Tenant extraction middleware |
| Audit | `src/dataware_audit.lua` | CRUD and tenant-violation audit events |

## Prepared-statement wrapper (`db`)

`db.execute(sql, params)` is the single gateway for every query in the framework. Before touching the driver it runs `validate_sql`, which rejects any SQL that is not parameterized: the statement must contain at least one `?` placeholder, the placeholder count must match the parameter count, the statement may not contain a semicolon (blocking stacked queries), and every parameter must be a scalar (`nil`, `boolean`, `number`, or `string`).

On a validation failure the query is blocked and a security event is logged; the caller receives `invalid_query`.

`db.with_transaction(work_fn)` runs `work_fn` between BEGIN and COMMIT, rolling back automatically when the function throws, returns an error, or when the commit itself fails.

## SQLite driver (`sqlite_driver`)

`sqlite_driver.from_lsqlite3(db_path, module)` loads (or accepts an injected) lsqlite3 module and opens a connection. `M.new(connection)` wraps the connection with an `execute_prepared` that always prepares the statement, binds parameters (via `bind_values` or a per-index `bind` fallback), reads rows through `nrows`, and finalizes the statement. Direct execution is used only for the fixed BEGIN/COMMIT/ROLLBACK statements.

## Query builder (`query_builder`)

`query_builder.new(model_definition, context)` returns a fluent builder with `select`, `where`, `order_by`, `limit`, `offset`, `with`, `all`, `first`, `paginate`, `create`, `update`, and `delete`. Two invariants keep it safe:

- every column, table, and tenant-field identifier passes `sanitize_identifier`, which accepts only `^[a-zA-Z_][a-zA-Z0-9_%.]*$`;
- every `where` operator must be in a fixed allow-list (`=`, `!=`, `<>`, `>`, `<`, `>=`, `<=`, `LIKE`, `IN`).

Tenancy is enforced during WHERE-clause assembly: when the model requires a tenant, the builder appends `tenant_id = ?` to every query and, if no tenant is set, logs a violation and aborts with `tenant_required`. `create` also injects the tenant id into the payload. `update` and `delete` refuse to run without at least one `where` filter.

## Model registry (`dataware`)

`dataware.model(name)` returns (and reuses) a model with defaults `table_name` = lowercased name + `s`, `primary_key` = `id`, and multi-tenancy **on** by default (`require_tenant = true`, `tenant_field = "tenant_id"`). The DSL exposes `schema`, `table`, `primary_key`, `tenant`, `without_tenant`, `has_many`, `find`, `create`, and `auto_crud`.

## Auto-CRUD (`auto_crud`)

`model:auto_crud(router, opts)` registers five routes — list (`GET base`), get (`GET base/:id`), create (`POST base`), update (`PUT base/:id`), delete (`DELETE base/:id`) — each resolving the tenant first. Errors map to statuses: `tenant_required` → 403, constraint violations → 409, `db_busy`/`db_locked` → 503 (marked `retryable`), and missing update/delete filters → 400.

## Tenancy and audit

`dataware_tenancy` reads the tenant from the `X-Tenant-Id` header (with query/request fallbacks) and, when absent, short-circuits with a 403. `dataware_audit` routes every create/update/delete and every tenant violation through the framework's security audit log.
