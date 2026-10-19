# Epic 4 — Story 1: Document, validate, and prepare the release

**Status:** Ready

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

- [ ] Inventory Portuguese wiki pages and English OpenWiki source/index pages without editing the `docs/` submodule in this planning worktree.
- [ ] Update user documentation during implementation with commands, examples, production warning, tenancy, CSP/CSRF, and limits.
- [ ] Update generated OpenWiki claim statement, `pageVersion`, and manifest per `openwiki/INSTRUCTIONS.md`.
- [ ] Run Lua 5.4, LuaJIT, rockspec, luacheck, generated-project, and HTTP/dev checks.
- [ ] Confirm all four new specs are in `SPEC_MODULES` and all six new source modules are in the rockspec.
- [ ] Perform security review for traversal, XSS/SSTI, SQL injection, secret leakage, and audit coverage; record failures as release blockers.

## Acceptance Criteria & Test Cases

- Documentation examples are copyable and accurately state all flags, paths, defaults, fail-closed behavior, and exit codes.
- `lua5.4 tests/run_all.lua` and `luajit tests/run_all.lua` each print `ALL SPECS PASSED`; `lua5.4 scripts/check_rockspec.lua` passes; `luacheck src hooks scripts tests bin` reports 0 warnings.
- A temporary project generated with `lua5.4 bin/guaraci generate endpoint ...` has three files, passes its generated spec, and does not modify `app.lua`.
- `guaraci dev` plus `curl` verifies docs/UI/assets, custom path, production 404, forced production, and CSRF rejection.
- Final review verifies no external network/dependency, assets under 50 KiB, zero inline script, deterministic output, route reset, and required audit calls.
