# Guaraci

Framework web minimalista em Lua, agnostico de servidor e orientado a seguranca by design (ISO 27001).

## Principios
- Simples e auditavel (zero-magic)
- Contrato agnostico req/res
- Templates estilo ASP Classico (`.gc`)
- Defesa nativa contra XSS, SSTI, SQLi e Path Traversal

## Requisitos
- Lua **5.3 ou superior** (recomendado 5.4). Lua 5.1 nao e suportado: o core usa `table.pack`, `table.unpack` e `goto`.
- Nenhuma dependencia externa no core. `lsqlite3` e opcional, apenas para o driver SQLite.

## Instalacao
<!-- TODO(WP2): preencher apos CLI -->
```bash
# TODO(WP2): comando de instalacao via LuaRocks sera publicado aqui
```

Enquanto o pacote nao estiver publicado, clone o repositorio e use `package.path`:

```bash
git clone https://github.com/Serigy/guaraci
cd guaraci
```

## Estrutura
- `src/`: core do framework
- `hooks/`: hooks nativos de runtime
- `views/`: templates `.gc`
- `tests/`: suite de testes estilo Busted (runner local)
- `scripts/`: utilitarios de smoke/execucao
- `docs/`: wiki do projeto (submodulo Git)
- `history/`: relatorios de validacao por fase
- `openwiki/`: indice de evidencias em ingles (gerado)

## Quickstart
### 1) Smoke test do adapter CGI
```bash
lua5.4 scripts/smoke_cgi.lua
```
Resultado esperado:
- `SMOKE CGI: OK`

### 2) Rodar suite de testes (integracao + regressao de seguranca)
```bash
lua5.4 tests/run_all.lua
```
Resultado esperado:
- `ALL SPECS PASSED`

### 3) Exemplo minimo de uso no seu adapter
```lua
package.path = "./src/?.lua;./?.lua;" .. package.path

local guaraci = require("guaraci")

local req = {
    method = "GET",
    path = "/",
    query = { nome = "Mundo" },
    headers = {}
}

local res = guaraci.handle_request(req, {
    templates_root = "views"
})

print(res.status)
print(res.body)
```

## Regras de seguranca importantes
- Nunca concatenar input em SQL
- Sempre escapar output dinamico em HTML
- Templates rodam em sandbox restrito
- Hooks e fluxo do request executam com tratamento defensivo e logs de auditoria

## Documentacao adicional
- Roadmap do MVP: `ROADMAP.md`
- Wiki (pt-BR): `docs/`
- Indice de evidencias (en): `openwiki/quickstart.md`
