-- ============================================================================
-- FUNÇÕES AUXILIARES: regional_user_helpers
-- Descrição: Funções de suporte para provisionamento de usuários regionais
-- Autor: Solution Architect
-- Data: 2024-01-20
-- ============================================================================

-- ============================================================================
-- FUNÇÃO: generate_secure_password
-- Descrição: Gera senha temporária segura seguindo padrão definido
-- ============================================================================
CREATE OR REPLACE FUNCTION public.generate_secure_password(
    p_role VARCHAR,
    p_co_uf VARCHAR,
    p_co_municipio VARCHAR DEFAULT NULL
) RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_prefix VARCHAR;
    v_random VARCHAR;
    v_password VARCHAR;
BEGIN
    -- Gerar 4 caracteres aleatórios hexadecimais
    v_random := substring(md5(random()::text) from 1 for 4);
    
    -- Construir senha baseada no role
    CASE p_role
        WHEN 'SEC_EDUC_MUN' THEN
            v_prefix := 'SecMun';
            v_password := v_prefix || p_co_municipio || '#' || v_random || '@MES2024';
        WHEN 'SEC_EDUC_EST' THEN
            v_prefix := 'SecEst';
            v_password := v_prefix || p_co_uf || '#' || v_random || '@MES2024';
        WHEN 'SEC_SEG_PUB' THEN
            v_prefix := 'SecSeg';
            v_password := v_prefix || p_co_uf || '#' || v_random || '@MES2024';
        ELSE
            RAISE EXCEPTION 'Role inválido: %', p_role;
    END CASE;
    
    RETURN v_password;
END;
$$;

COMMENT ON FUNCTION public.generate_secure_password IS 'Gera senha temporária segura para usuários regionais';

