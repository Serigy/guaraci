---
type: architecture
title: Error Handling
description: How Guaraci isolates pipeline failures, normalizes error payloads, masks internals in production, and negotiates JSON, XML, or HTML error bodies.
tags: [lua, errors, error-handler, negotiation]
---

# Error Handling

Guaraci treats every failure as a response that must be safe, stable, and traceable. `handle_request` wraps the pipeline in `pcall`, and all failures funnel through a single error handler that returns a complete response.

## Pipeline isolation

`src/guaraci.lua` runs the request pipeline inside `pcall`. An uncaught exception becomes status 500 with code `unhandled_exception` and is logged through `guaraci_audit.log_error`. Expected failures use dedicated codes:

| Code | Status | Source |
|---|---|---|
| `default_hook_load_error` | 500 | default security-headers hook did not load |
| `upload_error` | 400/413 | multipart failure or oversized file |
| `hook_error` | 500 | exception in any hook stage |
| `middleware_error` | 500 | exception in a `before_request`/`after_request` middleware |
| `route_invalid_path` | 404 | invalid path in the file-system router |
| `route_not_found` | 404 | template or route not found |
| `template_read_error` | 500 | template could not be read |
| `template_compile_error` | 500 | template could not be compiled |
| `template_render_error` | 500 | sandbox render failure |

Security middleware returns its own stable codes: `csrf_token_invalid` (403), `cors_origin_not_allowed` (403), and `rate_limit_exceeded` (429, `retryable: true`).

## Handler contract

`error_handler.create_default(config)` returns:

```lua
handler(err, { req = req, res = res, opts = opts }) -> { status, headers, body }
```

- Tables are normalized to `{ status, code, message, details }`; strings and unknown values become status 500.
- Missing messages fall back to standard HTTP texts (400, 401, 403, 404, 413, 500).
- `status >= 500` is masked as `Internal Error` unless the environment is `dev`.
- `dev` also exposes `details` for status >= 500.
- The payload includes `request_id` from `req.context_id` so responses correlate with JSONL logs.

The environment is resolved per request when the handler runs: `opts.env` when present (the dev server passes `"dev"`), otherwise `GUARACI_ENV`, otherwise `prod`. In `prod`, details never appear; in `dev`, `details` is exposed for status >= 500. The core's global handler does not fix an environment, so `GUARACI_ENV=dev` is honoured. `handle_request` prefers an explicit `opts.error_handler`, then builds `error_handler.create_default({ env = opts.env })` when `opts.env` is a string, and finally uses the global handler. To force `dev` without an environment variable, install `error_handler.create_default({ env = "dev" })` with `guaraci.set_error_handler`.

## Format negotiation

`src/error_formatter.lua` implements content negotiation on the request `Accept` header:

1. `application/json` -> JSON
2. `application/xml` or `text/xml` -> XML
3. `text/html` -> HTML
4. `application/*` -> JSON
5. `text/*` -> HTML
6. `*/*` or absent -> configured default (`json`)

JSON payload:

```json
{ "status": 404, "error": "route_not_found", "message": "Not Found", "request_id": "ctx-..." }
```

XML wraps `status`, `code`, and `message` in an `<error>` element. HTML renders a minimal escaped document.

## Custom handlers and fallback

`guaraci.set_error_handler(fn)` accepts a function only and returns `nil, "error_handler_must_be_function"` otherwise; `guaraci.reset_error_handler()` restores the production default. `error_handler.apply` calls the active handler under `pcall`; if the handler throws or returns a non-table, it falls back to a production handler with code `error_handler_failure` and status 500.

Failures inside hooks produce `hook_error`; failures inside `middleware_chain` are logged as `middleware_error` and abort the remaining chain.

## Related code and tests

- `src/error_handler.lua`, `src/error_formatter.lua`
- `tests/error_handler_spec.lua`, `tests/error_formatter_spec.lua`
- `tests/guaraci_error_flow_spec.lua`, `tests/guaraci_stress_errors_spec.lua`

See also [Routing and Middleware](./routing-middleware.md) and [Security Model](../security/security-model.md).
