---
type: architecture
title: Hooks and Audit
description: Hook stages, default security-headers loading, the middleware chain boundary, and JSONL audit logging with secret redaction.
tags: [lua, hooks, audit, security-headers, jsonl]
---

# Hooks and Audit

Guaraci exposes two extension mechanisms and one structured log channel. Hooks are the legacy stage API, `middleware_chain` is the priority-ordered chain used by the global pipeline, and `guaraci_audit` records security and error events as JSONL.

## Hooks

`src/hooks.lua` keeps one registry per stage: `before_request`, `before_render`, and `after_request`.

```lua
local hooks = require("hooks")

hooks.register("before_request", function(req, res, context)
  return false -- true short-circuits the stage
end, "auth_gate")
```

- `register(stage, fn, name)` returns `true` or `nil, err` (`invalid_stage`, `hook_must_be_function`).
- `list(stage)`, `clear(stage)`, and `clear()` inspect and reset the registry.
- `run_stage(stage, req, res, context)` returns `(stopped, reason)`, where reason is `short_circuit`, `hook_error`, or `invalid_stage`.
- A hook that raises makes `run_stage` mark the response as 500 and return `hook_error`; inside `handle_request` the error handler rewrites the body with code `hook_error`.
- `before_request` hooks run before the global middleware chain, so a hook stop skips all middleware.
- A hook returning `true` stops the stage. If it left status 200 with an empty body, the response becomes 403 (fail closed); use 204 for an intentional empty body. If it set no status, the default is 403 (or 401 when the hook set 401), with a matching default body.
- `after_request` hooks run on every response (success, 404, 500, upload errors, short-circuits) and cannot be stopped: a `true` return does not skip later hooks, and a failing hook or middleware still lets the security-headers hook run.

### Default security-headers hook

`hooks.register_default_hooks(opts)` loads `hooks/security_headers.lua` for the `after_request` stage:

- `security_headers_path` overrides the default path, which is resolved relative to the process working directory.
- `load_hook_from_file` uses `dofile`; the file must return a function.
- The default set is loaded once per process (`defaults_loaded`); `hooks.clear()` resets it.
- From this version, when the file is absent at the configured path, the core falls back to `require("hooks.security_headers")`, so an installed rock or a project without a `hooks/` directory still starts.
- If neither source loads, `handle_request` returns 500 with `default_hook_load_error`.

The hook injects `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Strict-Transport-Security: max-age=31536000; includeSubDomains`, and `Content-Security-Policy: default-src 'self'`.

## Middleware chain boundary

`middleware_chain` is not a replacement for hooks: it adds numeric priority (higher first, default 50), short-circuit for `before_request`/`before_render` only, and context replacement when a middleware returns a table. `guaraci.use` registers into the `before_request` stage. `middleware_chain.run_legacy` delegates to `hooks.run_stage`.

## Audit log

`src/guaraci_audit.lua` appends one JSON object per event to the path from `GUARACI_AUDIT_LOG` (or `guaraci_audit.log` in the working directory; `set_log_path` overrides it). A write failure leaves the request untouched and prints one warning per process to stderr:

```json
{ "timestamp": "2026-10-18T20:00:00Z", "level": "security", "message": "csrf_validation_failed", "context": { "method": "POST" } }
```

Public entry points: `log_error(message, context)` and `log_security(message, context)`. Write failures do not interrupt the request and warn on stderr once per process (`guaraci: WARNING: cannot write audit log ...`).

Redaction and bounds:
- Sensitive keys are replaced with `<redacted>`: `password`, `passwd`, `pwd`, `token`, `access_token`, `refresh_token`, `authorization`, `cookie`, `secret`, `api_key`, `apikey`.
- Depth beyond 6 becomes `<max-depth>`; functions, threads, and userdata become `<function>`, `<thread>`, `<userdata>`; cycles become `<cycle>`.

Events already emitted include hook failures and short-circuits, `route_path_refused` for refused route/static paths, `group_middleware_error` for group middleware exceptions, `response_header_rejected` for invalid response headers, `ratelimit_store_write_failed` for counter-store write/read failures, CSRF/CORS/rate-limit blocks, `file_upload_blocked`, SQL policy rejections, driver errors, and Dataware CRUD/tenant events (`dataware_create`, `dataware_update`, `dataware_delete`, `dataware_tenant_violation`).

Rejected uploads also log the raw reason (`file_upload_blocked`, upload error details); the HTTP body only carries `Payload too large`, `Invalid upload`, or a generic 500. Every control byte in an audit value is JSON-escaped as `\b`, `\f`, `\n`, `\r`, `\t`, or `\u00XX`.

## Operational notes

- Protect the log file with restrictive ACLs and rotate it externally; the library does not rotate or bound the file.
- Redaction covers known key names, not arbitrary payload content; never log credentials as free text.
- Correlate `request_id` from error responses with the audit trail.

## Related code and tests

- `src/hooks.lua`, `src/middleware_chain.lua`, `src/guaraci_audit.lua`, `hooks/security_headers.lua`
- `tests/middleware_chain_spec.lua`, `tests/guaraci_middleware_error_flow_spec.lua`
