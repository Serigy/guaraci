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

The rate limiter keeps an in-memory bucket per client within a window (default 60 s, 100 requests). The client is identified by `X-Forwarded-For`, then `X-Real-Ip`, then `remote_addr`. When a bucket exceeds the limit, the middleware returns 429 with a `Retry-After` header and logs `rate_limit_exceeded`.
