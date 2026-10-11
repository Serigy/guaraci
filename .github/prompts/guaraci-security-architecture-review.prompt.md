---
name: "Guaraci Security Architecture Review"
description: "Revisa proposta arquitetural de módulo do Guaraci sob ISO 27001, simplicidade e agnosticismo req/res, com decisão APROVADO ou BLOQUEADO."
argument-hint: "Informe nome do módulo e proposta inicial de implementação."
agent: "Guaraci Security Architect"
---

@Guaraci Security Architect

**Objetivo:** Projetar a arquitetura para o módulo de {{nome_do_modulo}}.

**Proposta Inicial:**
{{proposta_inicial}}

Faça uma revisão arquitetural desta proposta considerando o manifesto do Guaraci:
1. Avalie riscos de segurança (ISO 27001), especialmente manipulação de estado, vazamento de dados e necessidades de log.
2. Identifique riscos de complexidade desnecessária (over-engineering).
3. Se a proposta for aprovada, sugira a assinatura das funções principais respeitando o agnosticismo do framework (req/res).
4. Se a proposta for bloqueada, sugira a alternativa minimalista segura.

Formato obrigatório da resposta:
1. Veredito: APROVADO ou BLOQUEADO (1 linha)
2. Riscos críticos (ordem de severidade)
3. Aderência ISO 27001 (controles e lacunas)
4. Assinaturas propostas (se aprovado) ou alternativa minimalista (se bloqueado)
5. Checklist objetivo de implementação segura
