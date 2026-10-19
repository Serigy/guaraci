# Epic 3 — Story 2: Implement explorer request forms, responses, and CSRF handling

**Status:** Ready

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

- [ ] Parse and render OpenAPI operations, parameters, schemas, examples, and required markers.
- [ ] Build safe same-origin requests with encoded path/query values and JSON body validation.
- [ ] Implement cookie reading and CSRF header behavior by method.
- [ ] Render status, headers, JSON/text bodies, network errors, and non-2xx errors distinctly.
- [ ] Add HTTP simulations for CSRF absent/equal, required-field 400 before SQL, tenant behavior, and response formatting.
- [ ] Add parser/sandbox/security regression coverage if any protected pipeline surface changes.

## Acceptance Criteria & Test Cases

- UI source contains no `innerHTML` interpolation, `onclick`, external origin, `eval`, or `new Function`.
- GET/HEAD omit CSRF; POST/PUT/PATCH/DELETE echo the cookie exactly; absent/mismatched token produces visible 403 `csrf_token_invalid`.
- Required payload omission is shown client-side and server-side invalid payload returns 400 without a database call.
- A successful request shows status, every response header, and formatted JSON; plain text remains unchanged; network/non-2xx errors are not empty success.
- `lua5.4 tests/run_all.lua`, `luacheck src hooks scripts tests bin`, and `lua5.4 scripts/check_rockspec.lua` pass.
- Where applicable, run `curl` against `guaraci dev` to verify page, docs, assets, and a mutating request.
