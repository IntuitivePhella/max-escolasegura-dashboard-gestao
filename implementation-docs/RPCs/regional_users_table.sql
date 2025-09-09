-- ============================================================================
-- TABELA: regional_users
-- Descrição: Controla usuários regionais (SEC_EDUC_MUN, SEC_EDUC_EST, SEC_SEG_PUB)
-- Autor: Solution Architect
-- Data: 2024-01-20
-- ============================================================================

-- Drop table if exists (com cuidado em produção)
DROP TABLE IF EXISTS public.regional_users CASCADE;

-- Criar tabela principal
CREATE TABLE public.regional_users (
    -- Identificação primária
    id SERIAL PRIMARY KEY,
    
    -- Credenciais
    email VARCHAR(255) UNIQUE NOT NULL,
    role VARCHAR(50) NOT NULL CHECK (role IN ('SEC_EDUC_MUN', 'SEC_EDUC_EST', 'SEC_SEG_PUB')),
    
    -- Dados geográficos
    co_uf VARCHAR(2) NOT NULL,
    sg_uf VARCHAR(2) NOT NULL,
    co_municipio VARCHAR(7), -- NULL para SEC_EDUC_EST e SEC_SEG_PUB
    no_municipio VARCHAR(255), -- NULL para SEC_EDUC_EST e SEC_SEG_PUB
    
    -- Referência ao auth.users
    auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Controle de senha
    initial_password VARCHAR(255), -- Armazenado temporariamente para comunicação inicial
    password_changed BOOLEAN DEFAULT FALSE,
    password_change_date TIMESTAMP WITH TIME ZONE,
    
    -- Status e auditoria
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACTIVE', 'SUSPENDED', 'INACTIVE')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_by UUID REFERENCES auth.users(id),
    last_login TIMESTAMP WITH TIME ZONE,
    
    -- Comunicação
    notification_sent BOOLEAN DEFAULT FALSE,
    notification_sent_at TIMESTAMP WITH TIME ZONE,
    notification_method VARCHAR(50), -- EMAIL, SMS, OFICIO
    
    -- Metadados
    metadata JSONB DEFAULT '{}',
    
    -- Constraints únicas para evitar duplicação
    CONSTRAINT unique_municipal_user UNIQUE(role, co_uf, co_municipio),
    
    -- Validações de integridade
    CONSTRAINT check_municipal_fields CHECK (
        (role = 'SEC_EDUC_MUN' AND co_municipio IS NOT NULL AND no_municipio IS NOT NULL) OR
        (role IN ('SEC_EDUC_EST', 'SEC_SEG_PUB') AND co_municipio IS NULL AND no_municipio IS NULL)
    ),
    
    -- Validação de formato email
    CONSTRAINT check_email_format CHECK (email ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]+$')
);

-- Comentários descritivos
COMMENT ON TABLE public.regional_users IS 'Tabela de controle para usuários regionais do sistema Max Escola Segura';
COMMENT ON COLUMN public.regional_users.id IS 'Identificador único sequencial';
COMMENT ON COLUMN public.regional_users.email IS 'Email de login do usuário (único no sistema)';
COMMENT ON COLUMN public.regional_users.role IS 'Tipo de usuário regional: SEC_EDUC_MUN (municipal), SEC_EDUC_EST (estadual), SEC_SEG_PUB (segurança pública)';
COMMENT ON COLUMN public.regional_users.co_uf IS 'Código IBGE do estado (2 dígitos)';
COMMENT ON COLUMN public.regional_users.sg_uf IS 'Sigla do estado (2 caracteres)';
COMMENT ON COLUMN public.regional_users.co_municipio IS 'Código IBGE do município (7 dígitos) - apenas para SEC_EDUC_MUN';
COMMENT ON COLUMN public.regional_users.no_municipio IS 'Nome do município - apenas para SEC_EDUC_MUN';
COMMENT ON COLUMN public.regional_users.auth_user_id IS 'Referência ao usuário criado no Supabase Auth';
COMMENT ON COLUMN public.regional_users.initial_password IS 'Senha temporária inicial (será limpa após primeiro login)';
COMMENT ON COLUMN public.regional_users.password_changed IS 'Indica se o usuário já trocou a senha inicial';
COMMENT ON COLUMN public.regional_users.status IS 'Status atual do usuário: PENDING (aguardando ativação), ACTIVE (ativo), SUSPENDED (suspenso), INACTIVE (inativo)';
COMMENT ON COLUMN public.regional_users.metadata IS 'Dados adicionais em formato JSON para extensibilidade futura';

-- Índices para performance
CREATE INDEX idx_regional_users_role ON public.regional_users(role);
CREATE INDEX idx_regional_users_co_uf ON public.regional_users(co_uf);
CREATE INDEX idx_regional_users_co_municipio ON public.regional_users(co_municipio) WHERE co_municipio IS NOT NULL;
CREATE INDEX idx_regional_users_status ON public.regional_users(status);
CREATE INDEX idx_regional_users_auth_user_id ON public.regional_users(auth_user_id);
CREATE INDEX idx_regional_users_email_lower ON public.regional_users(LOWER(email));

-- Trigger para atualizar updated_at
CREATE OR REPLACE FUNCTION public.update_regional_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_regional_users_updated_at
    BEFORE UPDATE ON public.regional_users
    FOR EACH ROW
    EXECUTE FUNCTION public.update_regional_users_updated_at();

-- Permissões básicas
GRANT SELECT ON public.regional_users TO authenticated;
GRANT ALL ON public.regional_users TO service_role;
GRANT USAGE ON SEQUENCE public.regional_users_id_seq TO service_role;

-- RLS (Row Level Security)
ALTER TABLE public.regional_users ENABLE ROW LEVEL SECURITY;

-- Policy: Usuários podem ver apenas seus próprios dados
CREATE POLICY "Users can view own data" ON public.regional_users
    FOR SELECT
    USING (auth.uid() = auth_user_id);

-- Policy: Apenas service_role pode inserir/atualizar/deletar
CREATE POLICY "Service role full access" ON public.regional_users
    FOR ALL
    USING (auth.jwt()->>'role' = 'service_role');

-- Estatísticas iniciais esperadas
-- SEC_EDUC_MUN: ~2.859 registros (1 por município com escolas)
-- SEC_EDUC_EST: 7 registros (1 por estado)
-- SEC_SEG_PUB: 7 registros (1 por estado)
-- Total estimado: ~2.873 registros
