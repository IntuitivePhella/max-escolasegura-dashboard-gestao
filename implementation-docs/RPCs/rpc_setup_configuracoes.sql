-- ============================================
-- SQL 05 - SCRIPT DE SETUP E CONFIGURAÇÃO COMPLETA
-- ============================================
-- Descrição: Script para configuração inicial do sistema de dashboards
-- Inclui criação de roles, usuários de teste e triggers em schemas
--
-- IMPORTANTE: Execute security-fixes.sql e tabelas-adequacoes.sql ANTES
-- ============================================

-- 1. Função para setup completo de um novo schema de escola
-- ============================================
CREATE OR REPLACE FUNCTION public.setup_escola_dashboard(
    p_schema_name TEXT,
    p_instituicao_id INTEGER
)
RETURNS VOID AS $$
BEGIN
    -- SEGURANÇA: Validar schema
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.schemata 
        WHERE schema_name = p_schema_name
    ) THEN
        RAISE EXCEPTION 'Schema % não existe', p_schema_name;
    END IF;
    
    -- Validar se schema segue padrão
    IF p_schema_name !~ '^escola_[0-9]{8}$' THEN
        RAISE EXCEPTION 'Schema % não segue padrão escola_XXXXXXXX', p_schema_name;
    END IF;
    
    -- Aplicar triggers de notificação
    BEGIN
    PERFORM public.setup_presenca_trigger(p_schema_name);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Erro ao criar trigger de presença: %', SQLERRM;
    END;
    
    BEGIN
    PERFORM public.setup_denuncias_trigger(p_schema_name);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Erro ao criar trigger de denúncias: %', SQLERRM;
    END;
    
    BEGIN
    PERFORM public.setup_sentimento_trigger(p_schema_name);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Erro ao criar trigger de sentimento: %', SQLERRM;
    END;
    
    -- Registrar no log
    INSERT INTO public.tenant_operation_log (
        operation_type,
        schema_name,
        instituicao_id,
        user_id,
        status,
        details,
        started_at,
        completed_at
    ) VALUES (
        'SETUP_DASHBOARD',
        p_schema_name,
        p_instituicao_id,
        auth.uid(),
        'SUCCESS',
        jsonb_build_object(
            'triggers_created', ARRAY['presenca', 'denuncias', 'sentimento'],
            'setup_version', '2.0'
        ),
        NOW(),
        NOW()
    );
    
    RAISE NOTICE 'Dashboard setup concluído para schema %', p_schema_name;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.setup_escola_dashboard(TEXT, INTEGER) TO postgres;

-- 2. Criar roles de exemplo para cada tipo
-- ============================================
CREATE OR REPLACE FUNCTION public.create_sample_roles()
RETURNS VOID AS $$
DECLARE
    v_escola_code VARCHAR;
    v_municipio_code VARCHAR;
    v_uf_code VARCHAR;
    v_count INTEGER;
