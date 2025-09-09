-- ============================================
-- SECURITY FIXES - CORREÇÕES CRÍTICAS DE SEGURANÇA
-- ============================================
-- Descrição: Script consolidado com correções críticas de segurança
-- que devem ser executadas ANTES do deploy do dashboard
-- Ordem de execução: Execute este arquivo PRIMEIRO
-- ============================================

-- ============================================
-- 1. FUNÇÃO DE VALIDAÇÃO DE SCHEMA (Anti SQL Injection)
-- ============================================
-- Protege contra SQL injection validando schemas contra whitelist
CREATE OR REPLACE FUNCTION public.validate_schema_access(
    p_schema_name TEXT,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Validação 1: Schema não pode ser nulo ou vazio
    IF p_schema_name IS NULL OR p_schema_name = '' THEN
        RETURN FALSE;
    END IF;
    
    -- Validação 2: Schema deve existir no registry com status ATIVO
    IF NOT EXISTS (
        SELECT 1 
        FROM public.schema_registry 
        WHERE schema_name = p_schema_name 
        AND status = 'ATIVO'
    ) THEN
        RETURN FALSE;
    END IF;
    
    -- Validação 3: Schema deve seguir padrão esperado (escola_XXXXXXXX)
    IF p_schema_name !~ '^escola_[0-9]{8}$' THEN
        RETURN FALSE;
    END IF;
    
    -- Validação 4: Usuário deve ter acesso ao schema
    IF p_user_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 
        FROM public.user_tenant_mapping utm
        WHERE utm.user_id = p_user_id
        AND utm.schema_name = p_schema_name
        AND utm.status = 'ATIVO'
    ) THEN
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END;
$$;

-- Comentário de segurança
COMMENT ON FUNCTION public.validate_schema_access IS 
'Função crítica de segurança: Valida acesso a schemas para prevenir SQL injection. 
SEMPRE use esta função antes de executar queries dinâmicas com schema_name.';

-- ============================================
-- 2. FUNÇÃO DE VALIDAÇÃO DE SESSÃO MELHORADA
-- ============================================
-- Valida não apenas auth.uid() mas também se o usuário existe
CREATE OR REPLACE FUNCTION public.validate_user_session()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Obtém o ID do usuário da sessão
    v_user_id := auth.uid();
    
    -- Validação 1: Sessão deve existir
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Sessão inválida: usuário não autenticado' 
            USING HINT = 'Faça login novamente';
    END IF;
    
    -- Validação 2: Usuário deve existir no auth.users
    IF NOT EXISTS (
        SELECT 1 FROM auth.users WHERE id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Sessão inválida: usuário não encontrado' 
            USING HINT = 'Conta pode ter sido desativada';
    END IF;
    
    -- Validação 3: Usuário deve ter mapping ativo
    IF NOT EXISTS (
        SELECT 1 FROM public.user_tenant_mapping 
        WHERE user_id = v_user_id 
        AND status = 'ATIVO'
    ) THEN
        RAISE EXCEPTION 'Acesso negado: usuário sem permissão ativa' 
            USING HINT = 'Contate o administrador';
    END IF;
    
    RETURN v_user_id;
END;
$$;

COMMENT ON FUNCTION public.validate_user_session IS 
'Validação robusta de sessão: verifica auth.uid(), existência em auth.users e status ativo no sistema';

-- ============================================
-- 3. HABILITAR RLS NAS TABELAS CRÍTICAS
-- ============================================
-- Habilita Row Level Security em tabelas que estavam desprotegidas
DO $$
BEGIN
    -- Habilitar RLS na tabela role_permissions
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'public' 
        AND tablename = 'role_permissions'
        AND rowsecurity = true
    ) THEN
        ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
        RAISE NOTICE 'RLS habilitado em public.role_permissions';
    END IF;
    
    -- Habilitar RLS na tabela dashboard_access_log
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'public' 
        AND tablename = 'dashboard_access_log'
        AND rowsecurity = true
    ) THEN
        ALTER TABLE public.dashboard_access_log ENABLE ROW LEVEL SECURITY;
        RAISE NOTICE 'RLS habilitado em public.dashboard_access_log';
    END IF;
END $$;

