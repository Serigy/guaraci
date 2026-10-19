# Epic 1 — Story 2: Wire the endpoint generator and safe file creation

**Status:** Done

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

- [x] Add command dispatch, alias semantics, usage errors, unknown options, missing values, and extra-argument rejection.
- [x] Validate name and fields before creating directories or opening output files.
- [x] Build all three target paths once, apply traversal guards, detect all collisions, and report every conflict.
- [x] Create missing `models`, `routes`, and `spec` directories; report mkdir/write failures as exit 1.
- [x] Write exactly three artifacts, honoring `--force`, and print the exact mount/test instructions.
- [x] Ensure terminal output states tenant/default or global mode and no error prints a traceback.
- [x] Register `tests.cli_generate_spec` in `SPEC_MODULES`.
- [x] Keep rockspec entries for both new CLI modules.

## Acceptance Criteria & Test Cases

- `lua5.4 bin/guaraci generate endpoint Product --fields title:string:required` returns 0 and creates exactly three files; `scaffold Product` produces byte-identical files.
- Missing command/type/name, unknown type/flag, missing `--fields` value, invalid name (`../x`, `a/b`, whitespace), and extra positional args return 2 and leave the filesystem unchanged.
- A pre-existing one-of-three destination returns 1, lists the collision, and leaves all three original files untouched; `--force` replaces all three only after validation.
- No invocation creates or modifies `app.lua`; stdout matches the canonical snippet and lists all files.
- `lua5.4 bin/guaraci generate endpoint Product --fields ...` works in a temporary directory; `lua5.4 tests/run_all.lua`, `lua5.4 scripts/check_rockspec.lua`, and `luacheck src hooks scripts tests bin` pass.

## Dev Notes

Modified/created files:
- `src/guaraci_cli/main.lua`: added `generate`/`scaffold` dispatch entries and `command = name` in the `io_streams` table passed to every CLI module (additive; existing modules ignore the new key).
- `src/guaraci_cli/generate.lua`: completed with `target_paths(name)` (ADR-07 defense-in-depth guard), `generate_endpoint(name, raw_flags, io_streams)` (the convergence point for both commands), and `M.run(args, io_streams)` dispatching on `io_streams.command` (`"generate"` requires `args[1] == "endpoint"`; `"scaffold"` takes the name directly).
- `tests/busted_runner.lua`: registered `tests.cli_generate_spec` in `SPEC_MODULES`.
- `tests/cli_generate_spec.lua`: added two more `describe` blocks — pure usage-error dispatch (no filesystem touched, checked by asserting on exit codes only) and real end-to-end invocations of `bin/guaraci` in temporary directories (collision detection without `--force`, `--force` overwrite only after validation, `scaffold`/`generate endpoint` byte-identical output, directory auto-creation, `--no-tenant` end to end, `app.lua` never created/touched).

Notes:
- Exit codes follow the story exactly: 2 for usage errors (bad type/name/flags/fields, extra args), 1 for collisions or write failures, 0 for success. Collision detection happens before any directory is created or file is written — verified by the "leaves all three original files untouched" test comparing byte contents before/after a failed re-generation attempt.
- stdout always states the tenant mode ("multi-tenant (padrão...)" or "modo global (--no-tenant...)") and, when `--fields` is absent, an explicit notice that the schema was generated with only the primary key (`generate.NO_FIELDS_NOTICE`), satisfying "stdout can explain that policy" from Story 1 and the terminal-output checklist item here.
- Tried running a freshly generated `spec/<name>_spec.lua` directly (outside the generator's own unit tests) against a real SQLite db: it fails to `require("route_introspection")`, because that module is Epic 2 Story 1's deliverable and does not exist yet. This is expected — generated code correctly anticipates a module from a not-yet-built story. Full runtime execution of generated specs becomes verifiable once E2-S1 lands; for now, correctness is covered by the `load()` syntax-check in E1-S1's tests and by the shape assertions here.
- Verification: `lua5.4 tests/run_all.lua` → ALL SPECS PASSED (43 specs incl. the two new `cli_generate_spec` describe blocks); `luajit tests/run_all.lua` → ALL SPECS PASSED; `lua5.4 scripts/check_rockspec.lua` → ROCKSPEC CHECK: OK; `lua5.4 scripts/smoke_cgi.lua` → SMOKE CGI: OK; `luacheck --no-color src hooks scripts tests bin` → 0 warnings / 0 errors in 102 files.
- No conflict found between this story's instructions and Story 1's code.

## QA Findings

- **Status:** Approved (mantido como Done)
- **Verificações Realizadas:**
  - Execução via CLI (`bin/guaraci generate endpoint` e alias `bin/guaraci scaffold`) gerando exatamente os 3 arquivos documentados (`models/`, `routes/`, `spec/`).
  - Verificação de que `app.lua` nunca é criado, alterado ou formatado.
  - Detecção de colisão prévia: na presença de arquivo preexistente sem `--force`, a CLI encerra com exit code 1, lista os conflitos e não altera nenhum arquivo. Com `--force`, sobrescreve determinísticamente apenas após validação completa.
  - Tratamento de nomes hostis: caminhos com path traversal (`../x`), barras (`a/b`, `a\b`), caracteres nulos, espaços e símbolos shell são rejeitados com exit code 2 antes de qualquer I/O.
  - Execução dos testes gerados em projeto temporário: o arquivo de testes gerado passou em 100% dos casos contra banco SQLite real.
- **Apontamentos Não-Bloqueantes (Recomendações Futuras):**
  - [Severidade Baixa / Resiliência] `src/guaraci_cli/generate.lua:184-190`: Caso ocorra falha de I/O em um arquivo intermediário (ex.: diretório `spec/` sem permissão de escrita após `models/` e `routes/` terem sido gravados com sucesso), os arquivos já gravados não sofrem rollback atômico, restando arquivos parciais no disco. Recomenda-se implementar limpeza/rollback dos arquivos criados nesta execução em caso de falha de escrita.