BEGIN
    -- Verificar se já existem roles de exemplo
    SELECT COUNT(*) INTO v_count
    FROM public.role_permissions
    WHERE role_name LIKE '%_exemplo';
    
    IF v_count > 0 THEN
        RAISE NOTICE 'Roles de exemplo já existem';
        RETURN;
    END IF;
    
    -- Obter dados de uma escola real para exemplo
    SELECT 
        i."Codigo_INEP",
        i.co_municipio,
        i.co_uf
    INTO v_escola_code, v_municipio_code, v_uf_code
    FROM public.instituicoes i
    WHERE i.co_uf IS NOT NULL
    AND i.co_municipio IS NOT NULL
    LIMIT 1;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Nenhuma instituição encontrada com dados completos';
    END IF;
    
    -- Criar role DIRETORIA
    INSERT INTO public.role_permissions (
        role_name,
        role_type,
        escola_code,
        permissions
    ) VALUES (
        'diretoria_exemplo',
        'DIRETORIA',
        v_escola_code,
        jsonb_build_object(
            'indicators', ARRAY['presenca', 'denuncias', 'sentimento'],
            'can_export', true,
            'can_print', true,
            'max_date_range_days', 365,
            'dashboard_version', '2.0'
        )
    ) ON CONFLICT (role_name) DO UPDATE
    SET permissions = EXCLUDED.permissions,
        updated_at = NOW();
    
    -- Criar role SEC_EDUC_MUN
    INSERT INTO public.role_permissions (
        role_name,
        role_type,
        municipio_code,
        permissions
    ) VALUES (
        'sec_educ_mun_exemplo',
        'SEC_EDUC_MUN',
        v_municipio_code,
        jsonb_build_object(
            'indicators', ARRAY['presenca', 'denuncias', 'sentimento'],
            'can_export', true,
            'can_compare_schools', true,
            'can_aggregate_data', true,
            'max_date_range_days', 365,
            'max_schools_view', 50
        )
    ) ON CONFLICT (role_name) DO UPDATE
    SET permissions = EXCLUDED.permissions,
        updated_at = NOW();
    
    -- Criar role SEC_EDUC_EST
    INSERT INTO public.role_permissions (
        role_name,
        role_type,
        uf_code,
        permissions
    ) VALUES (
        'sec_educ_est_exemplo',
        'SEC_EDUC_EST',
        v_uf_code,
        jsonb_build_object(
            'indicators', ARRAY['presenca', 'denuncias', 'sentimento'],
            'can_export', true,
            'can_compare_schools', true,
            'can_aggregate_data', true,
            'can_view_trends', true,
            'max_date_range_days', 730,
            'max_schools_view', 200
        )
    ) ON CONFLICT (role_name) DO UPDATE
    SET permissions = EXCLUDED.permissions,
        updated_at = NOW();
    
    -- Criar role SEC_SEG_PUB
    INSERT INTO public.role_permissions (
        role_name,
        role_type,
        uf_code,
        permissions
    ) VALUES (
        'sec_seg_pub_exemplo',
        'SEC_SEG_PUB',
        v_uf_code,
        jsonb_build_object(
            'indicators', ARRAY['denuncias'],
            'categories', ARRAY['tráfico', 'assedio', 'discriminacao', 'violencia'],
            'can_export', true,
            'can_view_details', false,
            'anonymous_only', true,
            'max_date_range_days', 180
        )
    ) ON CONFLICT (role_name) DO UPDATE
    SET permissions = EXCLUDED.permissions,
        updated_at = NOW();
    
    RAISE NOTICE 'Roles de exemplo criados com sucesso';
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.create_sample_roles() TO postgres;

-- 3. Função para atribuir role a um usuário
-- ============================================
CREATE OR REPLACE FUNCTION public.assign_user_role(
    p_user_email TEXT,
    p_role_name TEXT
)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
    v_role_id INTEGER;
    v_current_mapping RECORD;
BEGIN
    -- Validar email
    IF p_user_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$' THEN
        RAISE EXCEPTION 'Email inválido: %', p_user_email;
    END IF;
    
    -- Buscar user_id pelo email
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = lower(p_user_email);
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Usuário com email % não encontrado', p_user_email;
    END IF;
    
    -- Buscar role_id
    SELECT id INTO v_role_id
    FROM public.role_permissions
    WHERE role_name = p_role_name;
    
    IF v_role_id IS NULL THEN
        RAISE EXCEPTION 'Role % não encontrado', p_role_name;
    END IF;
    
    -- Buscar mapping atual
    SELECT * INTO v_current_mapping
    FROM public.user_tenant_mapping
    WHERE user_id = v_user_id
    LIMIT 1;
    
    IF FOUND THEN
        -- Atualizar mapping existente
        UPDATE public.user_tenant_mapping
        SET special_role_id = v_role_id,
            updated_at = NOW()
        WHERE user_id = v_user_id;
        
        -- Log da operação
        INSERT INTO public.dashboard_access_log (
            user_id,
            role_type,
            indicator_type,
            accessed_at,
            endpoint,
            request_params
        ) VALUES (
            v_user_id,
            'ADMIN',
            'role_assignment',
            NOW(),
            'assign_user_role',
            jsonb_build_object(
                'email', p_user_email,
                'role_name', p_role_name,
                'previous_role_id', v_current_mapping.special_role_id,
                'new_role_id', v_role_id
            )
        );
        
        RAISE NOTICE 'Role % atribuído ao usuário %', p_role_name, p_user_email;
    ELSE
        RAISE EXCEPTION 'Usuário % não possui mapping de tenant', p_user_email;
    END IF;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.assign_user_role(TEXT, TEXT) TO postgres;