-- ============================================
-- 4. POLÍTICAS RLS PARA role_permissions
-- ============================================
-- Política 1: Apenas admins podem ver/modificar roles
CREATE POLICY IF NOT EXISTS role_permissions_admin_all ON public.role_permissions
    FOR ALL 
    TO postgres -- Apenas super admin
    USING (true)
    WITH CHECK (true);

-- Política 2: Usuários autenticados podem ver seu próprio role
CREATE POLICY IF NOT EXISTS role_permissions_read_own ON public.role_permissions
    FOR SELECT 
    TO authenticated
    USING (
        id IN (
            SELECT special_role_id 
            FROM public.user_tenant_mapping 
            WHERE user_id = auth.uid()
        )
    );

COMMENT ON TABLE public.role_permissions IS 
'Tabela crítica: contém definições de roles especiais. RLS habilitado - apenas admins podem modificar.';

-- ============================================
-- 5. POLÍTICAS RLS PARA dashboard_access_log
-- ============================================
-- Política 1: Usuários podem inserir seus próprios logs
CREATE POLICY IF NOT EXISTS dashboard_log_insert_own ON public.dashboard_access_log
    FOR INSERT 
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- Política 2: Apenas admins podem ver todos os logs
CREATE POLICY IF NOT EXISTS dashboard_log_admin_select ON public.dashboard_access_log
    FOR SELECT 
    TO postgres
    USING (true);

-- Política 3: Usuários podem ver seus próprios logs
CREATE POLICY IF NOT EXISTS dashboard_log_select_own ON public.dashboard_access_log
    FOR SELECT 
    TO authenticated
    USING (user_id = auth.uid());

COMMENT ON TABLE public.dashboard_access_log IS 
'Log de auditoria: RLS habilitado - usuários veem apenas próprios logs, admins veem tudo.';

-- ============================================
-- 6. TABELA DE CATEGORIAS POR ROLE (Remove hardcode)
-- ============================================
CREATE TABLE IF NOT EXISTS public.role_categoria_denuncia (
    id SERIAL PRIMARY KEY,
    role_type VARCHAR(20) NOT NULL CHECK (
        role_type IN ('DIRETORIA', 'SEC_EDUC_MUN', 'SEC_EDUC_EST', 'SEC_SEG_PUB')
    ),
    categoria VARCHAR(50) NOT NULL,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(role_type, categoria)
);

-- Habilitar RLS
ALTER TABLE public.role_categoria_denuncia ENABLE ROW LEVEL SECURITY;

-- Política: Apenas leitura para authenticated
CREATE POLICY role_categoria_read ON public.role_categoria_denuncia
    FOR SELECT 
    TO authenticated
    USING (ativo = true);

-- Popular categorias iniciais
INSERT INTO public.role_categoria_denuncia (role_type, categoria) VALUES
    -- DIRETORIA e SEC_EDUC_* veem categorias educacionais
    ('DIRETORIA', 'bullying'),
    ('DIRETORIA', 'infraestrutura'),
    ('SEC_EDUC_MUN', 'bullying'),
    ('SEC_EDUC_MUN', 'infraestrutura'),
    ('SEC_EDUC_EST', 'bullying'),
    ('SEC_EDUC_EST', 'infraestrutura'),
    -- SEC_SEG_PUB vê apenas categorias de segurança
    ('SEC_SEG_PUB', 'tráfico'),
    ('SEC_SEG_PUB', 'assedio'),
    ('SEC_SEG_PUB', 'discriminacao'),
    ('SEC_SEG_PUB', 'violencia')
ON CONFLICT (role_type, categoria) DO NOTHING;

COMMENT ON TABLE public.role_categoria_denuncia IS 
'Mapeia categorias de denúncia permitidas por role. Substitui hardcode nas RPCs.';

-- ============================================
-- 7. ÍNDICES CRÍTICOS PARA PERFORMANCE
-- ============================================
-- Usar CONCURRENTLY para não bloquear tabelas em produção

-- Índice 1: Lookup rápido de user_tenant_mapping
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_tenant_mapping_user_status 
    ON public.user_tenant_mapping(user_id, status);

-- Índice 2: Lookup de roles especiais
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_tenant_special 
    ON public.user_tenant_mapping(special_role_id, user_id, status) 
    WHERE special_role_id IS NOT NULL;

-- Índice 3: Consultas por localização em instituicoes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instituicoes_composite 
    ON public.instituicoes(co_uf, co_municipio, tp_dependencia, "ID")
    WHERE co_uf IS NOT NULL;

