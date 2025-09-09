-- ============================================================================
-- TRIGGERS: regional_users_triggers
-- Descrição: Triggers para manter sincronização e auditoria
-- Autor: Solution Architect
-- Data: 2024-01-20
-- ============================================================================

-- ============================================================================
-- TRIGGER: sync_regional_user_status
-- Descrição: Sincroniza status entre regional_users e user_tenant_mapping
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sync_regional_user_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Se o status do usuário regional mudou
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        -- Atualizar todos os mapeamentos do usuário
        UPDATE public.user_tenant_mapping
        SET status = CASE 
            WHEN NEW.status = 'ACTIVE' THEN 'ATIVO'
            WHEN NEW.status = 'SUSPENDED' THEN 'SUSPENSO'
            WHEN NEW.status = 'INACTIVE' THEN 'INATIVO'
            ELSE status
        END,
        updated_at = NOW()
        WHERE user_id = NEW.auth_user_id;
        
        RAISE NOTICE 'Status sincronizado para user_id %: % mapeamentos atualizados', 
                     NEW.auth_user_id, ROW_COUNT();
    END IF;
    
    -- Se houve login, atualizar last_access em todos os mapeamentos
    IF OLD.last_login IS DISTINCT FROM NEW.last_login AND NEW.last_login IS NOT NULL THEN
        UPDATE public.user_tenant_mapping
        SET last_access = NEW.last_login
        WHERE user_id = NEW.auth_user_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_sync_regional_user_status
    AFTER UPDATE ON public.regional_users
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_regional_user_status();

COMMENT ON TRIGGER trigger_sync_regional_user_status ON public.regional_users 
IS 'Mantém sincronização de status com user_tenant_mapping';

-- ============================================================================
-- TRIGGER: check_password_change
-- Descrição: Monitora mudança de senha e limpa senha temporária
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_password_change()
RETURNS TRIGGER AS $$
DECLARE
    v_regional_user RECORD;
BEGIN
    -- Verificar se é um usuário regional
    SELECT * INTO v_regional_user
    FROM public.regional_users
    WHERE auth_user_id = NEW.id;
    
    IF FOUND THEN
        -- Se a senha foi alterada (encrypted_password mudou)
        IF OLD.encrypted_password IS DISTINCT FROM NEW.encrypted_password THEN
            -- Atualizar regional_users
            UPDATE public.regional_users
            SET password_changed = TRUE,
                password_change_date = NOW(),
                initial_password = NULL, -- Limpar senha temporária
                updated_at = NOW(),
                updated_by = NEW.id
            WHERE auth_user_id = NEW.id;
            
            RAISE NOTICE 'Senha alterada para usuário regional %', v_regional_user.email;
        END IF;
        
        -- Se houve login, atualizar last_login
        IF OLD.last_sign_in_at IS DISTINCT FROM NEW.last_sign_in_at THEN
            UPDATE public.regional_users
            SET last_login = NEW.last_sign_in_at
            WHERE auth_user_id = NEW.id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Este trigger deve ser criado no schema auth
CREATE TRIGGER trigger_check_password_change
    AFTER UPDATE ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.check_password_change();

COMMENT ON TRIGGER trigger_check_password_change ON auth.users 
IS 'Monitora mudanças de senha para usuários regionais';

-- ============================================================================
-- TRIGGER: audit_regional_user_changes
-- Descrição: Registra todas as alterações em regional_users
-- ============================================================================

-- Primeiro, criar tabela de auditoria
CREATE TABLE IF NOT EXISTS public.regional_users_audit (
    id SERIAL PRIMARY KEY,
    action VARCHAR(10) NOT NULL, -- INSERT, UPDATE, DELETE
    user_id UUID,
    changed_by UUID,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    old_data JSONB,
    new_data JSONB,
    ip_address INET,
    user_agent TEXT
);

CREATE INDEX idx_regional_users_audit_user_id ON public.regional_users_audit(user_id);
CREATE INDEX idx_regional_users_audit_changed_at ON public.regional_users_audit(changed_at);

-- Função de auditoria
CREATE OR REPLACE FUNCTION public.audit_regional_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    -- INSERT
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.regional_users_audit (
            action, user_id, changed_by, new_data
        ) VALUES (
            'INSERT', 
            NEW.auth_user_id, 
            COALESCE(NEW.created_by, auth.uid()),
            to_jsonb(NEW)
        );
        RETURN NEW;
    
    -- UPDATE
    ELSIF TG_OP = 'UPDATE' THEN
        -- Registrar apenas se houve mudança significativa
        IF OLD IS DISTINCT FROM NEW THEN
            INSERT INTO public.regional_users_audit (
                action, user_id, changed_by, old_data, new_data
            ) VALUES (
                'UPDATE', 
                NEW.auth_user_id, 
                COALESCE(NEW.updated_by, auth.uid()),
                to_jsonb(OLD),
                to_jsonb(NEW)
            );
        END IF;
        RETURN NEW;
    
    -- DELETE
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO public.regional_users_audit (
            action, user_id, changed_by, old_data
        ) VALUES (
            'DELETE', 
            OLD.auth_user_id, 
            auth.uid(),
            to_jsonb(OLD)
        );
        RETURN OLD;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_audit_regional_users
    AFTER INSERT OR UPDATE OR DELETE ON public.regional_users
    FOR EACH ROW
    EXECUTE FUNCTION public.audit_regional_user_changes();

COMMENT ON TRIGGER trigger_audit_regional_users ON public.regional_users 
IS 'Registra todas as alterações para auditoria';

