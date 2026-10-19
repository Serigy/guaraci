# Epic 1 — Story 2: Wire the endpoint generator and safe file creation

**Status:** Ready

## User Story Goal

As a developer, I want `guaraci generate endpoint` and `guaraci scaffold` to create a complete CRUD slice safely so that I can mount it explicitly without application files being rewritten.

## Prerequisites

Epic 1 Story 1 — Parse endpoint options and render deterministic templates

## Injected Technical Context

Modify `src/guaraci_cli/main.lua`; create/complete `src/guaraci_cli/generate.lua`; modify `tests/busted_runner.lua` and `guaraci-scm-1.rockspec`. Dispatch additions are:

```lua
{ name = "generate", module = "guaraci_cli.generate",
  summary = "generate <type> <name> [--fields ..] [--no-tenant] [--force]: scaffold endpoint" },
{ name = "scaffold", module = "guaraci_cli.generate",
  summary = "alias: guaraci scaffold <name> == guaraci generate endpoint <name>" },
```

`main.lua` calls `mod.run(rest, { stdout=out, stderr=err, util=util, command=name })`. `generate` requires positional `endpoint` then name; `scaffold` takes name directly. Both converge to `generate_endpoint(name, raw_flags, io_streams)`. Parse flags with `util.parse_args(..., { value_flags={fields=true}, flags={["no-tenant"]=true, force=true} })`.

Names validate before I/O using `name:match("^[%w_][%w_%-]*$")`; files/base path use `string.lower(name)` and append only `"s"`. Destinations are exactly `models/<name>.lua`, `routes/<name>.lua`, `spec/<name>_spec.lua`. Existing destinations fail with code 1 unless `--force`; `--force` writes only after all validation. `target_paths` must retain the defense-in-depth checks from ADR-07. Never edit `app.lua`.

Applicable PRD text (verbatim): “A CLI deve aceitar `guaraci generate endpoint <name> [options]`”; “Deve aceitar `guaraci scaffold <name> [options]` como alias equivalente”; “Erro de uso retorna **2** ... Sucesso retorna **0**. Falha de geração, colisão ou falha de escrita retorna **1**”; “Uma execução válida gera exatamente ... `models/<name>.lua`; `routes/<name>.lua`; `spec/<name>_spec.lua`”; “O gerador não pode criar, editar, inserir ou reformatar `app.lua`”; “Antes de escrever, a CLI deve verificar os três destinos”; “`--force` não autoriza path traversal”; “Sem `--no-tenant`, o artefato ... deve manter `require_tenant = true`”. NFR05 also requires actionable failures without stack traces. The exact success snippet is architecture §5.4.

## Implementation Checklist

- [ ] Add command dispatch, alias semantics, usage errors, unknown options, missing values, and extra-argument rejection.
- [ ] Validate name and fields before creating directories or opening output files.
- [ ] Build all three target paths once, apply traversal guards, detect all collisions, and report every conflict.
- [ ] Create missing `models`, `routes`, and `spec` directories; report mkdir/write failures as exit 1.
- [ ] Write exactly three artifacts, honoring `--force`, and print the exact mount/test instructions.
- [ ] Ensure terminal output states tenant/default or global mode and no error prints a traceback.
- [ ] Register `tests.cli_generate_spec` in `SPEC_MODULES`.
- [ ] Keep rockspec entries for both new CLI modules.

## Acceptance Criteria & Test Cases

- `lua5.4 bin/guaraci generate endpoint Product --fields title:string:required` returns 0 and creates exactly three files; `scaffold Product` produces byte-identical files.
- Missing command/type/name, unknown type/flag, missing `--fields` value, invalid name (`../x`, `a/b`, whitespace), and extra positional args return 2 and leave the filesystem unchanged.
- A pre-existing one-of-three destination returns 1, lists the collision, and leaves all three original files untouched; `--force` replaces all three only after validation.
- No invocation creates or modifies `app.lua`; stdout matches the canonical snippet and lists all files.
- `lua5.4 bin/guaraci generate endpoint Product --fields ...` works in a temporary directory; `lua5.4 tests/run_all.lua`, `lua5.4 scripts/check_rockspec.lua`, and `luacheck src hooks scripts tests bin` pass.
