-- ============================================
-- SQL 04 - RPC DASHBOARD SOCIOEMOCIONAL
-- ============================================
-- Descrição: Funções para agregação de dados socioemocionais
-- com controle de acesso baseado em roles
--
-- SEGURANÇA: Requer execução de security-fixes.sql antes
-- ============================================

-- 1. Função principal para dashboard socioemocional
-- ============================================
CREATE OR REPLACE FUNCTION public.rpc_dashboard_sentimento(
    p_de TIMESTAMPTZ DEFAULT NOW() - INTERVAL '30 days',
    p_ate TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE (
    dimensao_id INTEGER,
    dimensao_nome VARCHAR,
    media_score NUMERIC,
    min_score INTEGER,
    max_score INTEGER,
    total_registros BIGINT,
    schema_name TEXT,
    escola_nome TEXT,
    detalhes JSONB
) 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_role_record RECORD;
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
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuário sem permissão de acesso'
            USING HINT = 'Verifique se seu usuário está ativo e tem role atribuído';
    END IF;
    
    -- SEC_SEG_PUB não tem acesso a dados socioemocionais
    IF v_role_record.role_type = 'SEC_SEG_PUB' THEN
        RAISE EXCEPTION 'Role SEC_SEG_PUB não tem acesso a dados socioemocionais'
            USING HINT = 'Este indicador está disponível apenas para roles educacionais';
    END IF;
    
    -- Rate limiting
    IF NOT public.check_rate_limit(v_user_id, 'dashboard_sentimento', 50, 5) THEN
        RAISE EXCEPTION 'Limite de requisições excedido'
            USING HINT = 'Aguarde alguns minutos antes de tentar novamente';
    END IF;
    
    -- Validar intervalo de datas
    IF p_ate < p_de THEN
        RAISE EXCEPTION 'Data final deve ser maior que data inicial';
    END IF;
    
    IF p_ate - p_de > INTERVAL '365 days' THEN
        RAISE EXCEPTION 'Intervalo máximo permitido é de 365 dias';
    END IF;
    
    -- Log de acesso
    INSERT INTO public.dashboard_access_log (
        user_id, 
        role_type, 
        indicator_type,
        accessed_at,
        endpoint,
        request_params
    ) VALUES (
        v_user_id,
        v_role_record.role_type,
        'sentimento',
        NOW(),
        'rpc_dashboard_sentimento',
        jsonb_build_object(
            'de', p_de,
            'ate', p_ate
        )
    );
    
    -- Criar tabela temporária para resultados
    CREATE TEMP TABLE IF NOT EXISTS temp_sentimento_results (
        dimensao_id INTEGER,
        dimensao_nome VARCHAR,
        media_score NUMERIC,
        min_score INTEGER,
        max_score INTEGER,
        total_registros BIGINT,
        schema_name TEXT,
        escola_nome TEXT,
        detalhes JSONB
    ) ON COMMIT DROP;
    
    -- Buscar escolas permitidas baseado no role
    FOR v_result IN
        SELECT 
            sr.schema_name,
            i."Nome_Fantasia" as escola_nome,
            i."Codigo_INEP" as codigo_inep
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
            
            -- Admin geral
            OR (v_role_record.role_type IS NULL 
                AND sr.schema_name = v_role_record.user_schema)
        )
    LOOP
        -- SEGURANÇA: Validar schema antes de usar
        IF NOT public.validate_schema_access(v_result.schema_name, v_user_id) THEN
            RAISE WARNING 'Schema % inválido ou sem acesso', v_result.schema_name;
            CONTINUE;
        END IF;
        
        -- Construir query dinâmica para cada schema
        -- CORREÇÃO: Melhorar cálculo de tendência usando regressão linear simples
        v_sql := format($dynamic$
            WITH scores_periodo AS (
                SELECT 
                    ds."Dimensao_ID",
                    dim."Nome" as dimensao_nome,
                    ds."Score",
                    ds."Emoji",
                    rs."Data_Registro",
                    -- Para regressão linear
                    EXTRACT(EPOCH FROM rs."Data_Registro" - %L::TIMESTAMPTZ) / 86400 as dias_desde_inicio
                FROM %I.registro_sentimentos rs
                INNER JOIN %I.detalhes_sentimento ds ON ds."Registro_ID" = rs."ID"
                INNER JOIN %I.dimensoes_sentimento dim ON dim."ID" = ds."Dimensao_ID"
                WHERE rs."Data_Registro" BETWEEN %L AND %L
                AND dim."Status" = 'ATIVO'
            ),
            -- Cálculo de regressão linear para tendência
            regressao AS (
                SELECT 
                    "Dimensao_ID",
                    -- Coeficiente de inclinação (slope)
                    CASE 
                        WHEN COUNT(*) > 1 THEN
                            (COUNT(*) * SUM(dias_desde_inicio * "Score") - SUM(dias_desde_inicio) * SUM("Score")) /
                            NULLIF((COUNT(*) * SUM(dias_desde_inicio * dias_desde_inicio) - SUM(dias_desde_inicio) * SUM(dias_desde_inicio)), 0)
                        ELSE NULL
                    END as slope
                FROM scores_periodo
                GROUP BY "Dimensao_ID"
            ),
            agregados AS (
                SELECT 
                    sp."Dimensao_ID" as dimensao_id,
                    sp.dimensao_nome,
                    ROUND(AVG(sp."Score")::NUMERIC, 2) as media_score,
                    MIN(sp."Score") as min_score,
                    MAX(sp."Score") as max_score,
                    COUNT(*) as total_registros,
                    jsonb_build_object(
                        'distribuicao_scores', (
                            SELECT jsonb_object_agg(
                                score::TEXT,
                                count
                            )
                            FROM (
                                SELECT 
                                    "Score" as score,
                                    COUNT(*) as count
                                FROM scores_periodo sp2
                                WHERE sp2."Dimensao_ID" = sp."Dimensao_ID"
                                GROUP BY "Score"
                                ORDER BY "Score"
                            ) dist
                        ),
                        'emoji_predominante', (
                            SELECT "Emoji"
                            FROM scores_periodo sp3
                            WHERE sp3."Dimensao_ID" = sp."Dimensao_ID"
                            GROUP BY "Emoji"
                            ORDER BY COUNT(*) DESC
                            LIMIT 1
                        ),
                        'tendencia', CASE
                            WHEN COUNT(*) < 3 THEN 'dados_insuficientes'
                            WHEN r.slope > 0.1 THEN 'melhora'
                            WHEN r.slope < -0.1 THEN 'piora'
                            ELSE 'estavel'
                        END,
                        'slope', ROUND(r.slope::NUMERIC, 4),
                        'desvio_padrao', ROUND(STDDEV(sp."Score")::NUMERIC, 2)
                    ) as detalhes
                FROM scores_periodo sp
                LEFT JOIN regressao r ON r."Dimensao_ID" = sp."Dimensao_ID"
                GROUP BY sp."Dimensao_ID", sp.dimensao_nome, r.slope
            )
            SELECT 
                dimensao_id,
                dimensao_nome,
                media_score,
                min_score,
                max_score,
                total_registros,
                %L as schema_name,
                %L as escola_nome,
                detalhes
            FROM agregados
            
            UNION ALL
            
            -- Incluir dimensões sem registros no período
            SELECT 
                dim."ID" as dimensao_id,
                dim."Nome" as dimensao_nome,
                0 as media_score,
                0 as min_score,
                0 as max_score,
                0 as total_registros,
                %L as schema_name,
                %L as escola_nome,
                jsonb_build_object(
                    'distribuicao_scores', '{}'::jsonb,
                    'emoji_predominante', null,
                    'tendencia', 'sem_dados',
                    'slope', null,
                    'desvio_padrao', null
                ) as detalhes
            FROM %I.dimensoes_sentimento dim
            WHERE dim."Status" = 'ATIVO'
            AND NOT EXISTS (
                SELECT 1
                FROM %I.registro_sentimentos rs
                INNER JOIN %I.detalhes_sentimento ds ON ds."Registro_ID" = rs."ID"
                WHERE ds."Dimensao_ID" = dim."ID"
                AND rs."Data_Registro" BETWEEN %L AND %L
            )
            ORDER BY dimensao_nome
        $dynamic$,
            p_de,                   -- Referência para dias_desde_inicio
            v_result.schema_name,  -- FROM registro_sentimentos
            v_result.schema_name,  -- FROM detalhes_sentimento
            v_result.schema_name,  -- FROM dimensoes_sentimento
            p_de,                   -- WHERE data inicio
            p_ate,                  -- WHERE data fim
            v_result.schema_name,  -- SELECT schema_name (agregados)
            v_result.escola_nome,  -- SELECT escola_nome (agregados)
            v_result.schema_name,  -- SELECT schema_name (sem registros)
            v_result.escola_nome,  -- SELECT escola_nome (sem registros)
            v_result.schema_name,  -- FROM dimensoes_sentimento (sem registros)
            v_result.schema_name,  -- FROM registro_sentimentos (EXISTS)
            v_result.schema_name,  -- FROM detalhes_sentimento (EXISTS)
            p_de,                   -- WHERE data inicio (EXISTS)
            p_ate                   -- WHERE data fim (EXISTS)
        );
        
        -- Executar query e inserir resultados
        BEGIN
            FOR v_result IN EXECUTE v_sql
            LOOP
                INSERT INTO temp_sentimento_results VALUES (
                    v_result.dimensao_id,
                    v_result.dimensao_nome,
                    v_result.media_score,
                    v_result.min_score,
                    v_result.max_score,
                    v_result.total_registros,
                    v_result.schema_name,
                    v_result.escola_nome,
                    v_result.detalhes
                );
            END LOOP;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Erro ao processar schema %: %', v_result.schema_name, SQLERRM;
            
            -- Log de erro
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
                'sentimento',
                NOW(),
                FALSE,
                format('Erro no schema %s: %s', v_result.schema_name, SQLERRM),
                'rpc_dashboard_sentimento'
            );
        END;
    END LOOP;
    
    -- Retornar resultados agregados
    RETURN QUERY
    SELECT * FROM temp_sentimento_results
    ORDER BY escola_nome, dimensao_nome;
    
