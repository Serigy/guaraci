# Epic 3 — Story 2: Implement explorer request forms, responses, and CSRF handling

**Status:** Done

## User Story Goal

As a developer, I want to fill route parameters and JSON payloads, send test requests, and inspect the full response safely so that the explorer replaces manual HTTP tooling during development.

## Prerequisites

Epic 3 Story 1 — Serve the static same-origin explorer shell and assets

## Injected Technical Context

Modify `src/api_explorer/assets.lua` JS and add HTTP-level cases to `tests/api_explorer_spec.lua`; if the existing CSRF pipeline needs a narrow integration hook, modify only the relevant existing surface and add the required security regression case. The JS consumes the live OpenAPI document, groups/filter operations by method/path/name, renders required path/query/body controls, and sends GET/POST/PUT/PATCH/DELETE.

Requests must remain same-origin and construct paths only from validated relative route data plus encoded user values. JSON body is validated before send; mutating requests read `guaraci_csrf_token` and send exactly `X-CSRF-Token` with that value; GET/HEAD omit it. Responses display status, all available headers, and JSON pretty-printed when valid, otherwise exact text. Network, invalid JSON, 403, and all non-2xx errors remain visibly errors.

All mutations traverse the normal `handle_request` middleware chain. Missing/invalid CSRF remains 403 `csrf_token_invalid`; never disable or bypass middleware. Audit behavior follows existing `guaraci_audit`/dataware pipeline and must never expose tokens/secrets.

Applicable PRD text (verbatim): “O usuário deve conseguir enviar GET, POST, PUT, PATCH e DELETE”; “O cliente deve preservar same-origin”; “Após cada tentativa, a UI deve mostrar status HTTP, todos os headers”; “Erros de rede, JSON inválido e respostas não-2xx devem ser visíveis”; “Para cada requisição mutável emitida pela UI, o cliente deve enviar `X-CSRF-Token` com exatamente o mesmo valor do cookie”; “Se o cookie/header estiver ausente ou inválido, o servidor deve continuar respondendo conforme `middleware_csrf` (403 e código `csrf_token_invalid`)”; “Toda mutação disparada pelo explorer deve passar pela mesma cadeia de middleware da aplicação.” NFR02/NFR03/NFR05/NFR06 also apply.

## Implementation Checklist

- [x] Parse and render OpenAPI operations, parameters, schemas, examples, and required markers.
- [x] Build safe same-origin requests with encoded path/query values and JSON body validation.
- [x] Implement cookie reading and CSRF header behavior by method.
- [x] Render status, headers, JSON/text bodies, network errors, and non-2xx errors distinctly.
- [x] Add HTTP simulations for CSRF absent/equal, required-field 400 before SQL, tenant behavior, and response formatting.
- [x] Add parser/sandbox/security regression coverage if any protected pipeline surface changes.

## Acceptance Criteria & Test Cases

- UI source contains no `innerHTML` interpolation, `onclick`, external origin, `eval`, or `new Function`.
- GET/HEAD omit CSRF; POST/PUT/PATCH/DELETE echo the cookie exactly; absent/mismatched token produces visible 403 `csrf_token_invalid`.
- Required payload omission is shown client-side and server-side invalid payload returns 400 without a database call.
- A successful request shows status, every response header, and formatted JSON; plain text remains unchanged; network/non-2xx errors are not empty success.
- `lua5.4 tests/run_all.lua`, `luacheck src hooks scripts tests bin`, and `lua5.4 scripts/check_rockspec.lua` pass.
- Where applicable, run `curl` against `guaraci dev` to verify page, docs, assets, and a mutating request.

## Dev Notes

