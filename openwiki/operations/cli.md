---
type: operations
title: CLI
description: The guaraci command-line interface: project scaffolding with new, template checking, spec running, and the development server.
tags: [lua, cli, tooling, quickstart, scaffolding]
---

# CLI

The `guaraci` binary ships with the LuaRocks package. It scaffolds projects, lints `.gc` templates, runs specs, and starts a development server.

## Install and update

```bash
git clone https://github.com/Serigy/guaraci
cd guaraci
luarocks make guaraci-scm-1.rockspec   # before the first release
luarocks install guaraci              # after publication
```

LuaRocks installs both the library and the `guaraci` binary and remains the update channel; the CLI does not self-update.

## Commands

| Command | Purpose |
|---|---|
| `guaraci new <name>` | scaffold a project |
| `guaraci check [--json] [--mode text] <files>` | static lint for `.gc` templates |
| `guaraci test [dir]` | run `spec/*_spec.lua` (fallback `tests/`) |
| `guaraci dev [--port N] [--host H] [--app file] [--container]` | development server |
| `guaraci version` | print the CLI version |
| `guaraci help` | print usage |

Exit codes: `0` success, `1` findings or failures, `2` usage error.

## `guaraci new`

```bash
guaraci new meu-app
cd meu-app
```

Generated layout:

- `app.lua`: returns the `guaraci_options` table and registers explicit routes with `guaraci.router().get(...)`; route params arrive as `ctx.params`
- `views/index.gc`: starter template
- `hooks/security_headers.lua`: copy of the default hook, editable per project
- `cgi-bin/app.cgi`: CGI entrypoint using `adapter_cgi.env_from_os()`
- `spec/index_spec.lua`: starter specs
- `paseo.json`: `dev` and `test` scripts
- `Dockerfile.dev`: Alpine image with Lua 5.4 and lighttpd
- `.gitignore` and `README.md`

`app.lua` example:

```lua
local guaraci = require("guaraci")

guaraci.router().get("/hello/:name", function(req, res, ctx)
    res.body = "<h1>Ola, " .. guaraci.escape_html(ctx.params.name) .. "!</h1>"
end)

return { templates_root = "views" }
```

## `guaraci check`

```bash
guaraci check views/index.gc
guaraci check --json views/*.gc
guaraci check --mode text views/email.gc
```

- checks template syntax and the compiled Lua without executing template code
- warns when `<%= %>` appears inside `<script>` or `<style>` (blocked in `html` mode)
- `--mode text` suppresses those context warnings
- `--json` emits one JSON object per file:

```json
{"file":"views/index.gc","diagnostics":[{"line":2,"col":9,"end_line":2,"severity":"warning","code":"blocked-context","message":"..."}]}
```

Findings return exit code `1`; unreadable files count as findings.

## `guaraci test`

```bash
guaraci test
guaraci test spec
```

Discovers `*_spec.lua` in `spec/` (or `tests/` when `spec/` is absent), runs them with the bundled harness, and prints `ALL SPECS PASSED` or `TOTAL FAILURES`.

## `guaraci dev`

```bash
luarocks install luasocket
guaraci dev
guaraci dev --port 3000
```

- luasocket-based server on `http://127.0.0.1:8080` by default
- reloads `app.lua` per request and resets routes, middleware, hooks, and models
- serves files from `public/` when it exists, refusing dotfiles and traversal
- runs with `env = "dev"`, so error details are visible; production hides them
- `--app` selects a different entry file

See [Dev Server and Docker](../integrations/dev-server-and-docker.md) for the container mode.

## Related

- [Quickstart](../quickstart.md)
- [Installation](https://github.com/Serigy/guaraci/wiki/Instalacao)
- Source: `src/guaraci_cli/`, `bin/guaraci`
