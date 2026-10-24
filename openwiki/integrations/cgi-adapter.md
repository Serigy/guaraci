---
type: integration
title: CGI Adapter
description: The reference CGI adapter that translates the CGI environment into Guaraci's agnostic request/response contract, plus the request/response factory and the smoke-test path.
tags: [lua, cgi, adapter, integration, smoke-test]
---

# CGI Adapter

Guaraci is server-agnostic; the reference `adapter_cgi` is the bridge between the CGI interface and the framework's `handle_request` contract.

## Request construction (`request_from_cgi`)

The adapter reads the CGI environment into the agnostic request shape: `REQUEST_METHOD` → `method`, `PATH_INFO`/`REQUEST_URI` → `path` (query stripped), every `HTTP_*` variable → a normalized header, `QUERY_STRING` → `query`, and `REMOTE_ADDR` → `remote_addr` (used by rate limiting). The request `context_id` comes only from server-provided ids: `REQUEST_ID`, then `UNIQUE_ID`, each accepted only when it matches `^[%w%-_@]{8,64}$` (the `@` covers Apache `mod_unique_id` values). The client's `X-Request-Id` is never used as `context_id`; it is exposed only as `req.client_request_id` (when valid) for correlation. Without a server id the adapter generates a `req-...` id with `guaraci_random` (`/dev/urandom`; the seeded fallback only avoids identical sequences and is not cryptographic). `X-Real-IP` is on the CGI header allow-list. The body is read up to `CONTENT_LENGTH`.

For `multipart/form-data` the adapter calls `multipart.parse`, then `file_manager.process_files` to validate and store uploaded files, populating `files` and `form_data` — or `upload_error` on failure. `application/x-www-form-urlencoded` bodies become `form_data`/`body_table`.

## Response output (`response_to_cgi`)

The adapter writes a CGI `Status: <code> <text>` line, every header (computing `Content-Length` from the body), a blank line, then the body. Before writing, it rejects any header name/value that is not an RFC 7230 token or that contains CR, LF, or NUL; that case becomes a generic 500 with a `response_header_rejected` security event, preventing response splitting. The rejection response still carries X-Frame-Options, nosniff, and CSP because the after_request security headers run first.

## Request/response factory (`guaraci_io`)

`guaraci_io.new_request` normalizes `method`/`path`, copies the query/body/headers/form/files/params/context fields, and returns a **read-only** request (a metatable raises on any write). `new_response` builds the mutable response (status, headers, body) and adds a `res.json(payload, status)` helper that encodes JSON and sets the content type.

## Smoke test (`scripts/smoke_cgi.lua`)

The smoke script runs `adapter.run_cgi` against a synthetic GET to `/` and asserts the output contains `Status: 200` and the rendered value, printing `SMOKE CGI: OK` on success.
