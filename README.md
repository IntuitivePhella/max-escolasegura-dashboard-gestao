# Max Escola Segura — Dashboard de Gestão (SECRETARIO/DIRETORIA)

Next.js + Supabase + Igniter.js

Este projeto implementa o dashboard de gestão do Max Escola Segura, com arquitetura multi-tenant. O acesso é restrito aos papéis:
- SECRETARIO: acesso multi-escolas (multi-select)
- DIRETORIA: acesso por escola (uma escola)

Dados são obtidos do Postgres (Supabase) e exibidos em tempo real (subscribe + refetch). A API é construída com Igniter.js, validada com Zod e protegida por RBAC baseado em `public.user_tenant_mapping`.

## Stack
- Next.js (App Router) + TypeScript
- Supabase (Auth, Postgres, Realtime)
- Igniter.js (router/clients) + Zod (validação)
- shadcn/ui (UI) + wrapper de charts em `src/components/ui/chart.tsx`

## Requisitos
- Node 18+
- Conta e projeto Supabase (URL + ANON KEY)

## Configuração
1. Variáveis de ambiente (crie `.env.local`):
```env
NEXT_PUBLIC_SUPABASE_URL=... 
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
```

2. Instalação e dev:
```bash
npm install
npm run dev
```
Acesse http://localhost:3000

## Autenticação e RBAC
- Login via Supabase Auth (middleware SSR mantém sessão)
- Fonte de autorização: `public.user_tenant_mapping`
  - Colunas: `user_id (uuid) | schema_name (text) | role ('SECRETARIO'|'DIRETORIA') | status`
- Regras de acesso:
  - Apenas SECRETARIO/DIRETORIA acessam o dashboard
  - Endpoints filtram automaticamente pelos `schema_name` autorizados

Provisionamento mínimo:
```sql
-- Garantir integridade de papéis e 1 diretoria por escola
alter table public.user_tenant_mapping
  add constraint user_tenant_mapping_role_chk check (role in ('DIRETORIA','SECRETARIO'));
create unique index if not exists ux_directoria_unica_por_schema
  on public.user_tenant_mapping(schema_name) where role = 'DIRETORIA';

-- RLS de leitura (se aplicável)
alter table public.user_tenant_mapping enable row level security;
create policy if not exists user_tenant_mapping_select_self
  on public.user_tenant_mapping for select using (user_id = auth.uid());
```

## API (Igniter.js)
Rota base: `/api/v1`

Endpoints atuais (MVP):
- `GET /dashboard/schemas` → `{ userId, roles, schemas[] }` para o usuário logado
- `GET /dashboard/events` → métricas operacionais por escola (fonte: `public.eventos_acesso_dashboard`)
- `GET /dashboard/alerts` → alertas/saúde por escola (fonte: `public.v_health_alerts_monitor`)
- `GET /dashboard/summary` → consolidado; fallback quando `public.dashboard_consolidado` estiver vazio

Todos os endpoints filtram por `schema_name` autorizado via SSR.

## Realtime (visão)
- Recomendação (em andamento):
  - Tabela `public.dashboard_feed(...)`
  - Triggers nos objetos-fonte (por escola) para publicar eventos no feed
  - Cliente assina Supabase Realtime no `public.dashboard_feed` e faz refetch dos endpoints ao receber eventos

## UI (MVP)
- Página inicial com KPIs:
  - Total de eventos, Pendentes, Alertas, Saúde
  - Lista de escolas autorizadas
- Próximos passos:
  - Selector de escolas (multi-select para SECRETARIO; oculto para DIRETORIA)
  - Gráficos (séries e barras) com `components/ui/chart.tsx`

## Estrutura do projeto
```
src/
  app/
    api/v1/[[...all]]/route.ts   # Adapter do Igniter.js
    login/                       # Página de login Supabase
    auth/callback/               # Callback auth
    page.tsx                     # Dashboard (KPIs)
  components/ui/                 # shadcn/ui + chart wrapper
  features/
    dashboard/
      controllers/dashboard.controller.ts  # Endpoints
  igniter.ts | igniter.router.ts | igniter.client.ts
```

## Scripts
- `npm run dev` — desenvolvimento
- `npm run build` — build produção
- `npm run start` — servidor produção
- `npm run lint` — lint

## Roadmap curto
- RBAC completo no middleware (bloquear não SECRETARIO/DIRETORIA)
- Selector de escolas e gráficos
- Realtime feed + triggers
- Views vs RPC por indicador (após receber especificações)

## Plano de Ação de Desenvolvimento
Consulte o plano detalhado de implementação em:
- `implementation-docs/action-plan.md`