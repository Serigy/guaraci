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

`busted_runner.SPEC_MODULES` lists 33 spec modules across the template, routing/middleware/context, Dataware ORM, validation/security, file-upload, and error-handling phases. `run_all` resets the harness, installs globals, `require`s every spec under `pcall` (counting load failures), then runs each suite; `run_suite` runs each test under `pcall`, counting failures from the test body, `before_each`, and `after_each`. It prints `ALL SPECS PASSED` or `TOTAL FAILURES`. `tests/run_all.lua` sets `package.path`, calls `runner.run()`, and exits 1 on failure.

## Release pipeline (`.github/workflows`)

Two workflows produce GitHub Releases. `release-on-tag.yml` triggers on pushed `v*.*.*`-shaped tags, archives the tree (`zip` + `tar.gz`) and creates the release. `release.yml` is a manual (`workflow_dispatch`) pipeline that validates a semver version, normalizes the tag, converts it to a LuaRocks-compatible rockspec version, creates/pushes the tag, generates archive packages, creates the GitHub Release, and — when `publish_luarocks` is true — generates a `guaraci-<version>.rockspec` (mapping every module to its source path) and publishes it via `luarocks pack` + `luarocks upload` using the `LUAROCKS_API_KEY` secret.

`ROADMAP.md` records phases 1-13 complete, the active integration + security-regression suite, and the configured release pipeline (GitHub Release + LuaRocks package).
