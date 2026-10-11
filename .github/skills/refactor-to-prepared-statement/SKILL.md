---
name: refactor-to-prepared-statement
description: 'Varre snippets Lua em busca de SQL com concatenação insegura e refatora para prepared statements com placeholders ?, retornando código corrigido e log de alteração.'
argument-hint: 'Cole o código Lua com SQL para refatoração automática para prepared statements.'
user-invocable: true
---

# Refactor To Prepared Statement

## O que esta skill produz
- Código Lua refatorado para prepared statements (`?`).
- Log de alteração descrevendo cada query transformada.

## Quando usar
- PRs com concatenação de SQL usando `..`.
- Correção rápida de risco de SQL Injection em camada de acesso a dados.
- Padronização do acesso a banco no Guaraci com consultas parametrizadas.

## Entrada esperada
- String com código Lua contendo uma ou mais consultas SQL potencialmente inseguras.

## Procedimento
1. Identificar consultas SQL no snippet.
- Procurar strings SQL em variáveis e chamadas diretas ao driver.
- Detectar padrões de concatenação como `"..." .. var .. "..."`.

2. Classificar risco de injeção.
- Se variável de origem externa (`req`, `Request`, parâmetros de função, payload), marcar como alta prioridade.
- Se concatenação ocorrer em cláusulas `WHERE`, `VALUES`, `IN`, `ORDER BY`, `LIMIT`, `OFFSET`, marcar vulnerável.

3. Extrair parâmetros dinâmicos.
- Substituir cada parte dinâmica por `?` mantendo a ordem original.
- Gerar lista de parâmetros para chamada ao driver.

4. Reescrever execução.
- Converter para padrão `db_driver.execute(sql, param1, param2, ...)`.
- Preservar semântica original da função e tratamento de erro existente.

5. Inserir validações mínimas.
- Se possível sem alterar comportamento, validar tipos básicos antes da execução.
- Não alterar regra de negócio além do necessário para segurança.

6. Produzir log de alteração.
- Para cada query, registrar: linha aproximada, padrão inseguro detectado e refatoração aplicada.

## Regras de decisão
- Se houver concatenação com input dinâmico dentro de SQL: refatorar obrigatoriamente.
- Se query já estiver parametrizada: manter e registrar como "sem alteração".
- Se não for possível inferir ordem de parâmetros sem risco de quebrar lógica: não aplicar transformação cega e registrar bloqueio com motivo.
- Nunca concatenar valores em SQL no código de saída.

## Critérios de qualidade e conclusão
- Toda query vulnerável encontrada deve estar refatorada ou explicitamente bloqueada com justificativa.
- Código final deve compilar semanticamente no mesmo estilo do snippet.
- Log deve ser objetivo, rastreável e curto.

## Formato de saída obrigatório
1. Bloco `refactored_code` com o código Lua resultante.
2. Bloco `change_log` em JSON array.

Exemplo:
```json
{
  "change_log": [
    {
      "location": "função get_user, linha ~12",
      "issue": "Concatenação de SQL com user_id",
      "action": "Substituído por placeholder ? e parâmetro posicional"
    }
  ]
}
```

## Restrições
- Não introduzir dependências externas.
- Não reescrever arquitetura de acesso a dados inteira.
- Não modificar naming, estilo ou estrutura fora do necessário para eliminar concatenação SQL insegura.
