---
type: security
title: Security Model
description: Threat model and native defenses against XSS, SSTI, SQL injection, and path traversal; sandbox isolation, audit logging, and ISO 27001 conformance.
tags: [lua, security, xss, ssti, sqli, sandbox, iso27001]
---

# Security Model

## Threat Model

Guaraci implements defense-in-depth against:
- **XSS (Cross-Site Scripting)**: Contextual output escaping per context type (HTML, HTML attributes, URLs)
- **SSTI (Server-Side Template Injection)**: Sandboxed template execution with restricted global access
- **SQL Injection**: Prepared statements via placeholder validation and parameterized queries
- **Path Traversal**: Sanitized route paths with normalization and parent-directory filtering
- **Information Disclosure**: Production error masking and redaction of sensitive audit fields

## XSS Defense: Contextual Escaping

Guaraci's `escape_context` module provides context-aware output escaping:

- **HTML Text Escaping** (`src/escape_context.lua#L16-L25`): Escapes `<>, &, "` for safe rendering in HTML body content
- **HTML Attribute Escaping** (`src/escape_context.lua#L27-L37`): Additional escaping for quoted attribute values
- **URL Attribute Defense** (`src/escape_context.lua#L39-L65`): Blocks `javascript:` and `data:` URIs; raises `blocked_context:URL_ATTR` error on unsafe schemes
- **Dispatch by Context** (`src/escape_context.lua#L95-L120`): Central `escape_by_context(context_name, value, opts)` function enforces context-specific rules
- **Blocked Contexts** (`src/escape_context.lua#L103-L104`): JavaScript and CSS string contexts raise `blocked_context` errors until fully supported

## SSTI Defense: Sandbox Isolation

Template execution via `sandbox.lua` enforces a whitelist sandbox:

- **Restricted Global Namespace** (`src/sandbox.lua#L13-L22`): `_G`, `debug`, `load`, `loadfile`, `loadstring` are blacklisted
- **Metatable Protection** (`src/sandbox.lua#L208-L210`): Sandbox environment wrapped with `setmetatable` to deny access to non-whitelisted symbols via `__index`
- **Security Logging** (`src/sandbox.lua#L90, L92`): Attempts to expose or overwrite reserved symbols logged via `log_security()`
- **Lua Version Compatibility** (`src/sandbox.lua#L238-L244`): Supports both Lua 5.1 (`loadstring` + `setfenv`) and Lua 5.4 (`load` with env parameter)

## SQL Injection Defense: Prepared Statements

Database module enforces parameterized execution:

- **Placeholder Validation** (`src/db.lua#L25-L43`): `count_placeholders(sql)` parses `?` markers; `validate_sql(sql, params)` ensures placeholder count matches parameter count
- **Parameter Type Validation** (`src/db.lua#L44-L50`): `validate_param_value(v)` allows only nil, boolean, number, string (reject tables, functions, userdata)
- **Prepared Execution** (`src/db.lua#L179-L199`): `db.execute(sql, params)` detects `driver.execute_prepared` and routes to parameterized path; falls back to `driver.execute(...table.unpack(params))` for non-prepared drivers
- **Query Builder Integration** (`src/query_builder.lua#L244, L291, L359, L405, L425`): All builder methods (`select`, `count`, `insert`, `update`, `delete`) route through `db.execute(sql, params)` with validated placeholders

## Path Traversal Defense: Route Sanitization

Router module validates and normalizes paths:

- **Path Sanitization** (`src/router.lua#L38-L65`): `sanitize_path(raw_path)` URL-decodes, normalizes `/`, ensures leading slash, splits by `/`, filters empty parts (blocks `../` sequences)
- **Physical Path Construction** (`src/router.lua#L115-L121`): Sanitized path appended to `root` directory; `local physical_path = root .. "/" .. relative` prevents escape via `../`
- **Path Splitting** (`src/router.lua#L61`): `split_path(normalized)` parses normalized path into segments; empty segments (from `//` or trailing `/`) filtered out

## Security Headers

Hook module injects protective headers (`hooks/security_headers.lua#L1-L18`):

- `X-Frame-Options: DENY` — Prevents clickjacking via iframe embedding
- `X-Content-Type-Options: nosniff` — Blocks MIME-type sniffing attacks
- `Strict-Transport-Security: max-age=31536000; includeSubDomains` — Enforces HTTPS for 1 year
- `Content-Security-Policy: default-src 'self'` — Restricts resource loading to same-origin

## Audit Logging & Sensitive Data Redaction

Audit module logs events with automatic secret masking (`src/guaraci_audit.lua`):

