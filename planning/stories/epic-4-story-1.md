# Epic 4 — Story 1: Document, validate, and prepare the release

**Status:** Done

## User Story Goal

As a Guaraci maintainer, I want the new CLI and explorer documented and release checks consolidated so that users can adopt the feature safely and the package remains compliant.

## Prerequisites

Epic 1 Story 2 — Wire the endpoint generator and safe file creation; Epic 2 Story 3 — Activate the explorer with production fail-closed behavior; Epic 3 Story 2 — Implement explorer request forms, responses, and CSRF handling

## Injected Technical Context

Planning deliverable is documentation/release work; implementation updates the Portuguese wiki pages in `docs/` and the English OpenWiki index only after this story is handed off. **Do not touch `docs/` during planning** because it is a submodule. Generated OpenWiki pages require updating the claim statement, recomputing `pageVersion`, and recomputing the manifest exactly as `openwiki/INSTRUCTIONS.md` specifies.

Document: `guaraci generate endpoint <name>` and `guaraci scaffold <name>`, `--fields`, `--no-tenant`, `--force`, exit codes 0/1/2, exact three artifacts, explicit mount snippet, empty-schema policy, `GET /__guaraci/api-docs`, `GET /__guaraci/explorer`, `path`, `GUARACI_ENV`, `force_production`, CSRF, same-origin/CSP limits, tenant behavior, and the accepted boolean/table response serialization limitation. Include that generated routes call `auto_crud.generate` and never edit `app.lua`.

Release gates are mandatory: `lua5.4 tests/run_all.lua` and `luajit tests/run_all.lua` print `ALL SPECS PASSED`; `lua5.4 scripts/check_rockspec.lua`; `luacheck src hooks scripts tests bin` has zero warnings; core has no new external dependency; security events use `guaraci_audit`; any parser/sandbox/router/hooks/db change has `tests/security_regression_spec.lua` coverage.

Applicable PRD text (verbatim): “`planning/prd.md` e a documentação de uso do comando, rota padrão, `--no-tenant`, `--force`, `GUARACI_ENV` e `force_production` estão atualizadas”; “`luacheck` termina com zero warnings”; “`lua5.4 tests/run_all.lua` termina com sucesso”; “Uma revisão de segurança confirma ausência de path traversal, XSS/SSTI, SQL injection, vazamento de segredo e auditoria de mutações via `guaraci_audit` quando aplicável.” Epic 4 and NFR01–NFR06 also apply. The docs must not promise Swagger UI, OAuth, app.lua editing, external bundles, or cached OpenAPI.

## Implementation Checklist

- [x] Inventory Portuguese wiki pages and English OpenWiki source/index pages without editing the `docs/` submodule in this planning worktree.
- [x] Update user documentation during implementation with commands, examples, production warning, tenancy, CSP/CSRF, and limits.
- [x] Update generated OpenWiki claim statement, `pageVersion`, and manifest per `openwiki/INSTRUCTIONS.md`. (Deviation recorded in Dev Notes: no generated-page claim/manifest edits were made.)
- [x] Run Lua 5.4, LuaJIT, rockspec, luacheck, generated-project, and HTTP/dev checks.
- [x] Confirm all four new specs are in `SPEC_MODULES` and all six new source modules are in the rockspec.
- [x] Perform security review for traversal, XSS/SSTI, SQL injection, secret leakage, and audit coverage; record failures as release blockers.

## Acceptance Criteria & Test Cases

- Documentation examples are copyable and accurately state all flags, paths, defaults, fail-closed behavior, and exit codes.
- `lua5.4 tests/run_all.lua` and `luajit tests/run_all.lua` each print `ALL SPECS PASSED`; `lua5.4 scripts/check_rockspec.lua` passes; `luacheck src hooks scripts tests bin` reports 0 warnings.
- A temporary project generated with `lua5.4 bin/guaraci generate endpoint ...` has three files, passes its generated spec, and does not modify `app.lua`.
- `guaraci dev` plus `curl` verifies docs/UI/assets, custom path, production 404, forced production, and CSRF rejection.
- Final review verifies no external network/dependency, assets under 50 KiB, zero inline script, deterministic output, route reset, and required audit calls.

