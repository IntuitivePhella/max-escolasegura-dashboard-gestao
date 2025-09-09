-- ============================================
-- SQL 02 - RPC DASHBOARD DE PRESENÇA
-- ============================================
-- Descrição: Função para agregação de dados de presença
-- com controle de acesso baseado em roles
-- 
-- SEGURANÇA: Requer execução de security-fixes.sql antes
-- ============================================

-- 1. Função principal para dashboard de presença
-- ============================================
CREATE OR REPLACE FUNCTION public.rpc_dashboard_presenca(
    p_data DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    schema_name TEXT,
    escola_nome TEXT,
    codigo_inep VARCHAR,
    co_uf VARCHAR,
    co_municipio VARCHAR,
    presentes BIGINT,
    total BIGINT,
    pct_presenca NUMERIC,
    detalhes JSONB
) 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_role_record RECORD;
    v_schema TEXT;
    v_sql TEXT;
    v_result RECORD;
BEGIN
    -- SEGURANÇA: Validação robusta de sessão
    v_user_id := public.validate_user_session();
    
    -- Obter informações do role do usuário
    SELECT 
        utm.schema_name AS user_schema,
        utm.instituicao_id,
        rp.role_type,
        rp.uf_code,
        rp.municipio_code,
        rp.escola_code,
        rp.permissions
    INTO v_role_record
    FROM public.user_tenant_mapping utm
    LEFT JOIN public.role_permissions rp ON utm.special_role_id = rp.id
    WHERE utm.user_id = v_user_id
    AND utm.status = 'ATIVO'
    LIMIT 1;
    
    -- Verificar se o usuário tem acesso
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuário sem permissão de acesso'
            USING HINT = 'Verifique se seu usuário está ativo e tem role atribuído';
    END IF;
    
    -- Rate limiting
    IF NOT public.check_rate_limit(v_user_id, 'dashboard_presenca', 100, 5) THEN
        RAISE EXCEPTION 'Limite de requisições excedido'
            USING HINT = 'Aguarde alguns minutos antes de tentar novamente';
    END IF;
    
    -- Log de acesso
    INSERT INTO public.dashboard_access_log (
        user_id, 
        role_type, 
        indicator_type,
        accessed_at,
        endpoint,
        http_method
    ) VALUES (
        v_user_id,
        v_role_record.role_type,
        'presenca',
        NOW(),
        'rpc_dashboard_presenca',
        'POST'
    );
    
    -- Criar tabela temporária para resultados
    CREATE TEMP TABLE IF NOT EXISTS temp_presenca_results (
        schema_name TEXT,
        escola_nome TEXT,
        codigo_inep VARCHAR,
        co_uf VARCHAR,
        co_municipio VARCHAR,
        presentes BIGINT,
        total BIGINT,
        pct_presenca NUMERIC,
        detalhes JSONB
    ) ON COMMIT DROP;
    
    -- Buscar escolas permitidas baseado no role
    FOR v_result IN
        SELECT 
            sr.schema_name,
            i."Nome_Fantasia" as escola_nome,
            i."Codigo_INEP" as codigo_inep,
            i.co_uf,
            i.co_municipio
        FROM public.schema_registry sr
        JOIN public.instituicoes i ON sr.instituicao_id = i."ID"
        WHERE sr.status = 'ATIVO'
        AND (
            -- DIRETORIA: apenas sua escola
            (v_role_record.role_type = 'DIRETORIA' 
             AND sr.schema_name = v_role_record.user_schema)
            
            -- SEC_EDUC_MUN: escolas municipais do município
            OR (v_role_record.role_type = 'SEC_EDUC_MUN' 
                AND i.co_municipio = v_role_record.municipio_code 
                AND i.tp_dependencia = '3')
            
            -- SEC_EDUC_EST: escolas estaduais do estado
            OR (v_role_record.role_type = 'SEC_EDUC_EST' 
                AND i.co_uf = v_role_record.uf_code 
                AND i.tp_dependencia = '2')
            
            -- Admin geral (sem role especial) - apenas sua própria escola
            OR (v_role_record.role_type IS NULL 
                AND sr.schema_name = v_role_record.user_schema)
        )
    LOOP
        -- SEGURANÇA: Validar schema antes de usar em query dinâmica
        IF NOT public.validate_schema_access(v_result.schema_name, v_user_id) THEN
            RAISE WARNING 'Schema % inválido ou sem acesso', v_result.schema_name;
            CONTINUE;
        END IF;
        
        -- Construir query dinâmica para cada schema
        -- CORREÇÃO: Lógica melhorada para considerar múltiplas entradas/saídas
        v_sql := format($dynamic$
            WITH alunos_total AS (
                SELECT COUNT(DISTINCT "ID") as total
                FROM %I.pessoas
                WHERE "Categoria_Principal" = 'ALUNO'
                AND "Status_Pessoa" = 'ATIVO'
            ),
            -- LÓGICA CORRIGIDA: Considera última movimentação do dia
            movimentacoes_dia AS (
                SELECT 
                    pessoa_id,
                    tipo_evento,
                    timestamp_evento,
                    ROW_NUMBER() OVER (
                        PARTITION BY pessoa_id 
                        ORDER BY timestamp_evento DESC
                    ) as rn
                FROM %I.eventos_acesso
                WHERE DATE(timestamp_evento) = %L
            ),
            presenca_atual AS (
                -- Aluno está presente se sua última movimentação foi ENTRADA
                SELECT COUNT(DISTINCT m.pessoa_id) as presentes
                FROM movimentacoes_dia m
                INNER JOIN %I.pessoas p ON p."ID" = m.pessoa_id
                WHERE m.rn = 1  -- Última movimentação do dia
                AND p."Categoria_Principal" = 'ALUNO'
                AND m.tipo_evento = 'Entrada'
            ),
            detalhes_presenca AS (
                SELECT 
                    jsonb_build_object(
                        'horario_pico', (
                            SELECT EXTRACT(HOUR FROM timestamp_evento)::INT
                            FROM %I.eventos_acesso
                            WHERE DATE(timestamp_evento) = %L
                            AND tipo_evento = 'Entrada'
                            GROUP BY EXTRACT(HOUR FROM timestamp_evento)
                            ORDER BY COUNT(*) DESC
                            LIMIT 1
                        ),
                        'total_entradas', (
                            SELECT COUNT(*)
                            FROM %I.eventos_acesso
                            WHERE DATE(timestamp_evento) = %L
                            AND tipo_evento = 'Entrada'
                        ),
                        'total_saidas', (
                            SELECT COUNT(*)
                            FROM %I.eventos_acesso
                            WHERE DATE(timestamp_evento) = %L
                            AND tipo_evento = 'Saida'
                        ),
                        'alunos_com_multiplas_entradas', (
                            SELECT COUNT(DISTINCT pessoa_id)
                            FROM %I.eventos_acesso
                            WHERE DATE(timestamp_evento) = %L
                            AND tipo_evento = 'Entrada'
                            GROUP BY pessoa_id
                            HAVING COUNT(*) > 1
                        )
                    ) as detalhes
            )
            SELECT 
                %L as schema_name,
                %L as escola_nome,
                %L as codigo_inep,
                %L as co_uf,
                %L as co_municipio,
                COALESCE(p.presentes, 0) as presentes,
                COALESCE(a.total, 0) as total,
                CASE 
                    WHEN COALESCE(a.total, 0) > 0 
                    THEN ROUND((COALESCE(p.presentes, 0)::NUMERIC / a.total) * 100, 2)
                    ELSE 0
                END as pct_presenca,
                d.detalhes
            FROM alunos_total a
            CROSS JOIN presenca_atual p
            CROSS JOIN detalhes_presenca d
        $dynamic$,
            v_result.schema_name, -- FROM pessoas
            v_result.schema_name, -- FROM eventos_acesso (movimentacoes)
            p_data,               -- WHERE DATE (movimentacoes)
            v_result.schema_name, -- INNER JOIN pessoas
            v_result.schema_name, -- FROM eventos_acesso (horario_pico)
            p_data,               -- WHERE DATE (horario_pico)
            v_result.schema_name, -- FROM eventos_acesso (total_entradas)
            p_data,               -- WHERE DATE (total_entradas)
            v_result.schema_name, -- FROM eventos_acesso (total_saidas)
            p_data,               -- WHERE DATE (total_saidas)
            v_result.schema_name, -- FROM eventos_acesso (multiplas_entradas)
            p_data,               -- WHERE DATE (multiplas_entradas)
            v_result.schema_name, -- SELECT schema_name
            v_result.escola_nome, -- SELECT escola_nome
            v_result.codigo_inep, -- SELECT codigo_inep
            v_result.co_uf,       -- SELECT co_uf
            v_result.co_municipio -- SELECT co_municipio
        );
        
        -- Executar query e inserir resultado na tabela temporária
        BEGIN
            EXECUTE v_sql INTO v_result;
            
            INSERT INTO temp_presenca_results VALUES (
                v_result.schema_name,
                v_result.escola_nome,
                v_result.codigo_inep,
                v_result.co_uf,
                v_result.co_municipio,
                v_result.presentes,
                v_result.total,
                v_result.pct_presenca,
                v_result.detalhes
            );
        EXCEPTION WHEN OTHERS THEN
            -- Log erro mas continua com próxima escola
            RAISE WARNING 'Erro ao processar schema %: %', v_result.schema_name, SQLERRM;
            
            -- Log erro detalhado
            INSERT INTO public.dashboard_access_log (
                user_id,
                role_type,
                indicator_type,
                accessed_at,
                success,
                error_message,
                endpoint
            ) VALUES (
                v_user_id,
                v_role_record.role_type,
                'presenca',
                NOW(),
                FALSE,
                format('Erro no schema %s: %s', v_result.schema_name, SQLERRM),
                'rpc_dashboard_presenca'
            );
        END;
    END LOOP;
    
    -- Retornar resultados agregados
    RETURN QUERY
    SELECT * FROM temp_presenca_results
    ORDER BY escola_nome;
    
