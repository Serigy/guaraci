---
name: format-io-handler
description: 'Envelopa lógica de negócio Lua no contrato padrão do Guaraci, garantindo entrada req e retorno res com status, headers e body.'
argument-hint: 'Cole a lógica de negócios crua para converter ao padrão de Entrypoint req/res.'
user-invocable: true
---

# Format IO Handler

## O que esta skill produz
- Código Lua pronto no padrão de Entrypoint do Guaraci.
- Função que sempre recebe `req` e retorna `res`.
- Estrutura mínima e auditável com `status`, `headers` e `body`.

## Quando usar
- Código de negócio sem contrato HTTP explícito.
- Migração de funções soltas para padrão req/res agnóstico.
- Revisão de PR para consistência de handlers no core do Guaraci.

## Entrada esperada
- String com lógica de negócios crua em Lua.
- Pode incluir variáveis locais, validações e acesso a serviços internos.

## Contrato alvo
- Assinatura: `local function handle_request(req)`
- Retorno: `res = { status = number, headers = table, body = string }`
- Cabeçalho padrão: `Content-Type: text/html; charset=utf-8`

## Procedimento
1. Identificar núcleo da lógica.
- Separar o trecho de regra de negócio da estrutura de transporte.

2. Criar envelope padrão.
- Gerar `res` com valores default seguros.
- Garantir que toda saída de sucesso e erro atualize `res` e faça `return res`.

3. Injetar lógica no fluxo do handler.
- Colocar regra de negócio dentro de bloco protegido (`pcall`) quando aplicável.
- Mapear resultado da lógica para `res.body`.

4. Normalizar tratamento de erro.
- Em erro interno: `status = 500`, corpo genérico e sem stack trace.
- Em entrada inválida: `status = 400` com mensagem curta e controlada.

5. Validar contrato final.
- A função deve aceitar apenas `req` no contrato público.
- A função deve retornar apenas a tabela `res` no retorno público.

## Regras de decisão
- Se a lógica de entrada já estiver no padrão req/res: preservar e apenas ajustar inconsistências mínimas.
- Se houver dependência de API de servidor no core (ex.: ngx): remover do contrato final e substituir por abstração baseada em req/res.
- Se o snippet não tiver informação suficiente para mapear resposta: gerar envelope mínimo com TODO explícito no ponto de decisão.
- Nunca retornar valores primitivos no lugar de `res`.

## Critérios de qualidade e conclusão
- Sempre receber `req` e retornar `res`.
- `res.status`, `res.headers` e `res.body` sempre presentes.
- Nenhum caminho de execução deve sair sem retorno explícito de `res`.
- Código final deve ser direto, legível e sem abstrações desnecessárias.

## Formato de saída obrigatório
- Retornar somente código Lua.
- Entregar a função completa no padrão de Entrypoint.

## Exemplo de saída esperada
```lua
local function handle_request(req)
    local res = {
        status = 200,
        headers = { ["Content-Type"] = "text/html; charset=utf-8" },
        body = ""
    }

    local ok, err = pcall(function()
        local name = req and req.query and req.query.name or "visitante"
        res.body = "<h1>Olá, " .. tostring(name) .. "</h1>"
    end)

    if not ok then
        res.status = 500
        res.body = "Erro interno."
    end

    return res
end
```

## Restrições
- Não introduzir dependências externas.
- Não acoplar o handler ao servidor web subjacente.
- Não alterar regras de negócio além do necessário para cumprir o contrato req/res.
