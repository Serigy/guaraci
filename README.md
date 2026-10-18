# Guaraci

Framework web minimalista em Lua, agnostico de servidor e orientado a seguranca by design (ISO 27001).

## Principios
- Simples e auditavel (zero-magic)
- Contrato agnostico req/res
- Templates estilo ASP Classico (`.gc`)
- Defesa nativa contra XSS, SSTI, SQLi e Path Traversal

## Requisitos
- **Lua 5.3 ou superior** (recomendado 5.4) **ou LuaJIT 2.1**; Lua 5.1 nao e suportado.
- **LuaRocks** para instalar a biblioteca e a CLI `guaraci`.
- Nenhuma dependencia externa no core. `lsqlite3` e opcional (driver SQLite); `luasocket` e opcional (apenas `guaraci dev`).

## Instalacao
A partir do checkout, antes da primeira release:

```bash
git clone https://github.com/Serigy/guaraci
cd guaraci
luarocks make guaraci-scm-1.rockspec
```

Depois da publicacao:

```bash
luarocks install guaraci
```

O LuaRocks instala a biblioteca e o binario `guaraci`; ele e o canal de atualizacao (a CLI nao se auto-atualiza). Para o dev server:

```bash
luarocks install luasocket
```

## Uso rapido
```bash
guaraci new meu-app
cd meu-app
guaraci test
guaraci dev            # http://127.0.0.1:8080
guaraci check views/index.gc
```

Comandos: `new`, `check`, `test`, `dev` (com `--container`), `version` e `help`. Codigos de saida: 0 sucesso, 1 achados/falhas, 2 erro de uso. Veja `docs/CLI.md`.

### Exemplo minimo sem CLI
```lua
package.path = "./src/?.lua;./?.lua;" .. package.path

local guaraci = require("guaraci")

local res = guaraci.handle_request({
    method = "GET",
    path = "/",
    query = { nome = "Mundo" },
    headers = {}
}, {
    templates_root = "views"
})

print(res.status)
print(res.body)
```

## Estrutura
- `src/`: core do framework
- `src/guaraci_cli/`: implementacao da CLI
- `bin/`: entrypoint `guaraci`
- `hooks/`: hooks nativos de runtime
- `views/`: templates `.gc`
- `tests/`: suite de testes estilo Busted (runner local)
- `scripts/`: utilitarios de smoke/execucao
- `docs/`: wiki do projeto (submodulo Git)
- `history/`: relatorios de validacao por fase
- `openwiki/`: indice de evidencias em ingles (gerado)

## Testes
```bash
lua5.4 tests/run_all.lua
lua5.4 scripts/smoke_cgi.lua
guaraci test
```
Resultados esperados: `ALL SPECS PASSED` e `SMOKE CGI: OK`.

O CI roda a suite em Lua 5.4, 5.3 e LuaJIT 2.1, alem de luacheck e um job com `lsqlite3`.

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

## Automação
O workflow `openwiki-update.yml` atualiza o OpenWiki diariamente e exige o secret de repositório `OPENAI_API_KEY` (configurado manualmente em Settings > Secrets).

## Documentacao adicional
- Roadmap do MVP: `ROADMAP.md`
- Wiki (pt-BR): `docs/`
- Indice de evidencias (en): `openwiki/quickstart.md`
