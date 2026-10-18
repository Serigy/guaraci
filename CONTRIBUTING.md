# Contributing

## Objetivo
Manter o Guaraci pequeno, seguro e auditavel.

## Requisitos
- **Lua 5.3 ou superior** (recomendado 5.4) **ou LuaJIT 2.1**; Lua 5.1 nao e suportado.
- Use o binario `lua5.4` nos comandos abaixo.

## Checklist obrigatorio para PR
1. Nao adicionar dependencias externas no core sem aprovacao explicita.
2. Manter contrato agnostico req/res no core.
3. Garantir protecao contra XSS/SSTI/SQLi/Traversal quando aplicavel.
4. Nao expor detalhes internos de erro ao usuario final.
5. Registrar falhas de seguranca e sistema via `guaraci_audit`.
6. Atualizar testes quando comportamento for alterado.

## Fluxo de desenvolvimento
1. Crie branch curta com escopo unico.
2. Rode smoke test:
```bash
lua5.4 scripts/smoke_cgi.lua
```
3. Rode suite completa:
```bash
lua5.4 tests/run_all.lua
```
4. Valide templates e a CLI:
```bash
guaraci check views/*.gc
guaraci test
```
5. Abra PR com:
- contexto da mudanca
- risco de seguranca avaliado
- evidencias de teste

## Documentacao
- `docs/`: wiki em portugues (submodulo GitHub Wiki). Mantenha o estilo `[[WikiLink]]` e atualize `Home.md` e `_Sidebar.md` ao criar paginas.
- `openwiki/`: indice de evidencias em ingles, gerado pelo OpenWiki. Nao edite paginas geradas (front matter com `verified:`) a mao; siga `openwiki/INSTRUCTIONS.md`.

## Padroes de codigo
- Sem over-engineering
- Sem metaprogramacao desnecessaria
- Comentarios apenas quando agregarem clareza real
- Funcoes pequenas e explicitas

## Seguranca
Se a mudanca afetar parser, sandbox, router, hooks ou db:
- inclua caso de regressao em `tests/security_regression_spec.lua`
