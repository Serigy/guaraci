---
name: "Guaraci Generate Hook"
description: "Gera hook Lua do Guaraci com assinatura req/res, short-circuit explícito, log de segurança e retorno booleano de continuidade."
argument-hint: "Informe propósito do hook e estágio (before_request, before_render, after_request)."
agent: "Guaraci Principal Lua Developer"
---

@Guaraci Principal Lua Developer

**Tarefa:** Criar um Hook de {{proposito_do_hook}}.

**Estágio:** {{estagio_hook}}  
(Valores esperados: `before_request`, `before_render`, `after_request`)

Gere a função de hook seguindo o padrão do framework:
1. A função deve receber `(req, res)`.
2. Defina claramente a condição de short-circuit (quando o hook deve retornar `true` e abortar a requisição com erro 403/401).
3. Inclua geração de log inalterável (`guaraci_audit.log_security`) quando a condição de bloqueio for atingida.
4. Se o fluxo for válido, retorne `false` para dar continuidade.

Formato obrigatório da resposta:
1. Código Lua completo do hook.
2. Justificativa curta da lógica de bloqueio e continuidade.
3. Exemplo mínimo de integração no pipeline do estágio informado.

Regras adicionais:
- Não usar dependências externas.
- Manter implementação explícita e auditável (sem over-engineering).
- Em caso de bloqueio, setar `res.status` e `res.body` com mensagem controlada (sem stack trace).
