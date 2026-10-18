---
type: integrations
title: Dev Server and Docker
description: Planned local development server and container workflow for Guaraci. Skeleton pending the WP2 CLI implementation.
tags: [lua, dev-server, docker, lighttpd, cgi]
---

# Dev Server and Docker

<!-- TODO(WP2): fill in after the CLI lands -->

## Status

Both development paths ship with the `guaraci` CLI, which is built in WP2 of this release. This page will carry concrete commands, ports, and image details once the CLI exists.

## Planned: luasocket dev server

- `guaraci dev` starts a local HTTP server using luasocket.
- luasocket is an optional, CLI-only dependency; the framework core stays dependency-free.
- The server forwards requests to `guaraci.handle_request` through the CGI adapter or a direct request builder.
- Rate-limit state remains in-process, so it resets when the server restarts.

## Planned: Docker container

- `guaraci dev --container` runs the app with alpine + lua5.4 + lighttpd CGI.
- The container mirrors the production CGI entrypoint, including `adapter.env_from_os()`.
- The project directory is mounted into the container; `views/` and `hooks/` must be visible at the working directory used by the entrypoint.

## Operational notes to confirm after WP2

- Image name, tag, and architecture support.
- Port mapping and how to override the listen address.
- Healthcheck endpoint and log destination.
- How `security_headers_path` resolves inside the container (working directory vs `require` fallback).

## Related

- [Quickstart](../quickstart.md)
- [CGI adapter](./cgi-adapter.md)
- [Error Handling](../architecture/error-handling.md)
