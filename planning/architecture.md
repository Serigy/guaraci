# Architecture: CRUD Scaffolding & API Explorer

**Projeto:** Guaraci Framework
**Fase BMAD:** 03 — Arquitetura de Solução
**Papel:** `bmad-architect` (Winston)
**Data:** 2026-10-19
**Status:** Pronto para slicing (`bmad-sm-po`)
**Entradas:** `planning/project-brief.md`, `planning/prd.md`, código-fonte em `src/`, `hooks/`, `tests/`

Este documento é lei estrita para o Developer. Toda decisão "a implementação deve escolher" deixada em aberto pelo PRD é resolvida aqui numa única opção. Nenhuma seção descreve alternativas pendentes fora da seção de ADRs.

---

## 0. Resumo executivo das decisões vinculantes

1. `routes/<name>.lua` gerado **chama** `auto_crud.generate(model, group, opts)` sobre um `route_group` com prefixo `base_path`; nunca reimplementa handlers CRUD. Validação de payload e política `--no-tenant` são injetadas via `opts.tenant_middleware` e via um middleware de grupo (`group.use(...)`), ambos pontos de extensão que já existem em `route_group.lua`/`auto_crud.lua` hoje.
2. Introspecção de rotas é **aditiva e explícita**: um novo módulo `route_introspection.lua` guarda metadados (modelo, operação, campos) por rota, preenchidos pelo próprio gerador logo após `auto_crud.generate`. Rotas manuais (não geradas) simplesmente não têm metadados e caem no fallback genérico do FR06.4. Nenhuma heurística de nome é usada para inferir vínculo rota↔modelo.
3. O documento OpenAPI é **recalculado a cada request** de `GET /__guaraci/api-docs` (sem cache, sem arquivo gerado pela CLI) — ver ADR-05.
4. O explorer é HTML/CSS/JS **estáticos** embutidos como strings Lua, servidos em rotas dedicadas; não há nenhum `<script>` inline, então a política de sandbox de templates (`JS_STRING`/`CSS_STRING`) nunca entra em jogo — ver ADR-02.
5. Sem `--fields`, o gerador produz um schema **sem campos de negócio** (apenas chave primária e metadados padrão) em vez de recusar a execução — ver ADR-04.
6. Em produção (`env == "prod"` e sem `force_production = true`), o explorer **não registra nenhuma rota**; a requisição cai no 404 padrão do framework. Fail-closed por ausência, não por checagem em runtime — ver ADR-03.

---

## 1. Definitive Tech Stack

| Camada | Permitido | Proibido |
|---|---|---|
| Core (`src/**`) | Lua 5.3/5.4 stdlib puro; módulos internos já existentes (`router_v2`, `route_group`, `middleware_chain`, `dataware`, `validator`, `binder`, `json_util`, `guaraci_audit`, `guaraci_random`) | Qualquer `require` de pacote LuaRocks novo; `io.popen`/`os.execute` fora da CLI; strings SQL concatenadas (usar `db`/`query_builder`) |
| CLI (`src/guaraci_cli/**`) | Lua 5.3/5.4 stdlib; `io.popen`/`os.execute` já usados em `new.lua`/`util.lua` para `mkdir -p`/`chmod` | `curl`/rede; dependências npm; prompts interativos (stdin) |
| Assets do explorer (`src/api_explorer/assets.lua`) | HTML5 semântico, CSS3, ES2017+ Vanilla JS (`fetch`, `async/await`, template literals) como strings Lua `[==[ ... ]==]` | CDN, `<script src="https://...">`, bundlers, frameworks (React/Vue/Swagger UI), `eval`, `new Function` |
| Testes | O harness interno `tests/busted_runner.lua` (`describe`/`it`/`assert`) já usado por todo `tests/**`; specs geradas usam o mesmo estilo "busted-like" que `guaraci_cli/templates.lua` já gera em `M.index_spec` | Frameworks de teste JS para o explorer (sem navegador headless no CI; testes do explorer são a nível de HTTP/Lua, não de DOM) |
| Lint | `luacheck src hooks scripts tests bin` deve continuar em 0 warnings nos arquivos novos e modificados | — |

Compatibilidade Lua 5.3/5.4/LuaJIT 2.1: nenhum módulo novo usa `goto`, bitwise operators nativos do 5.4 (`&`, `|`, `<<`) ou `utf8` fora do que já é usado no repo. `string.format("%02x", ...)`, `table.concat`, `os.date("!%Y-%m-%dT%H:%M:%SZ")` já são usados em `guaraci_audit.lua`/`guaraci_random.lua` e são compatíveis com os três runtimes-alvo.

---

## 2. Standard Directory Tree

```
src/
  guaraci.lua                      [MODIFICADO] + require("api_explorer.explorer") + M.enable_explorer(opts)
  route_introspection.lua          [NOVO] registro aditivo rota -> descritor (modelo/operação/campos)
  api_explorer/
    explorer.lua                   [NOVO] M.enable(router_v2, opts): fail-closed, registra 4 rotas
    openapi.lua                    [NOVO] M.build_document(opts) + M.encode(doc) (serialização ordenada)
    assets.lua                     [NOVO] M.html, M.css, M.js (strings Lua, <50 KiB somadas)
  guaraci_cli/
    main.lua                       [MODIFICADO] + comandos "generate"/"scaffold", + opts.command no dispatch
    dev.lua                        [MODIFICADO] dispatch() ativa explorer; reset_app_state() limpa route_introspection
    generate.lua                   [NOVO] M.run(args, io_streams): parsing, geração, exit codes
    generate_templates.lua         [NOVO] templates de models/<name>.lua, routes/<name>.lua, spec/<name>_spec.lua

tests/
  route_introspection_spec.lua     [NOVO]
  openapi_spec.lua                 [NOVO]
  api_explorer_spec.lua            [NOVO]
  cli_generate_spec.lua            [NOVO]
  busted_runner.lua                [MODIFICADO] SPEC_MODULES += os 4 módulos acima

guaraci-scm-1.rockspec             [MODIFICADO] build.modules += 6 entradas novas (ver §2.1)

planning/
  architecture.md                  [ESTE DOCUMENTO]
```

