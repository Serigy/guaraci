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
- Lua 5.4+ (compativel com fallback 5.1 em partes do sandbox)

### 2) Smoke test do adapter CGI
```bash
lua scripts/smoke_cgi.lua
```
Resultado esperado:
- `SMOKE CGI: OK`

### 3) Rodar suite de testes (integracao + regressao de seguranca)
```bash
lua tests/run_all.lua
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

## Rate limiting e proxies
A identidade do cliente em `middleware_ratelimit` e `req.remote_addr` (vem de `REMOTE_ADDR`);
`X-Forwarded-For` e `X-Real-IP` sao ignorados por padrao, pois o cliente controla esses headers.
Atras de um proxy reverso, use `middleware_ratelimit.create({ trusted_proxy = true })`; sem isso
todos os clientes compartilham o bucket do proxy. Com `trusted_proxy`, `X-Real-IP` tem prioridade;
senao vale o ultimo (mais a direita) token de `X-Forwarded-For`, o salto adicionado pelo proxy confiavel.
O estado do limitador vive no processo: em CGI ele reinicia a cada requisicao.

## Contrato de short-circuit de middleware
Um middleware (ou hook) `before_*` retorna `true` para interromper a requisicao. Defina `res.status`
(e o corpo) explicitamente. Se o status ficar no padrao (200) e o corpo vazio, o Guaraci responde
`403` (fail closed). Rejeicoes ainda passam pelos hooks `after_request` (headers de seguranca).

## Regras de seguranca importantes
- Nunca concatenar input em SQL
- Sempre escapar output dinamico em HTML
- Templates rodam em sandbox restrito
- Hooks e fluxo do request executam com tratamento defensivo e logs de auditoria

## Documentacao adicional
- Roadmap do MVP: `ROADMAP.md`
- Revisoes por fase: `docs/`
