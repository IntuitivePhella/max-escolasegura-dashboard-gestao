# Plano de Ação: Dashboard Max Escola Segura

## 1. Visão Geral

Este documento acompanha a execução do "Dashboard Max Escola Segura". Objetivo: entregar um dashboard multi-tenant, seguro e performático, com acesso restrito a SECRETARIO (multi-escolas) e DIRETORIA (1 escola).

---

## 2. Decisões e Diretrizes Atualizadas

- **Acesso (RBAC)**:
  - Somente `SECRETARIO` (multi-escolas) e `DIRETORIA` (por escola) podem acessar o dashboard.
  - `RESPONSAVEL` (e demais) não devem acessar o sistema de gestão.
  - Fonte de autorização: `public.user_tenant_mapping` (colunas: `user_id`, `schema_name`, `role`, `status`).
  - Enforcement: endpoints já filtram por `schema_name` permitido; middleware/UX ainda serão ajustados para bloquear papéis não permitidos.

- **Aquisição de dados**:
  - MVP prioriza as views públicas existentes quando possível (`eventos_acesso_dashboard`, `v_health_alerts_monitor`).
  - `dashboard_consolidado` está vazia no momento → criamos fallback automático no endpoint `/dashboard/summary` usando `eventos_acesso_dashboard` para preencher métricas básicas.
  - Próximo passo: O usuário listará os indicadores desejados e definiremos, para cada um, View vs RPC (e eventuais índices/materialized views) visando precisão e performance.

- **Gráficos**:
  - Usaremos os componentes de chart que já existem em `src/components/ui/chart.tsx` (wrapper estilizado do shadcn/ui sobre Recharts), garantindo consistência visual e boa performance.

- **Realtime**:
  - O dashboard deve atualizar em tempo real (telas públicas na diretoria/secretaria).
  - Estratégia: feed de eventos no `public` + triggers por escola nos objetos-fonte para publicar mudanças; cliente assina Supabase Realtime e refaz fetch dos endpoints.

- **Provisionamento DIRETORIA (novo)**:
  - Criação automática a partir de `public.instituicoes` (Email_Diretoria = login; senha = últimos 5 dígitos numéricos de Telefone_Diretoria).
  - Inserção não será em `public.user_tenant_mapping`; o usuário DIRETORIA será criado em `{schema_name}.usuarios` determinado via `public.schema_registry (instituicao_id → schema_name)`.
  - Arquitetura recomendada: "Outbox + Edge Function (service role)": Trigger AFTER INSERT em `public.instituicoes` → insere payload em `public.provisioning_queue`; Edge Function (service role) consome a fila, chama `auth.admin.createUser`, e faz `INSERT` em `{schema}.usuarios`. Opcional: espelho mínimo em `public.user_tenant_mapping` apenas para RBAC de dashboard.
  - Justificativa: criação em Auth requer service role/HTTP; manter no plano de dados (fila) isola privilégios e aumenta a auditabilidade.

---

## 3. Status por Fase

### Fase 1: Preparação e Limpeza (Setup & Cleanup) ✅ Concluída

- [x] Remover a página de exemplo (`src/app/page.tsx`) e substituir por base do dashboard
- [x] Remover a feature de exemplo (`src/features/example`)
- [x] Limpar roteador do Igniter (`src/igniter.router.ts`)

### Fase 2: Fundação de Segurança e Dados ✅ Concluída (MVP)

- [x] Autenticação Supabase (SSR + cookies, middleware)
- [x] Proteção de rotas: login obrigatório
- [x] Validação inicial de performance das views (90–350 ms em médias atuais)
- [x] Definição de RBAC e fonte (`public.user_tenant_mapping`) – aplicado no backend (endpoints)
- [ ] Middleware RBAC para bloquear papéis não permitidos (pendente – ver Próximos Passos)

### Fase 3: Construção da API de Dados ✅ Em operação (MVP)

