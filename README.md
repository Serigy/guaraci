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
Atras de um proxy reverso, declare-o: `client_ip_header = "x-forwarded-for"` (padrao) ou `"x-real-ip"`,
e `trusted_hops = N` (padrao 1): vale a N-esima entrada contada da direita de `X-Forwarded-For`, a que o
proxy confiavel adicionou. `trusted_proxy = true` e um alias para XFF com 1 salto. Sem isso, todos os
clientes compartilham o bucket do proxy. Use `X-Real-IP` so se o proxy o sobrescreve (nao apenas o repassa).

**Armazenamento.** Em CGI cada requisicao e um processo novo, entao contadores em memoria nunca limitam.
Com `GATEWAY_INTERFACE` definido (ou `store_path`/`GUARACI_RATELIMIT_STORE`), o middleware usa um arquivo
(`guaraci_ratelimit.db`, escrita atomica; contagem aproximada sob concorrencia). Voce pode passar
`store = {incr = ..., get = ..., set = ...}` para um backend proprio. `guaraci dev` mantem os contadores
no processo do servidor; um aviso e emitido se o store em memoria for usado em CGI.

## Contrato de short-circuit de middleware
Um middleware (ou hook) `before_*` retorna `true` para interromper a requisicao. Defina `res.status`
(e o corpo) explicitamente. Se o status ficar no padrao (200) e o corpo vazio, o Guaraci responde
`403` (fail closed); para respostas vazias intencionais (health check) use `204`. Rejeicoes ainda passam
pelos hooks `after_request` (headers de seguranca), que nunca podem ser interrompidos.
Ordem: hooks `before_request` rodam antes do middleware global; um stop de hook pula todo o middleware.

## Regras de seguranca importantes
- Nunca concatenar input em SQL
- Sempre escapar output dinamico em HTML
- Templates rodam em sandbox restrito
- Hooks e fluxo do request executam com tratamento defensivo e logs de auditoria

## Documentacao adicional
- Roadmap do MVP: `ROADMAP.md`
- Revisoes por fase: `docs/`
