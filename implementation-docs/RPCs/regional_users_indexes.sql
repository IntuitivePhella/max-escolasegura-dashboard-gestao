-- ============================================================================
-- ÍNDICES: regional_users_indexes
-- Descrição: Índices para otimização de performance
-- Autor: Solution Architect
-- Data: 2024-01-20
-- ============================================================================

-- ============================================================================
-- ÍNDICES PARA TABELA: regional_users
-- ============================================================================

-- Índices já criados na tabela principal (para referência):
-- CREATE INDEX idx_regional_users_role ON public.regional_users(role);
-- CREATE INDEX idx_regional_users_co_uf ON public.regional_users(co_uf);
-- CREATE INDEX idx_regional_users_co_municipio ON public.regional_users(co_municipio) WHERE co_municipio IS NOT NULL;
-- CREATE INDEX idx_regional_users_status ON public.regional_users(status);
-- CREATE INDEX idx_regional_users_auth_user_id ON public.regional_users(auth_user_id);
-- CREATE INDEX idx_regional_users_email_lower ON public.regional_users(LOWER(email));

-- Índices compostos para queries comuns
CREATE INDEX IF NOT EXISTS idx_regional_users_role_uf 
    ON public.regional_users(role, co_uf) 
    WHERE status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS idx_regional_users_role_uf_municipio 
    ON public.regional_users(role, co_uf, co_municipio) 
    WHERE role = 'SEC_EDUC_MUN' AND status = 'ACTIVE';

-- Índice para busca por data de criação
CREATE INDEX IF NOT EXISTS idx_regional_users_created_at 
    ON public.regional_users(created_at DESC);

-- Índice para usuários que não trocaram senha
CREATE INDEX IF NOT EXISTS idx_regional_users_password_not_changed 
    ON public.regional_users(password_changed) 
    WHERE password_changed = FALSE;

-- Índice para busca por último login
CREATE INDEX IF NOT EXISTS idx_regional_users_last_login 
    ON public.regional_users(last_login DESC NULLS LAST);

-- ============================================================================
-- ÍNDICES PARA TABELA: user_tenant_mapping (otimizações para usuários regionais)
-- ============================================================================

-- Índice para busca por role específico
CREATE INDEX IF NOT EXISTS idx_user_tenant_mapping_role 
    ON public.user_tenant_mapping(role) 
    WHERE role IN ('SEC_EDUC_MUN', 'SEC_EDUC_EST', 'SEC_SEG_PUB');

-- Índice composto para queries de acesso por usuário e role
CREATE INDEX IF NOT EXISTS idx_user_tenant_mapping_user_role 
    ON public.user_tenant_mapping(user_id, role) 
    WHERE status = 'ATIVO';

-- Índice para contagem de acessos por schema
CREATE INDEX IF NOT EXISTS idx_user_tenant_mapping_schema_role 
    ON public.user_tenant_mapping(schema_name, role) 
    WHERE status = 'ATIVO';

-- ============================================================================
-- ÍNDICES PARA TABELA: registro_inep (otimizações para provisionamento)
-- ============================================================================

-- Índice para busca de municípios com escolas municipais
CREATE INDEX IF NOT EXISTS idx_registro_inep_mun_escolas 
    ON public.registro_inep("CO_UF", "CO_MUNICIPIO") 
    WHERE "TP_DEPENDENCIA" = '3' AND "CO_MUNICIPIO" IS NOT NULL;

-- Índice para busca de escolas estaduais por UF
CREATE INDEX IF NOT EXISTS idx_registro_inep_est_escolas 
    ON public.registro_inep("CO_UF") 
    WHERE "TP_DEPENDENCIA" = '2';

-- Índice para contagem de escolas por tipo e localização
CREATE INDEX IF NOT EXISTS idx_registro_inep_tipo_local 
    ON public.registro_inep("TP_DEPENDENCIA", "CO_UF", "CO_MUNICIPIO");

