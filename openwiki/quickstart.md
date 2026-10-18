---
type: quickstart
title: Quickstart
description: How to install, run, and write a first Guaraci application: routing, .gc templates, and the CGI adapter.
tags: [lua, quickstart, getting-started, guaraci]
---

# Quickstart

## What is Guaraci?

Guaraci is a minimalist, server-agnostic web framework written in Lua with security-by-design. It provides ASP-style template rendering (.gc files), routing, middleware, and a built-in ORM for database operations - all without external dependencies in the core. The framework is auditable, defensive against XSS, SQL injection, and path traversal, and designed for ISO 27001 compliance.

## Prerequisites

- **Lua 5.3 or newer** (5.4 recommended). Lua 5.1 is not supported: the core uses `table.pack`, `table.unpack`, and `goto`.
- **lsqlite3** (optional, for SQLite ORM support via Dataware)

Install Lua 5.4 on your system, then clone the Guaraci repository:

```bash
git clone https://github.com/Serigy/guaraci
cd guaraci
```

## Minimal End-to-End Example

### 1. Create a Route

Create a simple GET route in your application. For example:

```lua
package.path = "./src/?.lua;./?.lua;" .. package.path

local guaraci = require("guaraci")

-- Define a route that renders a template
local req = {
    method = "GET",
    path = "/",
    query = { nome = "World" },
    headers = {}
}

local res = guaraci.handle_request(req, {
    templates_root = "views"
})

print("Status: " .. res.status)
print("Body:")
print(res.body)
```

### 2. Create a Template

Create a .gc template file at views/index.gc (ASP-style syntax):

```html
<h1>Guaraci MVP</h1>
<p>Hello, <%= Request.query.nome or "visitor" %>!</p>
```

The `<%= %>` blocks render variable values with automatic HTML escaping. The template engine compiles .gc files to sandboxed Lua.

### 3. Run Through the CGI Adapter

Guaraci ships with a CGI adapter for web server integration. Create a handler script:

```lua
package.path = "./src/?.lua;./?.lua;" .. package.path

local adapter = require("adapter_cgi")

adapter.run_cgi({
    env = adapter.env_from_os(),
    stdout_writer = io.write,
    guaraci_options = {
        templates_root = "views"
    }
})
```

Lua cannot enumerate `os.getenv()` on its own, so `adapter.env_from_os()` builds the CGI environment from a fixed allow-list of variables (request method, path, query string, content type/length, and HTTP headers). The adapter parses those variables and invokes `guaraci.handle_request()`; the options key is `guaraci_options`.

## Public API Surface

Functions live in `src/guaraci.lua`; see the source for exact signatures. Additional modules are listed at the end of this page.

### Core Functions

- **handle_request(raw_req, opts)**: Main request handler. Takes a raw request table and an options dict; returns a response with status, headers, and body. Option keys: `templates_root`, `base_response`, `error_handler`, `escape`, `template_mode`, `template_api`, `template_functions`, `template_partials`, `auto_register_default_hooks`, `security_headers_path`.
- **escape_html(value)**: HTML-safe escaping for template output.

### Routing (Phase 10)

- **router()**: Returns the router_v2 instance for explicit, method-based routing. Verbs: `get`, `post`, `put`, `patch`, `delete`, `head`; `:param` segments land in `req.params`.
- **group(prefix)**: Creates a route group with a prefix and group-local middleware list.
- **use(middleware_fn, name, priority)**: Registers global middleware in the `before_request` stage (higher priority runs first; default 50).

From this release, `handle_request` runs the global middleware chain, then `router_v2.match`, then falls back to the file-system router when no explicit route matches. Previously only the file-system router was dispatched.

### ORM & Data (Phase 11)

- **model(name)**: Creates or retrieves a named data model with a schema DSL.
- **get_model(name)**: Retrieves an already-defined model.
- **list_models()**: Lists all registered models.
- **clear_models()**: Clears the model registry.
- **init_dataware_sqlite(opts)**: Initializes the SQLite driver for Dataware (`db_path`, `sqlite_module`, or an open `connection`).

### Validation & Binding (Phase 14)

- **validator_schema(schema_def)**: Compiles a validation schema.
- **validate(payload, schema_def, opts)**: Validates a payload against a schema.
- **bind(req, schema_def, opts)**: Selects the request source, coerces types, and validates.
- **validate_and_bind(req, schema_def, opts)**: Alias of `bind`.

### Security Middleware (Phase 14)

- **middleware_cors(opts)**: CORS allow-list + OPTIONS preflight.
- **middleware_csrf(opts)**: CSRF double-submit cookie + header (default cookie `guaraci_csrf_token`).
- **middleware_ratelimit(opts)**: In-memory rate limiting by IP with a 429 response and `Retry-After`.

### Error Handling

- **set_error_handler(handler_fn)**: Sets a custom global error handler.
- **reset_error_handler()**: Resets to the default production error handler.

### Debug Helpers

- **debug_routes()**: Routes registered per HTTP method.
- **debug_middlewares()**: Middlewares per stage.
- **create_context(request_id)** / **cleanup_contexts()**: Request-scoped context lifecycle.

## Running Tests

Use the `lua5.4` binary (the system `lua` may be 5.1).

### Smoke Test

Run the CGI smoke test to verify the basic adapter:

```bash
lua5.4 scripts/smoke_cgi.lua
```

Expected output:

```
SMOKE CGI: OK
```

This test simulates a CGI request to `/` with query param `nome=Smoke%20Test`, invokes `adapter.run_cgi()`, and verifies HTTP status 200.

### Full Test Suite

Run all integration and security regression tests:

```bash
lua5.4 tests/run_all.lua
```

Expected output:

```
ALL SPECS PASSED
```

`tests/run_all.lua` loads the self-contained harness and runs the modules listed in `SPEC_MODULES` under `tests/busted_runner.lua`, covering template security, routing, middleware, ORM, uploads, validation, and error handling.

## Related Documentation

- **Architecture overview**: `openwiki/architecture/overview.md`
- **Template engine design**: `src/parser.lua` (compilation), `src/sandbox.lua` (execution), and `docs/Matriz-de-Contextos.md` (context-aware escaping)
- **Testing & release**: `history/` contains phase approvals and validation reports; `.github/workflows/` contains CI/CD
- **Security**: `src/guaraci_audit.lua` (audit logging), `src/db.lua` (prepared statements), `openwiki/security/security-model.md`

## Next Steps

1. Review `ROADMAP.md` for completed phases (1-14, now stable)
2. Explore `views/index.gc` as a template example
3. Check `tests/` for use-case patterns
4. Run `lua5.4 scripts/smoke_cgi.lua` to confirm setup
5. Integrate with your web server via the CGI adapter