END;
$$ LANGUAGE plpgsql;

-- Conceder execução para usuários autenticados
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_presenca(DATE) TO authenticated;

-- Adicionar comentário de documentação
COMMENT ON FUNCTION public.rpc_dashboard_presenca IS 
'Retorna dados de presença escolar por data. 
SEGURANÇA: Valida sessão, schema e aplica rate limiting.
LÓGICA: Considera última movimentação do dia (entrada/saída) para determinar presença.';

-- 2. Função para obter histórico de presença (últimos 30 dias)
-- ============================================
CREATE OR REPLACE FUNCTION public.rpc_dashboard_presenca_historico(
    p_dias INTEGER DEFAULT 30
)
RETURNS TABLE (
    data DATE,
    schema_name TEXT,
    escola_nome TEXT,
    presentes BIGINT,
    total BIGINT,
    pct_presenca NUMERIC
) 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_role_record RECORD;
    v_data DATE;
    v_schema TEXT;
    v_sql TEXT;
    v_result RECORD;
BEGIN
    -- SEGURANÇA: Validação robusta de sessão
    v_user_id := public.validate_user_session();
    
    -- Obter role do usuário
    SELECT 
        utm.schema_name AS user_schema,
        rp.role_type,
        rp.uf_code,
        rp.municipio_code,
        rp.escola_code
    INTO v_role_record
    FROM public.user_tenant_mapping utm
    LEFT JOIN public.role_permissions rp ON utm.special_role_id = rp.id
    WHERE utm.user_id = v_user_id
    AND utm.status = 'ATIVO'
    LIMIT 1;
    
    -- Rate limiting
    IF NOT public.check_rate_limit(v_user_id, 'dashboard_presenca_historico', 50, 5) THEN
        RAISE EXCEPTION 'Limite de requisições excedido';
    END IF;
    
    CREATE TEMP TABLE IF NOT EXISTS temp_historico_results (
        data DATE,
        schema_name TEXT,
        escola_nome TEXT,
        presentes BIGINT,
        total BIGINT,
        pct_presenca NUMERIC
    ) ON COMMIT DROP;
    
    -- Loop através das datas
    FOR v_data IN
        SELECT generate_series(
            CURRENT_DATE - INTERVAL '1 day' * p_dias,
            CURRENT_DATE,
            INTERVAL '1 day'
        )::DATE
    LOOP
        -- Para cada escola permitida
        FOR v_result IN
            SELECT 
                sr.schema_name,
                i."Nome_Fantasia" as escola_nome
            FROM public.schema_registry sr
            JOIN public.instituicoes i ON sr.instituicao_id = i."ID"
            WHERE sr.status = 'ATIVO'
            AND (
                (v_role_record.role_type = 'DIRETORIA' 
                 AND sr.schema_name = v_role_record.user_schema)
                OR (v_role_record.role_type = 'SEC_EDUC_MUN' 
                    AND i.co_municipio = v_role_record.municipio_code 
                    AND i.tp_dependencia = '3')
                OR (v_role_record.role_type = 'SEC_EDUC_EST' 
                    AND i.co_uf = v_role_record.uf_code 
                    AND i.tp_dependencia = '2')
                OR (v_role_record.role_type IS NULL 
                    AND sr.schema_name = v_role_record.user_schema)
            )
        LOOP
            -- SEGURANÇA: Validar schema
            IF NOT public.validate_schema_access(v_result.schema_name, v_user_id) THEN
                CONTINUE;
            END IF;
            
            v_sql := format($dynamic$
                WITH dados AS (
                    SELECT 
                        COUNT(DISTINCT CASE 
                            WHEN ea.tipo_evento = 'Entrada' THEN ea.pessoa_id 
                        END) as presentes,
                        COUNT(DISTINCT p."ID") as total
                    FROM %I.pessoas p
                    LEFT JOIN %I.eventos_acesso ea 
                        ON ea.pessoa_id = p."ID" 
                        AND DATE(ea.timestamp_evento) = %L
                    WHERE p."Categoria_Principal" = 'ALUNO'
                    AND p."Status_Pessoa" = 'ATIVO'
                )
                SELECT 
                    %L::DATE as data,
                    %L as schema_name,
                    %L as escola_nome,
                    presentes,
                    total,
                    CASE 
                        WHEN total > 0 
                        THEN ROUND((presentes::NUMERIC / total) * 100, 2)
                        ELSE 0
                    END as pct_presenca
                FROM dados
            $dynamic$,
                v_result.schema_name,
                v_result.schema_name,
                v_data,
                v_data,
                v_result.schema_name,
                v_result.escola_nome
            );
            
            BEGIN
                EXECUTE v_sql INTO v_result;
                INSERT INTO temp_historico_results VALUES (
                    v_result.data,
                    v_result.schema_name,
                    v_result.escola_nome,
                    v_result.presentes,
                    v_result.total,
                    v_result.pct_presenca
                );
            EXCEPTION WHEN OTHERS THEN
                CONTINUE;
            END;
        END LOOP;
    END LOOP;
    
    RETURN QUERY
    SELECT * FROM temp_historico_results
    ORDER BY data DESC, escola_nome;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.rpc_dashboard_presenca_historico(INTEGER) TO authenticated;

