## 📋 **Prompt para @po - Pós-MVP Frontend**

---

**@po**

Como Product Owner do projeto "Dashboard Max Escola Segura", você precisa criar user stories para as **próximas fases de desenvolvimento** após o MVP frontend ter sido implementado com sucesso.

**CONTEXTO ATUAL (15/01/2025)**: 
- ✅ **MVP Frontend IMPLEMENTADO**: Dashboard funcional com 3 gráficos shadcn/ui
- ✅ **Demo Acessível**: `/dashboard-demo` com dados mock funcionando
- ✅ **Componentes Prontos**: RadialBar (presença), StackedBar (denúncias), Radar (socioemocional)
- ✅ **Funcionalidades Específicas**: Botão 190 (DIRETORIA), Ticker alertas (SEC_SEG_PUB)
- ✅ **Hook Realtime**: Estrutura implementada aguardando integração
- 📋 **Pendente**: Integração com backend Supabase, autenticação, dados reais

**TECNOLOGIAS JÁ IMPLEMENTADAS**:
- Next.js 14 App Router (puro, sem Igniter.js)
- shadcn/ui + Recharts (gráficos funcionando)
- TypeScript com interfaces completas
- Build de produção sem erros

**SUA TAREFA**:
Criar user stories detalhadas para completar a integração do dashboard com o backend Supabase, implementar autenticação e popular com dados reais. Salve na pasta `implementation-docs/Stories/`.

**ESTRUTURA REQUERIDA**:

1. **Epic 1: Integração Backend** (2-3 dias)
   - Stories para executar scripts SQL no Supabase
   - Stories para validar RPCs com dados reais
   - Stories para configurar realtime triggers
   - Stories para conectar componentes aos RPCs

2. **Epic 2: Autenticação e Autorização** (2 dias) 
   - Stories para integrar Supabase Auth
   - Stories para implementar fluxo de login
   - Stories para ativar middleware RBAC
   - Stories para mapear usuários aos roles

3. **Epic 3: Dados Reais e Refinamentos** (1-2 dias)
   - Stories para popular drill-down com dados reais
   - Stories para implementar filtro de denúncias anônimas
   - Stories para conectar eventos realtime
   - Stories para testes de integração

4. **Epic 4: Deploy e Monitoramento** (1 dia)
   - Stories para configurar Vercel
   - Stories para variáveis de ambiente
   - Stories para monitoramento e logs

**FORMATO DE CADA STORY**:
```markdown
## US-XXX: [Título da Story]

**Como** [tipo de usuário]  
**Eu quero** [funcionalidade]  
**Para que** [valor/benefício]

### Critérios de Aceite
- [ ] Critério 1
- [ ] Critério 2
- [ ] Critério 3

### Definição de Pronto
- [ ] Código implementado e testado
- [ ] Integração funcionando
- [ ] Sem erros no console
- [ ] Performance adequada (< 2s)

### Tasks Técnicas
- [ ] Task 1 (especificar arquivo/componente)
- [ ] Task 2 (especificar RPC/função)

### Componentes/Arquivos Afetados
- `src/components/dashboard/[component].tsx`
- `supabase/functions/[rpc_name]`

### Dependências
- Dependente de: US-XXX
- Bloqueia: US-YYY

### Estimativa
Story Points: X (1-8)

### Notas de Integração
[Detalhes específicos sobre RPCs, schemas, ou configurações]
```

**PRIORIDADES**:
1. **CRÍTICA**: Scripts SQL + RPCs (sem isso nada funciona)
2. **ALTA**: Autenticação básica (login/logout)
3. **ALTA**: Conectar componentes aos dados reais
4. **MÉDIA**: Realtime funcionando completamente
5. **BAIXA**: Refinamentos e otimizações

**CONSIDERAÇÕES ESPECIAIS**:
- Componentes frontend JÁ EXISTEM - focar em integração
- Usar os RPCs já definidos nos scripts SQL
- Manter simplicidade - não adicionar features novas
- Cada story deve ser testável isoladamente
- Considerar multi-tenant desde o início
- Hook realtime já existe - apenas conectar eventos

**COMPONENTES JÁ IMPLEMENTADOS** (para referência):
- `presence-chart.tsx` - Precisa conectar com `rpc_dashboard_presenca`
- `complaints-chart.tsx` - Precisa conectar com `rpc_dashboard_denuncias`
- `emotional-chart.tsx` - Precisa conectar com `rpc_dashboard_socioemocional`
- `dashboard-main.tsx` - Orquestrador que gerencia todos os componentes
- `use-realtime-updates.ts` - Hook pronto para receber eventos Supabase

**ENTREGÁVEIS**:
1. `Epic-01-Integracao-Backend.md` com stories de integração
2. `Epic-02-Autenticacao.md` com stories de auth/RBAC
3. `Epic-03-Dados-Reais.md` com stories de população de dados
4. `Epic-04-Deploy.md` com stories de deployment
5. `Integration-Checklist.md` com checklist de validação

**CRONOGRAMA ESTIMADO**: 5-7 dias úteis (vs 14 dias originais)

**RESULTADO ESPERADO**: 
User stories focadas em INTEGRAÇÃO dos componentes existentes com o backend, sem criar novos componentes ou features. Dashboard totalmente funcional com dados reais ao final.

Comece pelo Epic 1 (Backend) que é bloqueador para todos os outros.