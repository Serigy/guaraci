---
type: "Reference"
title: "Template Engine"
openwiki_generated: true
---


# Template Engine

Guaraci renders Classic-ASP-style `.gc` templates (`<% %>` for code, `<%= %>` for output) through four modules: `parser` compiles the source to Lua, `escape_context` applies context-aware escaping, `sandbox` executes the compiled code in a restricted environment, and the function/partial registries expose a controlled allow-list of helpers.

## Compilation (`parser`)

`parser.compile` scans the template for `<%`/`%>` tags. Literal text becomes `__guaraci_write(...)` calls; a `<%= expr %>` block becomes a write wrapped in `__guaraci_escape_by_context`, while a `<% code %>` block is emitted as raw Lua. For each `<%= %>` the parser infers its output context by scanning the text before the tag: inside `<script>` → `JS_STRING`, inside `<style>` → `CSS_STRING`, a URL attribute (`href`, `src`, `action`, `formaction`, `poster`, `cite`, `data`, `srcset`) → `URL_ATTR`, any other quoted attribute → `HTML_ATTR_QUOTED`, and plain text → `HTML_TEXT`.

## Context-aware escaping (`escape_context`)

`escape_by_context` dispatches by context. In `html` mode, `JS_STRING` and `CSS_STRING` are blocked at runtime (raising `blocked_context:`), `HTML_TEXT` and `HTML_ATTR_QUOTED` HTML-escape the value, and `URL_ATTR` additionally rejects `javascript:` and `data:` schemes and any scheme outside the `http`/`https`/`mailto`/`ftp` allow-list. In `text` mode the value is returned raw (no auto-escaping).

## Sandboxed execution (`sandbox`)

`sandbox.render_template` builds a restricted `_ENV` (the `load`/5.1 `setfenv` path) exposing only `Request`, `Response`, `escape`, the escaping dispatcher, a few standard functions, and a `table` with just `insert`/concat. Forbidden globals (`_G`, `require`, `os`, `io`, `package`, `debug`, `load`/`loadfile`/`dofile`/`loadstring`) are never exposed. A metatable raises an error on any unknown read or write, making the sandbox read-only. When a `context_id` is present, `Context` is exposed as a read-only view of the request context.

## Function and partial registries

Template functions come only from an explicit allow-list registry: names must match `^[A-Za-z_][A-Za-z0-9_]*$`, and forbidden names (module loaders, `os`, `io`, `escape`, `write`, and the framework's internal symbols) are rejected with a security log. Partials are a name → template-source map exposed through `partial(name, data)` and `include(name, data)`, with a configurable recursion depth (default 5) that raises `partial_depth_exceeded` when exceeded.
