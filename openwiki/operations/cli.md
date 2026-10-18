---
type: operations
title: CLI
description: Planned Guaraci command-line interface for project scaffolding and local development. Skeleton pending the WP2 CLI implementation.
tags: [lua, cli, tooling, quickstart]
---

# CLI

<!-- TODO(WP2): fill in after the CLI lands -->

## Status

The `guaraci` CLI is being built in WP2 of this release. This page is a skeleton: commands, flags, and output will be documented here once the binary is published. Until then, use the manual flow in [Quickstart](../quickstart.md).

## Planned surface

| Command | Purpose |
|---|---|
| `guaraci new <project>` | scaffold `src/`, `views/`, and `hooks/` |
| `guaraci dev` | local development server (luasocket, optional CLI dependency) |
| `guaraci dev --container` | run the same app in Docker (alpine + lua5.4 + lighttpd CGI) |
| `guaraci --version` | print the CLI version |
| `guaraci --help` | command help |

## Packaging

The CLI ships through LuaRocks alongside the framework. Installation and upgrade instructions will be added to [Installation](https://github.com/Serigy/guaraci/wiki/Instalacao) and the repository README when the rockspec is published.

## Open questions to document after WP2

- Exact LuaRocks package name and install command.
- Whether `guaraci dev` defaults to a port and how to override it.
- Container image name/tag and volume layout for `--container`.
- Behaviour when `lsqlite3` is absent in the development environment.
