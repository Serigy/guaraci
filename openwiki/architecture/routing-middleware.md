---
type: architecture
title: Routing and Middleware
description: Explicit Gin-style routing with router_v2, prefixed route groups, the priority-ordered middleware chain, the request-scoped context store, and the deprecated file-system router.
tags: [lua, routing, middleware, route-group, context-store]
verified:
  - by: openwiki/0.7.2
    at: 2026-10-16T16:12:57.544Z
---

# Routing and Middleware

Guaraci has two routers: the original file-system router (`router`) and the explicit, Gin-style router (`router_v2`), plus a `route_group` abstraction, a priority-ordered `middleware_chain`, and a request-scoped `context_store`.

## Dispatch in `handle_request`

From this version, a request handled by `handle_request` runs in this order:

1. `before_request` hooks and the global middleware chain (`middleware_chain`, descending priority)
2. `router_v2.match(method, path)`, only for safe paths
3. if an explicit route matches: group middleware, then the handler
4. otherwise: fallback to the file-system router (`router.resolve_or_404`)

When an explicit route matches, its handler receives `(req, res, context)` and returns the response; matched `:param` segments are available in `ctx.params` (the third argument). Explicit routing refuses paths containing `..`, a backslash, or NUL, including percent-encoded forms; those paths fall through to the fallback, end as 404, and emit the `route_path_refused` security event. When no route matches, the legacy template flow continues with `before_render`, `parser.compile`, `sandbox.render_template`, and `after_request`; the `after_request` chain and hooks also run for explicit routes. Before this version, `handle_request` dispatched only the file-system router, while `router_v2`, route groups, and `middleware_chain` were registered but never executed.

## Explicit router (`router_v2`)

`router_v2` stores routes per HTTP method, so `GET /users` and `POST /users` are distinct. Patterns support `:param` segments (compiled to `([^/]+)` capture groups) and inline `{regex}` constraints. `match(method, path)` walks the method's route list, anchors the compiled pattern, and extracts named parameters into a `params` table. DSL helpers `get`, `post`, `put`, `delete`, `patch`, and `head` wrap `register`.

## Route groups (`route_group`)

A group wraps a prefix (e.g. `/api/v1`) and registers its routes with that prefix, while keeping a group-local middleware list via `group.use`. Each registered handler is wrapped: group middleware runs before the handler in descending priority and then by name. A middleware returning `true` short-circuits the handler; if it left the default empty 200, the wrapper sets 403 (fail closed). Each group middleware runs under `pcall`; an error is audited as `group_middleware_error` and re-raised. `route_group.subgroup` composes prefixes for nested namespaces such as `/api/v1/users`.

## Middleware chain (`middleware_chain`)

The chain runs three stages — `before_request`, `before_render`, `after_request`. Each middleware is registered with a priority (default 50), and `run` executes them in descending priority order under `pcall`. A middleware returning `true` short-circuits `before_request`/`before_render` (not `after_request`); a short-circuit that leaves the default empty 200 is turned into 403 (fail closed), and global short-circuits still run the `after_request` hooks so security headers are present. A middleware returning a table replaces the current context. `run_legacy` delegates to `hooks.run_stage` for backward compatibility.

## Request-scoped context (`context_store`)

`context_store` isolates per-request data under a generated UUID key, queuing each id for cleanup. Reserved keys (`_request_id`, `system`, `__meta`) are rejected. `make_readonly_api` wraps the context in a read-only table whose `__newindex` throws, so templates can read but never mutate the context.

## Legacy file-system router (`router`)

The deprecated `router` resolves a path to a `.gc` file under `templates_root`. Its `sanitize_path` URL-decodes the path, rejects NUL bytes and `..` traversal segments, and appends `.gc` (or `index.gc`) to form the file name; `resolve_or_404` sets a 404 response when resolution fails.
