# 📊 Plano Completo de Adequação - Dashboard Max Escola Segura

## 1. Visão Geral do Projeto

### 1.1 Objetivo
Implementar sistema de dashboards com controle de acesso baseado em roles para visualização de indicadores educacionais e de segurança, com 4 níveis de acesso distintos:
- **DIRETORIA**: Acesso aos dados de sua escola
- **SEC_EDUC_MUN**: Acesso às escolas municipais do município
- **SEC_EDUC_EST**: Acesso às escolas estaduais do estado
- **SEC_SEG_PUB**: Acesso a denúncias de segurança das escolas municipais e estaduais do estado

### 1.2 Indicadores a Implementar
1. **Presença**: Taxa atual vs total de alunos (Radial Chart)
   - Visível para: DIRETORIA, SEC_EDUC_MUN, SEC_EDUC_EST
   
2. **Denúncias Educacionais**: Bullying, Infraestrutura e Outros - TRATADA vs PENDENTE (Bar Chart Stacked)
   - Visível para: DIRETORIA, SEC_EDUC_MUN, SEC_EDUC_EST
   
3. **Socioemocional**: Scores por dimensão (Radar Chart)
   - Visível para: DIRETORIA, SEC_EDUC_MUN, SEC_EDUC_EST
   
4. **Denúncias de Segurança**: Tráfico, Assédio, Discriminação, Violência - TRATADA vs PENDENTE (Bar Chart Stacked)
   - Visível para: SEC_SEG_PUB exclusivamente

## 2. Arquitetura da Solução

### 2.1 Backend (Supabase + Edge Functions)
- **Banco de Dados**: PostgreSQL com estrutura multi-tenant
- **Autenticação**: Supabase Auth
- **Realtime**: Supabase Realtime para atualizações
- **RPCs**: PostgreSQL Functions para agregação de dados com controle de acesso
- **Edge Functions**: Supabase Edge Functions para lógica serverless complexa
- **RLS**: Row Level Security para isolamento de dados

### 2.2 Frontend
- **Framework**: Next.js 14+ com App Router
- **UI Components**: shadcn/ui
- **Gráficos**: Recharts (integrado com shadcn/ui)
- **Estilização**: Tailwind CSS
- **Estado**: React Context + Server Components
- **Data Fetching**: Server Actions + Route Handlers
- **Deploy**: Vercel

## 3. Adequações no Banco de Dados

### 3.1 Novas Tabelas
- [ ] `role_permissions`: Controle de roles especiais
- [ ] `role_categoria_denuncia`: Mapeamento de categorias por role
- [ ] `dashboard_access_log`: Auditoria de acessos com RLS
- [ ] `dashboard_rate_limit`: Controle de rate limiting
- [ ] Índices para otimização de consultas

### 3.2 Alterações em Tabelas Existentes
- [ ] `user_tenant_mapping`: Adicionar special_role_id e access_scope
- [ ] `instituicoes`: Adicionar co_uf, co_municipio, tp_dependencia
- [ ] Popular dados de localização usando `registro_inep`

### 3.3 Funções (RPCs)
- [ ] `rpc_dashboard_presenca`: Agregação de dados de presença
- [ ] `rpc_dashboard_denuncias`: Agregação de denúncias educacionais
- [ ] `rpc_dashboard_denuncias_seguranca`: Agregação de denúncias de segurança
- [ ] `rpc_dashboard_sentimento`: Agregação de scores socioemocionais
- [ ] `rpc_get_escolas_acessiveis`: Listar escolas acessíveis ao usuário

### 3.4 Triggers para Realtime
- [ ] `notify_presenca_change`: Atualização de presença
- [ ] `notify_denuncias_change`: Atualização de denúncias
- [ ] `notify_sentimento_change`: Atualização socioemocional

### 3.5 Funções de Segurança
- [ ] `validate_schema_access`: Prevenir SQL injection em queries dinâmicas
- [ ] `validate_user_session`: Validação robusta de sessão
- [ ] `check_rate_limit`: Controle de requisições por endpoint

## 4. Componentes Frontend

