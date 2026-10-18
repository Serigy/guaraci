---
type: integration
title: CGI Adapter
description: The reference CGI adapter that translates the CGI environment into Guaraci's agnostic request/response contract, plus the request/response factory and the smoke-test path.
tags: [lua, cgi, adapter, integration, smoke-test]
verified:
  - by: openwiki/0.7.2
    at: 2026-10-16T16:12:57.544Z
---

# CGI Adapter

Guaraci is server-agnostic; the reference `adapter_cgi` is the bridge between the CGI interface and the framework's `handle_request` contract.

## Request construction (`request_from_cgi`)

The adapter reads the CGI environment into the agnostic request shape: `REQUEST_METHOD` → `method`, `PATH_INFO`/`REQUEST_URI` → `path` (query stripped), every `HTTP_*` variable → a normalized header, `QUERY_STRING` → `query`, and `REMOTE_ADDR` → `remote_addr` (used by rate limiting). The request `context_id` is taken from the first valid candidate in this order: `X-Request-Id` header, `REQUEST_ID`, `UNIQUE_ID`. A candidate is valid only when it matches `^[%w%-_@]{8,64}$` (the `@` covers Apache `mod_unique_id` values); otherwise a generated `req-...` id is used. The body is read up to `CONTENT_LENGTH`.

For `multipart/form-data` the adapter calls `multipart.parse`, then `file_manager.process_files` to validate and store uploaded files, populating `files` and `form_data` — or `upload_error` on failure. `application/x-www-form-urlencoded` bodies become `form_data`/`body_table`.

## Response output (`response_to_cgi`)

The adapter writes a CGI `Status: <code> <text>` line, every header (computing `Content-Length` from the body), a blank line, then the body.

## Request/response factory (`guaraci_io`)

`guaraci_io.new_request` normalizes `method`/`path`, copies the query/body/headers/form/files/params/context fields, and returns a **read-only** request (a metatable raises on any write). `new_response` builds the mutable response (status, headers, body) and adds a `res.json(payload, status)` helper that encodes JSON and sets the content type.

## Smoke test (`scripts/smoke_cgi.lua`)

The smoke script runs `adapter.run_cgi` against a synthetic GET to `/` and asserts the output contains `Status: 200` and the rendered value, printing `SMOKE CGI: OK` on success.
