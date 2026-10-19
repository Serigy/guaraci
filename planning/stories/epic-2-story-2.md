# Epic 2 — Story 2: Build and serve the live simplified OpenAPI document

**Status:** Done

## User Story Goal

As a developer or API client, I want `GET /__guaraci/api-docs` to expose a valid, deterministic OpenAPI 3.0 document so that current routes can be inspected or imported.

## Prerequisites

Epic 2 Story 1 — Register and reset route introspection metadata

## Injected Technical Context

Create `src/api_explorer/openapi.lua`; create/register `tests/openapi_spec.lua`; add the module to `guaraci-scm-1.rockspec`. Required seams are `M.build_document(opts)` and `M.encode(doc)`. Rebuild per request; never cache or emit a static CLI file.

The document is OpenAPI `"3.0.3"` with `info.title` default `"Guaraci API"` and `info.version` from `guaraci_version`; include `paths`, operations, path/query parameters, request bodies, observable responses, and components. Generated descriptors map fields exactly: `string`, `number`, `integer`, `boolean`, and `table -> object/additionalProperties=true`; preserve `required`; include `tenant_id` only when `requires_tenant`. List has only `page` and `per_page` query parameters. Ad-hoc bodies are `{type="object", additionalProperties=true}` and receive no invented properties.

`operationId` is the registered route name; path parameters use `{id}`. Serialization must not depend on `pairs()` for `paths`, `properties`, or `responses`; preserve method, route-registration, field, and required order. On failure return HTTP 500 standard error and call `guaraci_audit.log_error("openapi_build_failed", {error=...})`.

Applicable PRD text (verbatim): “`GET /__guaraci/api-docs` deve retornar 200, `Content-Type: application/json; charset=utf-8` e um documento válido”; “Cada operação deve informar método, path, parâmetros de path, parâmetros de query quando conhecidos, `requestBody` ... e respostas observáveis”; “Campos do schema Dataware/validator devem mapear para tipos OpenAPI ... e `required` deve ser preservado”; “O endpoint deve retornar o catálogo atual do processo/request e não um arquivo stale.” FR06.2–FR06.4 and NFR01/NFR03/NFR05/NFR06 also apply.

## Implementation Checklist

- [x] Translate introspection/router/dataware metadata into the exact document shape and status descriptions.
- [x] Implement deterministic ordered-container encoding and safe JSON string escaping.
- [x] Ensure no closures, Lua code, credentials, tenant values, or stale file data enter the output.
- [x] Add tests for generated and ad-hoc routes, required fields, tenant schema, query parameters, and live second-request changes.
- [x] Add serialization failure coverage and audit assertion.

## Acceptance Criteria & Test Cases

- A generated Product route matches the architecture §3.4 shape, including 200/201/400/403/404 where applicable.
- An ad-hoc parametrized route has path parameters and generic body schema only.
- Two equivalent docs built with different associative insertion order encode identically; field and route order are stable.
- Registering a route between two builds changes the second document without process restart.
- `lua5.4 tests/run_all.lua`, `lua5.4 scripts/check_rockspec.lua`, and `luacheck src hooks scripts tests bin` pass.

## Dev Notes

Modified/created files:
- `src/api_explorer/openapi.lua` (new): `M.build_document(opts) -> doc | nil, err` (pcall-wrapped, never raises) and `M.encode(doc)`. Uses a small ordered-map helper (`new_omap`/`oset`) for `paths`, each path's per-method map, `responses`, and `components.schemas`/`properties` — the four places where key order carries runtime-determined meaning (route registration order, declared field order). Everything else (a parameter object, a `{type=...}` schema snippet, the operation object itself) is a plain Lua table; `M.encode` recurses into every value regardless of container kind, so a nested omap several levels deep is never accidentally handed to `pairs()`.
- `guaraci-scm-1.rockspec`: added `api_explorer.openapi`.
- `tests/busted_runner.lua`: registered `tests.openapi_spec`.
- `tests/openapi_spec.lua` (new): envelope defaults/overrides, full Product CRUD shape against architecture.md §3.4 (operationId, summary, parameters, requestBody, the exact non-alphabetical per-operation response-code order, components.schemas Product/ProductInput with field order and `required`), `--no-tenant`/no-fields omissions, the `table` → `object`/`additionalProperties` mapping, an ad-hoc route getting only path parameters + a generic body schema and no invented `properties`, no `parameters` key when an operation has none, byte-identical re-encoding, a route registered between two builds changing the second document, and a forced-failure path (`route_introspection.all` stubbed to error) proving `build_document` returns `nil, err` instead of raising, paired with a `guaraci_audit.log_error` call the caller is expected to make.

