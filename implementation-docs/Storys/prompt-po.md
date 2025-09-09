## 🎯 **Agente Recomendado: Product Owner (PO)**

O **Product Owner** é o mais adequado porque:
- Especialista em quebrar épicos em user stories executáveis
- Compreende priorização e sequenciamento de entregas
- Garante que stories tenham critérios de aceite claros
- Mantém foco no valor de negócio e MVP

## 📋 **Prompt para @po**

---

**@po**

Como Product Owner do projeto "Dashboard Max Escola Segura", você precisa transformar o plano de implementação aprovado (action-plan-V3.md) em user stories executáveis para a equipe de desenvolvimento.

**CONTEXTO**: 
- Plano V3 aprovado com arquitetura Next.js 14 App Router + Supabase
- **SITUAÇÃO ATUAL**: Projeto Next.js 14 já existe com Supabase configurado, mas usando Igniter.js
- **ESTRATÉGIA**: Migração incremental para App Router puro (não criar do zero)
- 4 indicadores definidos (presença, denúncias educacionais, socioemocional, denúncias de segurança)
- 4 tipos de usuários (DIRETORIA, SEC_EDUC_MUN, SEC_EDUC_EST, SEC_SEG_PUB)
- Deploy Vercel + Supabase Edge Functions
- Cronograma de 14 dias dividido em 5 fases

**SUA TAREFA**:
Criar user stories detalhadas organizadas por épicos, seguindo a estrutura do cronograma aprovado. Salve na pasta `implementation-docs/Stories/`.

**ESTRUTURA REQUERIDA**:

1. **Epic 1: Backend Base** (Dias 1-3)
   - Stories para setup do banco de dados
   - Stories para implementação de RPCs
   - Stories para funções de segurança

2. **Epic 2: Frontend Base** (Dias 4-6) 
   - Stories para migração de Igniter.js para App Router puro
   - Stories para implementação de Route Handlers nativos
   - Stories para remoção de dependências e atualização de layouts

3. **Epic 3: Componentes e Integração** (Dias 7-10)
   - Stories para cada um dos 4 indicadores
   - Stories para integração com RPCs
   - Stories para Realtime updates

4. **Epic 4: Edge Functions e Finalização** (Dias 11-12)
   - Stories para Edge Functions prioritárias
   - Stories para deploy e integração

5. **Epic 5: Refinamentos** (Dias 13-14)
   - Stories para otimizações
   - Stories para documentação

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
- [ ] Código implementado
- [ ] Testes passando
- [ ] Code review aprovado
- [ ] Deploy realizado

### Tasks Técnicas
- [ ] Task 1
- [ ] Task 2

### Dependências
- Dependente de: US-XXX
- Bloqueia: US-YYY

### Estimativa
Story Points: X

### Notas Técnicas
[Detalhes específicos de implementação]
```

**PRIORIDADES**:
1. **ALTA**: Backend base e autenticação (essencial para MVP)
2. **ALTA**: Indicador de presença (mais simples, validação rápida)
3. **MÉDIA**: Demais indicadores 
4. **BAIXA**: Edge Functions e otimizações

**CONSIDERAÇÕES ESPECIAIS**:
- Cada story deve ser implementável em 4-8 horas
- Stories de frontend dependem das de backend
- Considerar diferentes permissões por tipo de usuário
- Incluir stories de teste para cada funcionalidade crítica

**ENTREGÁVEIS**:
1. `Epic-01-Backend-Base.md` com stories detalhadas
2. `Epic-02-Frontend-Base.md` com stories detalhadas  
3. `Epic-03-Components-Integration.md` com stories detalhadas
4. `Epic-04-Edge-Functions.md` com stories detalhadas
5. `Epic-05-Refinements.md` com stories detalhadas
6. `README.md` com visão geral dos épicos e dependências

**RESULTADO ESPERADO**: 
User stories prontas para serem puxadas pela equipe de desenvolvimento, com critérios claros, dependências mapeadas e priorização definida.

Comece pelos épicos de maior prioridade e garanta que cada story seja autossuficiente e testável.