- [x] Controller `dashboard.controller.ts`
  - [x] `GET /dashboard/schemas` → `{ userId, roles, schemas[] }` a partir de `user_tenant_mapping`
  - [x] `GET /dashboard/events` → dados operacionais por escola a partir de `eventos_acesso_dashboard`
  - [x] `GET /dashboard/alerts` → dados de saúde/alertas via `v_health_alerts_monitor`
  - [x] `GET /dashboard/summary` → tenta `dashboard_consolidado`; fallback para `eventos_acesso_dashboard`
- [x] Filtragem por schemas autorizados (SSR) em todos os endpoints
- [x] Respostas validadas com Zod
- [ ] Cache leve (60s) nos endpoints (`events/alerts/summary`) para reduzir carga (pendente)
- [ ] Bloqueio por `role` no nível dos endpoints (403 se não SECRETARIO/DIRETORIA) – parte do RBAC de middleware/handler (pendente)
- [ ] Realtime (backend):
  - [ ] Tabela `public.dashboard_feed(id bigserial pk, schema_name text, kind text, at timestamptz default now(), meta jsonb)`
  - [ ] RPC `public.rpc_register_dashboard_triggers(schema_name text)` para instalar triggers em cada escola
  - [ ] Triggers nos objetos-fonte (eventos/alertas) dos schemas de escola para inserir em `dashboard_feed`
  - [ ] Publicação Realtime: incluir `public.dashboard_feed` em `supabase_realtime`
  - [ ] RLS/Grants do feed (somente leitura pública; filtro por `schema_name` via aplicação)

### Fase 4: Desenvolvimento do Frontend e UX ✅ Parcial

- [x] Homepage com KPIs (Total, Pendentes, Alertas, Saúde) + escolas autorizadas
- [ ] Selector de escolas (multi-select para `SECRETARIO`; oculto para `DIRETORIA`) (pendente)
- [ ] Gráfico(s) inicial(is) (ex.: série temporal de eventos por dia) (pendente)
- [ ] Estados refinados (empty/error/loading) e UX final (pendente)
- [ ] Realtime (frontend): assinatura do canal e refetch automático dos endpoints ao receber eventos do feed

---

## 4. Próximos Passos (Backlog Priorizado)

1) Planejamento de Indicadores (Alto)
- Usuário definirá a lista dos indicadores/visões. Para cada item, entregaremos:
  - Origem dos dados (esquema/rota de busca) e forma (View vs RPC)
  - Colunas/assunções, parâmetros (schemas, período), RLS, índices/materialized se necessário
  - SLA de latência esperado e estratégia de cache

2) Realtime end-to-end (Alto)
- Implementar `dashboard_feed`, RPC e triggers; habilitar publicação; cliente Realtime com refetch dos endpoints.

3) RBAC Completo (Alto)
- Middleware: negar acesso ao dashboard se `role` não for `SECRETARIO`/`DIRETORIA` (redirecionar para `/login`)
- API: reforçar `403 Forbidden` para papéis não permitidos (defesa em profundidade)
- UI: exibir mensagem “sem acesso” quando `schemas/roles` não contemplarem os perfis válidos

4) Selector de Escolas + Filtro (Alto)
- `SECRETARIO`: multi-select de `schemas` autorizados → atualizar chamadas para `events/alerts/summary`
- `DIRETORIA`: escola única, sem seletor

5) Estratégia Views vs RPC (Alto)
- Para cada indicador (da etapa 1), escolher:
  - View (quando métrica estável e barata) ou RPC parametrizada (período, múltiplas escolas)
  - Onde necessário, propor materialized view + refresh programado

6) Cache e Observabilidade (Médio)
- Cache leve (60s) nas rotas `events/alerts/summary`
- Logar `durationMs` e p95 por endpoint

7) Gráficos e Layout (Médio)
- Implementar gráficos com `components/ui/chart.tsx` (shadcn-style)
- Layouts responsivos e acessibilidade