-- Índice 4: Schema registry ativo
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_schema_registry_status 
    ON public.schema_registry(status, schema_name)
    WHERE status = 'ATIVO';

-- Índice 5: Logs por data (para limpeza)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dashboard_log_date 
    ON public.dashboard_access_log(accessed_at DESC);

-- ============================================
-- 8. FUNÇÃO DE RATE LIMITING BÁSICO
-- ============================================
CREATE TABLE IF NOT EXISTS public.dashboard_rate_limit (
    user_id UUID NOT NULL,
    endpoint VARCHAR(50) NOT NULL,
    window_start TIMESTAMPTZ NOT NULL,
    request_count INTEGER DEFAULT 1,
    PRIMARY KEY (user_id, endpoint, window_start)
);

-- Índice para limpeza de registros antigos
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rate_limit_window 
    ON public.dashboard_rate_limit(window_start);

-- Função de verificação de rate limit
CREATE OR REPLACE FUNCTION public.check_rate_limit(
    p_user_id UUID,
    p_endpoint VARCHAR(50),
    p_limit INTEGER DEFAULT 100,
    p_window_minutes INTEGER DEFAULT 5
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_window_start TIMESTAMPTZ;
    v_current_count INTEGER;
BEGIN
    -- Calcula início da janela atual
    v_window_start := date_trunc('minute', NOW() - INTERVAL '1 minute' * (EXTRACT(MINUTE FROM NOW())::INTEGER % p_window_minutes));
    
    -- Insere ou atualiza contador
    INSERT INTO public.dashboard_rate_limit (user_id, endpoint, window_start, request_count)
    VALUES (p_user_id, p_endpoint, v_window_start, 1)
    ON CONFLICT (user_id, endpoint, window_start) 
    DO UPDATE SET request_count = public.dashboard_rate_limit.request_count + 1
    RETURNING request_count INTO v_current_count;
    
    -- Limpa registros antigos (async via pg_cron recomendado)
    DELETE FROM public.dashboard_rate_limit 
    WHERE window_start < NOW() - INTERVAL '1 hour';
    
    RETURN v_current_count <= p_limit;
END;
$$;

COMMENT ON FUNCTION public.check_rate_limit IS 
'Rate limiting básico por usuário/endpoint. Retorna FALSE se limite excedido.';

-- ============================================
-- 9. CONSTRAINTS E VALIDAÇÕES ADICIONAIS
-- ============================================
-- Adicionar check constraint para tp_dependencia
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'chk_tp_dependencia_valida'
    ) THEN
        ALTER TABLE public.instituicoes 
        ADD CONSTRAINT chk_tp_dependencia_valida 
        CHECK (tp_dependencia IS NULL OR tp_dependencia IN ('1', '2', '3', '4'));
    END IF;
END $$;

-- ============================================
-- 10. GRANT NECESSÁRIOS
-- ============================================
-- Garantir que authenticated pode executar funções de validação
GRANT EXECUTE ON FUNCTION public.validate_schema_access TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_user_session TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_rate_limit TO authenticated;

-- Garantir acesso às tabelas necessárias
GRANT SELECT ON public.role_categoria_denuncia TO authenticated;
GRANT SELECT ON public.schema_registry TO authenticated;

-- ============================================
-- VERIFICAÇÃO FINAL
-- ============================================
DO $$
DECLARE
    v_errors TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Verificar se RLS está habilitado
    IF EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'public' 
        AND tablename IN ('role_permissions', 'dashboard_access_log')
        AND rowsecurity = false
    ) THEN
        v_errors := array_append(v_errors, 'RLS não habilitado em todas as tabelas');
    END IF;
    
    -- Verificar se funções críticas existem
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'validate_schema_access'
    ) THEN
        v_errors := array_append(v_errors, 'Função validate_schema_access não criada');
    END IF;
    
    -- Reportar erros
    IF array_length(v_errors, 1) > 0 THEN
        RAISE WARNING 'Verificação de segurança falhou: %', array_to_string(v_errors, ', ');
    ELSE
        RAISE NOTICE 'Todas as correções de segurança aplicadas com sucesso!';
    END IF;
END $$;

-- ============================================
-- FIM DO SCRIPT DE CORREÇÕES DE SEGURANÇA
-- ============================================
