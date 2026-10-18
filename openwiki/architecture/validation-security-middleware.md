---
type: architecture
title: Validation, Binding, and Security Middleware
description: Declarative schema validation, JSON/form binding with type coercion, and the native CORS, CSRF, and rate-limit security middlewares.
tags: [lua, validation, binding, cors, csrf, rate-limit, security]
verified:
  - by: openwiki/0.7.2
    at: 2026-10-16T16:12:57.544Z
---

# Validation, Binding, and Security Middleware

This layer validates and coerces incoming data (`validator` + `binder`) and ships three native security middlewares: CORS, CSRF, and rate limiting.

## Validation (`validator`)

`validator.schema` accepts a declarative schema where each field maps to a rule string such as `"string|required|min:3|max:100|email"` or a table form. Supported types are `string`, `number`, `integer`, `boolean`, and `table`. `validator.validate` first rejects a payload whose serialized size exceeds 1 MB (default), then checks each field for `required`, type, `min`/`max` (length for strings, value for numbers), `email`, `pattern`, and `enum`, returning `true` or a list of `{field, code, message}` errors.

## Binding (`binder`)

`binder.bind` picks the request source (`form_data` or `body_table`), coerces each present field to the schema's declared type, and then validates the coerced payload. Booleans accept `true/1/yes/on` and `false/0/no/off`; numbers use `tonumber`; integers additionally require a whole value. A coercion failure returns an `invalid_type` error per field before validation runs.

## CORS (`middleware_cors`)

The CORS middleware builds an allow-list from `allowed_origins`. An `Origin` outside the list returns a 403 with a `cors_origin_not_allowed` payload and logs `cors_origin_blocked`. Otherwise it sets `Access-Control-Allow-Origin`/`-Methods`/`-Headers` (and `-Credentials` when enabled), and short-circuits an `OPTIONS` preflight with a 204.

## CSRF (`middleware_csrf`)

For the unsafe methods `POST`, `PUT`, `PATCH`, and `DELETE`, the CSRF middleware performs a double-submit check: the `X-CSRF-Token` header must match the `guaraci_csrf_token` cookie, both at least the minimum length (default 16). The comparison is a length-plus-byte-difference scan rather than an early-exit equality. A failure returns a 403 `csrf_token_invalid` and logs `csrf_validation_failed`.

## Rate limiting (`middleware_ratelimit`)

The rate limiter counts requests per client within a window (default 60 s, 100 requests). The default identity is `req.remote_addr`, set by the CGI adapter from `REMOTE_ADDR` and by the dev server from the socket peer. Forwarded headers are client-controlled unless a proxy is declared: `client_ip_header` selects `x-forwarded-for` (default) or `x-real-ip`, and `trusted_hops` (default 1) picks the Nth entry counted from the right of `X-Forwarded-For`, the hop appended by the trusted proxy. `trusted_proxy = true` is an alias for XFF with one hop. Without a declaration, all clients behind a reverse proxy share its bucket. When a bucket exceeds the limit, the middleware returns 429 with a `Retry-After` header and logs `rate_limit_exceeded`.

Counters live in a pluggable store (`ratelimit_store`): an injected `store`, else a process default (the dev server installs a memory store), else a file store when `GATEWAY_INTERFACE`, `store_path`, or `GUARACI_RATELIMIT_STORE` is present. The file store writes via atomic rename, so counts are approximate under concurrency; using the memory store in a CGI process warns once on stderr because counters would reset every request. A store write failure is audited as `rate_limit_store_failed` and does not block every client.

## Short-circuit contract (fail closed)

`before_request` hooks run before the global middleware chain, so a hook stop skips all middleware. A middleware or `before_*` hook that returns `true` short-circuits the stage and should set `res.status` and `res.body` explicitly; for an intentional empty body (health check) return 204, because the default empty 200 becomes 403 (fail closed) in the global chain, in group middleware, and in hooks. The `after_request` chain and hooks run on every response — success, 404, 500, upload errors, and short-circuits — and an `after_request` hook cannot be stopped by a user `true` return or by a failing hook/middleware, so security headers are always applied. Group middleware runs under `pcall`; an error is audited as `group_middleware_error` and re-raised.