END;
$$ LANGUAGE plpgsql;

-- Conceder execução para usuários autenticados
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_sentimento(TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

-- Documentação
COMMENT ON FUNCTION public.rpc_dashboard_sentimento IS 
'Retorna agregação de dados socioemocionais por dimensão.
SEGURANÇA: Valida sessão, schema e bloqueia SEC_SEG_PUB.
TENDÊNCIA: Usa regressão linear para calcular tendência real.
LIMITES: Máximo 365 dias de intervalo.';

-- 2. Função para histórico de sentimentos por aluno
-- ============================================
CREATE OR REPLACE FUNCTION public.rpc_dashboard_sentimento_aluno(
    p_aluno_id BIGINT,
    p_dias INTEGER DEFAULT 30
)
RETURNS TABLE (
    data DATE,
    dimensao_nome VARCHAR,
    score INTEGER,
    emoji VARCHAR,
    comentario TEXT,
    schema_name TEXT
) 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_role_record RECORD;
    v_sql TEXT;
BEGIN
    -- SEGURANÇA: Validação robusta de sessão
    v_user_id := public.validate_user_session();
    
    -- Obter role do usuário
    SELECT 
        utm.schema_name AS user_schema,
        rp.role_type
    INTO v_role_record
    FROM public.user_tenant_mapping utm
    LEFT JOIN public.role_permissions rp ON utm.special_role_id = rp.id
    WHERE utm.user_id = v_user_id
    AND utm.status = 'ATIVO'
    LIMIT 1;
    
    -- SEC_SEG_PUB não tem acesso
    IF v_role_record.role_type = 'SEC_SEG_PUB' THEN
        RETURN;
    END IF;
    
    -- Rate limiting
    IF NOT public.check_rate_limit(v_user_id, 'dashboard_sentimento_aluno', 30, 5) THEN
        RAISE EXCEPTION 'Limite de requisições excedido';
    END IF;
    
    -- SEGURANÇA: Validar schema
    IF NOT public.validate_schema_access(v_role_record.user_schema, v_user_id) THEN
        RAISE EXCEPTION 'Acesso negado ao schema';
    END IF;
    
    -- Construir e executar query
    v_sql := format($dynamic$
        SELECT 
            DATE(rs."Data_Registro") as data,
            dim."Nome" as dimensao_nome,
            ds."Score" as score,
            ds."Emoji" as emoji,
            CASE 
                WHEN LENGTH(ds."Comentario") > 200 
                THEN LEFT(ds."Comentario", 197) || '...'
                ELSE ds."Comentario"
            END as comentario,
            %L as schema_name
        FROM %I.registro_sentimentos rs
        INNER JOIN %I.detalhes_sentimento ds ON ds."Registro_ID" = rs."ID"
        INNER JOIN %I.dimensoes_sentimento dim ON dim."ID" = ds."Dimensao_ID"
        WHERE rs."Aluno_ID" = %s
        AND rs."Data_Registro" >= CURRENT_DATE - INTERVAL '%s days'
        AND dim."Status" = 'ATIVO'
        ORDER BY rs."Data_Registro" DESC, dim."Ordem_Exibicao"
        LIMIT 500
    $dynamic$,
        v_role_record.user_schema,
        v_role_record.user_schema,
        v_role_record.user_schema,
        v_role_record.user_schema,
        p_aluno_id,
        p_dias
    );
    
    RETURN QUERY EXECUTE v_sql;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.rpc_dashboard_sentimento_aluno(BIGINT, INTEGER) TO authenticated;

-- 3. Função para comparação entre períodos
-- ============================================
CREATE OR REPLACE FUNCTION public.rpc_dashboard_sentimento_comparacao(
    p_periodo1_inicio DATE,
    p_periodo1_fim DATE,
    p_periodo2_inicio DATE,
    p_periodo2_fim DATE
)
RETURNS TABLE (
    dimensao_nome VARCHAR,
    media_periodo1 NUMERIC,
    media_periodo2 NUMERIC,
    diferenca NUMERIC,
    percentual_mudanca NUMERIC,
    tendencia TEXT,
    schema_name TEXT,
    escola_nome TEXT
) 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_role_record RECORD;
    v_sql TEXT;
    v_result RECORD;
BEGIN
    -- SEGURANÇA: Validação robusta de sessão
    v_user_id := public.validate_user_session();
    
    -- Verificação de role
    SELECT 
        utm.schema_name AS user_schema,
        rp.role_type,
        rp.uf_code,
        rp.municipio_code
    INTO v_role_record
    FROM public.user_tenant_mapping utm
    LEFT JOIN public.role_permissions rp ON utm.special_role_id = rp.id
    WHERE utm.user_id = v_user_id
    AND utm.status = 'ATIVO'
    LIMIT 1;
    
    IF v_role_record.role_type = 'SEC_SEG_PUB' THEN
        RAISE EXCEPTION 'SEC_SEG_PUB não tem acesso a dados socioemocionais';
    END IF;
    
    -- Validar períodos
    IF p_periodo1_fim < p_periodo1_inicio OR p_periodo2_fim < p_periodo2_inicio THEN
        RAISE EXCEPTION 'Períodos inválidos: data final deve ser maior que inicial';
    END IF;
    
    -- Rate limiting
    IF NOT public.check_rate_limit(v_user_id, 'dashboard_sentimento_comparacao', 20, 5) THEN
        RAISE EXCEPTION 'Limite de requisições excedido';
    END IF;
    
    CREATE TEMP TABLE IF NOT EXISTS temp_comparacao_results (
        dimensao_nome VARCHAR,
        media_periodo1 NUMERIC,
        media_periodo2 NUMERIC,
        diferenca NUMERIC,
        percentual_mudanca NUMERIC,
        tendencia TEXT,
        schema_name TEXT,
        escola_nome TEXT
    ) ON COMMIT DROP;
    
    -- Processar cada escola permitida
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
            WITH periodo1 AS (
                SELECT 
                    dim."Nome" as dimensao_nome,
                    AVG(ds."Score")::NUMERIC as media,
                    COUNT(*) as registros
                FROM %I.registro_sentimentos rs
                INNER JOIN %I.detalhes_sentimento ds ON ds."Registro_ID" = rs."ID"
                INNER JOIN %I.dimensoes_sentimento dim ON dim."ID" = ds."Dimensao_ID"
                WHERE rs."Data_Registro" BETWEEN %L AND %L
                AND dim."Status" = 'ATIVO'
                GROUP BY dim."Nome"
            ),
            periodo2 AS (
                SELECT 
                    dim."Nome" as dimensao_nome,
                    AVG(ds."Score")::NUMERIC as media,
                    COUNT(*) as registros
                FROM %I.registro_sentimentos rs
                INNER JOIN %I.detalhes_sentimento ds ON ds."Registro_ID" = rs."ID"
                INNER JOIN %I.dimensoes_sentimento dim ON dim."ID" = ds."Dimensao_ID"
                WHERE rs."Data_Registro" BETWEEN %L AND %L
                AND dim."Status" = 'ATIVO'
                GROUP BY dim."Nome"
            )
            SELECT 
                COALESCE(p1.dimensao_nome, p2.dimensao_nome) as dimensao_nome,
                ROUND(COALESCE(p1.media, 0), 2) as media_periodo1,
                ROUND(COALESCE(p2.media, 0), 2) as media_periodo2,
                ROUND(COALESCE(p2.media, 0) - COALESCE(p1.media, 0), 2) as diferenca,
                CASE 
                    WHEN COALESCE(p1.media, 0) > 0 
                    THEN ROUND(((COALESCE(p2.media, 0) - COALESCE(p1.media, 0)) / p1.media) * 100, 2)
                    ELSE NULL
                END as percentual_mudanca,
                CASE 
                    WHEN p1.registros < 3 OR p2.registros < 3 THEN 'dados_insuficientes'
                    WHEN COALESCE(p2.media, 0) - COALESCE(p1.media, 0) > 0.5 THEN 'melhora_significativa'
                    WHEN COALESCE(p2.media, 0) - COALESCE(p1.media, 0) > 0.1 THEN 'melhora'
                    WHEN COALESCE(p2.media, 0) - COALESCE(p1.media, 0) < -0.5 THEN 'piora_significativa'
                    WHEN COALESCE(p2.media, 0) - COALESCE(p1.media, 0) < -0.1 THEN 'piora'
                    ELSE 'estavel'
                END as tendencia,
                %L as schema_name,
                %L as escola_nome
            FROM periodo1 p1
            FULL OUTER JOIN periodo2 p2 ON p1.dimensao_nome = p2.dimensao_nome
            ORDER BY dimensao_nome
        $dynamic$,
            v_result.schema_name,  -- periodo1 FROM
            v_result.schema_name,  -- periodo1 JOIN 1
            v_result.schema_name,  -- periodo1 JOIN 2
            p_periodo1_inicio,
            p_periodo1_fim,
            v_result.schema_name,  -- periodo2 FROM
            v_result.schema_name,  -- periodo2 JOIN 1
            v_result.schema_name,  -- periodo2 JOIN 2
            p_periodo2_inicio,
            p_periodo2_fim,
            v_result.schema_name,
            v_result.escola_nome
        );
        
        BEGIN
            FOR v_result IN EXECUTE v_sql
            LOOP
                INSERT INTO temp_comparacao_results VALUES (
                    v_result.dimensao_nome,
                    v_result.media_periodo1,
                    v_result.media_periodo2,
                    v_result.diferenca,
                    v_result.percentual_mudanca,
                    v_result.tendencia,
                    v_result.schema_name,
                    v_result.escola_nome
                );
            END LOOP;
        EXCEPTION WHEN OTHERS THEN
            CONTINUE;
        END;
    END LOOP;
    
    RETURN QUERY
    SELECT * FROM temp_comparacao_results
    ORDER BY escola_nome, dimensao_nome;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.rpc_dashboard_sentimento_comparacao(DATE, DATE, DATE, DATE) TO authenticated;

