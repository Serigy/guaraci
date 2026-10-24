---
type: "Reference"
title: "Request Lifecycle"
openwiki_generated: true
---


# Request Lifecycle

Every request enters through `guaraci.handle_request(raw_req, opts)`. The function wraps the whole pipeline in a `pcall` so an unexpected exception is converted into a clean 500 response rather than escaping to the host.

## Pipeline order

1. **Context id** — a `context_id` is generated when absent, and the raw request/response are wrapped by the req/res factory.
2. **Default hooks** — the native security-headers hook is auto-registered (unless disabled) into the `after_request` stage.
3. **Upload guard** — a request that already carries an upload error is rejected early (413 for oversized, 400 otherwise).
4. **`before_request`** — the first hook stage runs; a short-circuit or hook error ends the request here.
5. **Route resolution** — `router.resolve_or_404` maps the path to a template, returning `invalid_path` or `not_found` on failure.
6. **Template read** — the resolved file is read defensively; a read failure becomes a 500.
7. **`before_render`** — the second hook stage runs before compilation.
8. **Compile** — `parser.compile` turns the `.gc` source into Lua.
9. **Render** — `sandbox.render_template` executes the compiled Lua against the request/response.
10. **`after_request`** — the final hook stage runs (with the template path), then uploaded files are cleaned up for the request.

## Hooks (`hooks`)

Hooks run in exactly three stages — `before_request`, `before_render`, and `after_request`. `run_stage` executes each registered hook under `pcall` in registration order; a hook returning `true` short-circuits the request (defaulting to 403 unless the hook set a status), and a thrown error produces a 500 `hook_error`. The default security-headers hook is loaded from `hooks/security_headers.lua` into `after_request`.

## Error handling (`error_handler` + `error_formatter`)

Any stage can invoke the error handler, which normalises the error into a status/code/message shape, selects a formatter by content negotiation on the `Accept` header (JSON, XML, or HTML), and returns the response. In non-`dev` environments a 5xx error's message is replaced with `Internal Error`, and error details are exposed only in `dev`. The handler itself is wrapped in `pcall` with a production fallback, so an error handler that throws still yields a valid 500.

## Upload cleanup

After the response (and after the `after_request` stage), the pipeline calls `file_manager.cleanup_request(req.context_id)`, which deletes every file stored for that request id, so failed or completed requests do not leak temporary uploads.
