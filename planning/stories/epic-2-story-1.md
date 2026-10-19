# Epic 2 — Story 1: Register and reset route introspection metadata

**Status:** Ready

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

- [ ] Implement `describe/get/clear` with overwrite idempotence for one method/pattern.
- [ ] Read registered route metadata without invoking route handlers.
- [ ] Implement stable aggregation with descriptor lookup and path parameter extraction.
- [ ] Clear metadata on every dev reload alongside router, middleware, hooks, and models.
- [ ] Add module/package/spec registration.

## Acceptance Criteria & Test Cases

- Manual descriptors round-trip with exact model, operation, fields, and tenant shape.
- A second `describe` for the same key replaces the descriptor; `clear` returns an empty catalog.
- Static and `:id` routes, generated and ad-hoc, appear in fixed method/registration order; ad-hoc entries have no invented fields.
- Two simulated dev reloads do not retain stale descriptors or duplicate metadata.
- Run `lua5.4 tests/run_all.lua`, `lua5.4 scripts/check_rockspec.lua`, and `luacheck src hooks scripts tests bin`.