8) Limpeza Técnica (Baixo)
- Remover dependências não utilizadas (ex.: Prisma no dashboard, se não for necessário)

---

## 5. Itens Entregues (Resumo)

- Autenticação Supabase (SSR) + middleware base
- Endpoints do dashboard com autorização por `schema_name` (SSR): `schemas`, `events`, `alerts`, `summary`
- Fallback de `summary` quando `dashboard_consolidado` estiver vazio
- Homepage com KPIs iniciais e lista de escolas autorizadas

---

## 6. Acordos e Aguardando Definição

- **Acesso**: somente `SECRETARIO` (multi) e `DIRETORIA` (1). RESPONSAVEL/Outros sem acesso – a ser reforçado no middleware/API.
- **Indicadores**: aguardando a lista detalhada do usuário (template abaixo) para projetar Views/RPC definitivas.
- **Gráficos**: usaremos `components/ui/chart.tsx` (padrão shadcn) com dados dos endpoints.
- **Realtime**: telas ficam abertas; push-imediato via feed + triggers; refetch automático na UI.

---

## 7. Anexos Técnicos

- Endpoints atuais:
  - `GET /api/v1/dashboard/schemas`
  - `GET /api/v1/dashboard/events?` (filtrado internamente pelos schemas autorizados)
  - `GET /api/v1/dashboard/alerts?` (idem)
  - `GET /api/v1/dashboard/summary?` (consolidado ou fallback)

- Fonte de autorização: `public.user_tenant_mapping` (RLS recomendada: `user_id = auth.uid()`).

---

## 8. Próxima Ação

- Usuário enviará os **indicadores prioritários** no template acordado; em seguida, mapearemos e projetaremos as **rotas de busca (View/RPC)** para cada um e implementaremos o **pipeline de realtime** (feed + triggers + subscribe) e o **selector de escolas**.

---

## 9. Template de Especificação de Indicadores (preencher pelo usuário)

Preencha um bloco por indicador. Quanto mais completo, melhor a definição da rota (View/RPC) e do gráfico.

```yaml
indicador: "nome-curto-do-indicador"
descricao: "o que mede e por quê é útil"
nivel_grao: "por_escola | por_dia | por_hora | total | outro"
janela: "1h | 24h | 7d | mes_atual | periodo_livre"
agregacao: "contagem | soma | media | percentil | status"
filtros:
  escolas: "lista de schemas ou 'todas_autorizadas'"
  periodo:
    de: "YYYY-MM-DDTHH:MM:SSZ | relativo (ex.: -24h)"
    ate: "YYYY-MM-DDTHH:MM:SSZ | agora"
  outros: ["status=HEALTHY", "tipo=..."]
visualizacao: "card | linha | barras | pizza | tabela"
frequencia_latency: "tempo_real | 1min | 15min | diario"
origem_preferida: "view | rpc | materialized | indefinido"
colunas_esperadas: ["schema_name", "valor", "data", "..."]
regras_negocio: ["limiar WARNING=..., ERROR=...", "regras especiais"]
observacoes: "qualquer contexto adicional"
```

Exemplo rápido:

```yaml
indicador: "eventos_pendentes_24h"
descricao: "Total de eventos pendentes nas últimas 24h"
nivel_grao: "por_escola"
janela: "24h"
agregacao: "contagem"
filtros:
  escolas: "todas_autorizadas"
visualizacao: "card"
frequencia_latency: "tempo_real"
origem_preferida: "rpc"
colunas_esperadas: ["schema_name", "total_pendentes"]
regras_negocio: ["WARNING >= 10", "ERROR >= 50"]
observacoes: "usar mesma definição de 'pendente' das rotinas de processamento"
```

---

## 10. Provisionamento de Usuários (DIRETORIA/SECRETARIO)

- Objetivo: refletir novo requisito de criação automática do DIRETORIA a partir de `public.instituicoes` e discutir o processo do SECRETARIO.

### 10.1 DIRETORIA — Arquitetura e Fluxo