Artefatos gerados em tempo de execução **dentro do projeto do usuário** (não neste repositório; produzidos por `guaraci generate endpoint <name>` / `guaraci scaffold <name>`):

```
models/<name>.lua
routes/<name>.lua
spec/<name>_spec.lua
```

### 2.1 Entradas novas em `guaraci-scm-1.rockspec` (`build.modules`)

```lua
route_introspection = "src/route_introspection.lua",
["api_explorer.explorer"] = "src/api_explorer/explorer.lua",
["api_explorer.openapi"] = "src/api_explorer/openapi.lua",
["api_explorer.assets"] = "src/api_explorer/assets.lua",
["guaraci_cli.generate"] = "src/guaraci_cli/generate.lua",
["guaraci_cli.generate_templates"] = "src/guaraci_cli/generate_templates.lua",
```

Sem isso, `lua5.4 scripts/check_rockspec.lua` falha (ele varre `find src -name '*.lua'` e compara com `build.modules`).

### 2.2 Entradas novas em `tests/busted_runner.lua` (`SPEC_MODULES`)

```lua
"tests.route_introspection_spec",
"tests.openapi_spec",
"tests.api_explorer_spec",
"tests.cli_generate_spec",
```

Essas specs cobrem os módulos **do framework**. Elas são distintas do `spec/<name>_spec.lua` que a CLI gera dentro do projeto do usuário, descoberto por `guaraci test` (ver §7).

---

## 3. Data Modeling & Schemas

### 3.1 Field-spec parse result (saída de `guaraci_cli.generate`'s `parse_fields(raw)`)

```lua
-- sucesso: preserva a ORDEM de declaração em --fields (determinismo depende disso)
{
  ok = true,
  fields = {
    { name = "title", type = "string",  required = true  },
    { name = "price", type = "number",  required = false },
    { name = "stock", type = "integer", required = false },
  }
}

-- falha (exit 2 antes de qualquer escrita em disco):
{ ok = false, code = "unknown_type",    message = "campo 'price': tipo desconhecido 'texto'" }
{ ok = false, code = "unknown_rule",    message = "campo 'price': regra desconhecida 'min:0' (somente 'required' nesta versão)" }
{ ok = false, code = "duplicate_field", message = "campo 'price' duplicado" }
{ ok = false, code = "empty_segment",   message = "segmento de campo vazio em --fields" }
{ ok = false, code = "missing_type",    message = "campo 'price': tipo ausente" }
{ ok = false, code = "invalid_name",    message = "campo 'pr ice': nome inválido" }
```

Regras de parsing (gramática `campo:tipo[:regra],...`):
- Separador de campos: `,`. Separador campo/tipo/regra: `:`.
- `campo` casa `^[%a_][%w_]*$` (identificador seguro, também válido como coluna SQL e chave JSON).
- `tipo` ∈ `{"string", "number", "integer", "boolean", "table"}` exatamente (case-sensitive, sem sinônimos).
- No máximo um terceiro segmento, e ele deve ser literalmente `required`. Qualquer outro token (`min:1`, `email`, `enum:a|b`, etc.) é `unknown_rule` — a mensagem de erro cita explicitamente que essas regras ficam para uma gramática futura (FR02.3).
- Campo repetido (mesmo nome, case-sensitive) é `duplicate_field`.
- Segmento vazio (`,,` ou `--fields ""`) é `empty_segment`.

### 3.2 Tipo de campo → coluna SQLite → tipo OpenAPI → regra do `validator`

| Vocabulário CLI | Coluna SQLite (schema do spec gerado) | Tipo OpenAPI | `validator.type_name` |
|---|---|---|---|
| `string`  | `TEXT`              | `"string"`  | `string`  |
| `number`  | `REAL`              | `"number"`  | `number`  |
| `integer` | `INTEGER`           | `"integer"` | `integer` |
| `boolean` | `INTEGER` (0/1)     | `"boolean"` | `boolean` |
| `table`   | `TEXT` (JSON-encoded via `json_util.encode`) | `"object"` (`additionalProperties: true`) | `table`   |

**Limitação documentada (não é bug, é escopo):** `auto_crud.generate` não é modificado, então seus handlers `list`/`get` devolvem a linha crua do banco sem pós-processamento. Para campos `boolean`, a resposta HTTP carrega `0`/`1` (não `true`/`false`); para campos `table`, a resposta carrega a string JSON crua da coluna (não um objeto aninhado). O contrato OpenAPI descreve o tipo **lógico** do campo (`boolean`/`object`) porque é isso que o schema do modelo declara e é isso que o FR02.2 exige documentar; o corpo de resposta real tem essa particularidade de serialização. O Developer não deve tentar "corrigir" isso reescrevendo `auto_crud`; é uma limitação aceita e deve ganhar um teste que **documenta o comportamento atual**, não que o proíbe.

### 3.3 Registro de rota introspectada (`route_introspection` — chave interna `METHOD " " pattern`)

```lua
-- devolvido por route_introspection.all() (ordenado; ver §5.5)
{
  method  = "GET",
  pattern = "/products/:id",
  name    = "products_get",          -- route_v2 route.name
  param_names = { "id" },            -- de router_v2, sempre presente
  descriptor = {                      -- nil quando a rota não foi registrada pelo gerador
    model           = "Product",
    operation       = "get",          -- "list" | "get" | "create" | "update" | "delete"
    fields          = { { name = "title", type = "string", required = true }, ... },
    requires_tenant = true,
  }
}
```

