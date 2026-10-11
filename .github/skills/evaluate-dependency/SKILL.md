---
name: evaluate-dependency
description: 'Avalia pedidos de nova biblioteca externa no Guaraci com foco em minimalismo, segurança e auditabilidade; retorna veredito e alternativa com Lua Standard Library ou FFI básico quando aplicável.'
argument-hint: 'Informe nome do pacote, objetivo e justificativa técnica para adoção.'
user-invocable: true
---

# Evaluate Dependency

## O que esta skill produz
Retorna uma decisão objetiva para adoção de dependência externa:
- verdict: APROVADO ou BLOQUEADO
- rationale: justificativa curta e verificável
- minimal_alternative: alternativa com Lua Standard Library ou FFI básico (quando aplicável)
- adoption_conditions: condições mínimas para aprovação (quando houver)

## Quando usar
- Solicitação para adicionar pacote externo (ex.: Redis, JWT, ORM, logger, utilitários).
- Discussão de arquitetura com risco de over-engineering.
- Revisão de PR que inclui nova dependência no core do Guaraci.

## Entrada esperada
- String com nome da biblioteca e justificativa de uso.
- Opcional: escopo (core, plugin, ferramenta de build), risco, requisitos de performance e compliance.

## Procedimento
1. Classificar o escopo da dependência.
- Core do framework, módulo opcional, ou tooling fora do runtime.

2. Verificar necessidade real.
- Confirmar se o problema é recorrente e crítico.
- Verificar se a justificativa cita limitação concreta da base atual.

3. Avaliar alternativa mínima.
- Tentar resolver com Lua Standard Library.
- Quando for integração de baixo nível e inevitável, considerar FFI básico com superfície mínima.
- Se alternativa mínima existir com custo aceitável, priorizar BLOQUEADO para dependência externa.

4. Avaliar risco de segurança e manutenção.
- Exposição de supply chain, CVEs, complexidade de atualização, licenciamento e lock-in.
- Impacto em auditabilidade e previsibilidade do fluxo.

5. Decidir veredito.
- APROVADO apenas se houver ganho claro, sem alternativa mínima viável e com mitigação definida.
- BLOQUEADO quando houver solução simples com biblioteca padrão/FFI básico ou quando risco superar benefício.

6. Emitir recomendação acionável.
- Informar caminho mínimo de implementação.
- Se aprovado, listar condições de adoção obrigatórias.

## Regras de decisão
- Dependência para resolver problema já coberto por Lua padrão: BLOQUEADO.
- Dependência no core sem justificativa técnica forte: BLOQUEADO.
- Dependência com histórico de vulnerabilidades sem plano de atualização: BLOQUEADO.
- Dependência inevitável para requisito não atendível por Lua padrão/FFI básico: APROVADO com condições.

## Critérios de qualidade e conclusão
- O veredito deve citar pelo menos 2 critérios objetivos.
- A alternativa mínima deve ser concreta (não genérica).
- Quando não houver alternativa viável, declarar explicitamente "não aplicável" em minimal_alternative.
- A resposta deve ser curta, auditável e focada no contexto do Guaraci.

## Formato de saída obrigatório
```json
{
  "verdict": "BLOQUEADO",
  "rationale": [
    "A funcionalidade pode ser implementada com Lua Standard Library sem dependência externa.",
    "A inclusão no core aumenta superfície de ataque e custo de manutenção sem ganho proporcional."
  ],
  "minimal_alternative": "Implementar assinatura e validação com primitives de string/table e encapsular integração externa atrás de interface opcional; usar FFI básico apenas no adaptador, se necessário.",
  "adoption_conditions": []
}
```

## Restrições
- Não aprovar dependência por conveniência isolada.
- Não recomendar arquitetura complexa para justificar pacote.
- Não ampliar escopo para benchmark extenso; foco na decisão minimalista e segura.