- Disparo: `AFTER INSERT` em `public.instituicoes`.
- Credenciais iniciais:
  - `login` = `Email_Diretoria` (obrigatório; validar formato)
  - `senha` = últimos 5 dígitos numéricos de `Telefone_Diretoria` (sanitizar; se < 5 dígitos, reprovar evento na fila com erro tratável)
- Determinação do schema: obter `schema_name` via `public.schema_registry` (`instituicao_id` = `public.instituicoes.id`).
- Escrita de usuário: inserir em `{schema_name}.usuarios` (papel/coluna correspondente a `DIRETORIA`, `status = 'ATIVO'`).
- Criação no Auth: `auth.admin.createUser({ email, password })` realizada fora do banco (service role).

#### Padrão recomendado: Outbox + Edge Function (service role)

1) DDL sugerido
```sql
create table if not exists public.provisioning_queue (
  id bigserial primary key,
  event text not null check (event in ('INSTITUICAO_CREATED')),
  instituicao_id bigint not null,
  email_diretoria text not null,
  telefone_diretoria text not null,
  created_at timestamptz default now(),
  status text not null default 'PENDING',
  error text
);

create or replace function public.enqueue_instituicao_created()
returns trigger language plpgsql as $$
begin
  insert into public.provisioning_queue (event, instituicao_id, email_diretoria, telefone_diretoria)
  values ('INSTITUICAO_CREATED', new.id, new."Email_Diretoria", new."Telefone_Diretoria");
  return new;
end;$$;

create trigger trg_instituicao_created
  after insert on public.instituicoes
  for each row execute function public.enqueue_instituicao_created();
```

2) Edge Function (service role)
- Passos:
  - Ler itens `PENDING` em `public.provisioning_queue`
  - Sanitizar `telefone_diretoria` (manter apenas dígitos) e extrair últimos 5
  - Criar usuário no Auth: `auth.admin.createUser({ email, password })`
  - Descobrir `schema_name` por `instituicao_id` em `public.schema_registry`
  - `INSERT` em `{schema}.usuarios` (papel DIRETORIA, status ATIVO, hash da senha se aplicável)
  - (Opcional para RBAC do dashboard) Inserir espelho mínimo em `public.user_tenant_mapping` com `role = 'DIRETORIA'`
  - Atualizar `status` na fila para `DONE` ou `ERROR` (guardar `error`)

3) Segurança
- Não logar senha; se armazenar no `{schema}.usuarios`, guardar `hash` (ex.: bcrypt) e nunca a senha em claro.
- Grants mínimos na fila para a Edge Function; RLS liberando somente leitura/escrita necessária.
- Justificativa de não usar apenas trigger SQL: criação em Auth exige service role/HTTP; lógica operacional isolada fora do banco melhora observabilidade e controle de falhas/retries.

4) Aceite
- Inserir linha em `public.instituicoes` cria o usuário DIRETORIA:
  - Usuário existe no Auth.
  - Registro criado em `{schema}.usuarios` com papel DIRETORIA.
  - (Se adotado) espelho mínimo em `public.user_tenant_mapping` para RBAC do dashboard.

### 10.2 SECRETARIO — Opções (Aberto)

- A) Manual: criação no Auth via Studio + vinculação multi-escolas (mapping em `public.user_tenant_mapping` ou estrutura equivalente) — simples para poucos usuários.
- B) Semelhante ao DIRETORIA: definir fonte e disparo (e.g., tabela de secretarias), outbox + Edge Function com parametrização de multi-escolas.

Perguntas a responder:
- Escopo de acesso (todas as escolas do município? subconjunto?)
- Origem dos dados (tabela/colunas que definem SECRETARIO)
- Workflow de criação e revogação (quem aprova? como alterar escolas?)

---

## 11. Indicadores DIRETORIA (Definições e Estratégia)

