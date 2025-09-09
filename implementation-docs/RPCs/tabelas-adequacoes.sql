-- ============================================
-- SQL 01 - CRIAÇÃO DE TABELAS DE CONTROLE DE ACESSO
-- ============================================
-- Descrição: Cria as tabelas necessárias para o controle de acesso
-- baseado em roles (DIRETORIA, SEC_EDUC_MUN, SEC_EDUC_EST, SEC_SEG_PUB)
-- 
-- ORDEM DE EXECUÇÃO: Execute security-fixes.sql ANTES deste arquivo
-- ============================================

-- 1. Criar tabela de permissões por role
-- ============================================
CREATE TABLE IF NOT EXISTS public.role_permissions (
    id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) NOT NULL UNIQUE,
    role_type VARCHAR(20) NOT NULL CHECK (
        role_type IN ('DIRETORIA', 'SEC_EDUC_MUN', 'SEC_EDUC_EST', 'SEC_SEG_PUB')
    ),
    uf_code VARCHAR(2), -- Código do estado (ex: '35' para SP)
    municipio_code VARCHAR(10), -- Código do município IBGE
    escola_code VARCHAR(20), -- Código INEP da escola
    permissions JSONB DEFAULT '{}', -- Permissões específicas em JSON
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- SEGURANÇA: Habilitar Row Level Security
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

-- Adicionar comentários para documentação
COMMENT ON TABLE public.role_permissions IS 'Tabela de controle de roles especiais para dashboard';
COMMENT ON COLUMN public.role_permissions.role_type IS 'Tipo do role: DIRETORIA, SEC_EDUC_MUN, SEC_EDUC_EST, SEC_SEG_PUB';
COMMENT ON COLUMN public.role_permissions.uf_code IS 'Código IBGE do estado (2 dígitos)';
COMMENT ON COLUMN public.role_permissions.municipio_code IS 'Código IBGE do município (7 dígitos)';
COMMENT ON COLUMN public.role_permissions.escola_code IS 'Código INEP da escola (8 dígitos)';
COMMENT ON COLUMN public.role_permissions.permissions IS 'JSON com permissões específicas do role';

-- 2. Criar índices para otimização
-- ============================================
CREATE INDEX IF NOT EXISTS idx_role_permissions_type 
    ON public.role_permissions(role_type);

CREATE INDEX IF NOT EXISTS idx_role_permissions_uf 
    ON public.role_permissions(uf_code) 
    WHERE uf_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_role_permissions_municipio 
    ON public.role_permissions(municipio_code) 
    WHERE municipio_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_role_permissions_escola 
    ON public.role_permissions(escola_code) 
    WHERE escola_code IS NOT NULL;

-- 3. Estender tabela user_tenant_mapping
-- ============================================
-- Verificar se as colunas já existem antes de adicionar
DO $$
BEGIN
    -- Adicionar special_role_id se não existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'user_tenant_mapping'
        AND column_name = 'special_role_id'
    ) THEN
        ALTER TABLE public.user_tenant_mapping 
        ADD COLUMN special_role_id INTEGER REFERENCES public.role_permissions(id);
    END IF;
    
    -- Adicionar access_scope se não existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'user_tenant_mapping'
        AND column_name = 'access_scope'
    ) THEN
ALTER TABLE public.user_tenant_mapping 
        ADD COLUMN access_scope JSONB DEFAULT '{}';
    END IF;
END $$;

-- Adicionar comentários
COMMENT ON COLUMN public.user_tenant_mapping.special_role_id IS 'ID do role especial (se aplicável)';
COMMENT ON COLUMN public.user_tenant_mapping.access_scope IS 'Escopo de acesso adicional em JSON';

-- Criar índice para performance
CREATE INDEX IF NOT EXISTS idx_user_tenant_special_role 
    ON public.user_tenant_mapping(special_role_id) 
    WHERE special_role_id IS NOT NULL;

