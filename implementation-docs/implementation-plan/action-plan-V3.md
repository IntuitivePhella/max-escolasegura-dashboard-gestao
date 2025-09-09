# 📊 Dashboard Max Escola Segura - MVP APROVADO

## 🚨 **DECISÕES FINAIS IMPLEMENTADAS (15/01/2025)**

### **✅ MVP Ultra-Simplificado Aprovado**
**Análise PO**: Protótipos UX originais continham over-engineering severo (mapas SVG, rankings, comparativos complexos)  
**Decisão**: Focar em MVP simples baseado na referência visual `diretoria.html`  
**Cronograma**: 2-3 dias vs 2-3 semanas da proposta original

### **✅ Especificações Finais:**
1. **Realtime para TODOS**: presence_update, complaint_update, emotional_update, security_update
2. **DIRETORIA específico**: Botão "Emergência 190" + Visão Temporal/Por Aluno + Filtro tipo denúncia
3. **SEC_SEG_PUB específico**: Ticker alertas críticos + APENAS gráfico segurança
4. **Drill-down detalhes**: Sentimentos (todos) + Denúncias (APENAS não anônimas)
5. **Gráficos shadcn/ui obrigatórios**: RadialBarChart + StackedBarChart + RadarChart (baseados em chart-examples/)

### **❌ Funcionalidades Removidas (Over-engineering):**
- Mapas SVG interativos estaduais
- Rankings top 10 municípios  
- Comparativos vs Estado/Região
- Sistema emergência complexo
- Edge Functions desnecessárias

---

## 1. Visão Geral do Projeto MVP

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
- **Framework**: Next.js 14+ com App Router (migração de Igniter.js existente)
- **UI Components**: shadcn/ui (já instalado)
- **Gráficos**: Recharts (integrado com shadcn/ui)
- **Estilização**: Tailwind CSS
- **Estado**: React Context + Server Components
- **Data Fetching**: Server Actions + Route Handlers (substitui controllers Igniter)
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

## 7. Cronograma MVP Simplificado - 2-3 DIAS

### ✅ **DECISÃO APROVADA**: MVP Ultra-Simplificado
**Referência**: Simplicidade visual do `diretoria.html`  
**Princípio**: Dashboards são sobre DADOS, não interfaces complexas

### **Fase 1: Backend Mínimo (1 dia)**
- [x] Scripts SQL já implementados (security-fixes, tabelas-adequacoes, middleware_helpers, RPCs indicadores)
- [ ] **Dia 1**: Validar RPCs existentes + implementar realtime triggers

### **Fase 2: Frontend MVP (1-2 dias)**
- [ ] **Dia 2**: Implementar layout universal com shadcn/ui
  - 4 cards KPI + 3 gráficos (RadialBar + StackedBar + Radar)
  - Hook realtime universal
  - Filtros mínimos por role
- [ ] **Dia 3**: Drill-down modais + funcionalidades específicas por role
  - DIRETORIA: Botão 190 + visão temporal/por aluno + filtro denúncia
  - SEC_SEG_PUB: Ticker alertas críticos
  - SEC_EDUC_*: Multi-select escolas

### **Funcionalidades Removidas do Escopo (Over-engineering):**
- ❌ Mapas SVG interativos estaduais
- ❌ Rankings top 10 municípios  
- ❌ Comparativos vs Estado/Região
- ❌ Sistema emergência complexo
- ❌ Edge Functions desnecessárias

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
**Status**: ✅ DEFINIDO - Criação Automatizada em Batch

**Estratégia Aprovada**:
- Criação automatizada via RPC `provision_regional_users()`
- Usuários SEC_EDUC_MUN: 1 por município com escolas municipais (~2.859)
- Usuários SEC_EDUC_EST: 1 por estado (7 total)
- Usuários SEC_SEG_PUB: 1 por estado (7 total)
- Total estimado: ~2.873 usuários regionais

**Regras de Negócio**:
- Municípios sem escolas não geram usuário
- Escolas federais (TP_DEPENDENCIA = 1) fora do escopo inicial
- Comunicação com secretarias tratada externamente
- Senhas temporárias seguras com troca obrigatória no primeiro login

**Implementação Técnica**:
- Tabela `public.regional_users` para controle e auditoria
- Senhas temporárias com padrão seguro e complexo
- Mapeamento automático no `user_tenant_mapping`
- Chunking de 100 usuários por vez para evitar timeout
- Progress tracking e rollback em caso de falha