-- ============================================================================
-- FUNÇÃO: validate_regional_user_data
-- Descrição: Valida dados antes de criar usuário regional
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_regional_user_data(
    p_role VARCHAR,
    p_co_uf VARCHAR,
    p_co_municipio VARCHAR DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_exists BOOLEAN;
    v_escola_count INTEGER;
BEGIN
    -- Validar role
    IF p_role NOT IN ('SEC_EDUC_MUN', 'SEC_EDUC_EST', 'SEC_SEG_PUB') THEN
        RAISE EXCEPTION 'Role inválido: %', p_role;
    END IF;
    
    -- Validar UF existe
    SELECT EXISTS (
        SELECT 1 FROM public.registro_inep 
        WHERE "CO_UF" = p_co_uf
        LIMIT 1
    ) INTO v_exists;
    
    IF NOT v_exists THEN
        RAISE EXCEPTION 'UF não encontrado: %', p_co_uf;
    END IF;
    
    -- Para SEC_EDUC_MUN, validar município e verificar se tem escolas
    IF p_role = 'SEC_EDUC_MUN' THEN
        IF p_co_municipio IS NULL THEN
            RAISE EXCEPTION 'Código do município é obrigatório para SEC_EDUC_MUN';
        END IF;
        
        -- Verificar se município existe e tem escolas municipais
        SELECT COUNT(*) INTO v_escola_count
        FROM public.registro_inep
        WHERE "CO_UF" = p_co_uf
          AND "CO_MUNICIPIO" = p_co_municipio
          AND "TP_DEPENDENCIA" = '3'; -- Municipal
        
        IF v_escola_count = 0 THEN
            RAISE WARNING 'Município % não tem escolas municipais', p_co_municipio;
            RETURN FALSE;
        END IF;
    END IF;
    
    -- Verificar se usuário já existe
    SELECT EXISTS (
        SELECT 1 FROM public.regional_users
        WHERE role = p_role
          AND co_uf = p_co_uf
          AND (p_co_municipio IS NULL OR co_municipio = p_co_municipio)
    ) INTO v_exists;
    
    IF v_exists THEN
        RAISE WARNING 'Usuário regional já existe para role=%, uf=%, municipio=%', 
                      p_role, p_co_uf, p_co_municipio;
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.validate_regional_user_data IS 'Valida dados antes de criar usuário regional';

-- ============================================================================
-- FUNÇÃO: map_regional_user_access
-- Descrição: Mapeia acessos do usuário regional às escolas apropriadas
-- ============================================================================
CREATE OR REPLACE FUNCTION public.map_regional_user_access(
    p_user_id UUID,
    p_role VARCHAR,
    p_co_uf VARCHAR,
    p_co_municipio VARCHAR DEFAULT NULL
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_mapped_count INTEGER := 0;
    v_escola RECORD;
    v_instituicao RECORD;
BEGIN
    -- Validar parâmetros
    IF p_user_id IS NULL OR p_role IS NULL OR p_co_uf IS NULL THEN
        RAISE EXCEPTION 'Parâmetros obrigatórios não fornecidos';
    END IF;
    
    -- Mapear baseado no role
    CASE p_role
        WHEN 'SEC_EDUC_MUN' THEN
            -- Mapear todas as escolas municipais do município
            FOR v_escola IN
                SELECT DISTINCT ri."CO_ENTIDADE", i.id as instituicao_id, i.schema_name
                FROM public.registro_inep ri
                INNER JOIN public.instituicoes i ON i.co_inep::text = ri."CO_ENTIDADE"
                WHERE ri."CO_UF" = p_co_uf
                  AND ri."CO_MUNICIPIO" = p_co_municipio
                  AND ri."TP_DEPENDENCIA" = '3' -- Municipal
                  AND i.schema_name IS NOT NULL
            LOOP
                -- Inserir mapeamento
                INSERT INTO public.user_tenant_mapping (
                    user_id, instituicao_id, schema_name, role, status, created_at
                ) VALUES (
                    p_user_id, v_escola.instituicao_id, v_escola.schema_name, 
                    p_role, 'ATIVO', NOW()
                ) ON CONFLICT DO NOTHING;
                
                v_mapped_count := v_mapped_count + 1;
            END LOOP;
            
        WHEN 'SEC_EDUC_EST' THEN
            -- Mapear todas as escolas estaduais do estado
            FOR v_escola IN
                SELECT DISTINCT ri."CO_ENTIDADE", i.id as instituicao_id, i.schema_name
                FROM public.registro_inep ri
                INNER JOIN public.instituicoes i ON i.co_inep::text = ri."CO_ENTIDADE"
                WHERE ri."CO_UF" = p_co_uf
                  AND ri."TP_DEPENDENCIA" = '2' -- Estadual
                  AND i.schema_name IS NOT NULL
            LOOP
                INSERT INTO public.user_tenant_mapping (
                    user_id, instituicao_id, schema_name, role, status, created_at
                ) VALUES (
                    p_user_id, v_escola.instituicao_id, v_escola.schema_name, 
                    p_role, 'ATIVO', NOW()
                ) ON CONFLICT DO NOTHING;
                
                v_mapped_count := v_mapped_count + 1;
            END LOOP;
            
        WHEN 'SEC_SEG_PUB' THEN
            -- Mapear TODAS as escolas do estado (municipais e estaduais)
            FOR v_escola IN
                SELECT DISTINCT ri."CO_ENTIDADE", i.id as instituicao_id, i.schema_name
                FROM public.registro_inep ri
                INNER JOIN public.instituicoes i ON i.co_inep::text = ri."CO_ENTIDADE"
                WHERE ri."CO_UF" = p_co_uf
                  AND ri."TP_DEPENDENCIA" IN ('2', '3') -- Estadual e Municipal
                  AND i.schema_name IS NOT NULL
            LOOP
                INSERT INTO public.user_tenant_mapping (
                    user_id, instituicao_id, schema_name, role, status, created_at
                ) VALUES (
                    p_user_id, v_escola.instituicao_id, v_escola.schema_name, 
                    p_role, 'ATIVO', NOW()
                ) ON CONFLICT DO NOTHING;
                
                v_mapped_count := v_mapped_count + 1;
            END LOOP;
            
        ELSE
            RAISE EXCEPTION 'Role não suportado para mapeamento: %', p_role;
    END CASE;
    
    RETURN v_mapped_count;
END;
$$;

COMMENT ON FUNCTION public.map_regional_user_access IS 'Mapeia acessos do usuário regional às escolas apropriadas';

-- ============================================================================
-- FUNÇÃO: create_supabase_user
-- Descrição: Cria usuário no Supabase Auth (wrapper para facilitar)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_supabase_user(
    p_email VARCHAR,
    p_password VARCHAR,
    p_role VARCHAR,
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_encrypted_password TEXT;
    v_full_metadata JSONB;
BEGIN
    -- Construir metadata completo
    v_full_metadata := p_metadata || jsonb_build_object(
        'role', p_role,
        'created_by', 'provision_regional_users',
        'created_at', NOW()::text
    );
    
    -- Criptografar senha usando crypt do pgcrypto
    v_encrypted_password := crypt(p_password, gen_salt('bf'));
    
    -- Inserir usuário no auth.users
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        recovery_sent_at,
        last_sign_in_at,
        raw_user_meta_data,
        created_at,
        updated_at,
        confirmation_token,
        email_change,
        email_change_token_new,
        recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        LOWER(p_email),
        v_encrypted_password,
        NOW(), -- Email pré-confirmado
        NULL,
        NULL,
        v_full_metadata,
        NOW(),
        NOW(),
        encode(gen_random_bytes(32), 'hex'),
        NULL,
        NULL,
        NULL
    ) RETURNING id INTO v_user_id;
    
    -- Criar identidade
    INSERT INTO auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        gen_random_uuid(),
        v_user_id,
        jsonb_build_object('sub', v_user_id::text, 'email', LOWER(p_email)),
        'email',
        NOW(),
        NOW(),
        NOW()
    );
    
    RETURN v_user_id;
END;
$$;

COMMENT ON FUNCTION public.create_supabase_user IS 'Cria usuário no Supabase Auth de forma segura';

-- ============================================================================
-- FUNÇÃO: batch_progress_log
-- Descrição: Registra progresso do processamento em batch
-- ============================================================================
CREATE OR REPLACE FUNCTION public.batch_progress_log(
    p_batch_id UUID,
    p_total INTEGER,
    p_processed INTEGER,
    p_success INTEGER,
    p_errors INTEGER,
    p_message TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    -- Log simples no console (pode ser expandido para tabela de log)
    RAISE NOTICE 'Batch %: Processados % de % (Sucesso: %, Erros: %) - %', 
                 p_batch_id, p_processed, p_total, p_success, p_errors, 
                 COALESCE(p_message, 'Em progresso...');
END;
$$;

COMMENT ON FUNCTION public.batch_progress_log IS 'Registra progresso do processamento em batch';