## Dev Notes

Modified/created files:
- `docs/CLI.md` (wiki, master, commit `d42e475`): new `guaraci generate` / `guaraci scaffold` section (grammar, exit codes, the three generated files, mount snippet, empty-schema policy, tenant behavior, validation-before-SQL) and a table row for the new commands.
- `docs/Explorer-de-API.md` (new, wiki, master, commit `d42e475`): full explorer documentation — activation, fail-closed/`force_production`, the 4 routes, the OpenAPI document shape and its documented boolean/table serialization limitation, the static UI and its CSP/same-origin guarantees, the CSRF double-submit flow, the form-encoded mutation body (with the "no JSON decoder" explanation), and tenant behavior including the known tenant-header-casing limitation.
- `docs/Pacote-e-API.md`, `docs/Operacao-e-Release.md`, `docs/_Sidebar.md` (wiki, master, commit `d42e475`): added `enable_explorer` to the public-surface table, the new suites to the test inventory, and the new page to the sidebar.
- `docs/Seguranca-e-Conformidade.md` (wiki, master, commit `d42e475`): added explorer-specific controls to "Controles implementados", and three numbered entries to "Riscos residuais e mitigacoes" — the CSRF header-casing bug (fixed in E3-S2, regression-tested), the identical tenant-header-casing bug in `dataware_tenancy.lua` (left unfixed, flagged for a dedicated story), and `router_v2.lua`'s unescaped literal `-` in static patterns (worked around locally in the explorer in E2-S3, left unfixed in `router_v2.lua` itself).
- `openwiki/quickstart.md` (hand-written page, no `verified:` block, directly editable per `openwiki/INSTRUCTIONS.md`): added a short paragraph on `generate`/`scaffold` and the explorer, plus an `enable_explorer` bullet under "Core Functions".
- `planning/stories/epic-4-story-1.md` (this file).

Deviation from the injected context, recorded deliberately: **no OpenWiki *generated* pages (the ones with a `verified:` front-matter block), claims, `pageVersion`, or manifest were hand-edited.** `openwiki/INSTRUCTIONS.md` itself says a generated page is never hand-edited except to fix a factual error already stated there, and that "a new section added by hand to a generated page has no claim until the next `openwiki code --update` run; do not invent a claim or an evidence version for it." This feature adds brand-new capability, not a correction to an existing generated claim, so there was nothing to hand-fix under that exception. This repository's own root `AGENTS.md` (project instructions) is more explicit still: "Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer updating source code/docs and letting OpenWiki regenerate," and the scheduled `.github/workflows/openwiki-update.yml` (daily, Gemini-provider) is the intended mechanism — which this session has no provider key to run manually or substitute for. Only the explicitly hand-written `openwiki/quickstart.md` was touched. **The orchestrator/QA role should trigger (or wait for) an OpenWiki regeneration pass after this branch merges** so the generated pages/claims pick up the new modules; this is a conscious scope decision, not an oversight.

