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
- serves static files from `public/` when present; dotfiles, backslashes, and traversal are refused
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
- mounts the project at `/app`, the installed core at `/guaraci` read-only, and a temporary lighttpd config
- lighttpd listens on port 80 inside the container and rewrites every path to `/cgi-bin/app.cgi`
- maps `<port>:80`, so `guaraci dev --container --port 3000` is served at `http://localhost:3000/`
- sets `GUARACI_ENV=dev` and `LUA_PATH=/guaraci/?.lua;;` for the container process
- `app.cgi` uses `adapter_cgi.env_from_os()` and the project's `app.lua` options

The scaffold's `Dockerfile.dev` mirrors this image for use outside the CLI:

```dockerfile
FROM alpine:3.20
RUN apk add --no-cache lua5.4 lighttpd
WORKDIR /app
EXPOSE 80
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
```

## Caveats

- `guaraci dev` needs luasocket; use `--container` or install it with LuaRocks.
- Container mode rebuilds the image on each run; the image name is fixed (`guaraci-dev`).
- Rate-limit and other in-memory middleware state reset per request in dev because the app is reloaded.

## Related

- [CLI](../operations/cli.md)
- [Quickstart](../quickstart.md)
- [CGI adapter](./cgi-adapter.md)
