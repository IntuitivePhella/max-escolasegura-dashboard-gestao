-- ============================================
-- MIDDLEWARE HELPERS - FUNÇÕES PARA MIDDLEWARE
-- ============================================
-- Descrição: Funções auxiliares para o middleware Next.js
-- verificar roles e permissões dos usuários
-- 
-- ORDEM DE EXECUÇÃO: Execute após security-fixes.sql
-- ============================================

-- ============================================
-- 1. FUNÇÃO PARA BUSCAR INFORMAÇÕES DE ROLE DO USUÁRIO
-- ============================================
CREATE OR REPLACE FUNCTION public.get_user_role_info(
    p_user_id UUID
)
RETURNS TABLE (
    user_id UUID,
    email TEXT,
    role_type VARCHAR,
    uf_code VARCHAR,
    municipio_code VARCHAR,
    escola_code VARCHAR,
    allowed_schemas TEXT[],
    permissions JSONB,
    status VARCHAR
)
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_record RECORD;
    v_role_record RECORD;
    v_schemas TEXT[];
BEGIN
    -- Validação de entrada
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID não pode ser nulo';
    END IF;
    
    -- Buscar informações básicas do usuário
    SELECT 
        au.id,
        au.email
    INTO v_user_record
    FROM auth.users au
    WHERE au.id = p_user_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuário não encontrado: %', p_user_id;
    END IF;
    
    -- Buscar role e permissões do usuário
    SELECT 
        utm.schema_name,
        utm.status as mapping_status,
        rp.role_type,
        rp.uf_code,
        rp.municipio_code,
        rp.escola_code,
        rp.permissions
    INTO v_role_record
    FROM public.user_tenant_mapping utm
    LEFT JOIN public.role_permissions rp ON utm.special_role_id = rp.id
    WHERE utm.user_id = p_user_id
    AND utm.status = 'ATIVO'
    LIMIT 1;
    
    -- Se não encontrou role especial, verificar se é DIRETORIA
    IF NOT FOUND THEN
        SELECT 
            utm.schema_name,
            utm.status as mapping_status,
            'DIRETORIA' as role_type,
            NULL as uf_code,
            NULL as municipio_code,
            NULL as escola_code,
            '{}'::JSONB as permissions
        INTO v_role_record
        FROM public.user_tenant_mapping utm
        WHERE utm.user_id = p_user_id
        AND utm.status = 'ATIVO'
        AND utm.special_role_id IS NULL
        LIMIT 1;
    END IF;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuário sem mapeamento de tenant ativo: %', p_user_id;
    END IF;
    
    -- Buscar todos os schemas permitidos para o usuário
    IF v_role_record.role_type = 'DIRETORIA' THEN
        -- DIRETORIA: apenas seu schema
        SELECT ARRAY[utm.schema_name]
        INTO v_schemas
        FROM public.user_tenant_mapping utm
        WHERE utm.user_id = p_user_id 
        AND utm.status = 'ATIVO';
        
    ELSIF v_role_record.role_type = 'SEC_EDUC_MUN' THEN
        -- SEC_EDUC_MUN: escolas municipais do município
        SELECT ARRAY_AGG(DISTINCT i.schema_name)
        INTO v_schemas
        FROM public.instituicoes i
        WHERE i.co_municipio = v_role_record.municipio_code
        AND i.tp_dependencia = '3' -- Municipal
        AND i.status = 'ATIVO';
        
    ELSIF v_role_record.role_type = 'SEC_EDUC_EST' THEN
        -- SEC_EDUC_EST: escolas estaduais do estado
        SELECT ARRAY_AGG(DISTINCT i.schema_name)
        INTO v_schemas
        FROM public.instituicoes i
        WHERE i.co_uf = v_role_record.uf_code
        AND i.tp_dependencia = '2' -- Estadual
        AND i.status = 'ATIVO';
        
    ELSIF v_role_record.role_type = 'SEC_SEG_PUB' THEN
        -- SEC_SEG_PUB: todas as escolas do estado (municipais + estaduais)
        SELECT ARRAY_AGG(DISTINCT i.schema_name)
        INTO v_schemas
        FROM public.instituicoes i
        WHERE i.co_uf = v_role_record.uf_code
        AND i.tp_dependencia IN ('2', '3') -- Estadual + Municipal
        AND i.status = 'ATIVO';
        
    ELSE
        -- Role não reconhecido
        v_schemas := ARRAY[]::TEXT[];
    END IF;
    
    -- Garantir que schemas não seja nulo
    IF v_schemas IS NULL THEN
        v_schemas := ARRAY[]::TEXT[];
    END IF;
    
    -- Retornar informações do usuário
    RETURN QUERY SELECT
        p_user_id,
        v_user_record.email,
        v_role_record.role_type,
        v_role_record.uf_code,
        v_role_record.municipio_code,
        v_role_record.escola_code,
        v_schemas,
        v_role_record.permissions,
        v_role_record.mapping_status;
        
EXCEPTION
    WHEN OTHERS THEN
        -- Log do erro para debugging
        RAISE WARNING 'Erro em get_user_role_info para usuário %: %', p_user_id, SQLERRM;
        
        -- Retornar informações básicas em caso de erro
        RETURN QUERY SELECT
            p_user_id,
            v_user_record.email,
            'UNKNOWN'::VARCHAR,
            NULL::VARCHAR,
            NULL::VARCHAR, 
            NULL::VARCHAR,
            ARRAY[]::TEXT[],
            '{}'::JSONB,
            'ERROR'::VARCHAR;
END;
$$;

-- Adicionar comentários
COMMENT ON FUNCTION public.get_user_role_info(UUID) IS 'Busca informações completas de role e permissões do usuário para uso no middleware';