- **Sensitive Key Detection** (`src/guaraci_audit.lua#L28-L40`): `is_sensitive_key(key)` matches patterns like `password`, `token`, `secret`, `apikey`, `auth`, `session`
- **Automatic Redaction** (`src/guaraci_audit.lua#L118-L119`): During context serialization, sensitive keys replaced with `<redacted>`
- **Structured Logging** (`src/guaraci_audit.lua#L143-L150`): Events written as JSON to configurable log path (`guaraci_audit.log` by default)
- **Security & Error Events** (`src/guaraci_audit.lua#L161-L180`): Separate `log_error(message, context)` and `log_security(message, context)` functions for categorized events

## Error Handling & Information Disclosure Prevention

Error handler masks internal details in production (`src/error_handler.lua`):

- **Status Code Mapping** (`src/error_handler.lua#L11, L30-L32`): Maps error status to safe messages; 500-level errors normalized
- **Production Masking** (`src/error_handler.lua#L66-L67`): If `status >= 500 and env ~= "dev"`, public message forced to `"Internal Error"`
- **Detail Exposure Control** (`src/error_handler.lua#L77-L79`): Stack traces and `details` field only exposed when `env == "dev"`
- **Error Normalization** (`src/error_handler.lua#L43-L52`): Unhandled errors wrapped with default status 500 and generic message

## Rate Limiting Identity and Store

`middleware_ratelimit` keys counters on `req.remote_addr`, which the CGI adapter sets from `REMOTE_ADDR` and the dev server from the socket peer. The `X-Forwarded-For` and `X-Real-Ip` headers are client-controlled: declare a proxy with `client_ip_header` (`x-forwarded-for` default, or `x-real-ip`) and `trusted_hops` (default 1, counted from the right), or use the `trusted_proxy = true` alias for XFF with one hop. The rightmost entry is the hop the trusted proxy appended; earlier tokens are client-supplied. Without a declaration, every client behind a reverse proxy shares its bucket.

Counters live in a pluggable store (`ratelimit_store`): an injected `store`, a process default (the dev server installs a memory store), or a file store when `GATEWAY_INTERFACE`, `store_path`, or `GUARACI_RATELIMIT_STORE` is set. Without a path, the file store defaults to `$TMPDIR` (or `/tmp`) plus `/guaraci_ratelimit_<hash of PWD>.db` and rewrites the whole file each request (a documented limitation). Write/close failures and corrupt files are store failures: they are audited as `ratelimit_store_write_failed` and answer 429 `rate_limit_unavailable` (fail closed) unless `fail_open = true`; an unusable path warns once at creation, and a memory store inside CGI warns on every request because counters reset per request. An unknown `client_ip_header` value raises at creation.

## Short-circuit Contract

`before_request` hooks run before the global middleware chain, so a hook stop skips all middleware. A middleware or `before_*` hook that returns `true` must set `res.status` and `res.body`; for an intentional empty body (health check) return 204, because the default empty 200 becomes 403 (fail closed) in the global chain, in group middleware, and in hooks. The `after_request` chain and hooks run on every response — success, 404, 500, upload errors, and short-circuits — and cannot be stopped by a user `true` return or a failing hook/middleware, so security headers are always applied. Response headers are validated before writing: an invalid name or a value containing CR/LF/NUL becomes a generic 500 that still carries X-Frame-Options, nosniff, and CSP, with a `response_header_rejected` event. Refused route paths (traversal, backslash, NUL, including percent-encoded) emit `route_path_refused` and end as 404.

## ISO 27001 Annexe A.14 Conformance

Guaraci meets ISO 27001 A.14 (Secure Development) controls (`history/PHASE13_ISO27001_VALIDATION.md`):

| Control | Implementation | Evidence |
|---------|---|---|
| **A.14.1.1** Secure Development Policy | Global error isolation + centralized handler | `src/error_handler.lua#L30-L80` |
| **A.14.1.2** Software Security Requirements | Input validation + output escaping | `src/escape_context.lua#L1-L120`, `src/db.lua#L52-L85` |
| **A.14.2.1** Availability & Resilience | Global pcall + cleanup hooks | `src/guaraci.lua` middleware chain |
| **A.14.2.2** Data Input Security | Validated params, content negotiation | `src/db.lua#L44-L85`, `src/escape_context.lua` |
| **A.14.2.3** Safe Output Encoding | Context-aware escaping in error formatters | `src/error_formatter.lua`, `src/escape_context.lua` |
| **A.14.2.4** Secure Storage | Sanitized file paths | `src/router.lua#L38-L121` |
| **A.14.3.1** Malware Protection | Sandbox + error containment | `src/sandbox.lua#L208-L244` |
| **A.14.3.2** Cryptography Controls | Secret masking in audit logs | `src/guaraci_audit.lua#L28-L150` |

---