-- 4. Função para criar dados de teste REALISTAS
-- ============================================
CREATE OR REPLACE FUNCTION public.create_test_dashboard_data(
    p_schema_name TEXT,
    p_days_back INTEGER DEFAULT 30
)
RETURNS VOID AS $$
DECLARE
    v_aluno_id BIGINT;
    v_data DATE;
    v_hora INTEGER;
    v_minuto INTEGER;
    v_dimensao_id INTEGER;
    v_random FLOAT;
    v_categoria TEXT;
    v_status TEXT;
    v_anonima BOOLEAN;
BEGIN
    -- SEGURANÇA: Validar schema
    IF NOT public.validate_schema_access(p_schema_name, auth.uid()) THEN
        RAISE EXCEPTION 'Schema % inválido ou sem acesso', p_schema_name;
    END IF;
    
    -- Criar eventos de acesso de teste com padrão realista
    FOR v_data IN
        SELECT generate_series(
            CURRENT_DATE - INTERVAL '1 day' * p_days_back,
            CURRENT_DATE - INTERVAL '1 day', -- Não incluir hoje
            INTERVAL '1 day'
        )::DATE
    LOOP
        -- Pular finais de semana
        IF EXTRACT(DOW FROM v_data) IN (0, 6) THEN
            CONTINUE;
        END IF;
        
        -- Para cada aluno, criar entrada/saída
        FOR v_aluno_id IN
            EXECUTE format('SELECT "ID" FROM %I.pessoas WHERE "Categoria_Principal" = ''ALUNO'' AND "Status_Pessoa" = ''ATIVO'' LIMIT 20', p_schema_name)
        LOOP
            v_random := random();
            
            -- 95% de presença em dias normais
            IF v_random < 0.95 THEN
                -- Entrada pela manhã (6:30-8:00) com distribuição normal
                v_hora := 6 + (random() * 1.5)::INTEGER;
                v_minuto := (random() * 59)::INTEGER;
                
            EXECUTE format($dynamic$
                INSERT INTO %I.eventos_acesso (
                    id, pessoa_id, tipo_evento, timestamp_evento, 
                    dispositivo_origem, evento_processado, notificacao_enviada
                ) VALUES (
                    gen_random_uuid(),
                    %s,
                    'Entrada',
                    %L::DATE + INTERVAL '%s hours' + INTERVAL '%s minutes',
                        'CATRACA_PRINCIPAL',
                    true,
                    true
                )
            $dynamic$,
                p_schema_name,
                v_aluno_id,
                v_data,
                v_hora,
                    v_minuto
                );
                
                -- Saída (variada por dia da semana)
                IF EXTRACT(DOW FROM v_data) = 5 THEN -- Sexta
                    v_hora := 11 + (random() * 2)::INTEGER; -- Saída mais cedo
                ELSE
                    v_hora := 12 + (random() * 6)::INTEGER; -- Saída normal
                END IF;
                
                -- 85% dos alunos que entraram também saem
                IF random() < 0.85 THEN
                EXECUTE format($dynamic$
                    INSERT INTO %I.eventos_acesso (
                        id, pessoa_id, tipo_evento, timestamp_evento,
                        dispositivo_origem, evento_processado, notificacao_enviada
                    ) VALUES (
                        gen_random_uuid(),
                        %s,
                        'Saida',
                        %L::DATE + INTERVAL '%s hours' + INTERVAL '%s minutes',
                            'CATRACA_PRINCIPAL',
                        true,
                        true
                    )
                $dynamic$,
                    p_schema_name,
                    v_aluno_id,
                    v_data,
                    v_hora,
                    (random() * 59)::INTEGER
                );
                END IF;
            END IF;
        END LOOP;
    END LOOP;
    
    -- Criar denúncias de teste com distribuição realista
    FOR i IN 1..(5 + random() * 10)::INTEGER LOOP -- 5-15 denúncias
        v_random := random();
        
        -- Distribuição de categorias
        IF v_random < 0.4 THEN
            v_categoria := 'bullying';
        ELSIF v_random < 0.7 THEN
            v_categoria := 'infraestrutura';
        ELSIF v_random < 0.8 THEN
            v_categoria := 'outros';
        ELSIF v_random < 0.85 THEN
            v_categoria := 'assedio';
        ELSIF v_random < 0.9 THEN
            v_categoria := 'discriminacao';
        ELSIF v_random < 0.95 THEN
            v_categoria := 'violencia';
        ELSE
            v_categoria := 'tráfico';
        END IF;
        
        -- Status baseado na categoria
        IF v_categoria IN ('tráfico', 'violencia') THEN
            v_status := (ARRAY['PENDENTE', 'EM_ANALISE', 'RESOLVIDA'])[floor(random() * 3 + 1)];
        ELSE
            v_status := (ARRAY['PENDENTE', 'EM_ANALISE', 'RESOLVIDA', 'ARQUIVADA', 'REJEITADA'])[floor(random() * 5 + 1)];
        END IF;
        
        -- Denúncias graves são mais anônimas
        v_anonima := v_categoria IN ('tráfico', 'violencia', 'assedio') AND random() > 0.3;
        
    EXECUTE format($dynamic$
        INSERT INTO %I.denuncias (
            "ID", "Aluno_ID", "Categoria", "Descricao", "Anonima",
            "Protocolo", "Status", "Criado_Em", "Atualizado_Em"
        )
        SELECT 
            gen_random_uuid(),
            (SELECT "ID" FROM %I.pessoas WHERE "Categoria_Principal" = 'ALUNO' ORDER BY random() LIMIT 1),
                %L,
                CASE 
                    WHEN %L THEN 'Denúncia anônima de teste - conteúdo sigiloso'
                    ELSE 'Denúncia de teste - ' || %L || ' - caso #' || floor(random() * 9999 + 1)::TEXT
                END,
                %L,
                'TEST-' || to_char(NOW() - INTERVAL '%s days', 'YYYYMMDD') || '-' || floor(random() * 9999 + 1)::TEXT,
                %L::status_denuncia,
                NOW() - INTERVAL '%s days' * random(),
                NOW() - INTERVAL '%s days' * random() * 0.5
            FROM generate_series(1, 1)
    $dynamic$,
        p_schema_name,
        p_schema_name,
            v_categoria,
            v_anonima,
            v_categoria,
            v_anonima,
            floor(random() * p_days_back),
            v_status,
            p_days_back,
        p_days_back
    );
    END LOOP;
    
    -- Criar registros socioemocionais de teste
    FOR v_data IN
        SELECT generate_series(
            CURRENT_DATE - INTERVAL '1 day' * p_days_back,
            CURRENT_DATE - INTERVAL '1 day',
            INTERVAL '7 days'
        )::DATE
    LOOP
        FOR v_aluno_id IN
            EXECUTE format('SELECT "ID" FROM %I.pessoas WHERE "Categoria_Principal" = ''ALUNO'' AND "Status_Pessoa" = ''ATIVO'' ORDER BY random() LIMIT 10', p_schema_name)
        LOOP
            -- Criar registro de sentimento
            EXECUTE format($dynamic$
                WITH novo_registro AS (
                    INSERT INTO %I.registro_sentimentos (
                        "ID", "Aluno_ID", "Data_Registro", "Status"
                    ) VALUES (
                        gen_random_uuid(),
                        %s,
                        %L::TIMESTAMPTZ + INTERVAL '%s hours',
                        'ATIVO'
                    ) RETURNING "ID"
                ),
                dimensoes AS (
                    SELECT "ID", "Ordem_Exibicao" FROM %I.dimensoes_sentimento WHERE "Status" = 'ATIVO'
                )
                INSERT INTO %I.detalhes_sentimento (
                    "Registro_ID", "Dimensao_ID", "Score", "Emoji", "Comentario"
                )
                SELECT 
                    nr."ID",
                    d."ID",
                    -- Score com tendência central (distribuição normal simulada)
                    GREATEST(1, LEAST(10, 5 + (random() - 0.5) * 4 + (random() - 0.5) * 2))::INTEGER,
                    CASE 
                        WHEN GREATEST(1, LEAST(10, 5 + (random() - 0.5) * 4 + (random() - 0.5) * 2))::INTEGER >= 8 THEN '😊'
                        WHEN GREATEST(1, LEAST(10, 5 + (random() - 0.5) * 4 + (random() - 0.5) * 2))::INTEGER >= 6 THEN '😐'
                        WHEN GREATEST(1, LEAST(10, 5 + (random() - 0.5) * 4 + (random() - 0.5) * 2))::INTEGER >= 4 THEN '😔'
                        ELSE '😢'
                    END,
                    CASE 
                        WHEN random() < 0.3 THEN 'Tudo bem'
                        WHEN random() < 0.6 THEN 'Normal'
                        WHEN random() < 0.8 THEN NULL
                        ELSE 'Preciso conversar'
                    END
                FROM novo_registro nr
                CROSS JOIN dimensoes d
            $dynamic$,
                p_schema_name,
                v_aluno_id,
                v_data,
                8 + (random() * 2)::INTEGER, -- Entre 8-10h da manhã
                p_schema_name,
                p_schema_name
            );
        END LOOP;
    END LOOP;
    
    -- Log da operação
    INSERT INTO public.dashboard_access_log (
        user_id,
        role_type,
        indicator_type,
        accessed_at,
        endpoint,
        request_params,
        success
    ) VALUES (
        auth.uid(),
        'ADMIN',
        'test_data_creation',
        NOW(),
        'create_test_dashboard_data',
        jsonb_build_object(
            'schema_name', p_schema_name,
            'days_back', p_days_back
        ),
        true
    );
    
    RAISE NOTICE 'Dados de teste criados para schema %', p_schema_name;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.create_test_dashboard_data(TEXT, INTEGER) TO postgres;

