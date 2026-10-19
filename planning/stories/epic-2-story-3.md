# Epic 2 — Story 3: Activate the explorer with production fail-closed behavior

**Status:** Done

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

- [x] Implement route registration and option defaults without query/header/cookie override.
- [x] Delegate `guaraci.enable_explorer` and activate it in dev reload.
- [x] Ensure disabled production performs no registration and no request-time introspection/assets work.
- [x] Add custom path, dev, production 404, forced production, and audit tests.
- [x] Confirm reload clears route state before reactivation.

## Acceptance Criteria & Test Cases

- `env="dev"` makes docs and explorer endpoints reachable; custom `path` changes only page/assets paths.
- `env="prod"` without force returns the error and all four explorer endpoints are byte-equivalent to ordinary missing-route 404s.
- `env="prod", force_production=true` returns docs/UI/assets and audits the enable event without secrets.
- Rebuilding dev state twice does not duplicate routes.
- Run `lua5.4 tests/run_all.lua`, `lua5.4 scripts/check_rockspec.lua`, and `luacheck src hooks scripts tests bin`.

## Dev Notes

Modified/created files:
- `src/api_explorer/explorer.lua` (new): `M.enable(router, opts) -> true | nil, "explorer_disabled_in_production"`. `current_env` follows the documented `opts.env -> GUARACI_ENV -> "prod"` cascade (case-insensitive, lowercased). Blocked (`env=="prod"` and `opts.force_production ~= true`) returns early without touching `router` at all — no routes, no per-request cost. Otherwise registers `GET /__guaraci/api-docs` (fully working: calls `api_explorer.openapi`, 200/JSON on success, 500 + `guaraci_audit.log_error("openapi_build_failed", ...)` on failure, body matches the documented `{status,error,message,request_id}` shape using the real `req.context_id`) plus the configured HTML page, `<path>/app.js` and `<path>/style.css` routes as **placeholders** (correct status/Content-Type, empty body) — their real content and the CSRF cookie are Epic 3 Story 1's job ("complete asset routes"), per that story's own injected context. `force_production=true` in prod additionally calls `guaraci_audit.log_security("api_explorer_enabled_in_production", {path=...})` exactly once.
- `src/guaraci.lua`: added `local api_explorer = require("api_explorer.explorer")` and `M.enable_explorer(opts)` delegating to `api_explorer.enable(router_v2, opts)` — no other line changed, `handle_request` stays unaware the explorer exists (just more `router_v2` routes).
- `src/guaraci_cli/dev.lua`: `M.dispatch` now calls `require("guaraci").enable_explorer({ env = "dev" })` immediately after `reset_app_state(config.baseline)`, so every dev-server request gets a freshly-reactivated explorer alongside the freshly-reloaded app routes.
- `guaraci-scm-1.rockspec`: added `api_explorer.explorer`.
- `src/api_explorer/openapi.lua` (amendment to E2-S2's file): `build()` now skips any `route_introspection` entry whose pattern starts with `/__guaraci/` before grouping by path. Discovered while integration-testing this story: once the explorer registers its own 4 routes on the same shared `router_v2`, `route_introspection.all()` — which intentionally reads *every* registered route, generated or ad-hoc — started including the explorer's own utility routes as nameless ad-hoc entries, which would otherwise document the explorer's own plumbing inside its own catalog. E2-S2's acceptance criteria didn't anticipate this interaction (it predates the explorer's routes existing); excluding framework-internal routes from the user-facing API document is the only sensible behavior, so the fix was applied directly rather than filed as a blocked conflict.
- `tests/busted_runner.lua`: registered `tests.api_explorer_spec`.
- `tests/openapi_spec.lua`: added a regression test asserting `/__guaraci/...` routes never appear in the built document even when registered.
- `tests/api_explorer_spec.lua` (new): dev reachability (all 4 routes), custom `path` affecting only the page/asset routes (never `api-docs`), prod fail-closed with byte-equivalent 404s (request_id stripped before comparing, since it's random per request), `force_production` ignoring query/header overrides, `force_production=true` enabling everything and auditing exactly once, two simulated dev reloads not duplicating routes, and the 500 + audit path when `openapi.build_document` fails.

Blocking bug found and worked around (not a story conflict, but worth flagging loudly): **`router_v2.lua`'s pattern compiler does not escape Lua pattern magic characters in literal path segments.** It only substitutes `:param` and `{regex}` placeholders and leaves everything else as a raw Lua pattern; a literal `-` in a static path (e.g. the architecture-mandated fixed path `/__guaraci/api-docs`, or any custom `--path` a user might choose, e.g. `/custom-explorer`) is interpreted as the Lua pattern "lazy zero-or-more" quantifier on the preceding character, so the route silently never matches its own literal path — proven directly: `router_v2.get("/api-docs", fn); router_v2.match("GET", "/api-docs")` returns not-found. This is a pre-existing defect in a module outside this story's (and this role's) file scope (`src/route_introspection.lua`/`src/guaraci.lua`/`src/guaraci_cli/dev.lua`/`src/api_explorer/*` are the mandated files; `router_v2.lua` is not listed and has its own dedicated test suite from an earlier phase). Rather than editing `router_v2.lua`, `explorer.lua` escapes its own literal path strings before registering them (`escape_pattern_literal`, a local helper that escapes `^$()%.[]*+-?`) — safe because none of the explorer's 4 routes use `:param`/`{regex}` syntax, so escaping the whole string can't collide with placeholder detection. This only fixes it for the explorer's own routes; any future generated/ad-hoc route with a hyphen (or other magic character) in a literal segment elsewhere in the framework would hit the same defect. Recommend the orchestrator/QA role file this as a tracked bug for `router_v2.lua` against its own phase, outside this chain's scope.
- Verification: `lua5.4 tests/run_all.lua` (×5) and `luajit tests/run_all.lua` (×3) → ALL SPECS PASSED, zero stray files; `lua5.4 scripts/check_rockspec.lua` → ROCKSPEC CHECK: OK; `lua5.4 scripts/smoke_cgi.lua` → SMOKE CGI: OK; `luacheck --no-color src hooks scripts tests bin` → 0 warnings / 0 errors in 108 files. Also manually verified end-to-end over a real `guaraci dev --port 8099` HTTP server (not just simulated `handle_request`): `curl` against all 4 routes returned the correct status/content-type, and `/__guaraci/api-docs` correctly reflected the scaffolded project's ad-hoc `/hello/:name` route from `guaraci new`.
- Found and fixed a second test-only flake while writing this story's specs, same root cause pattern as E2-S2: `math.random` is unseeded (deterministic) in Lua 5.4 unless something explicitly seeds it, so `os.time() .. "_" .. math.random(1000,9999)`-style temp filenames can collide across separate process invocations when two runs' internal timing lands on the same integer second. Switched both this story's and E2-S2's temp audit-log filenames to `guaraci_random.hex(8)` (the project's own `/dev/urandom`-backed helper) instead of `math.random`.
