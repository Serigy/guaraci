---
type: operations
title: Testing and Release
description: The self-contained Busted-style test harness, the local runner, and the GitHub Actions release/packaging pipeline (GitHub Release + LuaRocks).
tags: [lua, testing, busted, ci, release, luarocks, github-actions]
verified:
  - by: openwiki/0.7.2
    at: 2026-10-16T16:12:57.544Z
---

# Testing and Release

Guaraci ships its own Busted-style test harness (no external Busted dependency) plus a local runner and a GitHub Actions release pipeline.

## Test harness (`tests/busted_lite.lua`)

`busted_lite` is a self-contained harness. `install_globals` defines `describe`/`it`/`before_each`/`after_each` and swaps the global `assert` for a richer matcher table (`is_true`, `is_nil`, `is_not_nil`, `are.equal`), with a `__call` fallback to the native `assert`. `describe` creates a suite and pushes it onto the suite stack while its function runs; `it` appends a test to the current suite; `before_each`/`after_each` attach per-suite hooks. `install_globals` returns a restore function.

## Local runner (`tests/busted_runner.lua` + `tests/run_all.lua`)

`busted_runner.SPEC_MODULES` lists 34 spec modules across the template, routing/middleware/context, Dataware ORM, validation/security, file-upload, and error-handling phases. The count is derived from the `SPEC_MODULES` table, so the page stays correct if a spec is added or removed. `run_all` resets the harness, installs globals, `require`s every spec under `pcall` (counting load failures), then runs each suite; `run_suite` runs each test under `pcall`, counting failures from the test body, `before_each`, and `after_each`. It prints `ALL SPECS PASSED` or `TOTAL FAILURES`. `tests/run_all.lua` sets `package.path`, calls `runner.run()`, and exits 1 on failure.

## CI workflows

`.github/workflows/ci.yml` runs on push, pull request, and `workflow_call`:

- **test**: matrix of Lua 5.4, 5.3, and LuaJIT 2.1. Lua 5.4 is blocking; the other entries are `continue-on-error`. Each job runs `tests/run_all.lua`, `scripts/smoke_cgi.lua`, `scripts/check_rockspec.lua`, `luarocks lint`, `luarocks make guaraci-scm-1.rockspec`, and `guaraci version`.
- **luacheck**: static analysis over `src`, `hooks`, `scripts`, and `tests`.
- **sqlite**: installs `libsqlite3-dev` and `lsqlite3`, then runs the suite with the real driver.
- **stale-names**: fails when the project's former name or former template extension remains in `docs`, `src`, `README.md`, or `openwiki`.

`.github/workflows/openwiki-update.yml` refreshes this index daily and on manual dispatch. It uses the Gemini (Google AI Studio) provider and requires the `GEMINI_API_KEY` repository secret; without that secret the scheduled run fails.

## Release pipeline (`.github/workflows`)

Two workflows produce GitHub Releases. Both call the composite action `.github/actions/derive-rock`, which copies `guaraci-scm-1.rockspec`, derives a versioned rockspec with `luarocks new_version` (semver prereleases become LuaRocks versions such as `0.0.5.pre.alpha.1-1`), lints it, installs it with `luarocks make`, smoke-tests `require("guaraci")` and `guaraci version`, and optionally packs the `.src.rock`.

- `release-on-tag.yml` triggers on pushed `v*.*.*`, `X.Y.Z`, `v*.*.*-*`, and `X.Y.Z-*` tags. It runs CI, derives and packs the rock, archives the tree (`zip` + `tar.gz`), and creates the GitHub Release with the `.rockspec` and `.src.rock`.
- `release.yml` is a manual (`workflow_dispatch`) pipeline that validates a semver version, normalizes the tag, runs CI and rockspec validation, creates/pushes the tag, generates archive packages, creates the GitHub Release, publishes to LuaRocks when `publish_luarocks` is true (using the `LUAROCKS_API_KEY` secret), and commits the versioned rockspec under `rockspecs/`.

LuaRocks remains the install and update channel; the CLI does not self-update.

`ROADMAP.md` records phases 1-14 complete, the active integration + security-regression suite, and the configured release pipeline (GitHub Release + LuaRocks package).