`route_introspection.lua` expõe:

```lua
-- M.describe(method, pattern, descriptor) -> true
-- Idempotente: uma segunda chamada com a mesma (method, pattern) sobrescreve o descritor.
function M.describe(method, pattern, descriptor) end

-- M.get(method, pattern) -> descriptor | nil
function M.get(method, pattern) end

-- M.all() -> array ordenada de { method, pattern, name, param_names, descriptor } (ver §5.5 para ordem)
function M.all() end

-- M.clear() -> limpa o registro (chamado por guaraci_cli.dev em cada reload)
function M.clear() end
```

### 3.4 Documento OpenAPI — exemplo concreto

Para `guaraci generate endpoint Product --fields "title:string:required,price:number"` (tenant habilitado por padrão):

```json
{
  "openapi": "3.0.3",
  "info": { "title": "Guaraci API", "version": "0.1.0" },
  "paths": {
    "/products": {
      "get": {
        "operationId": "products_list",
        "summary": "List products",
        "parameters": [
          { "name": "page", "in": "query", "required": false, "schema": { "type": "integer" } },
          { "name": "per_page", "in": "query", "required": false, "schema": { "type": "integer" } }
        ],
        "responses": {
          "200": {
            "description": "Paginated list",
            "content": { "application/json": { "schema": { "type": "object", "properties": {
              "data": { "type": "array", "items": { "$ref": "#/components/schemas/Product" } },
              "page": { "type": "integer" },
              "per_page": { "type": "integer" },
              "total": { "type": "integer" }
            } } } }
          },
          "403": { "description": "Tenant context required" }
        }
      },
      "post": {
        "operationId": "products_create",
        "summary": "Create product",
        "requestBody": {
          "required": true,
          "content": { "application/json": { "schema": { "$ref": "#/components/schemas/ProductInput" } } }
        },
        "responses": {
          "201": { "description": "Created", "content": { "application/json": { "schema": { "type": "object", "properties": { "ok": { "type": "boolean" } } } } } },
          "400": { "description": "Invalid request" },
          "403": { "description": "Tenant context required" }
        }
      }
    },
    "/products/{id}": {
      "get": {
        "operationId": "products_get",
        "summary": "Get product",
        "parameters": [ { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } } ],
        "responses": {
          "200": { "description": "OK", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Product" } } } },
          "404": { "description": "Resource not found" },
          "403": { "description": "Tenant context required" }
        }
      },
      "put": {
        "operationId": "products_update",
        "summary": "Update product",
        "parameters": [ { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } } ],
        "requestBody": { "required": true, "content": { "application/json": { "schema": { "$ref": "#/components/schemas/ProductInput" } } } },
        "responses": {
          "200": { "description": "OK" }, "400": { "description": "Invalid request" },
          "403": { "description": "Tenant context required" }, "404": { "description": "Resource not found" }
        }
      },
      "delete": {
        "operationId": "products_delete",
        "summary": "Delete product",
        "parameters": [ { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } } ],
        "responses": {
          "200": { "description": "OK" },
          "403": { "description": "Tenant context required" }, "404": { "description": "Resource not found" }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Product": {
        "type": "object",
        "properties": { "id": { "type": "integer" }, "title": { "type": "string" }, "price": { "type": "number" }, "tenant_id": { "type": "string" } }
      },
      "ProductInput": {
        "type": "object",
        "properties": { "title": { "type": "string" }, "price": { "type": "number" } },
        "required": ["title"]
      }
    }
  }
}
```

Notas vinculantes sobre este documento:
- `operationId` = `route.name` tal como registrado no `router_v2` (vem de `resource .. "_" .. operation` dentro de `auto_crud.generate`, ex.: `products_list`). Para rotas sem descritor (ad-hoc), `operationId` é o nome auto-gerado do `router_v2` (`GET__users__id__12345` etc.) — feio mas estável dentro do processo; não é "consertado" com heurísticas.
- `tenant_id` só aparece em `Product`/`ProductInput` quando o recurso **não** foi gerado com `--no-tenant`.
- `parameters` de query (`page`, `per_page`) só aparecem na operação `list`, porque são os únicos nomes que `auto_crud.generate` efetivamente lê (`req.query.page`, `req.query.per_page`); nada é inventado.
- Rotas sem `descriptor` (ad-hoc) nunca ganham `requestBody.content.schema.properties` — apenas `type: object, additionalProperties: true` (FR06.4: "não podem receber campos inventados").

---

## 4. API Contracts

### 4.1 `guaraci.enable_explorer(opts) -> ok, err`

```lua
-- src/guaraci.lua
function M.enable_explorer(opts)
    return api_explorer.enable(router_v2, opts)
end
```

```lua
-- src/api_explorer/explorer.lua
-- M.enable(router, opts) -> true | nil, "explorer_disabled_in_production"
function M.enable(router, opts) end
```

`opts` (todas as chaves opcionais):

| Chave | Default | Efeito |
|---|---|---|
| `path` | `"/__guaraci/explorer"` | Rota da página HTML. `app.js`/`style.css` são sempre `path .. "/app.js"` / `path .. "/style.css"` (não configuráveis individualmente). |
| `env` | `nil` → `os.getenv("GUARACI_ENV")` → `"prod"` | Mesma cascata de `error_handler.current_env`, para consistência de comportamento entre módulos. |
| `force_production` | `false` | Único jeito de habilitar em `env == "prod"`. Nunca lido de query string, cookie ou header do cliente (FR08.4). |
| `title` | `"Guaraci API"` | `info.title` do documento OpenAPI. |
| `version` | `require("guaraci_version")` | `info.version` do documento OpenAPI. |