### 4.1 Estrutura de Pastas (Next.js App Router)
```
app/
├── (auth)/
│   ├── login/
│   │   ├── page.tsx
│   │   └── loading.tsx
│   └── layout.tsx
├── (dashboard)/
│   ├── layout.tsx              # Layout com sidebar/header
│   ├── page.tsx                # Dashboard principal
│   ├── loading.tsx             # Loading state global
│   ├── error.tsx               # Error boundary
│   ├── components/
│   │   ├── presence-chart.tsx
│   │   ├── complaints-chart.tsx
│   │   ├── security-complaints-chart.tsx
│   │   ├── emotional-chart.tsx
│   │   ├── school-selector.tsx
│   │   └── dashboard-header.tsx
│   └── [schoolId]/
│       ├── page.tsx            # Dashboard específico
│       └── loading.tsx
├── api/
│   └── dashboard/              # Route handlers
│       ├── presence/route.ts
│       ├── complaints/route.ts
│       ├── security/route.ts
│       └── emotional/route.ts
└── layout.tsx                  # Root layout

components/
├── ui/                         # shadcn/ui components
│   ├── chart.tsx
│   ├── card.tsx
│   ├── select.tsx
│   └── ...
└── charts/                     # Wrappers específicos
    ├── radial-chart.tsx
    ├── bar-chart-stacked.tsx
    └── radar-chart.tsx
```

### 4.2 Componentes de Gráficos (shadcn/ui + Recharts)

#### Presença (Radial Chart)
- Componente: `@/components/ui/chart` com RadialBarChart
- Props: presentes, total, porcentagem
- Cores: Verde (presente) / Cinza (ausente)
- Animação: Transição suave ao atualizar

#### Denúncias Educacionais (Bar Chart Stacked)
- Componente: `@/components/ui/chart` com BarChart
- Props: meses, categorias (bullying, infraestrutura, outros), status
- Cores: Azul (tratada) / Laranja (pendente)
- Tooltip customizado com detalhes

#### Denúncias de Segurança (Bar Chart Stacked)
- Componente: `@/components/ui/chart` com BarChart
- Props: meses, categorias (tráfico, assédio, discriminação, violência), status
- Cores: Verde (tratada) / Vermelho (pendente)
- Filtros por categoria e período

#### Socioemocional (Radar Chart)
- Componente: `@/components/ui/chart` com RadarChart
- Props: dimensões, scores (0-10)
- Cores: Gradiente de cores por dimensão
- Comparação temporal (período anterior)

### 4.3 Fluxo de Autenticação
1. Login via Supabase Auth
2. Middleware verifica role do usuário via RPC
3. Redirect para dashboard apropriado
4. Server Component carrega escolas permitidas
5. Cliente seleciona escola(s) para visualização

## 5. Edge Functions (Supabase)

### 5.1 Funções Planejadas
- [ ] `process-user-provisioning`: Processar fila de provisionamento de usuários
- [ ] `aggregate-dashboard-data`: Pré-processar dados para cache
- [ ] `export-dashboard-pdf`: Gerar relatórios em PDF
- [ ] `send-alert-notifications`: Enviar notificações de alertas

### 5.2 Estrutura
```
supabase/functions/
├── process-user-provisioning/
│   └── index.ts
├── aggregate-dashboard-data/
│   └── index.ts
├── export-dashboard-pdf/
│   └── index.ts
└── shared/
    ├── supabase-client.ts
    └── auth-helpers.ts
```

## 6. Configuração do Deploy

### 6.1 Vercel (Frontend)

#### Variáveis de Ambiente
```env
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
```

#### vercel.json
```json
{
  "buildCommand": "npm run build",
  "outputDirectory": ".next",
  "framework": "nextjs",
  "regions": ["gru1"],
  "functions": {
    "app/api/dashboard/*.ts": {
      "maxDuration": 10
    }
  }
}
```

### 6.2 Supabase (Backend)

#### Edge Functions Deploy
```bash
supabase functions deploy process-user-provisioning
supabase functions deploy aggregate-dashboard-data
supabase functions deploy export-dashboard-pdf
```

## 7. Cronograma de Implementação