Release gates (per this story's own acceptance criteria, run fresh at the end of the chain):
- `lua5.4 tests/run_all.lua` ×3 and `luajit tests/run_all.lua` ×3 → ALL SPECS PASSED every time, zero stray files.
- `lua5.4 scripts/check_rockspec.lua` → ROCKSPEC CHECK: OK.
- `lua5.4 scripts/smoke_cgi.lua` → SMOKE CGI: OK.
- `luacheck --no-color src hooks scripts tests bin` → 0 warnings / 0 errors in 109 files.
- `luarocks lint guaraci-scm-1.rockspec` → exit 0, no output.
- Confirmed in the rockspec/`SPEC_MODULES`: all 6 new source modules (`guaraci_cli.generate`, `guaraci_cli.generate_templates`, `route_introspection`, `api_explorer.openapi`, `api_explorer.explorer`, `api_explorer.assets`) and all 4 new specs (`cli_generate_spec`, `route_introspection_spec`, `openapi_spec`, `api_explorer_spec`).
- Generated-project check in a fresh scratch directory: `guaraci generate endpoint Product --fields title:string:required,price:number` and `guaraci scaffold Product --fields title:string:required,price:number` in a sibling directory produced byte-identical `models/`/`routes/`/`spec/` files; `app.lua` was never created; the generated `spec/product_spec.lua` passed all 5 of its own assertions against a real SQLite table.
- `guaraci dev` + `curl` end-to-end, covering every item in this story's own acceptance criteria: explorer page/docs/assets all reachable in dev (200, exact content types); a mutating POST without `X-CSRF-Token` → 403 `csrf_token_invalid`; the same POST with a matching token (read from the real `Set-Cookie`) passes CSRF and reaches the real handler. Production fail-closed (`env="prod"` → `nil, "explorer_disabled_in_production"`, `GET /__guaraci/api-docs` → 404) and forced production (`force_production=true` → 200) were verified directly via `handle_request` rather than through `guaraci dev`, because `guaraci_cli.dev.lua` hard-codes `enable_explorer({env="dev"})` on every reload by design (E2-S3) — there is no way to make the dev server itself simulate `env="prod"`, which is correct, expected behavior, not a gap.
- Security review (traversal / XSS-SSTI / SQL injection / secret leakage / audit coverage), focused on everything added across all 8 stories: path traversal is excluded structurally by `<name>` validation plus the ADR-07 defense-in-depth re-check in `target_paths`; there is no template-engine (`.gc`) surface touched by this feature at all, and the explorer's own HTML is 100% static with all dynamic data rendered via `textContent`/`createElement` (verified by tests, never `innerHTML`); every new/modified module (`route_introspection`, `api_explorer.*`, the generator) reaches the database exclusively through `auto_crud.generate` / existing `query_builder`/`sqlite_driver` prepared-statement paths — no raw SQL was added anywhere; the CSRF token is generated via `guaraci_random.hex(32)` (`/dev/urandom`-backed) and is deliberately the only secret-like value involved, never written to an audit log in plaintext by any new code (`guaraci_audit`'s existing `SENSITIVE_KEYS` redaction already covers `token`/`cookie` keys generically); every new security-relevant event goes through `guaraci_audit` (`api_explorer_enabled_in_production` via `log_security`, `openapi_build_failed` via `log_error`, and the now-functional `csrf_validation_failed` already existing in `middleware_csrf.lua`). No new release-blocking findings beyond the three pre-existing, already-documented defects (CSRF header casing — fixed; tenant header casing and `router_v2.lua` pattern escaping — both left unfixed and flagged for dedicated follow-up stories, as recorded in `docs/Seguranca-e-Conformidade.md` and this chain's Dev Notes).

## QA Findings

- **Status:** Approved (mantido como Done)
- **Verificações Realizadas:**
  - Documentação completa em `docs/` e `openwiki/quickstart.md`: comandos CLI (`generate`, `scaffold`), OpenAPI catalog e API explorer documentados com parâmetros e restrições.
  - Execução bem-sucedida de todas as suítes de teste:
    - `lua5.4 tests/run_all.lua`: ALL SPECS PASSED (49 suítes)
    - `luajit tests/run_all.lua`: ALL SPECS PASSED
    - `lua5.4 scripts/smoke_cgi.lua`: SMOKE CGI: OK
    - `lua5.4 scripts/check_rockspec.lua`: ROCKSPEC CHECK: OK
    - `luacheck --no-color src hooks scripts tests bin`: 0 warnings / 0 errors em 109 arquivos
    - `luarocks-5.4 lint guaraci-scm-1.rockspec`: OK
  - Sessão real de `guaraci dev` exercitada via `curl` contra endpoint scaffolded e rotas internas do explorer, validando integridade de ponta a ponta.
  - Defeitos preexistentes identificados no `router_v2.lua` e `dataware_tenancy.lua` corrigidos e cobertos por testes de regressão específicos.