Modified/created files:
- `src/api_explorer/assets.lua` (completes E3-S1's catalog view): each operation now gets a "try it" `<form>` built from `createElement`/`textContent` only — one labeled text input per path/query parameter (path params visually marked `*`/required and checked client-side before sending), a JSON-body `<textarea>` when the operation has a `requestBody`, and a Send button. On submit: required path params are validated client-side; a non-empty body is `JSON.parse`d (invalid JSON shows an inline error and never sends) and must be a plain object (not array/primitive) or it's rejected client-side too. `readCookie("guaraci_csrf_token")` reads the cookie E3-S1 sets; `X-CSRF-Token` is sent with that exact value only for POST/PUT/PATCH/DELETE (never GET/HEAD). The response panel (`#response`/`#response-meta`/`#response-body`, static markup from E3-S1) is populated with status, every response header (via `Headers.forEach`), and the body — pretty-printed with `JSON.stringify(JSON.parse(body), null, 2)` when it parses as JSON, the raw text otherwise; network failures render a distinct "Network error" row instead of silently looking like success. Combined asset size is 17086 bytes (still well under the 50 KiB budget).
- `src/middleware_csrf.lua` (narrow CSRF-pipeline hook, explicitly pre-authorized by this story's own injected context): added `find_header(headers, name)`, a case-insensitive fallback header lookup, and used it for both the CSRF token header and the `Cookie` header.
- `tests/security_regression_spec.lua`: added the required security regression case for the CSRF fix (see below).
- `tests/api_explorer_spec.lua`: added static-source checks for the CSRF/validation/response-rendering/form-encoding behavior, plus an HTTP-level `handle_request` describe block covering CSRF absent/mismatched/matching, a required-field 400 that makes zero database calls (fake `db.set_driver`), a `--no-tenant` request not being blocked, and a tenant-required request without `X-Tenant-Id` returning 403.

Two significant findings from end-to-end verification over a real `guaraci dev` server (not just simulated `handle_request` calls, which the whole test suite — mine included — otherwise relies on exclusively):

1. **No JSON request-body decoder exists anywhere in the framework.** Confirmed by reading `src/adapter_cgi.lua` (only `application/x-www-form-urlencoded` and `multipart` bodies populate `req.body_table`) and `src/json_util.lua` (only `M.encode`, no `M.decode`). A `Content-Type: application/json` request would never populate `req.body_table` over real HTTP/CGI, so `auto_crud`'s create/update handlers would always see it as a missing body. This directly affects this story's own acceptance criterion ("run curl... to verify... a mutating request"). **Resolution kept inside this story's own scoped file**: `app.js`'s JSON editor still validates the payload as a JSON object client-side (satisfying "corpo JSON é validado antes do envio"), but transmits it as `application/x-www-form-urlencoded` form fields (top-level keys, JSON-stringifying any nested object/array value) — a format `adapter_cgi.lua` already parses correctly today. This also happens to match the documented "table" field contract more precisely (§3.2: the column stores the JSON-encoded string, not a nested object). No core framework file was touched for this; verified end-to-end with `curl --data-urlencode` against a scaffolded endpoint. **Recommend a future story add a real `json_util.decode` + `adapter_cgi.lua` JSON body path** so a genuine `application/json` client (not just this explorer) works; flagged for the orchestrator/QA role, same as the router_v2 bug from E2-S3.
2. **`adapter_cgi.lua`'s header-name round-trip breaks every case-sensitive header lookup over real HTTP.** `guaraci dev`'s `cgi_env` builds `HTTP_X_CSRF_TOKEN`/`HTTP_COOKIE` env vars via `name:upper()`, and `adapter_cgi.parse_headers` turns those back into `X-CSRF-TOKEN`/`COOKIE` (all upper-case) — which matches neither a Title-Case nor an all-lowercase lookup. Confirmed directly: `middleware_csrf.lua`'s old `headers[header_name] or headers[string.lower(header_name)]` found neither `"X-CSRF-Token"` nor `"x-csrf-token"` against the real `"X-CSRF-TOKEN"` key, so **CSRF protection never actually worked over real HTTP/CGI before this fix** — only in handle_request-level tests that construct the headers table with whatever casing the test author chose, which is every CSRF test that existed before this story. Fixed (per this story's explicit pre-authorization to patch the CSRF pipeline with a narrow hook) via a case-insensitive `find_header` helper in `middleware_csrf.lua`, covering both the token header and the cookie header. Verified over a real `guaraci dev` server: a matching `X-CSRF-Token` now passes through to the real handler (confirmed by the response changing from `403 csrf_token_invalid` to a downstream, CSRF-unrelated error from the handler itself).
3. **The identical case-mismatch bug also affects `src/dataware_tenancy.lua`'s default tenant-header extractor** (`headers["X-Tenant-Id"] or headers["x-tenant-id"]`, which likewise never matches the real `"X-TENANT-ID"` key) — confirmed directly over a real `guaraci dev` server: a tenant-required endpoint returned 403 `Tenant context required` even with `X-Tenant-Id` set correctly. **This one was left unfixed**: `dataware_tenancy.lua` is outside every one of this chain's 8 stories' file lists, and this story's injected context only pre-authorizes a narrow hook into "the existing CSRF pipeline," not the tenant system. Flagging it prominently here and in memory for the orchestrator/QA role — it is a real, currently-shipping defect (tenant extraction via header has never worked over real HTTP/CGI, only in direct `handle_request` tests), independent of anything in this BMAD chain, and arguably more impactful than the CSRF one since multi-tenancy is a core framework feature advertised everywhere in the architecture docs.
- Verification: `lua5.4 tests/run_all.lua` (×3) and `luajit tests/run_all.lua` (×2) → ALL SPECS PASSED, no stray files; `lua5.4 scripts/check_rockspec.lua` → ROCKSPEC CHECK: OK; `lua5.4 scripts/smoke_cgi.lua` → SMOKE CGI: OK; `luacheck --no-color src hooks scripts tests bin` → 0 warnings / 0 errors in 109 files. End-to-end over a real `guaraci dev` server with `curl`: explorer page/cookie, a CSRF-protected mutating POST (403 without token, passes CSRF with a matching token), and generated-endpoint GET/POST all exercised directly (not just simulated).