Comportamento:
- `GET /__guaraci/api-docs` é **sempre** uma rota fixa (não configurável) quando o explorer está habilitado — é o contrato público citado no PRD 2.2.
- Quando `env == "prod"` e `force_production ~= true`: `M.enable` **não registra nenhuma rota** e retorna `nil, "explorer_disabled_in_production"`. Nenhum trabalho extra por request (NFR03): zero rotas = zero introspecção = zero custo no `handle_request`.
- Quando habilitado com `force_production = true` em `env == "prod"`: registra as rotas normalmente e emite `guaraci_audit.log_security("api_explorer_enabled_in_production", { path = opts.path })` uma vez, na chamada de `enable`.
- Chamar `enable_explorer` duas vezes no mesmo processo sem um `router_v2.clear()` entre as chamadas registra rotas duplicadas (mesmo comportamento de `router_v2.register`/`guaraci.use` hoje — o primeiro match ganha, sem erro). Não é um caso coberto por deduplicação nova; `guaraci dev` já limpa o router a cada request, e CGI é um processo por request.

### 4.2 HTTP — `GET /__guaraci/api-docs`

| | |
|---|---|
| Sucesso | `200`, `Content-Type: application/json; charset=utf-8`, corpo = documento OpenAPI (§3.4) |
| Falha de introspecção/serialização | `500`, `Content-Type: application/json; charset=utf-8`, corpo = formato padrão de erro do framework (`{status,error="openapi_build_failed",message="Internal Error",request_id}`); `guaraci_audit.log_error` é chamado |
| Explorer desabilitado (prod sem override) | `404` (rota nunca registrada; cai no fluxo padrão `route_not_found` de `guaraci.lua`) |

### 4.3 HTTP — `GET /__guaraci/explorer`, `GET /__guaraci/explorer/app.js`, `GET /__guaraci/explorer/style.css`

| Rota | Content-Type | Observações |
|---|---|---|
| `path` (HTML) | `text/html; charset=utf-8` | Emite `Set-Cookie: guaraci_csrf_token=<64 hex chars>; Path=/; SameSite=Lax` (sem `HttpOnly` — o JS precisa ler o cookie para o double-submit). Token gerado com `guaraci_random.hex(16)` (32 bytes → 64 hex, bem acima do mínimo de 16 caracteres do middleware). |
| `path .. "/app.js"` | `application/javascript; charset=utf-8` | String estática de `api_explorer.assets.js`; nenhuma interpolação de dados do servidor. |
| `path .. "/style.css"` | `text/css; charset=utf-8` | String estática de `api_explorer.assets.css`. |

Todas as três respondem `404` (rota ausente) quando o explorer está desabilitado, pela mesma razão do §4.2.

### 4.4 Contrato HTTP das rotas geradas (via `auto_crud.generate`, inalterado)

Reaproveitado tal como já implementado em `src/auto_crud.lua` — ver `map_error_to_status`/`ERROR_MESSAGES` lidos do código-fonte. O gerador **não** adiciona nem remove códigos de status desse contrato; apenas insere uma camada de validação de payload (400) **antes** do handler do `auto_crud`, via middleware de grupo (ver §5.2).

### 4.5 `guaraci_cli.generate.run(args, io_streams) -> exit_code`

```lua
-- io_streams agora inclui `command` ("generate" | "scaffold"), setado por main.lua
function M.run(args, io_streams) end
```

Dispatch em `main.lua` (adição, não substitui o laço existente):

```lua
{ name = "generate", module = "guaraci_cli.generate",
  summary = "generate <type> <name> [--fields ..] [--no-tenant] [--force]: scaffold endpoint" },
{ name = "scaffold", module = "guaraci_cli.generate",
  summary = "alias: guaraci scaffold <name> == guaraci generate endpoint <name>" },
```

```lua
-- dentro de main.lua M.run, no ponto em que hoje monta `rest`:
local code = mod.run(rest, { stdout = out, stderr = err, util = util, command = name })
```

Regras de parsing dentro de `guaraci_cli/generate.lua`:
- `command == "generate"`: `args[1]` deve ser exatamente `"endpoint"` (único tipo suportado nesta versão); ausência ou valor diferente → exit 2, mensagem `"generate <type>: tipo desconhecido '<x>' (suportado: endpoint)"`. `args[2]` é `<name>`.
- `command == "scaffold"`: `args[1]` é `<name>` diretamente, sem palavra-chave.
- Ambos convergem para a mesma função interna `generate_endpoint(name, raw_flags, io_streams)`, garantindo bytes idênticos (FR01.2).
- Flags aceitas via `util.parse_args(rest_after_name, { value_flags = { fields = true }, flags = { ["no-tenant"] = true, force = true } })`.

Exit codes: `0` sucesso; `2` erro de uso (nome inválido, tipo/regra de campo inválidos, opção desconhecida, valor faltante, argumentos extras, tipo de `generate` desconhecido); `1` colisão sem `--force`, falha de escrita/mkdir.

---

## 5. Coding Standards & Cross-Cutting Concerns

### 5.1 Nomenclatura e normalização de `<name>`

