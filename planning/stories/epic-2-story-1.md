# Epic 2 — Story 1: Register and reset route introspection metadata

**Status:** Done

## User Story Goal

As an API tooling consumer, I want the router’s current routes and explicit generated-resource descriptors available in stable order so that documentation reflects reality without executing handlers.

## Prerequisites

Epic 1 Story 2 — Wire the endpoint generator and safe file creation

## Injected Technical Context

Create `src/route_introspection.lua`; modify `src/guaraci_cli/dev.lua` to clear it during `reset_app_state`; add the module to `guaraci-scm-1.rockspec`; create/register `tests/route_introspection_spec.lua`.

Required API:

```lua
M.describe(method, pattern, descriptor) -> true
M.get(method, pattern) -> descriptor | nil
M.all() -> { { method, pattern, name, param_names, descriptor } }
M.clear()
```

Internal key is `METHOD .. " " .. pattern`. `descriptor` is `{model, operation, fields, requires_tenant}` and is nil for ad-hoc routes. `all()` follows fixed methods `GET, POST, PUT, PATCH, DELETE, HEAD`, then `router_v2.get_routes(method)` registration order; never use unordered `pairs()` for document ordering. `param_names` comes from router metadata and `:param` patterns. The generated route from Story 1 calls `describe` after `auto_crud.generate`.

Applicable PRD text (verbatim): “O produto deve expor uma leitura aditiva das rotas registradas em `router_v2`”; “A descoberta deve refletir todas as rotas registradas, inclusive rotas avulsas; não deve executar handlers para construir o catálogo”; “A ordem do documento deve ser determinística”; “Rotas sem modelo devem exibir os parâmetros de caminho extraídos do padrão ... não podem receber campos inventados.” NFR03 and NFR06 also apply. The catalog must be additive, explicit, and must not infer route/model links by name.

## Implementation Checklist

- [x] Implement `describe/get/clear` with overwrite idempotence for one method/pattern.
- [x] Read registered route metadata without invoking route handlers.
- [x] Implement stable aggregation with descriptor lookup and path parameter extraction.
- [x] Clear metadata on every dev reload alongside router, middleware, hooks, and models.
- [x] Add module/package/spec registration.

## Acceptance Criteria & Test Cases

- Manual descriptors round-trip with exact model, operation, fields, and tenant shape.
- A second `describe` for the same key replaces the descriptor; `clear` returns an empty catalog.
- Static and `:id` routes, generated and ad-hoc, appear in fixed method/registration order; ad-hoc entries have no invented fields.
- Two simulated dev reloads do not retain stale descriptors or duplicate metadata.
- Run `lua5.4 tests/run_all.lua`, `lua5.4 scripts/check_rockspec.lua`, and `luacheck src hooks scripts tests bin`.

## Dev Notes

Modified/created files:
- `src/route_introspection.lua` (new): `M.describe/get/all/clear`, keyed on `"METHOD pattern"`, fixed `GET,POST,PUT,PATCH,DELETE,HEAD` iteration order over `router_v2.get_routes(method)` (registration order within a method, never `pairs()`).
- `src/guaraci_cli/dev.lua`: `reset_app_state` now also clears `route_introspection` when loaded (guarded by `package.loaded`, matching ADR-06 — this module is never force-required by `dev.lua`/`guaraci.lua`, only cleared if some app code already pulled it in).
- `guaraci-scm-1.rockspec`: added `route_introspection`.
- `tests/busted_runner.lua`: registered `tests.route_introspection_spec`.
- `tests/route_introspection_spec.lua` (new): round-trip shape, method/pattern key sensitivity, overwrite idempotence, `clear()`, fixed-order aggregation mixing generated + ad-hoc + static + `:id` routes, a check that `all()` never invokes a handler, and two simulated dev-reload cycles with no stale/duplicate descriptors.

Notes:
- End-to-end sanity check beyond the story's own unit tests: regenerated a `Product` (tenant, 2 fields) and a `Widget` (`--no-tenant`, no fields) endpoint with `bin/guaraci` in a scratch directory and ran their generated `spec/*_spec.lua` files directly — all 10 generated assertions passed (list/create/400/404/tenant-isolation for Product; list/create/non-table-400/404/no-tenant-header for Widget). This was blocked in E1-S2 because `route_introspection` did not exist yet; it now resolves and the whole generator → runtime chain works.
- Verification: `lua5.4 tests/run_all.lua` → ALL SPECS PASSED; `luajit tests/run_all.lua` → ALL SPECS PASSED; `lua5.4 scripts/check_rockspec.lua` → ROCKSPEC CHECK: OK; `lua5.4 scripts/smoke_cgi.lua` → SMOKE CGI: OK; `luacheck --no-color src hooks scripts tests bin` → 0 warnings / 0 errors in 104 files.
- No conflict found between this story's instructions and Epic 1's code.
