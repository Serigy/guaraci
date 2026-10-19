# Product Requirements Document: CRUD Scaffolding e API Explorer

**Produto:** Guaraci Framework  
**Fase:** BMAD 02 - Product Requirements  
**Data:** 2026-10-19  
**Status:** Pronto para arquitetura

## 1. Product Objectives & Success Metrics

O produto deve reduzir o tempo entre a decisão de criar um recurso e uma API testável, sem aumentar a superfície de risco do framework:

1. Um desenvolvedor consegue gerar um recurso CRUD, montar as rotas seguindo o snippet impresso e executar o spec gerado em um comando de shell, em menos de 30 segundos em um projeto local já instalado.
2. O comando gera exatamente os três artefatos contratados e o `guaraci test` descobre o spec na raiz de `spec/` sem configuração adicional.
3. Em `guaraci dev`, uma pessoa consegue abrir o explorer, localizar 100% das rotas registradas, preencher parâmetros/payload e ver status, headers e corpo da resposta sem usar ferramenta externa.
4. O explorer permanece inacessível por padrão quando o ambiente é produção; uma suíte de teste deve comprovar que não há resposta 2xx nesse modo sem a opção explícita de override.
5. A implementação mantém `lua5.4 tests/run_all.lua` verde, `luacheck` em zero warnings e não adiciona dependências de runtime ao core.
6. A interface entregue (HTML, CSS e JavaScript) totaliza menos de 50 KiB, não referencia origem externa e funciona com `Content-Security-Policy: default-src 'self'`.

## 2. Decisões de Produto para as Questões em Aberto

### 2.1 Rota padrão do explorer

**Decisão:** `GET /__guaraci/explorer` é a rota padrão da página. O caminho pode ser alterado pela opção programática `path`, mas não há alias público implícito.

**Racional:** o namespace reservado reduz colisões com rotas da aplicação e sinaliza que a ferramenta é de desenvolvimento. A configuração permite staging ou convenções locais sem obrigar o framework a ocupar `/explorer` ou `/api-docs`.

### 2.2 Contrato de metadados

**Decisão:** `GET /__guaraci/api-docs` publica um documento **OpenAPI 3.0 simplificado**, com `openapi`, `info`, `paths`, operações, parâmetros, `requestBody` e respostas. O documento é o contrato público da introspecção; o explorer o consome sem formato proprietário adicional.

**Racional:** um contrato conhecido permite salvar o JSON e usar Postman, Insomnia ou Swagger Editor, sem impedir uma UI própria leve. “Simplificado” significa que só os campos inferíveis pelo router e pelos schemas registrados são obrigatórios; extensões não inferíveis não devem ser inventadas.

### 2.3 Multi-tenancy no gerador

**Decisão:** multi-tenancy é o padrão e o gerador oferece `--no-tenant` para recursos globais. Sem a flag, modelo, rotas e spec gerados exigem o contexto de tenant conforme o contrato atual; com a flag, o artefato explicita que o recurso não requer tenant.

**Racional:** o padrão preserva o isolamento seguro do Dataware. A exceção é explícita, reproduzível em CI e adequada a recursos públicos, sem transformar uma decisão de segurança em comportamento implícito.

## 3. Escopo e Não-Objetivos

Inclui o gerador de endpoint REST, a descoberta de rotas, o documento OpenAPI 3.0 simplificado e uma UI vanilla para inspeção e requisições no mesmo servidor. Não inclui reescrita do algoritmo de matching do `router_v2`, Swagger UI ou outro bundle de terceiros, OAuth/SSO/RBAC, edição automática de `app.lua`, dependências npm/LuaRocks ou mudança no comportamento de rotas de negócio.

## 4. Requisitos Funcionais (FR)

### FR01 - Comandos e parsing

