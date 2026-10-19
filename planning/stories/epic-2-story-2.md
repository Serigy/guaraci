# Epic 2 — Story 2: Build and serve the live simplified OpenAPI document

**Status:** Ready

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

- [ ] Translate introspection/router/dataware metadata into the exact document shape and status descriptions.
- [ ] Implement deterministic ordered-container encoding and safe JSON string escaping.
- [ ] Ensure no closures, Lua code, credentials, tenant values, or stale file data enter the output.
- [ ] Add tests for generated and ad-hoc routes, required fields, tenant schema, query parameters, and live second-request changes.
- [ ] Add serialization failure coverage and audit assertion.

## Acceptance Criteria & Test Cases

- A generated Product route matches the architecture §3.4 shape, including 200/201/400/403/404 where applicable.
- An ad-hoc parametrized route has path parameters and generic body schema only.
- Two equivalent docs built with different associative insertion order encode identically; field and route order are stable.
- Registering a route between two builds changes the second document without process restart.
- `lua5.4 tests/run_all.lua`, `lua5.4 scripts/check_rockspec.lua`, and `luacheck src hooks scripts tests bin` pass.
