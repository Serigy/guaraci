# Guaraci

Framework web minimalista em Lua, agnostico de servidor e orientado a seguranca by design (ISO 27001).

## Principios
- Simples e auditavel (zero-magic)
- Contrato agnostico req/res
- Templates estilo ASP Classico (`.gc`)
- Defesa nativa contra XSS, SSTI, SQLi e Path Traversal

## Estrutura
- `src/`: core do framework
- `hooks/`: hooks nativos de runtime
- `views/`: templates `.gc`
- `tests/`: suite de testes estilo Busted (runner local)
- `scripts/`: utilitarios de smoke/execucao
- `docs/`: relatorios de validacao por fase

## Quickstart
### 1) Requisitos
- Lua 5.3+ (recomendado 5.4)

### 2) Smoke test do adapter CGI
```bash
lua5.4 scripts/smoke_cgi.lua
```
Resultado esperado:
- `SMOKE CGI: OK`

### 3) Rodar suite de testes (integracao + regressao de seguranca)
```bash
lua5.4 tests/run_all.lua
```
Resultado esperado:
- `ALL SPECS PASSED`

### 4) Exemplo minimo de uso no seu adapter
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

## Automação
O workflow `openwiki-update.yml` atualiza o OpenWiki diariamente e exige o secret de repositório `OPENAI_API_KEY` (configurado manualmente em Settings > Secrets).

## Documentacao adicional
- Roadmap do MVP: `ROADMAP.md`
- Revisoes por fase: `docs/`