-- ============================================================================
-- ÍNDICES PARA TABELA: instituicoes (otimizações para mapeamento)
-- ============================================================================

-- Índice para join com registro_inep
CREATE INDEX IF NOT EXISTS idx_instituicoes_co_inep 
    ON public.instituicoes(co_inep::text);

-- Índice para busca de escolas com schema ativo
CREATE INDEX IF NOT EXISTS idx_instituicoes_schema_active 
    ON public.instituicoes(schema_name) 
    WHERE schema_name IS NOT NULL AND status = 'Ativo';

-- ============================================================================
-- ÍNDICES PARA TABELA: regional_users_audit
-- ============================================================================

-- Índices já criados na tabela de auditoria (para referência):
-- CREATE INDEX idx_regional_users_audit_user_id ON public.regional_users_audit(user_id);
-- CREATE INDEX idx_regional_users_audit_changed_at ON public.regional_users_audit(changed_at);

-- Índice adicional para busca por ação
CREATE INDEX IF NOT EXISTS idx_regional_users_audit_action 
    ON public.regional_users_audit(action, changed_at DESC);

-- Índice para busca por quem fez a mudança
CREATE INDEX IF NOT EXISTS idx_regional_users_audit_changed_by 
    ON public.regional_users_audit(changed_by, changed_at DESC);

-- ============================================================================
-- ANÁLISE E ESTATÍSTICAS
-- ============================================================================

-- Atualizar estatísticas das tabelas após criar índices
ANALYZE public.regional_users;
ANALYZE public.user_tenant_mapping;
ANALYZE public.registro_inep;
ANALYZE public.instituicoes;
ANALYZE public.regional_users_audit;

-- ============================================================================
-- MONITORAMENTO DE PERFORMANCE
-- ============================================================================

-- View para monitorar uso dos índices
CREATE OR REPLACE VIEW public.v_regional_users_index_usage AS
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND tablename IN ('regional_users', 'user_tenant_mapping', 'regional_users_audit')
ORDER BY idx_scan DESC;

COMMENT ON VIEW public.v_regional_users_index_usage IS 'Monitoramento de uso de índices do sistema de usuários regionais';

-- View para identificar queries lentas relacionadas a usuários regionais
CREATE OR REPLACE VIEW public.v_regional_users_slow_queries AS
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    min_time,
    max_time
FROM pg_stat_statements
WHERE query LIKE '%regional_users%'
   OR query LIKE '%user_tenant_mapping%'
ORDER BY mean_time DESC
LIMIT 20;

COMMENT ON VIEW public.v_regional_users_slow_queries IS 'Queries lentas relacionadas a usuários regionais';

-- ============================================================================
-- RECOMENDAÇÕES DE MANUTENÇÃO
-- ============================================================================

-- Script para reindexar periodicamente (executar mensalmente)
/*
REINDEX TABLE CONCURRENTLY public.regional_users;
REINDEX TABLE CONCURRENTLY public.user_tenant_mapping;
REINDEX TABLE CONCURRENTLY public.regional_users_audit;
*/

-- Script para verificar bloat dos índices
/*
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    indexrelid::regclass
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND pg_relation_size(indexrelid) > 1048576 -- Índices maiores que 1MB
ORDER BY pg_relation_size(indexrelid) DESC;
*/

-- ============================================================================
-- NOTAS DE PERFORMANCE
-- ============================================================================

/*
1. Os índices parciais (WHERE clauses) reduzem o tamanho e melhoram performance
2. Índices compostos são ordenados pela cardinalidade (mais seletivo primeiro)
3. LOWER(email) permite buscas case-insensitive eficientes
4. Índices em JSONB não foram criados pois metadata tem uso limitado
5. Considerar particionamento se regional_users > 100k registros
6. Monitorar pg_stat_user_indexes regularmente para identificar índices não utilizados
*/
