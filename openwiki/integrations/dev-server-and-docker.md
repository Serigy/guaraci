---
type: integrations
title: Dev Server and Docker
description: The Guaraci development server (luasocket, hot reload) and the Docker container mode (Alpine, Lua 5.4, lighttpd CGI).
tags: [lua, dev-server, docker, lighttpd, cgi, luasocket]
---

# Dev Server and Docker

Both development paths are part of the `guaraci` CLI. The dev server is a small luasocket HTTP loop; the container mode runs the same project behind lighttpd CGI in Docker.

## Local dev server

```bash
luarocks install luasocket
guaraci dev
guaraci dev --port 3000 --host 0.0.0.0
```

- listens on `127.0.0.1:8080` by default; `--port` and `--host` override it
- `--app` selects the entry file (default `app.lua`)
- each request reloads `app.lua` and resets `router_v2`, `middleware_chain`, `hooks`, and the model registry, mirroring a fresh CGI process
- serves static files from `public/` when present, **before** app middleware and hooks; dotfiles, backslashes, and traversal are refused, and refused paths are audit-logged as `route_path_refused`
- sets `REMOTE_ADDR` from the socket peer for the rate limiter and keeps counters in the server process (`ratelimit_store.memory`)
- reads request/header lines byte by byte with a hard 8 KB cap (431), answers 501 for `Transfer-Encoding: chunked`, strips control characters from logged paths, and enforces a 15-second deadline covering the request line, headers, and body
- dotfile paths under `public/` return 403; refused paths are audit-logged as `route_path_refused`
- warns when `--host` is not loopback, because it exposes dev error details to the network
- passes `env = "dev"` to `handle_request`, so error bodies include details
- reads the request into CGI variables and reuses `adapter_cgi`, so the dev path matches production
- luasocket is an optional, CLI-only dependency; the framework core stays dependency-free
- the loop is single-threaded and keeps in-process state (for example, rate-limit buckets) only for the life of the process

## Container mode

```bash
guaraci dev --container
guaraci dev --container --port 3000
```

Requirements: Docker is installed and running, and the project has `cgi-bin/app.cgi` (created by `guaraci new`).

Behavior:

- builds the image `guaraci-dev` from an embedded Dockerfile: Alpine 3.20 + `lua5.4` + lighttpd (`mod_cgi`)
- creates `uploads/`, `logs/`, and `public/` when missing; the scaffold's `.gitignore` covers `logs/`
- mounts the project at `/app` read-only with writable `/app/uploads` and `/app/logs` volumes, the installed core at `/guaraci` read-only, and a temporary lighttpd config
- runs as the host `uid:gid` with `--cap-drop ALL` and `--security-opt no-new-privileges`; project paths containing `:` are refused (a `docker -v` limitation)
- if the host uid is 0, it runs as `65534:65534` with a warning and makes `uploads/` and `logs/` world-writable
- lighttpd listens on internal port 8080 (mapped to `<host>:<port>`) with `public/` as its document root, so `app.lua`, `views/`, and `hooks/` are never served as files; existing static files are served directly and other paths go to `/cgi-bin/app.cgi`
- dotfiles under `public/` are denied with 403 via `mod_access`
- static files bypass app middleware and hooks, as in the local dev server
- publishes on `127.0.0.1:<port>` by default; `--host` overrides it with a network-exposure warning
- `guaraci dev --container --port 3000` is served at `http://127.0.0.1:3000/`
- sets `GUARACI_ENV=dev`, `LUA_PATH=/guaraci/?.lua;;`, `GUARACI_AUDIT_LOG=/app/logs/guaraci_audit.log`, `GUARACI_RATELIMIT_STORE=/app/logs/ratelimit.db`, and `GUARACI_UPLOAD_DIR=/app/uploads`; audit write failures warn once on stderr
- `app.cgi` uses `adapter_cgi.env_from_os()` and the project's `app.lua` options

The scaffold's `Dockerfile.dev` mirrors this image for use outside the CLI:

```dockerfile
FROM alpine:3.20
RUN apk add --no-cache lua5.4 lighttpd
WORKDIR /app
EXPOSE 8080
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
```

## Caveats

- `guaraci dev` needs luasocket; use `--container` or install it with LuaRocks.
- Container mode rebuilds the image on each run; the image name is fixed (`guaraci-dev`).
- Rate-limit counters survive app reloads in dev because they live in a server-process memory store; app state (routes, middleware, hooks, models) is reset per request.

## Related

- [CLI](../operations/cli.md)
- [Quickstart](../quickstart.md)
- [CGI adapter](./cgi-adapter.md)