-- ÍNDICES CRÍTICOS DE PERFORMANCE (identificados pelo QA)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_tenant_mapping_user_status 
    ON public.user_tenant_mapping(user_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_tenant_special 
    ON public.user_tenant_mapping(special_role_id, user_id, status) 
    WHERE special_role_id IS NOT NULL;

-- 4. Adicionar metadados às instituições
-- ============================================
-- Verificar se as colunas já existem antes de adicionar
DO $$
BEGIN
    -- Adicionar co_uf se não existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'instituicoes'
        AND column_name = 'co_uf'
    ) THEN
        ALTER TABLE public.instituicoes
        ADD COLUMN co_uf VARCHAR(2);
    END IF;
    
    -- Adicionar co_municipio se não existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'instituicoes'
        AND column_name = 'co_municipio'
    ) THEN
        ALTER TABLE public.instituicoes
        ADD COLUMN co_municipio VARCHAR(10);
    END IF;
    
    -- Adicionar tp_dependencia se não existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'instituicoes'
        AND column_name = 'tp_dependencia'
    ) THEN
        ALTER TABLE public.instituicoes
        ADD COLUMN tp_dependencia VARCHAR(1);
    END IF;
    
    -- Adicionar constraint para tp_dependencia se não existir
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'chk_tp_dependencia_valida'
    ) THEN
ALTER TABLE public.instituicoes
        ADD CONSTRAINT chk_tp_dependencia_valida 
        CHECK (tp_dependencia IS NULL OR tp_dependencia IN ('1', '2', '3', '4'));
    END IF;
END $$;

-- Adicionar comentários
COMMENT ON COLUMN public.instituicoes.co_uf IS 'Código IBGE do estado';
COMMENT ON COLUMN public.instituicoes.co_municipio IS 'Código IBGE do município';
COMMENT ON COLUMN public.instituicoes.tp_dependencia IS 'Tipo de dependência: 1=Federal, 2=Estadual, 3=Municipal, 4=Privada';

-- Criar índices para consultas por localização
CREATE INDEX IF NOT EXISTS idx_instituicoes_uf 
    ON public.instituicoes(co_uf) 
    WHERE co_uf IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_instituicoes_municipio 
    ON public.instituicoes(co_municipio) 
    WHERE co_municipio IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_instituicoes_dependencia 
    ON public.instituicoes(tp_dependencia) 
    WHERE tp_dependencia IS NOT NULL;

-- Índice composto para consultas frequentes
CREATE INDEX IF NOT EXISTS idx_instituicoes_uf_municipio_dep 
    ON public.instituicoes(co_uf, co_municipio, tp_dependencia) 
    WHERE co_uf IS NOT NULL AND co_municipio IS NOT NULL;

-- ÍNDICE CRÍTICO DE PERFORMANCE (identificado pelo QA)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instituicoes_composite 
    ON public.instituicoes(co_uf, co_municipio, tp_dependencia, "ID")
    WHERE co_uf IS NOT NULL;

-- 5. Popular dados de localização das instituições usando registro_inep
-- ============================================
-- CORREÇÃO: Adicionar CAST explícito para compatibilidade de tipos
UPDATE public.instituicoes i
SET 
    co_uf = r."CO_UF"::VARCHAR(2),
    co_municipio = r."CO_MUNICIPIO"::VARCHAR(10),
    tp_dependencia = r."TP_DEPENDENCIA"::VARCHAR(1)
FROM public.registro_inep r
WHERE i."Codigo_INEP" = r."CO_ENTIDADE"
AND i.co_uf IS NULL;

-- 6. Criar tabela de auditoria para acessos ao dashboard
-- ============================================
CREATE TABLE IF NOT EXISTS public.dashboard_access_log (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    role_type VARCHAR(20),
    accessed_at TIMESTAMPTZ DEFAULT NOW(),
    indicator_type VARCHAR(50),
    schemas_accessed TEXT[],
    ip_address INET,
    user_agent TEXT,
    response_time_ms INTEGER,
    success BOOLEAN DEFAULT TRUE,
    error_message TEXT,
    -- Campos adicionais para debugging (recomendados pelo QA)
    request_params JSONB,
    endpoint VARCHAR(100),
    http_method VARCHAR(10)
);

