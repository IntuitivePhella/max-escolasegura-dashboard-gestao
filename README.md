# 📊 Dashboard Max Escola Segura

Sistema de dashboards educacionais multi-tenant com controle de acesso baseado em roles para monitoramento em tempo real de indicadores escolares.

## 🎯 Visão Geral

Dashboard de gestão para o projeto Max Escola Segura com 4 níveis de acesso distintos:

- **DIRETORIA**: Visualiza dados exclusivamente de sua escola
- **SEC_EDUC_MUN**: Visualiza dados de escolas municipais do município
- **SEC_EDUC_EST**: Visualiza dados de escolas estaduais do estado  
- **SEC_SEG_PUB**: Visualiza denúncias de segurança de escolas municipais e estaduais

### Indicadores Disponíveis

1. **📊 Presença Escolar** - Taxa de alunos presentes em tempo real
2. **📋 Denúncias Educacionais** - Bullying, infraestrutura e outros
3. **💭 Monitoramento Socioemocional** - Bem-estar dos alunos por dimensões
4. **🚨 Denúncias de Segurança** - Tráfico, assédio, discriminação e violência (exclusivo SEC_SEG_PUB)

## 🛠️ Stack Tecnológica

### Frontend
- **Framework**: Next.js 14+ com App Router
- **UI Components**: shadcn/ui + Recharts
- **Styling**: Tailwind CSS
- **Type Safety**: TypeScript + Zod
- **Deploy**: Vercel

### Backend
- **Database**: PostgreSQL (Supabase) multi-tenant
- **Auth**: Supabase Auth com RBAC
- **Realtime**: Supabase Realtime
- **Edge Functions**: Supabase Edge Functions
- **Security**: RLS + Rate Limiting

## 🚀 Quick Start

### Pré-requisitos
- Node.js 18+
- Conta Supabase com projeto configurado
- PostgreSQL com estrutura multi-tenant

### Instalação

1. Clone o repositório:
```bash
git clone https://github.com/IntuitivePhella/max-escolasegura-dashboard-gestao.git
cd max-escolasegura-dashboard-gestao
```

2. Instale as dependências:
```bash
npm install
```

3. Configure as variáveis de ambiente:
```bash
cp .env.example .env.local
```

Edite `.env.local`:
```env
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
```

4. Execute as migrations do banco:
```bash
npm run db:migrate
```

5. Inicie o servidor de desenvolvimento:
```bash
npm run dev
```

Acesse http://localhost:3000

## 🏗️ Arquitetura

### Estrutura do Projeto (App Router)

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
│   ├── loading.tsx             
│   ├── error.tsx               
│   ├── components/
│   │   ├── presence-chart.tsx
│   │   ├── complaints-chart.tsx
│   │   ├── security-complaints-chart.tsx
│   │   ├── emotional-chart.tsx
│   │   └── school-selector.tsx
│   └── [schoolId]/
│       └── page.tsx
├── api/
│   └── dashboard/
│       ├── presence/route.ts
│       ├── complaints/route.ts
│       ├── security/route.ts
│       └── emotional/route.ts
└── layout.tsx

components/
├── ui/                         # shadcn/ui components
└── charts/                     # Chart wrappers
```

### Fluxo de Dados

1. **Autenticação**: Login via Supabase Auth
2. **Autorização**: Middleware valida role via `user_tenant_mapping`
3. **Data Fetching**: Server Components + Route Handlers
4. **Realtime**: Supabase subscriptions com auto-refetch
5. **Caching**: Edge Functions para agregações pesadas

## 🔐 Segurança e RBAC

### Controle de Acesso

```sql
-- Tabela de mapeamento usuário-tenant-role
public.user_tenant_mapping (
  user_id UUID,
  schema_name TEXT,
  role TEXT CHECK (role IN ('DIRETORIA', 'SEC_EDUC_MUN', 'SEC_EDUC_EST', 'SEC_SEG_PUB')),
  special_role_id INTEGER,
  status TEXT DEFAULT 'ATIVO'
)

-- Role permissions define acesso a features
public.role_permissions (
  id SERIAL PRIMARY KEY,
  role_type TEXT,
  permissions JSONB
)

-- Categorias de denúncia por role
public.role_categoria_denuncia (
  role_type TEXT,
  categoria TEXT,
  ativo BOOLEAN
)
```

### Funções de Segurança

- `validate_schema_access()` - Previne SQL injection
- `validate_user_session()` - Validação robusta de sessão
- `check_rate_limit()` - Rate limiting por endpoint

## 📡 API Endpoints

### Dashboard APIs

```typescript
// Presença escolar
GET /api/dashboard/presence
Response: { 
  schools: [{ 
    name, 
    present: number, 
    total: number, 
    percentage: number 
  }] 
}

// Denúncias educacionais  
GET /api/dashboard/complaints
Response: { 
  months: [{ 
    month, 
    bullying: { treated, pending },
    infrastructure: { treated, pending }
  }] 
}

// Denúncias de segurança (SEC_SEG_PUB only)
GET /api/dashboard/security
Response: { 
  months: [{ 
    month,
    categories: { 
      traffic, harassment, 
      discrimination, violence 
    }
  }] 
}

// Monitoramento socioemocional
GET /api/dashboard/emotional
Response: { 
  dimensions: [{ 
    name, 
    score, 
    trend 
  }] 
}
```

## 🚀 Deploy

### Frontend (Vercel)

```bash
# Deploy automático via GitHub
git push origin main

# Deploy manual
vercel --prod
```

### Edge Functions (Supabase)

```bash
# Deploy todas as functions
npm run deploy:functions

# Deploy específica
supabase functions deploy process-user-provisioning
```

## 📊 Monitoramento

- **Frontend**: Vercel Analytics + Web Vitals
- **Backend**: Supabase Dashboard + Logs
- **Errors**: Sentry integration
- **Uptime**: Status page

## 🧪 Testes

```bash
# Testes unitários
npm run test

# Testes E2E
npm run test:e2e

# Testes de carga
npm run test:load
```

## 📚 Documentação

- [Plano de Implementação](./implementation-docs/action-plan-V3.md)
- [Arquitetura do Banco](./implementation-docs/database-schema.md)
- [Guia de Contribuição](./CONTRIBUTING.md)
- [Changelog](./CHANGELOG.md)

## 🤝 Contribuindo

1. Fork o projeto
2. Crie sua feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📄 Licença

Este projeto é proprietário e confidencial. Todos os direitos reservados.

---

**Status**: 🚧 Em Desenvolvimento  
**Versão**: 0.1.0  
**Última Atualização**: Janeiro 2024

Para mais informações, consulte o [Plano de Ação V3](./implementation-docs/action-plan-V3.md)