- Validação (antes de qualquer I/O): `name:match("^[%w_][%w_%-]*$")` — letra/dígito/`_` inicial, seguido de letras/dígitos/`_`/`-`; rejeita implicitamente `/`, `\`, espaço e `..` (nenhum desses caracteres está na classe permitida). Falha → exit 2.
- `<name>` é usado **verbatim** como nome do modelo Dataware (`dataware.model(name)` preserva a capitalização que o usuário digitou, ex.: `Product`), espelhando a convenção de `auto_crud.lua`.
- Nomes de arquivo e `base_path` usam `string.lower(name)` e pluralização **apenas por sufixo `"s"`** — exatamente o default já usado em `auto_crud.generate` (`string.lower(info.name) .. "s"`). Não implementar um pluralizador melhor (ex. `category` → `categorys`, não `categories`); é uma limitação aceita e documentada, não um bug a corrigir nesta fase.

### 5.2 `routes/<name>.lua` — forma canônica gerada

```lua
-- routes/product.lua (gerado; exemplo ilustrativo)
local auto_crud = require("auto_crud")
local route_introspection = require("route_introspection")
local model = require("models.product")

local FIELDS = {
    { name = "title", type = "string", required = true },
    { name = "price", type = "number", required = false },
}

local function validate_mutation(req, res, context)
    local method = string.upper(tostring(req.method or "GET"))
    if method ~= "POST" and method ~= "PUT" then
        return false
    end
    local payload = type(req.body_table) == "table" and req.body_table or {}
    for _, field in ipairs(FIELDS) do
        if field.required and (payload[field.name] == nil or payload[field.name] == "") then
            res.status = 400
            res.headers = res.headers or {}
            res.headers["Content-Type"] = "application/json; charset=utf-8"
            res.body = '{"code":"invalid_request","message":"Field '.. field.name ..' is required","retryable":false}'
            return true
        end
    end
    return false
end

return function(guaraci)
    local group = guaraci.group("/products")
    group.use(validate_mutation, "product_validate_mutation", 60)

    local opts = { base_path = "" }
    -- --no-tenant gera, em vez do bloco abaixo, opts.tenant_middleware fixo (ver corpo do texto)

    auto_crud.generate(model, group, opts)

    for _, op in ipairs({ "list", "get", "create", "update", "delete" }) do
        local method = ({ list = "GET", get = "GET", create = "POST", update = "PUT", delete = "DELETE" })[op]
        local pattern = (op == "get" or op == "update" or op == "delete") and "/products/:id" or "/products"
        route_introspection.describe(method, pattern, {
            model = "Product", operation = op, fields = FIELDS, requires_tenant = true
        })
    end

    return group
end
```

Para `--no-tenant`, `opts.tenant_middleware` é fixado assim (e `requires_tenant = false` nos descritores):

```lua
opts.tenant_middleware = function(req, res, context)
    context.tenant_id = "__global__"
    return false
end
```

Isso funciona porque `query_builder` só filtra/exige `tenant_id` quando `model_definition.require_tenant == true` (ver `src/query_builder.lua`); como o modelo gerado chama `:without_tenant()`, o valor fixo `"__global__"` satisfaz apenas o gate de `auto_crud.resolve_tenant` e nunca toca o SQL. **Nenhuma mudança em `auto_crud.lua` ou `query_builder.lua` é necessária.**

O middleware de validação usa o **ponto de extensão existente** de `route_group.use()`: ele roda antes de qualquer handler do grupo (inclusive os registrados por `auto_crud.generate`, já que o grupo é passado como `router` para `auto_crud.generate`), e `base_path = ""` garante que os padrões internos do `auto_crud` (`base_path` e `base_path .. "/:id"`) colem exatamente no prefixo do grupo.

### 5.3 `models/<name>.lua` — forma canônica gerada

```lua
-- models/product.lua
local guaraci = require("guaraci")

local model = guaraci.model("Product")
model:table("products")
-- :without_tenant() só aparece quando --no-tenant foi passado; caso contrário omitido (tenant é o default do dataware.model)
model:schema({
    title = { type = "string", required = true },
    price = { type = "number" },
})

return model
```

Sem `--fields`, `model:schema({})` é gerado (tabela vazia) — ver ADR-04.

### 5.4 Mount snippet impresso em stdout (FR03.4)

```
Criado:
  models/product.lua
  routes/product.lua
  spec/product_spec.lua

Para montar em app.lua:
  local guaraci = require("guaraci")
  require("routes.product")(guaraci)

Em seguida:
  guaraci test