-- SEGURANÇA: Habilitar Row Level Security
ALTER TABLE public.dashboard_access_log ENABLE ROW LEVEL SECURITY;

-- Índices para análise de logs
CREATE INDEX IF NOT EXISTS idx_dashboard_access_user 
    ON public.dashboard_access_log(user_id);

CREATE INDEX IF NOT EXISTS idx_dashboard_access_date 
    ON public.dashboard_access_log(accessed_at DESC);

CREATE INDEX IF NOT EXISTS idx_dashboard_access_role 
    ON public.dashboard_access_log(role_type) 
    WHERE role_type IS NOT NULL;

-- ÍNDICE CRÍTICO para limpeza de logs antigos
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dashboard_log_date 
    ON public.dashboard_access_log(accessed_at DESC);

-- 7. Criar função para atualizar updated_at automaticamente
-- ============================================
-- CORREÇÃO: Verificar se função já existe antes de criar
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'update_updated_at_column'
        AND pronamespace = 'public'::regnamespace
    ) THEN
        CREATE FUNCTION public.update_updated_at_column()
        RETURNS TRIGGER AS $func$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
        $func$ LANGUAGE plpgsql;
    END IF;
END $$;

-- Aplicar trigger na tabela role_permissions
DROP TRIGGER IF EXISTS update_role_permissions_updated_at ON public.role_permissions;
CREATE TRIGGER update_role_permissions_updated_at
    BEFORE UPDATE ON public.role_permissions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 8. Criar tabela de categorias por role (remove hardcode)
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

-- SEGURANÇA: Habilitar Row Level Security
ALTER TABLE public.role_categoria_denuncia ENABLE ROW LEVEL SECURITY;

-- Política: Apenas leitura para authenticated
CREATE POLICY IF NOT EXISTS role_categoria_read ON public.role_categoria_denuncia
    FOR SELECT 
    TO authenticated
    USING (ativo = true);

-- Popular categorias iniciais
INSERT INTO public.role_categoria_denuncia (role_type, categoria) VALUES
    -- DIRETORIA e SEC_EDUC_* veem categorias educacionais
    ('DIRETORIA', 'bullying'),
    ('DIRETORIA', 'infraestrutura'),
    ('DIRETORIA', 'outros'),
    ('SEC_EDUC_MUN', 'bullying'),
    ('SEC_EDUC_MUN', 'infraestrutura'),
    ('SEC_EDUC_MUN', 'outros'),
    ('SEC_EDUC_EST', 'bullying'),
    ('SEC_EDUC_EST', 'infraestrutura'),
    ('SEC_EDUC_EST', 'outros'),
    -- SEC_SEG_PUB vê apenas categorias de segurança
    ('SEC_SEG_PUB', 'tráfico'),
    ('SEC_SEG_PUB', 'assedio'),
    ('SEC_SEG_PUB', 'discriminacao'),
    ('SEC_SEG_PUB', 'violencia')
ON CONFLICT (role_type, categoria) DO NOTHING;

-- 9. Inserir dados de exemplo para testes
-- ============================================
-- Exemplo de DIRETORIA
INSERT INTO public.role_permissions (
    role_name, 
    role_type, 
    escola_code, 
    permissions
) VALUES (
    'dir_escola_42145490',
    'DIRETORIA',
    '42145490',
    '{"indicators": ["presenca", "denuncias", "sentimento"], "can_export": true}'::jsonb
) ON CONFLICT (role_name) DO NOTHING;

-- Exemplo de SEC_EDUC_MUN
INSERT INTO public.role_permissions (
    role_name,
    role_type,
    municipio_code,
    permissions
) VALUES (
    'sec_mun_3550308', -- São Paulo
    'SEC_EDUC_MUN',
    '3550308',
    '{"indicators": ["presenca", "denuncias", "sentimento"], "can_export": true, "can_compare": true}'::jsonb
) ON CONFLICT (role_name) DO NOTHING;