-- ============================================================================
-- TRIGGER: validate_regional_user_insert
-- Descrição: Validações antes de inserir usuário regional
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_regional_user_insert()
RETURNS TRIGGER AS $$
BEGIN
    -- Validar email formato
    IF NEW.email !~* '^[A-Za-z0-9._%-]+@maxescolasegura\.com\.br$' THEN
        RAISE EXCEPTION 'Email deve terminar com @maxescolasegura.com.br';
    END IF;
    
    -- Validar combinação role/município
    IF NEW.role = 'SEC_EDUC_MUN' THEN
        IF NEW.co_municipio IS NULL OR NEW.no_municipio IS NULL THEN
            RAISE EXCEPTION 'SEC_EDUC_MUN requer código e nome do município';
        END IF;
    ELSIF NEW.role IN ('SEC_EDUC_EST', 'SEC_SEG_PUB') THEN
        IF NEW.co_municipio IS NOT NULL OR NEW.no_municipio IS NOT NULL THEN
            RAISE EXCEPTION '% não deve ter município associado', NEW.role;
        END IF;
    END IF;
    
    -- Validar UF
    IF length(NEW.co_uf) != 2 OR length(NEW.sg_uf) != 2 THEN
        RAISE EXCEPTION 'Códigos de UF devem ter 2 caracteres';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_regional_user_insert
    BEFORE INSERT ON public.regional_users
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_regional_user_insert();

COMMENT ON TRIGGER trigger_validate_regional_user_insert ON public.regional_users 
IS 'Validações de integridade antes de inserir';

-- ============================================================================
-- TRIGGER: auto_map_new_schools
-- Descrição: Mapeia automaticamente novas escolas para usuários regionais
-- ============================================================================
CREATE OR REPLACE FUNCTION public.auto_map_new_schools()
RETURNS TRIGGER AS $$
DECLARE
    v_rec RECORD;
    v_uf VARCHAR(2);
    v_municipio VARCHAR(7);
    v_tp_dependencia VARCHAR(1);
BEGIN
    -- Buscar dados da escola no registro_inep
    SELECT "CO_UF", "CO_MUNICIPIO", "TP_DEPENDENCIA"
    INTO v_uf, v_municipio, v_tp_dependencia
    FROM public.registro_inep
    WHERE "CO_ENTIDADE" = NEW.co_inep::text
    LIMIT 1;
    
    IF NOT FOUND THEN
        RAISE WARNING 'Escola % não encontrada no registro_inep', NEW.co_inep;
        RETURN NEW;
    END IF;
    
    -- Mapear para SEC_EDUC_MUN se escola municipal
    IF v_tp_dependencia = '3' AND v_municipio IS NOT NULL THEN
        FOR v_rec IN 
            SELECT ru.auth_user_id
            FROM public.regional_users ru
            WHERE ru.role = 'SEC_EDUC_MUN'
              AND ru.co_uf = v_uf
              AND ru.co_municipio = v_municipio
              AND ru.status = 'ACTIVE'
        LOOP
            INSERT INTO public.user_tenant_mapping (
                user_id, instituicao_id, schema_name, role, status, created_at
            ) VALUES (
                v_rec.auth_user_id, NEW.id, NEW.schema_name, 
                'SEC_EDUC_MUN', 'ATIVO', NOW()
            ) ON CONFLICT DO NOTHING;
        END LOOP;
    END IF;
    
    -- Mapear para SEC_EDUC_EST se escola estadual
    IF v_tp_dependencia = '2' THEN
        FOR v_rec IN 
            SELECT ru.auth_user_id
            FROM public.regional_users ru
            WHERE ru.role = 'SEC_EDUC_EST'
              AND ru.co_uf = v_uf
              AND ru.status = 'ACTIVE'
        LOOP
            INSERT INTO public.user_tenant_mapping (
                user_id, instituicao_id, schema_name, role, status, created_at
            ) VALUES (
                v_rec.auth_user_id, NEW.id, NEW.schema_name, 
                'SEC_EDUC_EST', 'ATIVO', NOW()
            ) ON CONFLICT DO NOTHING;
        END LOOP;
    END IF;
    
    -- Mapear para SEC_SEG_PUB (todas as escolas do estado)
    IF v_tp_dependencia IN ('2', '3') THEN
        FOR v_rec IN 
            SELECT ru.auth_user_id
            FROM public.regional_users ru
            WHERE ru.role = 'SEC_SEG_PUB'
              AND ru.co_uf = v_uf
              AND ru.status = 'ACTIVE'
        LOOP
            INSERT INTO public.user_tenant_mapping (
                user_id, instituicao_id, schema_name, role, status, created_at
            ) VALUES (
                v_rec.auth_user_id, NEW.id, NEW.schema_name, 
                'SEC_SEG_PUB', 'ATIVO', NOW()
            ) ON CONFLICT DO NOTHING;
        END LOOP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_auto_map_new_schools
    AFTER INSERT ON public.instituicoes
    FOR EACH ROW
    WHEN (NEW.schema_name IS NOT NULL)
    EXECUTE FUNCTION public.auto_map_new_schools();

COMMENT ON TRIGGER trigger_auto_map_new_schools ON public.instituicoes 
IS 'Mapeia automaticamente novas escolas para usuários regionais apropriados';

-- Permissões para tabela de auditoria
GRANT SELECT ON public.regional_users_audit TO authenticated;
GRANT ALL ON public.regional_users_audit TO service_role;
GRANT USAGE ON SEQUENCE public.regional_users_audit_id_seq TO service_role;

-- RLS para tabela de auditoria
ALTER TABLE public.regional_users_audit ENABLE ROW LEVEL SECURITY;

-- Policy: Apenas administradores podem ver logs de auditoria
CREATE POLICY "Admin view audit logs" ON public.regional_users_audit
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.regional_users
            WHERE auth_user_id = auth.uid()
              AND role IN ('ADMIN', 'SUPER_ADMIN')
        )
    );