-- 5. Função de validação do setup
-- ============================================
CREATE OR REPLACE FUNCTION public.validate_dashboard_setup()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Verificar funções de segurança
    RETURN QUERY
    SELECT 
        'Função validate_schema_access'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc 
            WHERE proname = 'validate_schema_access'
            AND pronamespace = 'public'::regnamespace
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Função crítica de segurança para validar schemas'::TEXT;
    
    RETURN QUERY
    SELECT 
        'Função validate_user_session'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc 
            WHERE proname = 'validate_user_session'
            AND pronamespace = 'public'::regnamespace
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Função de validação robusta de sessão'::TEXT;
    
    -- Verificar tabelas necessárias
    RETURN QUERY
    SELECT 
        'Tabela role_permissions'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = 'role_permissions'
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Tabela de controle de roles'::TEXT;
    
    -- Verificar se RLS está habilitado
    RETURN QUERY
    SELECT 
        'RLS em role_permissions'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_tables 
            WHERE schemaname = 'public' 
            AND tablename = 'role_permissions'
            AND rowsecurity = true
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Row Level Security habilitado'::TEXT;
    
    RETURN QUERY
    SELECT 
        'RLS em dashboard_access_log'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_tables 
            WHERE schemaname = 'public' 
            AND tablename = 'dashboard_access_log'
            AND rowsecurity = true
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Row Level Security habilitado'::TEXT;
    
    -- Verificar colunas em user_tenant_mapping
    RETURN QUERY
    SELECT 
        'Coluna special_role_id'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
            AND table_name = 'user_tenant_mapping'
            AND column_name = 'special_role_id'
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Coluna para role especial em user_tenant_mapping'::TEXT;
    
    -- Verificar colunas em instituicoes
    RETURN QUERY
    SELECT 
        'Colunas de localização'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
            AND table_name = 'instituicoes'
            AND column_name IN ('co_uf', 'co_municipio', 'tp_dependencia')
            HAVING COUNT(*) = 3
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Colunas co_uf, co_municipio, tp_dependencia em instituicoes'::TEXT;
    
    -- Verificar tabela de categorias
    RETURN QUERY
    SELECT 
        'Tabela role_categoria_denuncia'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = 'role_categoria_denuncia'
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Tabela de mapeamento de categorias por role'::TEXT;
    
    -- Verificar RPCs
    RETURN QUERY
    SELECT 
        'RPC Dashboard Presença'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.routines 
            WHERE routine_schema = 'public' 
            AND routine_name = 'rpc_dashboard_presenca'
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Função rpc_dashboard_presenca'::TEXT;
    
    RETURN QUERY
    SELECT 
        'RPC Dashboard Denúncias'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.routines 
            WHERE routine_schema = 'public' 
            AND routine_name = 'rpc_dashboard_denuncias'
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Função rpc_dashboard_denuncias'::TEXT;
    
    RETURN QUERY
    SELECT 
        'RPC Dashboard Sentimento'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.routines 
            WHERE routine_schema = 'public' 
            AND routine_name = 'rpc_dashboard_sentimento'
        ) THEN 'OK'::TEXT ELSE 'ERRO'::TEXT END,
        'Função rpc_dashboard_sentimento'::TEXT;
    
    -- Verificar se há roles criados
    RETURN QUERY
    SELECT 
        'Roles configurados'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM public.role_permissions
        ) THEN 'OK'::TEXT ELSE 'AVISO'::TEXT END,
        'Existem ' || COUNT(*)::TEXT || ' roles configurados'::TEXT
    FROM public.role_permissions;
    
    -- Verificar se há usuários com roles
    RETURN QUERY
    SELECT 
        'Usuários com roles'::TEXT,
        CASE WHEN EXISTS (
            SELECT 1 FROM public.user_tenant_mapping
            WHERE special_role_id IS NOT NULL
        ) THEN 'OK'::TEXT ELSE 'AVISO'::TEXT END,
        'Existem ' || COUNT(*)::TEXT || ' usuários com roles especiais'::TEXT
    FROM public.user_tenant_mapping
    WHERE special_role_id IS NOT NULL;
    
    -- Verificar índices críticos
    RETURN QUERY
    SELECT 
        'Índices de performance'::TEXT,
        CASE WHEN COUNT(*) >= 5 THEN 'OK'::TEXT ELSE 'AVISO'::TEXT END,
        'Existem ' || COUNT(*)::TEXT || ' índices críticos criados'::TEXT
    FROM pg_indexes
    WHERE schemaname = 'public'
    AND indexname IN (
        'idx_user_tenant_mapping_user_status',
        'idx_user_tenant_special',
        'idx_instituicoes_composite',
        'idx_schema_registry_status',
        'idx_dashboard_log_date'
    );
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.validate_dashboard_setup() TO authenticated;