```

Exatamente essas duas linhas de `require`, sem variação — a saída precisa ser previsível para documentação/CI copiarem.

### 5.5 Determinismo e ordenação

- `route_introspection.all()` e `openapi.build_document()` iteram métodos nesta ordem fixa: `GET, POST, PUT, PATCH, DELETE, HEAD`; dentro de cada método, iteram `router_v2.get_routes(method)` na ordem de registro (array, não `pairs()` — já estável). Nenhuma ordenação alfabética é aplicada por cima; "determinístico" aqui significa "mesma ordem de registro produz mesma ordem de documento", que é o que FR06.3 pede.
- **Serialização JSON do documento OpenAPI não usa `json_util.encode` para os três contêineres associativos por string (`paths`, `properties`, `responses`)**, porque `json_util.encode` itera com `pairs()` e não garante ordem estável entre execuções. `src/api_explorer/openapi.lua` constrói esses três níveis como uma representação interna ordenada (array de `{key=, value=}`) e serializa com um encoder recursivo próprio do módulo; valores-folha (strings, números, booleans, arrays já ordenadas) continuam delegando para `json_util.encode`. Isso não altera `json_util.lua` (módulo do core intocado).
- Campos de `--fields` preservam a ordem de declaração do usuário em todo lugar: no schema Lua gerado, no array `FIELDS` usado pela validação, e no array `properties`/`required` do OpenAPI. Nada é reordenado alfabeticamente.
- Nenhum arquivo gerado contém timestamp, UUID ou qualquer valor não determinístico — mesma invocação (`name`, flags, estado do diretório) produz os mesmos bytes sempre (NFR06).

### 5.6 Escaping e segurança de conteúdo

- A UI do explorer renderiza nomes de rota, métodos e nomes de campo vindos de `GET /__guaraci/api-docs` **no DOM via `textContent`/`createElement`, nunca via `innerHTML` com concatenação de string**. Isso é a defesa contra um nome de rota ou campo malicioso (ex.: um dev registra manualmente uma rota ad-hoc chamada `<img onerror=...>` — improvável, mas o contrato não deve confiar na entrada).
- O HTML base (`assets.lua` `M.html`) não interpola nenhum dado dinâmico — é uma string estática fixa. Isso elimina qualquer necessidade de escape no lado Lua para a página em si; todo dado dinâmico entra via `fetch()` + DOM APIs no `app.js`.
- Nenhum `onclick`/`onload` inline; todos os listeners são `addEventListener` dentro do próprio `app.js`.

### 5.7 Auditoria

- Mutações disparadas pelo explorer passam pela mesma `handle_request` pipeline que qualquer outra requisição — CSRF, middleware de grupo, `auto_crud`, `dataware_audit` (chamado de dentro de `query_builder.lua`) — nenhuma chamada de auditoria nova é necessária para o caminho de dados em si (FR11.4 já está coberto pela cadeia existente).
- `enable_explorer` com `force_production = true` chama `guaraci_audit.log_security` uma vez, conforme §4.1.
- Falhas de introspecção/serialização em `/__guaraci/api-docs` chamam `guaraci_audit.log_error("openapi_build_failed", { error = tostring(err) })`.

### 5.8 Modificações pontuais em arquivos existentes

**`src/guaraci_cli/dev.lua`** — duas mudanças mínimas:

```lua
-- em reset_app_state(baseline), depois das linhas existentes:
local introspection = package.loaded["route_introspection"]
if introspection then introspection.clear() end

-- em M.dispatch, logo após reset_app_state(config.baseline):
require("guaraci").enable_explorer({ env = "dev" })
```

**`src/guaraci.lua`** — um `require` novo e uma função delegadora, no mesmo estilo de `M.middleware_csrf`/`M.validator_schema`:

```lua
local api_explorer = require("api_explorer.explorer")
...
function M.enable_explorer(opts)
    return api_explorer.enable(router_v2, opts)
end
```

Nenhuma outra linha de `guaraci.lua` muda; `handle_request` não precisa saber que o explorer existe — ele é só mais um conjunto de rotas em `router_v2`.

---

## 6. Architecture Decision Records

### ADR-01: Assets embutidos como strings Lua vs. servidos de disco

**Contexto:** o explorer precisa de HTML/CSS/JS same-origin, abaixo de 50 KiB, sem dependência de arquivos presentes no diretório de trabalho do usuário.

**Opções:** (a) ler de disco a partir de um diretório instalado junto ao rock; (b) embutir como strings Lua no módulo.

**Decisão:** (b), embutido em `src/api_explorer/assets.lua`, no mesmo padrão de `guaraci_cli/templates.lua` (`M.app_lua`, `M.index_gc`, etc. como strings `[==[ ]==]`).

**Consequências:** nenhuma dependência de `package.path`/instalação para localizar arquivos estáticos; funciona idêntico em CGI (processo novo por request) e em `guaraci dev` (reload); o tamanho total é verificável estaticamente com `wc -c` nos três literais do módulo (ligado a NFR03 — CI pode checar o módulo sem precisar de um servidor rodando). Custo: assets ficam "dentro" do arquivo `.lua`, exigindo disciplina de não deixar o literal crescer sem perceber — mitigado por um teste em `api_explorer_spec.lua` que mede `#assets.html + #assets.css + #assets.js < 50*1024`.

### ADR-02: Scripts inline sob CSP — hash/nonce vs. zero inline

**Contexto:** `Content-Security-Policy: default-src 'self'` bloqueia `<script>` inline sem hash/nonce aprovado; o sandbox de templates (`escape_context.lua`) bloqueia interpolação em contexto `JS_STRING`/`CSS_STRING` quando o conteúdo passa por `sandbox.render_template` (compilação `.gc`).

**Opções:** (a) calcular um hash SHA-256 do bloco de script e adicionar `script-src 'self' 'sha256-...'` ao CSP; (b) usar um nonce por request; (c) não ter nenhum `<script>` inline — tudo em `app.js` externo same-origin.

**Decisão:** (c). O HTML base não contém nenhuma tag `<script>` com conteúdo; há apenas `<script src="/__guaraci/explorer/app.js"></script>`. Isso automaticamente satisfaz `default-src 'self'` sem tocar no CSP existente (`hooks/security_headers.lua` não muda) e sem envolver o sandbox de templates — o explorer não usa `.gc` em nenhum ponto, então `blocked_context:JS_STRING` nunca é avaliado para este código.

**Consequências:** zero necessidade de hash/nonce, zero acoplamento com `hooks/security_headers.lua`. Custo: toda lógica de UI precisa viver em `app.js`/`style.css`; nada de atributos `style="..."` ou `onclick="..."` inline (reforçado em §5.6).

### ADR-03: Fail-closed em produção — ausência de rota vs. checagem em runtime

**Contexto:** FR08.3/08.5 exigem que, em produção sem `force_production`, o explorer não responda 2xx e não registre rotas nem gaste trabalho por request de negócio.

**Opções:** (a) registrar as rotas sempre e checar `env` dentro de cada handler, respondendo 403/404 quando bloqueado; (b) nunca registrar as rotas quando bloqueado, deixando o 404 padrão do roteador agir.

**Decisão:** (b). `api_explorer.explorer.lua.enable()` decide o modo **uma vez**, na chamada de `enable_explorer`; se bloqueado, retorna cedo sem tocar em `router_v2.register`.