Notes (this cost real debugging time, worth recording):
- Found a flaky-looking failure: `tests.openapi_spec` passed in isolation but failed with 3 assertion errors when run after certain other spec files inside the *same* `lua5.4 tests/run_all.lua` process (e.g. after `cli_check_spec`, not after `cli_main_spec`/`cli_dev_spec`). Root cause was in the **tests**, not the implementation: a few assertions string-matched a literal substring like `'"Widget":{"type":"object","properties":{...}}'` assuming `type` always serializes before `properties` in a plain 2-key Lua table. Lua's `pairs()` order for a small literal table depends on the table's internal hash layout, which is sensitive to incidental factors (table size history, prior allocations in the same process) — it is *not* guaranteed to match source-code key order, and apparently differed depending on what ran earlier in the same process. Per architecture.md §5.5, only `paths`/`properties`/`responses`/`components.schemas` are documented as needing deterministic ordering (because their key set is runtime-determined); smaller fixed-key wrapper tables (`{type=,properties=}`, `{type=,additionalProperties=}`) were never meant to have a guaranteed key order. Fixed by loosening those three assertions to accept either key order (`a or b`) instead of asserting one exact adjacency. Re-ran `lua5.4`/`luajit` `tests/run_all.lua` three times each afterward with no flakes.
- Confirmed the architecture's claim that `json_util.encode`'s `pairs()`-based serialization is unsuitable for `paths`/`properties`/`responses`: it is not just "unstable across runs" but has no relationship to insertion order at all, which is why those four containers go through the ordered-map path while leaf/small-fixed-shape objects reuse `pairs()` safely.
- Found a second, more interesting bug the same way: after the ordering fix, a *file* (`tests/tmp_openapi_audit_<ts>_<rand>.log`) kept reappearing in `git status` after full-suite runs, even though the owning test read, asserted, and `os.remove`d it. Root cause: `guaraci_audit.set_log_path` mutates a process-wide singleton (`config.log_path` inside `src/guaraci_audit.lua`) with no restore helper, and my failure-path test called it to redirect logging for one assertion but never pointed it back at the default. Every later spec in the same `lua5.4 tests/run_all.lua` process that calls `guaraci_audit.log_error`/`log_security` without its own explicit path (several do) kept appending to my already-deleted throwaway filename, recreating it on disk by the time the run finished — 78 lines of unrelated log entries from `security_final_spec`/template specs by the end. `tests/dataware_audit_spec.lua` has the identical latent gap (also never restores the path) but it runs late enough in `SPEC_MODULES` that nothing downstream reads the default log, so it never surfaced. Fixed only in my own new test (not in scope to touch `dataware_audit_spec.lua` for this story): compute the actual default (`os.getenv("GUARACI_AUDIT_LOG") or "guaraci_audit.log"`) and call `audit.set_log_path(default_log_path)` again right after reading/removing my temp file. Confirmed with 3 repeated full-suite runs producing zero stray files and a clean `git status`.
- Verification: `lua5.4 tests/run_all.lua` (×3) → ALL SPECS PASSED; `luajit tests/run_all.lua` (×3) → ALL SPECS PASSED; `lua5.4 scripts/check_rockspec.lua` → ROCKSPEC CHECK: OK; `lua5.4 scripts/smoke_cgi.lua` → SMOKE CGI: OK; `luacheck --no-color src hooks scripts tests bin` → 0 warnings / 0 errors in 106 files.
- Scope note: this story only builds the `openapi.lua` module; it is not yet reachable over HTTP. `GET /__guaraci/api-docs` (and the other 3 explorer routes) are registered by `api_explorer/explorer.lua` in E2-S3, which will call `M.build_document`/`M.encode` from its route handler and do the actual HTTP-500 + `guaraci_audit.log_error` mapping on failure.

## QA Findings

- **Status:** Approved (mantido como Done)
- **Verificações Realizadas:**
  - Construção ao vivo do catálogo OpenAPI 3.0.3 a partir de `router_v2` e `route_introspection`, sem dependência de artefato estático (ADR-05).
  - Serialização determinística via `openapi.encode()`: uso de ordered maps (`omap`) para `paths`, `properties`, `schemas` e `responses`, eliminando variabilidade de iteração de tabelas Lua.
  - Mapeamento correto de tipos para todos os campos suportados (incluindo `table` -> `object` com `additionalProperties: true`).
  - Extração de múltiplos parâmetros de caminho em rotas aninhadas (ex: `/users/{user_id}/posts/{post_id}`).
  - Rotas framework internas `/__guaraci/...` nunca são vazadas no catálogo gerado.
  - Tratamento de erro resiliente: falhas de compilação retornam `nil, err` capturados com log de auditoria `openapi_build_failed`.