-- 6. Executar setup inicial
-- ============================================
DO $$
DECLARE
    v_result RECORD;
    v_error_count INTEGER := 0;
    v_warning_count INTEGER := 0;
BEGIN
    -- Criar roles de exemplo
    BEGIN
    PERFORM public.create_sample_roles();
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Erro ao criar roles de exemplo: %', SQLERRM;
    END;
    
    -- Validar setup
    RAISE NOTICE 'Validando setup do dashboard...';
    RAISE NOTICE '================================';
    
    FOR v_result IN 
        SELECT * FROM public.validate_dashboard_setup()
    LOOP
        RAISE NOTICE '% - % (%)', 
            rpad(v_result.check_name, 30), 
            rpad(v_result.status, 6), 
            v_result.details;
        
        IF v_result.status = 'ERRO' THEN
            v_error_count := v_error_count + 1;
        ELSIF v_result.status = 'AVISO' THEN
            v_warning_count := v_warning_count + 1;
        END IF;
    END LOOP;
    
    RAISE NOTICE '================================';
    RAISE NOTICE 'Resumo: % erros, % avisos', v_error_count, v_warning_count;
    
    IF v_error_count > 0 THEN
        RAISE NOTICE '';
        RAISE NOTICE '⚠️  ATENÇÃO: Existem erros críticos!';
        RAISE NOTICE 'Execute security-fixes.sql e tabelas-adequacoes.sql antes de continuar.';
    ELSE
        RAISE NOTICE '';
        RAISE NOTICE '✅ Setup do dashboard validado com sucesso!';
        RAISE NOTICE '';
        RAISE NOTICE 'Próximos passos:';
        RAISE NOTICE '1. Execute assign_user_role() para atribuir roles aos usuários';
        RAISE NOTICE '2. Execute setup_escola_dashboard() para cada schema de escola';
        RAISE NOTICE '3. Execute create_test_dashboard_data() para criar dados de teste';
    END IF;
END $$;

-- ============================================
-- FIM DO SCRIPT SQL 05
-- ============================================