-- Exemplo de SEC_EDUC_EST
INSERT INTO public.role_permissions (
    role_name,
    role_type,
    uf_code,
    permissions
) VALUES (
    'sec_est_35', -- Estado de SP
    'SEC_EDUC_EST',
    '35',
    '{"indicators": ["presenca", "denuncias", "sentimento"], "can_export": true, "can_compare": true}'::jsonb
) ON CONFLICT (role_name) DO NOTHING;

-- Exemplo de SEC_SEG_PUB
INSERT INTO public.role_permissions (
    role_name,
    role_type,
    uf_code,
    permissions
) VALUES (
    'sec_seg_35', -- Segurança Pública SP
    'SEC_SEG_PUB',
    '35',
    '{"indicators": ["denuncias"], "categories": ["trafico", "assedio", "discriminacao", "violencia"], "can_export": true}'::jsonb
) ON CONFLICT (role_name) DO NOTHING;

-- 10. Criar view para facilitar consultas de permissões
-- ============================================
CREATE OR REPLACE VIEW public.v_user_permissions AS
SELECT 
    utm.user_id,
    utm.schema_name,
    utm.role as basic_role,
    rp.role_type as special_role,
    rp.uf_code,
    rp.municipio_code,
    rp.escola_code,
    rp.permissions,
    utm.status,
    i."Nome_Fantasia" as escola_nome,
    i."Codigo_INEP" as codigo_inep
FROM public.user_tenant_mapping utm
LEFT JOIN public.role_permissions rp ON utm.special_role_id = rp.id
LEFT JOIN public.schema_registry sr ON utm.schema_name = sr.schema_name
LEFT JOIN public.instituicoes i ON sr.instituicao_id = i."ID"
WHERE utm.status = 'ATIVO';

-- Conceder permissões necessárias
GRANT SELECT ON public.v_user_permissions TO authenticated;

-- 11. Criar função helper para obter role do usuário atual
-- ============================================
CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS TABLE (
    role_type VARCHAR,
    uf_code VARCHAR,
    municipio_code VARCHAR,
    escola_code VARCHAR,
    permissions JSONB
) 
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rp.role_type,
        rp.uf_code,
        rp.municipio_code,
        rp.escola_code,
        rp.permissions
    FROM public.user_tenant_mapping utm
    LEFT JOIN public.role_permissions rp ON utm.special_role_id = rp.id
    WHERE utm.user_id = auth.uid()
    AND utm.status = 'ATIVO'
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Conceder execução para usuários autenticados
GRANT EXECUTE ON FUNCTION public.get_current_user_role() TO authenticated;

-- 12. Criar políticas RLS (SEGURANÇA CRÍTICA)
-- ============================================
-- Políticas para role_permissions
CREATE POLICY IF NOT EXISTS role_permissions_admin_all ON public.role_permissions
    FOR ALL 
    TO postgres
    USING (true)
    WITH CHECK (true);

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

-- Políticas para dashboard_access_log
CREATE POLICY IF NOT EXISTS dashboard_log_insert_own ON public.dashboard_access_log
    FOR INSERT 
    TO authenticated
    WITH CHECK (user_id = auth.uid());

CREATE POLICY IF NOT EXISTS dashboard_log_admin_select ON public.dashboard_access_log
    FOR SELECT 
    TO postgres
    USING (true);

CREATE POLICY IF NOT EXISTS dashboard_log_select_own ON public.dashboard_access_log
    FOR SELECT 
    TO authenticated
    USING (user_id = auth.uid());

-- Criar índice para schema_registry (crítico para performance)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_schema_registry_status 
    ON public.schema_registry(status, schema_name)
    WHERE status = 'ATIVO';

-- ============================================
-- FIM DO SCRIPT SQL 01
-- ============================================