**Scripts SQL Implementados**:
1. `regional_users_table.sql` - Tabela principal com constraints e RLS
2. `regional_user_helpers.sql` - 5 funções auxiliares para provisionamento
3. `provision_regional_users.sql` - RPC principal com chunking e validação
4. `regional_users_triggers.sql` - 5 triggers para sincronização e auditoria
5. `regional_users_indexes.sql` - 20+ índices otimizados + views monitoramento

**Sequência de Implementação**:

1. **Preparação do Ambiente**:
   ```bash
   # Executar scripts na ordem obrigatória
   psql -f implementation-docs/RPCs/regional_users_table.sql
   psql -f implementation-docs/RPCs/regional_user_helpers.sql
   psql -f implementation-docs/RPCs/provision_regional_users.sql
   psql -f implementation-docs/RPCs/regional_users_triggers.sql
   psql -f implementation-docs/RPCs/regional_users_indexes.sql
   ```

2. **Validação em Desenvolvimento**:
   ```sql
   -- Teste dry-run (não persiste dados)
   SELECT * FROM provision_regional_users(100, TRUE);
   
   -- Verificar resultado esperado:
   -- total_expected: ~2873, total_success: ~2873, total_errors: 0
   ```

3. **Execução em Produção**:
   ```sql
   -- Provisionamento completo
   SELECT * FROM provision_regional_users();
   
   -- Validar criação por role
   SELECT role, COUNT(*) FROM regional_users GROUP BY role;
   ```

4. **Validação Pós-Deploy**:
   ```sql
   -- Verificar mapeamentos criados
   SELECT ru.role, COUNT(utm.id) as escolas_mapeadas
   FROM regional_users ru
   LEFT JOIN user_tenant_mapping utm ON ru.auth_user_id = utm.user_id
   GROUP BY ru.role;
   
   -- Monitorar performance
   SELECT * FROM v_regional_users_index_usage;
   ```

**Critérios de Validação**:
- ✅ Provisionamento: 100% usuários criados sem erro
- ✅ Mapeamento: Escolas associadas corretamente por role
- ✅ Performance: Execução completa em < 60 segundos
- ✅ Segurança: RLS e validações funcionando
- ✅ Auditoria: Logs de criação registrados em `regional_users_audit`

### 11.2 Funcionalidades Futuras
- [ ] Export de relatórios (PDF/Excel)
- [ ] Comparação entre períodos
- [ ] Alertas automáticos
- [ ] Dashboard mobile app

## 12. Checklist MVP Simplificado

### ✅ **Backend Mínimo**
- [x] Scripts SQL base já implementados (12 arquivos)
- [ ] RPCs indicadores validados (presença, denúncias, socioemocional, segurança)
- [ ] Realtime triggers configurados (presence_update, complaint_update, emotional_update, security_update)
- [ ] Validação: queries executam em < 2s com dados reais

### ✅ **Frontend MVP - shadcn/ui**
- [ ] Layout universal baseado em `diretoria.html`
- [ ] 4 cards KPI simples (total alunos, presentes, denúncias, bem-estar)
- [ ] 3 gráficos shadcn/ui:
  - [ ] **RadialBarChart** presença (chart-examples/radial-chart-shape)
  - [ ] **StackedBarChart** denúncias (chart-examples/barchart-stacked+legend) 
  - [ ] **RadarChart** socioemocional (chart-examples/radarchart-grid-circle)
- [ ] Hook realtime universal funcionando
- [ ] Drill-down modais com tabelas de detalhes
- [ ] Filtros funcionais por role:
  - [ ] **DIRETORIA**: Botão 190 + visão temporal/aluno + filtro denúncia
  - [ ] **SEC_SEG_PUB**: Ticker alertas críticos realtime
  - [ ] **SEC_EDUC_***: Multi-select escolas

### ✅ **Funcionalidades Específicas**
- [ ] Drill-down sentimentos: modal com tabela completa
- [ ] Drill-down denúncias: APENAS não anônimas (`WHERE Anonima = false`)
- [ ] Realtime: todos os roles recebem updates apropriados
- [ ] Responsividade: mobile-first, stack vertical

### ✅ **Deploy**
- [ ] Build Next.js 14 sem erros
- [ ] Deploy Vercel funcionando  
- [ ] Variáveis ambiente configuradas
- [ ] SSL ativo

---

**Status**: 🚀 **MVP APROVADO - SIMPLICIDADE TOTAL**  
**Cronograma**: 2-3 dias vs 2-3 semanas originais  
**Última Atualização**: 15/01/2025  
**Versão**: 4.0-MVP  
**Princípio**: Dashboards são sobre DADOS, não interfaces complexas
