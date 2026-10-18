---
type: quickstart
title: Quickstart
description: How to install, run, and write a first Guaraci application: routing, .gc templates, and the CGI adapter.
tags: [lua, quickstart, getting-started, guaraci]
---

# Quickstart

## What is Guaraci?

Guaraci is a minimalist, server-agnostic web framework written in Lua 5.4 with security-by-design. It provides ASP-style template rendering (.gc files), routing, middleware, and a built-in ORM for database operations—all without external dependencies in the core. The framework is auditable, defensive against XSS, SQL injection, and path traversal, and designed for ISO 27001 compliance.

## Prerequisites

- **Lua 5.4+** (required)
- **lsqlite3** (optional, for SQLite ORM support via Dataware)

Install Lua 5.4 on your system, then clone the Guaraci repository:

```bash
git clone https://github.com/your-org/guaraci
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

The <%= %> blocks render variable values with automatic HTML escaping. The template engine compiles .gc files to sandboxed Lua.

### 3. Run Through the CGI Adapter

Guaraci ships with a CGI adapter for web server integration. Create a handler script:

```lua
package.path = "./src/?.lua;./?.lua;" .. package.path

local adapter = require("adapter_cgi")

adapter.run_cgi({
    env = os.getenv(),
    stdout_writer = io.write,
    guaraci_options = {
        templates_root = "views"
    }
})
```

The adapter parses CGI environment variables and invokes guaraci.handle_request().

## Public API Surface (src/guaraci.lua)

### Core Functions

- **handle_request(raw_req, opts)** [src/guaraci.lua#L86-L249]: Main request handler. Takes raw request table, options dict; returns response with status, headers, body.
- **escape_html(value)** [src/guaraci.lua#L66-L74]: HTML-safe escaping for template output.

### Routing (Phase 10)

- **router()** [src/guaraci.lua#L256]: Returns router_v2 instance for Gin-style explicit routing.
- **group(prefix)** [src/guaraci.lua#L260]: Creates route group with prefix and scoped middleware.
- **use(middleware_fn, name, priority)** [src/guaraci.lua#L264]: Registers global middleware.

### ORM & Data (Phase 11)

- **model(name)** [src/guaraci.lua#L300]: Creates or retrieves a named data model with schema DSL.
- **get_model(name)** [src/guaraci.lua#L304]: Retrieves an already-defined model.
- **list_models()** [src/guaraci.lua#L308]: Lists all registered models.
- **init_dataware_sqlite(opts)** [src/guaraci.lua#L313-L346]: Initializes SQLite driver for Dataware ORM.

### Validation & Binding (Phase 14)

- **validator_schema(schema_def)** [src/guaraci.lua#L349]: Defines a validation schema.
- **validate(payload, schema_def, opts)** [src/guaraci.lua#L353]: Validates a payload against schema.
- **validate_and_bind(req, schema_def, opts)** [src/guaraci.lua#L361]: Extracts and validates request body data.

### Security Middleware (Phase 14)

- **middleware_cors(opts)** [src/guaraci.lua#L367]: CORS allow-list + OPTIONS preflight.
- **middleware_csrf(opts)** [src/guaraci.lua#L371]: CSRF double-submit cookie + header.
- **middleware_ratelimit(opts)** [src/guaraci.lua#L375]: Rate-limiting by IP with 429 response.

### Error Handling

- **set_error_handler(handler_fn)** [src/guaraci.lua#L379-L385]: Sets custom error handler.
- **reset_error_handler()** [src/guaraci.lua#L387-L392]: Resets to default error handler.

## Running Tests

### Smoke Test

Run the CGI smoke test to verify the basic adapter:

```bash
lua scripts/smoke_cgi.lua
```

Expected output:
```
SMOKE CGI: OK
```

This test [scripts/smoke_cgi.lua#L1-L32] simulates a CGI request to / with query param nome=Smoke%20Test, invokes adapter.run_cgi(), and verifies HTTP status 200.

### Full Test Suite

Run all integration and security regression tests:

```bash
lua tests/run_all.lua
```

Expected output:
```
ALL SPECS PASSED
```

The test suite [tests/run_all.lua#L1-L8] executes all specs under tests/, covering template security, routing, ORM, and SQL injection defenses.

## Related Documentation

- **Architecture overview**: See docs/ for phase-wise validation reports
- **Template engine design**: src/parser.lua (compilation), src/sandbox.lua (execution), docs/TEMPLATE_CONTEXT_MATRIX.md (context-aware escaping)
- **Testing & release**: history/ contains phase approvals; .github/workflows/ contains CI/CD
- **Security**: src/guaraci_audit.lua (audit logging), src/db.lua (prepared statements)

## Next Steps

1. Review ROADMAP.md for completed phases (1–14, now stable)
2. Explore views/index.gc as a template example
3. Check tests/ for use-case patterns
4. Run lua scripts/smoke_cgi.lua to confirm setup
5. Integrate with your web server via the CGI adapter
