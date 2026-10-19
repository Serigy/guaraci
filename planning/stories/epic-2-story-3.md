# Epic 2 — Story 3: Activate the explorer with production fail-closed behavior

**Status:** Ready

## User Story Goal

As an application operator, I want the explorer enabled in development but absent in production unless explicitly forced so that documentation and UI routes cannot accidentally expose production metadata.

## Prerequisites

Epic 2 Story 2 — Build and serve the live simplified OpenAPI document

## Injected Technical Context

Create `src/api_explorer/explorer.lua`; modify `src/guaraci.lua` and `src/guaraci_cli/dev.lua`; add the module to the rockspec; create/register `tests/api_explorer_spec.lua`.

Contracts:

```lua
-- src/guaraci.lua
function M.enable_explorer(opts)
  return api_explorer.enable(router_v2, opts)
end

-- src/api_explorer/explorer.lua
M.enable(router, opts) -> true | nil, "explorer_disabled_in_production"
```

Options: `path="/__guaraci/explorer"`, `env` then `os.getenv("GUARACI_ENV")` then `"prod"`, `force_production=false`, `title`, and `version`. Enabled routes are fixed `/__guaraci/api-docs` plus the configured HTML/assets routes. In `prod` without exact boolean `force_production=true`, register none and return the stated error; the normal router produces indistinguishable 404s. With production force, call `guaraci_audit.log_security("api_explorer_enabled_in_production", {path=opts.path})` once. `guaraci dev` calls `enable_explorer({env="dev"})` after reset.

Applicable PRD text (verbatim): “`guaraci dev` deve ativar o explorer por padrão”; “Se `GUARACI_ENV=prod`, `env == "prod"` ... explorer e metadata devem ser **fail-closed**”; “Em produção, o bloqueio só pode ser removido com a opção explícita `force_production = true`”; “O estado desabilitado não deve registrar as rotas internas nem acrescentar trabalho a cada requisição de negócio.” NFR03 and NFR05 also apply. `handle_request` remains unchanged; explorer is ordinary router routes.

## Implementation Checklist

- [ ] Implement route registration and option defaults without query/header/cookie override.
- [ ] Delegate `guaraci.enable_explorer` and activate it in dev reload.
- [ ] Ensure disabled production performs no registration and no request-time introspection/assets work.
- [ ] Add custom path, dev, production 404, forced production, and audit tests.
- [ ] Confirm reload clears route state before reactivation.

## Acceptance Criteria & Test Cases

- `env="dev"` makes docs and explorer endpoints reachable; custom `path` changes only page/assets paths.
- `env="prod"` without force returns the error and all four explorer endpoints are byte-equivalent to ordinary missing-route 404s.
- `env="prod", force_production=true` returns docs/UI/assets and audits the enable event without secrets.
- Rebuilding dev state twice does not duplicate routes.
- Run `lua5.4 tests/run_all.lua`, `lua5.4 scripts/check_rockspec.lua`, and `luacheck src hooks scripts tests bin`.