-- 3. Função para obter escolas acessíveis ao usuário
-- ============================================
CREATE OR REPLACE FUNCTION public.rpc_get_escolas_acessiveis()
RETURNS TABLE (
    schema_name TEXT,
    escola_nome TEXT,
    codigo_inep VARCHAR,
    co_uf VARCHAR,
    co_municipio VARCHAR,
    tp_dependencia VARCHAR,
    can_access BOOLEAN
) 
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_role_record RECORD;
BEGIN
    -- SEGURANÇA: Validação robusta de sessão
    v_user_id := public.validate_user_session();
    
    SELECT 
        utm.schema_name AS user_schema,
        rp.role_type,
        rp.uf_code,
        rp.municipio_code,
        rp.escola_code,
        rp.permissions
    INTO v_role_record
    FROM public.user_tenant_mapping utm
    LEFT JOIN public.role_permissions rp ON utm.special_role_id = rp.id
    WHERE utm.user_id = v_user_id
    AND utm.status = 'ATIVO'
    LIMIT 1;
    
    RETURN QUERY
    SELECT 
        sr.schema_name,
        i."Nome_Fantasia" as escola_nome,
        i."Codigo_INEP" as codigo_inep,
        i.co_uf,
        i.co_municipio,
        i.tp_dependencia,
        CASE 
            WHEN v_role_record.role_type = 'DIRETORIA' 
                AND sr.schema_name = v_role_record.user_schema THEN TRUE
            WHEN v_role_record.role_type = 'SEC_EDUC_MUN' 
                AND i.co_municipio = v_role_record.municipio_code 
                AND i.tp_dependencia = '3' THEN TRUE
            WHEN v_role_record.role_type = 'SEC_EDUC_EST' 
                AND i.co_uf = v_role_record.uf_code 
                AND i.tp_dependencia = '2' THEN TRUE
            WHEN v_role_record.role_type = 'SEC_SEG_PUB' 
                AND i.co_uf = v_role_record.uf_code 
                AND i.tp_dependencia IN ('2', '3') THEN TRUE
            WHEN v_role_record.role_type IS NULL 
                AND sr.schema_name = v_role_record.user_schema THEN TRUE
            ELSE FALSE
        END as can_access
    FROM public.schema_registry sr
    JOIN public.instituicoes i ON sr.instituicao_id = i."ID"
    WHERE sr.status = 'ATIVO'
    ORDER BY i."Nome_Fantasia";
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.rpc_get_escolas_acessiveis() TO authenticated;

