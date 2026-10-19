# Epic 1 — Story 1: Parse endpoint options and render deterministic templates

**Status:** Ready

## User Story Goal

As a Guaraci developer, I want one validated, deterministic representation of an endpoint and its fields so that every generated artifact is safe, repeatable, and consistent.

## Prerequisites

none

## Injected Technical Context

Create `src/guaraci_cli/generate.lua` and `src/guaraci_cli/generate_templates.lua`; add both modules to `guaraci-scm-1.rockspec`. The public seam is `guaraci_cli.generate.run(args, io_streams) -> exit_code`; expose or make testable the equivalent of `parse_fields(raw)`. `io_streams` includes `stdout`, `stderr`, `util`, and `command` (`"generate"` or `"scaffold"`).

The parser result must preserve declaration order:

```lua
{ ok = true, fields = {
  { name = "title", type = "string", required = true },
  { name = "price", type = "number", required = false },
} }
```

Failures use `ok=false` and an identifying `code`, including `unknown_type`, `unknown_rule`, `duplicate_field`, `empty_segment`, `missing_type`, and `invalid_name`. Fields match `^[%a_][%w_]*$`; types are exactly `string`, `number`, `integer`, `boolean`, `table`; the only rule is `required`. `table` maps to SQLite `TEXT`, OpenAPI `object` with `additionalProperties: true`, and validator type `table`. Without `--fields`, generate `model:schema({})`.

Generated Lua must use the canonical model and route shapes from architecture §5.2–§5.3: routes call `auto_crud.generate(model, group, opts)`, use `group.use()` for mutation validation, and never reimplement CRUD. `--no-tenant` uses `opts.tenant_middleware` to set `context.tenant_id = "__global__"` and `model:without_tenant()`. Generated routes register descriptors with `route_introspection.describe`; generated files contain no timestamps, UUIDs, or external dependencies. The exact mount output is the architecture §5.4 snippet.

Applicable PRD text (verbatim): “`--fields` usa a gramática `campo:tipo[:regra],campo:tipo[:regra]...`”; “Tipos suportados são exatamente `string`, `number`, `integer`, `boolean` e `table`”; “Sem `--fields`, o comando deve seguir uma política determinística documentada pelo gerador: gerar schema sem campos de negócio”; “O schema gerado deve representar os campos e regras para o modelo, a validação das entradas mutáveis e a documentação OpenAPI correspondente.” Also FR03.3, FR05.1, and NFR01/NFR04/NFR05/NFR06 apply.

## Implementation Checklist

- [ ] Implement `parse_fields` with all grammar, duplicate, empty, unknown-type, and unknown-rule errors before I/O.
- [ ] Implement canonical model, route, and spec template functions using ordered fields and the selected tenant mode.
- [ ] Ensure required-field validation enters through `group.use()` and only covers POST/PUT.
- [ ] Ensure generated route calls `auto_crud.generate` and registers all five operation descriptors.
- [ ] Ensure empty schema is rendered for absent `--fields` and stdout can explain that policy.
- [ ] Add the two module entries to `guaraci-scm-1.rockspec`.
- [ ] Add parser/template unit coverage to `tests/cli_generate_spec.lua` (registration is handled by Story 2).

## Acceptance Criteria & Test Cases

- `parse_fields("title:string:required,price:number")` returns the exact ordered shape; `table` produces the documented mappings.
- Empty segments, repeated names, missing type, invalid field name, unknown type, and `min:0` each return `ok=false` with exit-2-compatible error text and no filesystem operation.
- Two renders with identical inputs are byte-identical; absent fields render `model:schema({})`.
- Route output visibly calls `auto_crud.generate`, `group.use`, and `route_introspection.describe`, and does not contain an inline CRUD implementation.
- Generated files pass `luacheck` once placed in a fixture project.
- Run targeted specs with `lua5.4 tests/run_all.lua`; run `lua5.4 scripts/check_rockspec.lua`; run `luacheck src hooks scripts tests bin`.