**Consequências:** satisfaz literalmente "não deve registrar as rotas internas" (FR08.5) e "não deve... acrescentar trabalho a cada requisição de negócio" (mesmo item) — zero overhead, porque não há handler nenhum para rodar. O código de bloqueio é 404 (não 403): uma rota ausente é indistinguível de uma rota que nunca existiu, o que não revela sequer que a feature existe. Custo: quem espera um 403 explícito (comportamento "ativo") não o recebe; isso é aceitável porque o PRD permite explicitamente escolher entre 404 e 403 ("conforme o código escolhido pela implementação").

### ADR-04: Schema vazio vs. recusa quando `--fields` está ausente

**Contexto:** FR02.5 deixa em aberto a política para "sem `--fields`": gerar schema sem campos de negócio, ou recusar com exit 2.

**Opções:** (a) recusar com exit 2, forçando o usuário a sempre declarar campos; (b) gerar um recurso funcional com schema vazio (apenas chave primária e, quando aplicável, `tenant_id`).

**Decisão:** (b).

**Racional:** o fluxo de scaffolding do Guaraci é não-interativo e deliberadamente parecido com geradores maduros (Rails/Phoenix), onde `rails generate scaffold Product` sem atributos também produz um recurso funcional e editável — não um erro. Recusar a execução sem `--fields` quebraria o caso de uso "quero um esqueleto de CRUD agora, adiciono campos depois à mão", que é exatamente o tipo de iteração rápida que o PRD define como objetivo de produto (seção 1, item 1: "menos de 30 segundos"). Como as validações de uso (nome, tipos, regras) já rodam e falham com exit 2 quando *há* `--fields` mal formado, a ausência total da flag não é ambígua nem silenciosa: o terminal explicitamente informa "nenhum campo de negócio declarado; schema gerado com apenas a chave primária" no stdout de sucesso.

**Consequências:** `models/<name>.lua` gerado tem `model:schema({})`; `spec/<name>_spec.lua` gerado ainda cobre 200/201/400/404 (o 400 do teste de "entrada inválida" neste caso é o corpo não-tabela, já que não há campo `required` para violar); o documento OpenAPI tem `ProductInput.properties = {}` e `required` ausente (lista vazia não é emitida, por limpeza). Testado explicitamente em `cli_generate_spec.lua` (ver §7).

### ADR-05: Introspecção em runtime vs. documento estático emitido pela CLI

**Contexto:** o PRD deixa em aberto como o catálogo OpenAPI é produzido.

**Opções:** (a) a CLI gera um `openapi.json` estático no momento do scaffold, servido depois como arquivo; (b) o servidor recalcula o documento a cada `GET /__guaraci/api-docs`, lendo `router_v2`/`route_introspection`/`dataware` ao vivo.

**Decisão:** (b).

**Racional:** FR07.4 exige explicitamente "o catálogo atual do processo/request, não um arquivo stale". Em CGI, cada request é um processo novo; em `guaraci dev`, `app.lua` é recarregado a cada request e rotas são limpas e re-registradas — um arquivo gerado na hora do `scaffold` ficaria desatualizado assim que o usuário editasse `routes/<name>.lua` à mão (coisa que o PRD espera que aconteça — ver Socratic Q2 do brief). O custo de reconstrução é desprezível (número de rotas de uma aplicação típica, sem I/O).

**Consequências:** nenhuma etapa de build/geração de artefato estático; nenhuma necessidade de invalidação de cache; o documento é sempre consistente com o estado real do `router_v2` no momento da requisição. Testado diretamente: registrar uma rota extra entre duas chamadas de `GET /__guaraci/api-docs` no mesmo teste deve mudar o `paths` da segunda resposta.

### ADR-06: Onde o código do explorer mora, para o core continuar dependency-free

**Contexto:** o core (`src/guaraci.lua` e o que ele `require`s incondicionalmente) deve continuar sem introduzir custo de carregamento para quem não usa CRUD scaffolding/explorer.

**Opções:** (a) carregar `api_explorer`/`route_introspection` sempre, dentro do bloco de `require`s no topo de `guaraci.lua`; (b) `require("api_explorer.explorer")` continua no topo de `guaraci.lua` (porque `M.enable_explorer` precisa existir como função pública sempre disponível), mas `route_introspection` só é carregado por quem efetivamente usa o gerador (`routes/<name>.lua` gerado) ou o próprio `api_explorer.openapi`.

**Decisão:** (b). `guaraci.lua` ganha **um** `require` novo (`api_explorer.explorer`), consistente com todos os outros módulos de feature opcional que ele já carrega incondicionalmente hoje (`middleware_cors`, `middleware_csrf`, `middleware_ratelimit` — nenhum deles é "sempre usado", mas todos são sempre carregados). `route_introspection` não entra no `require` de `guaraci.lua`; é carregado sob demanda por quem chama `route_introspection.describe/all` (o código gerado, e internamente por `api_explorer.openapi`).

**Consequências:** o padrão de carregamento de `guaraci.lua` não muda de categoria — ele já é um módulo "fachada" que puxa todo o framework. O ganho de isolamento real está em `route_introspection` nunca ser tocado por aplicações que não usam scaffolding nem explorer, e os assets (`api_explorer/assets.lua`, potencialmente o maior módulo em bytes) só serem carregados quando `enable_explorer` de fato roda (ele é `require`d dentro de `explorer.lua`, não dentro de `guaraci.lua`).

### ADR-07: Idempotência e path traversal no gerador

**Contexto:** o gerador escreve em `models/`, `routes/`, `spec/`; precisa ser seguro contra nomes maliciosos e determinístico em reexecuções.