-- 4. Trigger para notificação em tempo real de mudanças de presença
-- ============================================
CREATE OR REPLACE FUNCTION notify_presenca_change()
RETURNS TRIGGER AS $$
DECLARE
    v_payload JSONB;
BEGIN
    -- Construir payload para notificação
    v_payload := jsonb_build_object(
        'schema', TG_TABLE_SCHEMA,
        'action', TG_OP,
        'tipo_evento', NEW.tipo_evento,
        'pessoa_id', NEW.pessoa_id,
        'timestamp', NEW.timestamp_evento,
        'data', DATE(NEW.timestamp_evento)
    );
    
    -- Enviar notificação através do canal realtime
    PERFORM pg_notify(
        'dashboard_presenca_update',
        v_payload::text
    );
    
    -- Se for entrada ou saída, atualizar cache se existir
    IF NEW.tipo_evento IN ('Entrada', 'Saida') THEN
        -- Aqui poderia atualizar uma tabela de cache/agregação
        NULL; -- Placeholder para futura implementação
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Função para aplicar trigger em um schema específico
-- ============================================
-- CORREÇÃO: Verificar se trigger já existe antes de criar
CREATE OR REPLACE FUNCTION public.setup_presenca_trigger(p_schema_name TEXT)
RETURNS VOID AS $$
BEGIN
    -- SEGURANÇA: Validar schema
    IF NOT EXISTS (
        SELECT 1 FROM public.schema_registry 
        WHERE schema_name = p_schema_name 
        AND status = 'ATIVO'
    ) THEN
        RAISE EXCEPTION 'Schema % não encontrado ou inativo', p_schema_name;
    END IF;
    
    -- Verificar se trigger já existe
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger 
        WHERE tgname = 'trg_notify_presenca_change'
        AND tgrelid = format('%I.eventos_acesso', p_schema_name)::regclass
    ) THEN
        EXECUTE format($dynamic$
            CREATE TRIGGER trg_notify_presenca_change
            AFTER INSERT OR UPDATE ON %I.eventos_acesso
            FOR EACH ROW
            EXECUTE FUNCTION notify_presenca_change()
        $dynamic$, p_schema_name);
        
        RAISE NOTICE 'Trigger de presença criado para schema %', p_schema_name;
    ELSE
        RAISE NOTICE 'Trigger de presença já existe para schema %', p_schema_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.setup_presenca_trigger(TEXT) TO postgres;

-- ============================================
-- FIM DO SCRIPT SQL 02
-- ============================================            