### Fase 1: Backend Base (3 dias)
- [ ] Dia 1: Criar script SQL com todas as tabelas e alterações
- [ ] Dia 2: Implementar RPCs de segurança e consulta
- [ ] Dia 3: Implementar RPCs dos indicadores e testes

### Fase 2: Frontend Base (3 dias)
- [ ] Dia 4: Setup Next.js 14 App Router + shadcn/ui
- [ ] Dia 5: Implementar autenticação e middleware
- [ ] Dia 6: Criar layouts e estrutura de rotas

### Fase 3: Componentes e Integração (4 dias)
- [ ] Dia 7: Implementar componentes de gráficos
- [ ] Dia 8: Integração com RPCs e data fetching
- [ ] Dia 9: Implementar seletor de escolas e filtros
- [ ] Dia 10: Configurar Realtime updates

### Fase 4: Edge Functions e Finalização (2 dias)
- [ ] Dia 11: Implementar Edge Functions prioritárias
- [ ] Dia 12: Deploy Vercel + testes de integração

### Fase 5: Refinamentos (2 dias)
- [ ] Dia 13: Otimizações de performance
- [ ] Dia 14: Documentação e handoff

## 8. Considerações de Segurança

### 8.1 Backend
- RLS ativado em todas as tabelas
- RPCs com SECURITY DEFINER e validações
- Funções anti SQL injection
- Rate limiting por usuário/endpoint
- Logs de auditoria com retenção de 90 dias

### 8.2 Frontend
- Sanitização de inputs via Zod
- CSRF protection via Vercel
- Content Security Policy headers
- Secrets em variáveis de ambiente
- HTTPS obrigatório

### 8.3 Edge Functions
- Validação de origem das requisições
- Timeout configurado (max 30s)
- Retry logic para operações críticas
- Dead letter queue para falhas

## 9. Monitoramento e Manutenção

### 9.1 Métricas a Monitorar
- Taxa de erro das RPCs (< 0.1%)
- Tempo de resposta dos dashboards (p95 < 2s)
- Taxa de sucesso do Realtime (> 99.9%)
- Uso de Edge Functions (custo/invocações)

### 9.2 Ferramentas
- Vercel Analytics (Frontend)
- Supabase Dashboard (Backend)
- Sentry (Error tracking)
- Uptime monitoring

## 10. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| Performance com muitas escolas | Média | Alto | Cache em Edge Functions + paginação |
| Complexidade das permissões | Alta | Médio | Testes automatizados por role |
| Custo Edge Functions | Média | Médio | Monitorar uso e otimizar chamadas |
| Dados inconsistentes | Média | Alto | Validações em múltiplas camadas |
| Falha no Realtime | Baixa | Médio | Fallback para polling + reconexão |

## 11. Pendências e Decisões Futuras

### 11.1 Provisionamento de Usuários
**Status**: PENDENTE - A ser definido com a equipe

Opções em consideração:
1. Processo manual via admin panel
2. Importação em batch via CSV
3. Integração com sistema existente
4. Self-service com aprovação

### 11.2 Funcionalidades Futuras
- [ ] Export de relatórios (PDF/Excel)
- [ ] Comparação entre períodos
- [ ] Alertas automáticos
- [ ] Dashboard mobile app

## 12. Checklist de Entrega

### Backend
- [ ] Script SQL executado sem erros
- [ ] Todas as RPCs testadas
- [ ] Triggers de Realtime funcionando
- [ ] Edge Functions deployadas
- [ ] Documentação das APIs

### Frontend
- [ ] Build sem erros no Vercel
- [ ] Autenticação funcionando
- [ ] Todos os 4 indicadores implementados
- [ ] Realtime updates testados
- [ ] Responsividade validada

### Segurança
- [ ] Testes de permissão por role
- [ ] Validação de SQL injection
- [ ] Rate limiting testado
- [ ] Logs de auditoria verificados

### Deploy
- [ ] Domínio configurado
- [ ] SSL ativo
- [ ] Variáveis de ambiente
- [ ] Monitoramento configurado
- [ ] Backup automático

---

**Status**: 📋 Planejamento Aprovado
**Última Atualização**: 2024-01-20
**Versão**: 3.0.0
**Próximo Marco**: Início da implementação do backend