### 11.1 Presença atual vs total de alunos (radial — @radial-chart-shape)
- Definição: `presentes` = `pessoa_id` com `tipo_evento='Entrada'` e sem `tipo_evento='Saida'` na MESMA data em `{schema}.eventos_acesso`. `total` vem de `{schema}.pessoas` (tipo = ALUNO).
- Estratégia: RPC `rpc_dashboard_presenca(schemas text[], data date)` — computa por escola e retorna `{ schema_name, presentes, total, pct_presenca }`.
- Índices: `{schema}.eventos_acesso(tipo_evento, data_evento, pessoa_id)`; considerar partição por data.
- Realtime: trigger em `{schema}.eventos_acesso` (inserções de `Entrada`/`Saida`) → publicar no `dashboard_feed`.

### 11.2 Denúncias “bulling” e “infraestrutura” — TRATADA vs PENDENTE (barras empilhadas — @barchart-stacked+legend)
- Fonte: `{schema}.denuncias`.
- Janela: anual, série mês a mês.
- Estratégia: RPC `rpc_dashboard_denuncias(schemas text[], ano int, categorias text[])` ou materialized view mensal por categoria+status (escolha conforme volume esperado). Saída `{ mes, tratada, pendente, schema_name? }`.
- Realtime: trigger em `{schema}.denuncias` para o feed.

### 11.3 Socio-Emocional (radar — @radarchart-grid-circle)
- Fonte: `{schema}.dimensoes_sentimento (Nome)`, `{schema}.detalhes_sentimento (Dimensao_ID, Score)`.
- Cálculo: média(Score) por dimensão no período (diário/semanal/mensal/anual), máximo lógico 10.
- Estratégia: RPC `rpc_dashboard_sentimento(schemas text[], de timestamptz, ate timestamptz)` → `{ dimensao_nome, media_score }`.
- Realtime: trigger em `{schema}.detalhes_sentimento` (inserção/atualização).

### 11.4 Denúncias “tráfico”, “assedio”, “discriminacao”, “violencia” — TRATADA vs PENDENTE (barras empilhadas)
- Estratégia: reutilizar `rpc_dashboard_denuncias` com `categorias` parametrizadas.
- Observação: confirmar se este indicador é para SECRETARIO (multi-escolas) ou também DIRETORIA.

Referências de UI (shadcn/recharts): `https://ui.shadcn.com/charts`

---

## 12. Riscos / Ambiguidades e Decisões

- Telefone_Diretoria < 5 dígitos: decisão → reprovar evento na fila com `ERROR` e orientar correção.
- Mudança de fonte de RBAC: manter `public.user_tenant_mapping` como espelho mínimo para o dashboard vs endpoints consultarem `{schema}.usuarios` diretamente.
  - Prós (espelho): mantém API atual, simples de filtrar por `schema_name`; Contras: duplicidade de estado.
  - Prós (consultar `{schema}.usuarios`): fonte única por escola; Contras: mais complexidade multi-schema na API.
  - Recomendação: manter espelho mínimo no curto prazo (velocidade e menor refatoração); reavaliar depois.
- Volume de denúncias alto: optar por materialized view mensal com refresh agendado.
- Realtime: cuidado com tempestade de eventos; usar debounce/refetch seletivo por endpoint.

Decisões propostas:
- Adotar Outbox + Edge Function para DIRETORIA.
- Manter `user_tenant_mapping` como espelho mínimo temporário para RBAC do dashboard.
- Implementar RPCs parametrizadas para indicadores e apenas materializar onde necessário.

---

## 13. Notas de DX (Charts e Lint)

- Exemplos de charts (radial/bar/radar) devem permanecer como documentação (`.md/.mdx`) e não como arquivos `.ts/.tsx` soltos fora de `src/` para evitar erros de lint.
- Alternativamente, adicionar `apps/administrativo/diretoria/Dashboard/implementation-docs` ao `.eslintignore`.
- Componentes de produção usarão `src/components/ui/chart.tsx` (padrão shadcn/recharts).
