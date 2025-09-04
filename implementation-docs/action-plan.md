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

- **Objetivo**: criar usuários que ainda não existem no Auth e vinculá-los às escolas (schemas) com os papéis corretos.

- **Opções de provisionamento**:
  - A) Manual (rápido): criar usuário no Supabase Studio (Auth) → inserir linha em `public.user_tenant_mapping`.
  - B) Script Admin (recomendado): script Node/Edge (service role) usando `auth.admin.createUser` + INSERT em `user_tenant_mapping`.

- **DDL/Guardrails sugeridos** (executar no Supabase):

```sql
-- Normalizar papéis e integridade
alter table public.user_tenant_mapping
  add constraint user_tenant_mapping_role_chk
  check (role in ('DIRETORIA','SECRETARIO'));

-- Garantir 1 DIRETORIA por escola
create unique index if not exists ux_directoria_unica_por_schema
  on public.user_tenant_mapping(schema_name)
  where role = 'DIRETORIA';

-- RLS de leitura pelo próprio usuário (recomendado se não existir)
alter table public.user_tenant_mapping enable row level security;
create policy if not exists user_tenant_mapping_select_self
  on public.user_tenant_mapping for select
  using (user_id = auth.uid());
```

- **Inserção (exemplo)**:

```sql
insert into public.user_tenant_mapping (user_id, pessoa_id, instituicao_id, schema_name, role, status)
values ('<uuid_do_usuario>', null, null, 'escola_12345678', 'DIRETORIA', 'active');
```

- **Critérios de aceite**:
  - Login com usuário novo funciona.
  - `/dashboard/schemas` retorna `{ schemas, roles }` conforme mapeamento.
  - RBAC: somente DIRETORIA/SECRETARIO acessam dashboard; demais → 403/redirect.