-- 4. Trigger para notificação em tempo real
-- ============================================
CREATE OR REPLACE FUNCTION notify_sentimento_change()
RETURNS TRIGGER AS $$
DECLARE
    v_payload JSONB;
BEGIN
    v_payload := jsonb_build_object(
        'schema', TG_TABLE_SCHEMA,
        'action', TG_OP,
        'registro_id', NEW."ID",
        'aluno_id', NEW."Aluno_ID",
        'data_registro', NEW."Data_Registro",
        'timestamp', NOW()
    );
    
    PERFORM pg_notify(
        'dashboard_sentimento_update',
        v_payload::text
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Função para aplicar trigger em um schema
-- ============================================
-- CORREÇÃO: Verificar existência antes de criar
CREATE OR REPLACE FUNCTION public.setup_sentimento_trigger(p_schema_name TEXT)
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
        WHERE tgname = 'trg_notify_sentimento_change'
        AND tgrelid = format('%I.registro_sentimentos', p_schema_name)::regclass
    ) THEN
        EXECUTE format($dynamic$
            CREATE TRIGGER trg_notify_sentimento_change
            AFTER INSERT OR UPDATE ON %I.registro_sentimentos
            FOR EACH ROW
            EXECUTE FUNCTION notify_sentimento_change()
        $dynamic$, p_schema_name);
        
        RAISE NOTICE 'Trigger de sentimento criado para schema %', p_schema_name;
    ELSE
        RAISE NOTICE 'Trigger de sentimento já existe para schema %', p_schema_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.setup_sentimento_trigger(TEXT) TO postgres;

-- ============================================
-- FIM DO SCRIPT SQL 04
-- ============================================