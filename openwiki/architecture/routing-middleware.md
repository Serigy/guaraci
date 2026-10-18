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

## Explicit router (`router_v2`)

`router_v2` stores routes per HTTP method, so `GET /users` and `POST /users` are distinct. Patterns support `:param` segments (compiled to `([^/]+)` capture groups) and inline `{regex}` constraints. `match(method, path)` walks the method's route list, anchors the compiled pattern, and extracts named parameters into a `params` table. DSL helpers `get`, `post`, `put`, `delete`, `patch`, and `head` wrap `register`.

## Route groups (`route_group`)

A group wraps a prefix (e.g. `/api/v1`) and registers its routes with that prefix, while keeping a group-local middleware list via `group.use`. `route_group.subgroup` composes prefixes for nested namespaces such as `/api/v1/users`.

## Middleware chain (`middleware_chain`)

The chain runs three stages — `before_request`, `before_render`, `after_request`. Each middleware is registered with a priority (default 50), and `run` executes them in descending priority order under `pcall`. A middleware returning `true` short-circuits `before_request`/`before_render` (not `after_request`), and a middleware returning a table replaces the current context. `run_legacy` delegates to `hooks.run_stage` for backward compatibility.

## Request-scoped context (`context_store`)

`context_store` isolates per-request data under a generated UUID key, queuing each id for cleanup. Reserved keys (`_request_id`, `system`, `__meta`) are rejected. `make_readonly_api` wraps the context in a read-only table whose `__newindex` throws, so templates can read but never mutate the context.

## Legacy file-system router (`router`)

The deprecated `router` resolves a path to a `.gc` file under `templates_root`. Its `sanitize_path` URL-decodes the path, rejects NUL bytes and `..` traversal segments, and appends `.gc` (or `index.gc`) to form the file name; `resolve_or_404` sets a 404 response when resolution fails.