-- ============================================
-- 2. FUNÇÃO PARA VERIFICAR PERMISSÃO DE ROTA
-- ============================================
CREATE OR REPLACE FUNCTION public.check_route_permission(
    p_user_id UUID,
    p_route TEXT
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_info RECORD;
    v_allowed_routes TEXT[];
BEGIN
    -- Buscar informações do usuário
    SELECT * INTO v_user_info
    FROM public.get_user_role_info(p_user_id)
    LIMIT 1;
    
    IF NOT FOUND OR v_user_info.status != 'ATIVO' THEN
        RETURN FALSE;
    END IF;
    
    -- Definir rotas permitidas por role
    CASE v_user_info.role_type
        WHEN 'DIRETORIA' THEN
            v_allowed_routes := ARRAY[
                '/dashboard',
                '/api/dashboard/presence',
                '/api/dashboard/complaints',
                '/api/dashboard/emotional',
                '/api/v1/dashboard/summary',
                '/api/v1/dashboard/events',
                '/api/v1/dashboard/schemas'
            ];
        WHEN 'SEC_EDUC_MUN' THEN
            v_allowed_routes := ARRAY[
                '/dashboard',
                '/api/dashboard/presence',
                '/api/dashboard/complaints',
                '/api/dashboard/emotional',
                '/api/v1/dashboard/summary',
                '/api/v1/dashboard/events',
                '/api/v1/dashboard/schemas'
            ];
        WHEN 'SEC_EDUC_EST' THEN
            v_allowed_routes := ARRAY[
                '/dashboard',
                '/api/dashboard/presence',
                '/api/dashboard/complaints',
                '/api/dashboard/emotional',
                '/api/v1/dashboard/summary',
                '/api/v1/dashboard/events',
                '/api/v1/dashboard/schemas'
            ];
        WHEN 'SEC_SEG_PUB' THEN
            v_allowed_routes := ARRAY[
                '/dashboard',
                '/api/dashboard/security',
                '/api/v1/dashboard/summary',
                '/api/v1/dashboard/alerts',
                '/api/v1/dashboard/schemas'
            ];
        ELSE
            RETURN FALSE;
    END CASE;
    
    -- Verificar se a rota está permitida
    RETURN EXISTS (
        SELECT 1 
        FROM unnest(v_allowed_routes) AS allowed_route
        WHERE p_route = allowed_route 
        OR p_route LIKE allowed_route || '/%'
    );
    
END;
$$;

-- Adicionar comentários
COMMENT ON FUNCTION public.check_route_permission(UUID, TEXT) IS 'Verifica se usuário tem permissão para acessar rota específica';

-- ============================================
-- 3. FUNÇÃO PARA RATE LIMITING (OPCIONAL)
-- ============================================
CREATE TABLE IF NOT EXISTS public.rate_limit_log (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    endpoint TEXT NOT NULL,
    request_count INTEGER DEFAULT 1,
    window_start TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_rate_limit_user_endpoint 
    ON public.rate_limit_log(user_id, endpoint);
    
CREATE INDEX IF NOT EXISTS idx_rate_limit_window 
    ON public.rate_limit_log(window_start);

-- Habilitar RLS
ALTER TABLE public.rate_limit_log ENABLE ROW LEVEL SECURITY;

-- Política de RLS - apenas sistema pode acessar
CREATE POLICY rate_limit_system_only ON public.rate_limit_log
    FOR ALL USING (false); -- Nenhum usuário pode acessar diretamente

-- Função para verificar rate limit
CREATE OR REPLACE FUNCTION public.check_rate_limit(
    p_user_id UUID,
    p_endpoint TEXT,
    p_max_requests INTEGER DEFAULT 100,
    p_window_minutes INTEGER DEFAULT 1
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_window_start TIMESTAMPTZ;
    v_current_count INTEGER;
BEGIN
    -- Calcular início da janela atual
    v_window_start := date_trunc('minute', NOW()) - (EXTRACT(minute FROM NOW())::INTEGER % p_window_minutes) * INTERVAL '1 minute';
    
    -- Buscar ou criar registro da janela atual
    SELECT request_count INTO v_current_count
    FROM public.rate_limit_log
    WHERE user_id = p_user_id
    AND endpoint = p_endpoint
    AND window_start = v_window_start;
    
    IF FOUND THEN
        -- Atualizar contador existente
        IF v_current_count >= p_max_requests THEN
            RETURN FALSE; -- Rate limit excedido
        END IF;
        
        UPDATE public.rate_limit_log
        SET request_count = request_count + 1,
            updated_at = NOW()
        WHERE user_id = p_user_id
        AND endpoint = p_endpoint
        AND window_start = v_window_start;
    ELSE
        -- Criar novo registro
        INSERT INTO public.rate_limit_log (user_id, endpoint, window_start)
        VALUES (p_user_id, p_endpoint, v_window_start);
    END IF;
    
    -- Limpar registros antigos (mais de 24h)
    DELETE FROM public.rate_limit_log
    WHERE window_start < NOW() - INTERVAL '24 hours';
    
    RETURN TRUE;
    
END;
$$;

-- Adicionar comentários
COMMENT ON FUNCTION public.check_rate_limit(UUID, TEXT, INTEGER, INTEGER) IS 'Verifica e controla rate limiting por usuário e endpoint';

-- ============================================
-- 4. GRANTS E PERMISSÕES
-- ============================================

-- Permitir execução das funções para usuários autenticados
GRANT EXECUTE ON FUNCTION public.get_user_role_info(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_route_permission(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- Comentários finais
COMMENT ON TABLE public.rate_limit_log IS 'Log de rate limiting por usuário e endpoint';