**Decisão:** a validação de `<name>` (§5.1) já exclui estruturalmente `/`, `\` e `..` da classe de caracteres aceita — não é necessário um segundo filtro de "path traversal" depois da validação de nome, porque não existe entrada que passe na regex e ainda contenha esses caracteres. Como defesa em profundidade (caso a regex seja relaxada numa versão futura), os três caminhos de destino são construídos por uma função única `target_paths(name)` em `generate.lua` que, antes de qualquer escrita, reafirma `not path:find("..", 1, true)` e `path:match("^[%w_%-/]+%.lua$")` — um segundo guard barato, não uma nova política.

Idempotência: nenhuma entrada de tempo (timestamp, random) é escrita nos três arquivos gerados; a mesma combinação de `(name, --fields, --no-tenant)` sobre o mesmo estado de diretório produz bytes idênticos a cada execução — verificado em `cli_generate_spec.lua` rodando a geração duas vezes com `--force` e comparando os bytes.

---

## 7. Test Strategy Handoff

### 7.1 Seams testáveis sem servidor

| Seam | Como testar | FRs cobertos |
|---|---|---|
| `guaraci_cli.generate.parse_fields(raw)` (ou equivalente interno exposto para teste) | Chamar diretamente com strings de `--fields`; checar `ok`/`fields`/`code` | FR02.1–02.5 |
| `guaraci_cli.generate.run(args, io_streams)` com `io_streams.stdout/stderr` como tabelas fake (`{write=...}`) | Rodar com argv variados; checar exit code e strings de stderr/stdout; checar `util.file_exists` dos 3 artefatos num diretório temporário | FR01, FR03, FR04, FR05 |
| `route_introspection.describe/all/clear` | Registrar descritores manualmente; checar ordem e shape de `all()` | FR06 |
| `api_explorer.openapi.build_document(opts)` | Popular `router_v2`/`route_introspection`/`dataware` manualmente num `before_each`; comparar o doc Lua (antes de serializar) campo a campo | FR07.1–07.3 |
| `api_explorer.openapi.encode(doc)` | Construir dois documentos com as mesmas chaves em ordens de inserção diferentes; `encode` deve produzir a mesma string nos dois casos | NFR06 |
| `api_explorer.explorer.enable(router_v2, opts)` + `guaraci.handle_request` | Chamar `enable` com `env="prod"` sem/com `force_production`; disparar `handle_request` para as 4 rotas; checar 404 vs 200 | FR08 |
| `luacheck`/`check_rockspec.lua`/`busted_runner.lua` | Rodar como já documentado no CONTRIBUTING.md | NFR04 |

### 7.2 Seams que precisam de `guaraci.handle_request` (HTTP simulado, sem socket real)

Seguir o padrão já usado em `tests/guaraci_routing_spec.lua` (chamar `guaraci.handle_request({method=,path=,headers=,body_table=}, opts)` diretamente, sem abrir socket). Cobrir:
- CSRF: GET em `/__guaraci/explorer` devolve `Set-Cookie`; POST para uma rota gerada sem `X-CSRF-Token` devolve 403 `csrf_token_invalid`; com header igual ao cookie, passa.
- Validação de grupo: POST com campo `required` ausente devolve 400 antes de qualquer chamada ao `model:create` (usar um `db.set_driver` fake que registra chamadas, como em `tests/auto_crud_spec.lua`, e assertar que a lista de chamadas SQL ficou vazia).
- `--no-tenant`: POST sem `X-Tenant-Id` não é bloqueado por `tenant_required`.
- Produção fail-closed: com `GUARACI_ENV=prod` (ou `opts.env="prod"`) e sem `force_production`, as 4 rotas do explorer devolvem 404; com `force_production=true`, devolvem 200/200/200 e `GET /__guaraci/api-docs` tem `Content-Type` correto.
- NFR03: chamar `router_v2.clear()` + reconstruir rotas duas vezes (simulando reload do `guaraci dev`) e checar `router_v2.count()` não duplica.

### 7.3 Specs geradas dentro do projeto do usuário (`spec/<name>_spec.lua`)

Seguem o padrão de `tests/sqlite_dataware_integration_spec.lua`: cada `it` começa com `local ok, sqlite = pcall(require, "lsqlite3"); if not ok then assert.is_true(true); return end`, cria uma tabela SQLite temporária com `CREATE TABLE` (colunas conforme §3.2), chama `guaraci.init_dataware_sqlite({connection=connection})`, depois exercita `routes/<name>.lua` via `guaraci.handle_request`. Casos mínimos (FR03.2): listagem 200, criação 201, entrada inválida 400 (campo `required` faltando, ou corpo não-tabela quando não há campos), recurso ausente 404, isolamento de tenant (requisição de outro tenant não vê a linha) — ou, em modo `--no-tenant`, o caso equivalente vira "requisição sem tenant não é bloqueada por esse motivo".

### 7.4 O que a QA deve auditar especificamente (ligado ao Global DoD do PRD)

- Nenhum teste de explorer depende de rede externa ou de um navegador real — tudo via `guaraci.handle_request` e inspeção de string (HTML/JS/CSS) com `wc -c`/`#string` para o limite de 50 KiB.
- Confirmar que o `encode()` do OpenAPI realmente não depende da ordem de `pairs()` — o teste do ADR em 7.1 precisa rodar múltiplas vezes (ou com `math.randomseed` diferente) para não passar por acaso.
- Confirmar que a resposta de bloqueio em produção (404) não vaza nenhuma string como `"explorer"`, `"api-docs"` ou nomes de rota no corpo — deve ser byte-a-byte igual ao 404 padrão de uma rota qualquer inexistente.
- Confirmar `scripts/check_rockspec.lua` e `tests/busted_runner.lua` atualizados antes de considerar qualquer ticket "Done".