1. A CLI deve aceitar `guaraci generate endpoint <name> [options]`.
2. Deve aceitar `guaraci scaffold <name> [options]` como alias equivalente, produzindo os mesmos bytes de arquivo e a mesma semântica.
3. As opções são `--fields <lista>`, `--no-tenant` e `--force`; devem funcionar também na forma `--fields=<lista>`.
4. `<name>` é obrigatório, único e limitado a um identificador de recurso seguro: inicia com letra, dígito ou `_`, contém somente letras, dígitos, `_` ou `-`, e não contém `/`, `\`, `..` ou whitespace. O nome é normalizado para o nome de arquivo/rota conforme a convenção existente; entradas inválidas não podem tocar no filesystem.
5. Comando ausente, subcomando desconhecido, opção desconhecida, valor faltante, nome ausente ou argumentos posicionais extras são erros de uso.
6. Erro de uso retorna **2** e escreve uma mensagem objetiva e a forma correta de uso em stderr. Sucesso retorna **0**. Falha de geração, colisão ou falha de escrita retorna **1**.

### FR02 - Vocabulário de campos e validação

1. `--fields` usa a gramática `campo:tipo[:regra],campo:tipo[:regra]...`; cada campo tem nome seguro, tipo obrigatório e no máximo uma regra por entrada na primeira versão.
2. Tipos suportados são exatamente `string`, `number`, `integer`, `boolean` e `table`, correspondentes aos tipos aceitos pelo `validator`. A saída deve preservar o tipo declarado no schema; `table` deve ser documentado como objeto no contrato OpenAPI.
3. A regra suportada na sintaxe desta versão é exatamente `required`. Ausência da regra significa campo opcional. `min`, `max`, `email`, `pattern` e `enum` permanecem disponíveis somente se uma futura versão ampliar formalmente a gramática da CLI. Campo repetido, segmento vazio, tipo ausente, regra desconhecida ou sintaxe malformada são erros de uso (exit 2) antes de qualquer arquivo ser criado.
4. Um tipo desconhecido nunca deve ser convertido silenciosamente em `string`, omitido ou aceito pelo template; deve produzir erro identificável em stderr e exit 2.
5. Sem `--fields`, o comando deve seguir uma política determinística documentada pelo gerador: gerar schema sem campos de negócio (somente a chave primária e metadados padrão), ou rejeitar a invocação com exit 2. A implementação deve escolher uma única política e testá-la; não pode solicitar input interativo.
6. O schema gerado deve representar os campos e regras para o modelo, a validação das entradas mutáveis e a documentação OpenAPI correspondente.

### FR03 - Artefatos e integração explícita

1. Uma execução válida gera exatamente:
   - `models/<name>.lua`;
   - `routes/<name>.lua`;
   - `spec/<name>_spec.lua`.
2. O spec deve ser imediatamente descoberto pela busca `spec/*_spec.lua` do `guaraci test` e cobrir, no mínimo, sucesso de listagem (200), criação (201), entrada inválida (400), recurso ausente (404) e isolamento de tenant quando aplicável.
3. As rotas devem expor as operações CRUD compatíveis com `auto_crud.generate(model, router, opts)` e seguir os contratos JSON e de erro já existentes, sem exigir que a CLI replique uma implementação de banco.
4. O gerador não pode criar, editar, inserir ou reformatar `app.lua` nem qualquer arquivo não listado. Depois da criação, stdout deve imprimir o snippet exato de montagem modular, incluindo os `require` necessários e a chamada para montar `routes.<name>` no router da aplicação.
5. A saída deve listar cada arquivo criado e terminar com instruções para executar o snippet e `guaraci test`. Não deve imprimir stack trace em caso de erro.

### FR04 - Colisões e `--force`

1. Antes de escrever, a CLI deve verificar os três destinos. Se qualquer um existir e `--force` não estiver presente, não deve escrever nenhum arquivo, deve reportar os caminhos conflitantes e retornar 1.
2. Com `--force`, os três destinos podem ser substituídos somente após a validação completa dos argumentos. A operação deve ser determinística e deixar os três arquivos no mesmo resultado lógico; falha de escrita deve retornar 1 e ser explicitamente reportada.
3. Diretórios `models/`, `routes/` e `spec/` devem ser criados quando ausentes; falha de permissão ou de criação retorna 1.
4. `--force` não autoriza path traversal nem altera arquivos fora desses três caminhos.

### FR05 - Tenant flag

1. Sem `--no-tenant`, o artefato do modelo e o módulo de rotas devem manter `require_tenant = true`/opção equivalente e as operações devem rejeitar contexto ausente conforme o contrato do `auto_crud` (403 `tenant_required`).
2. Com `--no-tenant`, o recurso deve ser explicitamente configurado como global e o spec deve verificar que uma requisição sem tenant não é rejeitada somente por esse motivo.
3. A flag não pode alterar a validação de campos, autorizar acesso a outro recurso ou ser inferida do nome do endpoint. O terminal deve mostrar qual modo foi gerado.

### FR06 - Descoberta de rotas

1. O produto deve expor uma leitura aditiva das rotas registradas em `router_v2`: método, padrão, nome, parâmetros `:param` e, quando disponível, vínculo inferido com schema/modelo.
2. A descoberta deve refletir todas as rotas registradas, inclusive rotas avulsas; não deve executar handlers para construir o catálogo.
3. A ordem do documento deve ser determinística (método e caminho/registro em ordem estável), para que snapshots e diffs sejam reproduzíveis.
4. Rotas sem modelo devem exibir os parâmetros de caminho extraídos do padrão e um corpo JSON genérico quando a operação aceitar corpo; não podem receber campos inventados.

### FR07 - Documento OpenAPI

1. `GET /__guaraci/api-docs` deve retornar 200, `Content-Type: application/json; charset=utf-8` e um documento válido com `openapi: "3.0.x"`, `info` e `paths`.
2. Cada operação deve informar método, path, parâmetros de path, parâmetros de query quando conhecidos, `requestBody` para operações mutáveis aplicáveis e respostas observáveis (incluindo pelo menos 200/201/400/403/404 quando pertinentes).
3. Campos do schema Dataware/validator devem mapear para tipos OpenAPI (`string`, `number`, `integer`, `boolean`) e `required` deve ser preservado. O documento não pode expor closures, código Lua, credenciais ou valores de tenant.
4. O endpoint deve retornar o catálogo atual do processo/request e não um arquivo stale. Falha de serialização ou introspecção retorna erro HTTP não-2xx e registra erro; não retorna JSON de sucesso parcial.

### FR08 - Ativação e produção

1. `guaraci dev` deve ativar o explorer por padrão, sem exigir uma flag adicional.
2. O módulo programático deve permitir ativação/configuração explícita (incluindo `path` e ambiente) para staging e testes.
3. Se `GUARACI_ENV=prod`, `env == "prod"` ou equivalente de configuração indicar produção, explorer e metadata devem ser **fail-closed**: não respondem 2xx e não expõem catálogo ou UI.
4. Em produção, o bloqueio só pode ser removido com a opção explícita `force_production = true` na configuração do módulo; essa opção deve ser visível na documentação e não pode ser ativada por query string, cookie ou header do cliente.
5. O estado desabilitado não deve registrar as rotas internas nem acrescentar trabalho a cada requisição de negócio. A resposta de bloqueio deve seguir o código escolhido pela implementação (404 ou 403), ser consistente e ser testada.

### FR09 - Página e assets do explorer

1. `GET /__guaraci/explorer` (ou o `path` configurado) deve retornar HTML semântico com `Content-Type: text/html; charset=utf-8`.
2. A página deve carregar somente assets same-origin: `app.js` com `application/javascript` e `style.css` com `text/css`, ou mecanismo equivalente que mantenha a mesma política.
3. A UI deve listar todas as operações agrupadas ou filtráveis por método HTTP e caminho, mostrando nome quando disponível.
4. Cada operação deve renderizar parâmetros de caminho como campos obrigatórios, parâmetros de query como campos separados e request body como editor/formulário coerente com o schema. Campos `required`, tipo e exemplo devem ser distinguíveis.
5. Respostas da API de documentação, inclusive erro de contrato, devem ser apresentadas ao usuário de modo legível; uma falha de carregamento não pode parecer uma lista vazia válida.

### FR10 - Requisições de teste e resposta

1. O usuário deve conseguir enviar GET, POST, PUT, PATCH e DELETE para a operação selecionada, substituindo parâmetros de caminho e query com valores fornecidos e serializando body JSON quando aplicável.
2. O cliente deve preservar same-origin e não enviar requisições para uma origem derivada de input sem validação.
3. Após cada tentativa, a UI deve mostrar status HTTP, todos os headers de resposta disponíveis e o corpo formatado como JSON quando válido, ou texto sem alteração quando não for JSON.
4. Erros de rede, JSON inválido e respostas não-2xx devem ser visíveis e não podem ser convertidos em “sucesso vazio”.
5. A UI deve impedir o envio de payload malformado e indicar o campo que precisa de correção, mas não deve esconder o status retornado pelo servidor.

### FR11 - CSRF e auditoria

1. Ao servir a página do explorer, o servidor deve disponibilizar o cookie `guaraci_csrf_token` com valor aleatório seguro, `Path=/` e `SameSite=Lax`, respeitando o mecanismo de geração aprovado pelo framework.
2. Para cada requisição mutável emitida pela UI, o cliente deve enviar `X-CSRF-Token` com exatamente o mesmo valor do cookie e comprimento mínimo aceito pelo middleware. GET/HEAD não precisam desse header.
3. Se o cookie/header estiver ausente ou inválido, o servidor deve continuar respondendo conforme `middleware_csrf` (403 e código `csrf_token_invalid`); a UI deve mostrar essa resposta, não tentar desabilitar o middleware.
4. Toda mutação disparada pelo explorer deve passar pela mesma cadeia de middleware da aplicação. Quando `guaraci_audit` estiver disponível, a ação, método, caminho e resultado devem ser registrados sem token ou segredo em claro.

## 5. Requisitos Não Funcionais (NFR)

### NFR01 - Dependências e compatibilidade

O core, gerador e explorer devem funcionar com Lua 5.3/5.4 e bibliotecas padrão, sem novas dependências de runtime. SQLite e LuaSocket continuam opcionais conforme o estado atual. Nenhum pacote npm, CDN, fonte externa ou bundle de terceiros pode ser necessário.

### NFR02 - Segurança web e conteúdo

Todos os assets devem funcionar com `Content-Security-Policy: default-src 'self'`: sem origem externa, sem `onclick`/handlers inline e sem script inline não justificado por hash/nonce aprovado. Dados de rotas e schemas devem ser escapados ao renderizar a UI; input de usuário não pode virar HTML executável. O explorer não pode revelar segredos, stack traces ou credenciais.

### NFR03 - Desempenho e isolamento

O pacote total HTML+CSS+JS deve ser menor que 50 KiB (medido por `wc -c` nos assets entregues). Com explorer desabilitado, o caminho de dispatch de uma requisição de negócio não deve executar introspecção nem carregar os assets. O explorer deve tolerar recarga de estado do `guaraci dev` sem acumular rotas duplicadas.

### NFR04 - Qualidade do código gerado

Os três arquivos gerados devem passar por `luacheck` com **0 warnings**, carregar sem erro no interpretador suportado e obedecer às regras de prepared statements, escaping e isolamento de tenant. A execução de `lua5.4 tests/run_all.lua` deve permanecer verde.

### NFR05 - Observabilidade e falhas

Input inválido, colisões, falhas de filesystem, falhas de serialização, bloqueios de produção e falhas de CSRF devem ser reportados com mensagens acionáveis. Erros internos devem ser auditados pelos mecanismos existentes quando aplicável e nunca expor stack trace ao navegador.

### NFR06 - Determinismo e acessibilidade

Mesmas entradas, versão e diretório devem produzir os mesmos arquivos e metadata ordenados. A UI deve ser navegável por teclado, usar labels associados aos controles e manter contraste legível sem depender de imagens, fontes ou JavaScript inline.

## 6. Epic Roadmap

### Epic 1 - CLI scaffolding de recursos CRUD

**Objetivo:** entregar o comando determinístico que gera modelo, rotas e spec, sem tocar em `app.lua`.  
**Cobre:** FR01, FR02, FR03, FR04 e FR05; NFR01, NFR04, NFR05 e NFR06.

### Epic 2 - Descoberta de rotas e documento OpenAPI

**Objetivo:** tornar o catálogo do router e dos schemas consumível por ferramentas e pela UI, com contrato estável e fail-closed.  
**Cobre:** FR06, FR07 e FR08; NFR01, NFR03, NFR05 e NFR06.

### Epic 3 - Interface web do API explorer

**Objetivo:** permitir inspeção visual e requisições de teste same-origin com apresentação clara da resposta e proteção CSRF.  
**Cobre:** FR09, FR10 e FR11; NFR02, NFR03, NFR05 e NFR06.

### Epic 4 - Documentação, validação e release

**Objetivo:** documentar comandos, contrato OpenAPI, ativação/override de produção, tenancy e limites de segurança; consolidar testes, lint e pacote leve para release.  
**Cobre:** todos os FRs e NFRs, com ênfase em FR03, FR08, FR11, NFR02, NFR04 e NFR06.

## 7. Global Definition of Done

Uma entrega só está pronta quando:

1. `planning/prd.md` e a documentação de uso do comando, rota padrão, `--no-tenant`, `--force`, `GUARACI_ENV` e `force_production` estão atualizadas sem alterar o submódulo `docs/` durante esta fase.
2. Testes automatizados cobrem parsing e códigos 0/1/2, nomes inválidos, tipo/regra desconhecidos, ausência de campos conforme política escolhida, colisões com e sem `--force`, os três arquivos, snippet de montagem e descoberta por `guaraci test`.
3. Testes cobrem tenancy default e `--no-tenant`, contratos CRUD e respostas 200/201/400/403/404; nenhum teste depende de rede externa.
4. Testes cobrem rotas estáticas e parametrizadas, ordem determinística, schema OpenAPI 3.0 simplificado, rota customizada, ambiente de produção fail-closed e override explícito.
5. Testes de navegador/HTTP verificam renderização de método, path/query/body, status, headers e JSON/texto formatado; verificam cookie e header CSRF em toda mutação e o tratamento de 403.
6. A política CSP é testada por inspeção dos headers e dos assets: zero origens externas, zero inline script sem justificativa e tamanho total abaixo de 50 KiB.
7. `luacheck` termina com zero warnings nos arquivos alterados e gerados.
8. `lua5.4 tests/run_all.lua` termina com sucesso; quando disponível, `lua5.3 tests/run_all.lua` também termina com sucesso.
9. Uma verificação de regressão demonstra que o explorer desabilitado não altera o dispatch nem duplica rotas após recargas do dev server.
10. Uma revisão de segurança confirma ausência de path traversal, XSS/SSTI, SQL injection, vazamento de segredo e auditoria de mutações via `guaraci_audit` quando aplicável.

## 8. Handoff para o Architect

Este PRD define comportamento, contratos, limites e critérios verificáveis. Ficam deliberadamente para a arquitetura: quais módulos e arquivos implementarão a introspecção e o explorer; como registrar middleware e rotas sem alterar o algoritmo de matching; como representar e serializar OpenAPI; como embutir/servir os assets; como gerar templates de modelo/rotas/spec; estratégia de compatibilidade Lua 5.3/5.4; e ADRs de segurança, cache, ordenação e auditoria.
