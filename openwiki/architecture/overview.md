---
type: "Reference"
title: "Architecture Overview"
openwiki_generated: true
verified:
  - by: openwiki/0.7.2
    at: 2026-10-16T16:12:57.544Z
---


# Architecture Overview

Guaraci is a minimalist Lua web framework designed to be server-agnostic and security-by-design, targeting ISO 27001 conformance. Its stated principles are a zero-magic, auditable implementation; an agnostic request/response contract; Classic-ASP-style templates (`.gc`); and native defense against XSS, SSTI, SQL injection, and path traversal. It requires Lua 5.4+.

## Directory layout

| Path | Role |
| --- | --- |
| `src/` | Core framework modules |
| `hooks/` | Native runtime hooks (e.g. security headers) |
| `views/` | `.gc` templates |
| `tests/` | Busted-style test suite with a local runner |
| `scripts/` | Smoke/execution utilities |
| `docs/` | Per-phase validation reports |
| `history/` | ISO 27001 phase validation notes |

## Public surface (`guaraci`)

The single entrypoint module `guaraci` exposes the whole framework surface:

- `handle_request(raw_req, opts)` — the request pipeline orchestrator, plus `escape_html`.
- `router()`, `group(prefix)`, `use(fn, name, priority)` — explicit routing, route groups, and global middleware.
- `model(name)`, `get_model`, `list_models`, `clear_models`, `init_dataware_sqlite(opts)` — the model registry and its SQLite reference backend.
- `validator_schema`, `validate`, `bind`, `validate_and_bind` — validation and request binding.
- `middleware_cors`, `middleware_csrf`, `middleware_ratelimit` — security middleware factories.
- `set_error_handler`, `reset_error_handler` — global error-handling configuration.

## Evolution

The `ROADMAP.md` records fourteen completed phases in three eras:

1. **Phases 1–5 (MVP)** — structured audit logging and the req/res factory, the ASP parser and sandbox, routing with hooks and the security-headers hook, the parameterized `db` wrapper, and the entrypoint with the reference CGI adapter.
2. **Phases 6–9 (template parity with Go)** — the output-context matrix, context-aware escaping, the function and partial registries, text mode, and the equivalence/pentest suites.
3. **Phases 10–14 (mature framework)** — explicit routing with the request-scoped context store and middleware chain, the Dataware ORM with auto-CRUD, file uploads with multipart parsing, centralised error handling, and validation/binding with native security middleware.

Each subsystem is documented in its own page: [Request Lifecycle](request-lifecycle.md), [Template Engine](template-engine.md), [Routing and Middleware](routing-middleware.md), [Data Layer](data-layer.md), [File Uploads](file-uploads.md), and [Validation, Binding, and Security Middleware](validation-security-middleware.md).
