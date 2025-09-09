-- ============================================
-- SQL 03 - RPC DASHBOARD DE DENÚNCIAS
-- ============================================
-- Descrição: Funções para agregação de dados de denúncias
-- com controle de acesso baseado em roles e filtro por categorias
--
-- SEGURANÇA: Requer execução de security-fixes.sql antes
-- ============================================

-- 1. Função principal para dashboard de denúncias
-- ============================================
CREATE OR REPLACE FUNCTION public.rpc_dashboard_denuncias(
    p_ano INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
    p_categorias TEXT[] DEFAULT NULL -- Agora opcional, busca da tabela se NULL
)
RETURNS TABLE (
    mes INTEGER,
    mes_nome TEXT,
    categoria VARCHAR,
    tratadas BIGINT,
    pendentes BIGINT,
    total BIGINT,
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
    v_categorias_permitidas TEXT[];
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
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuário sem permissão de acesso'
            USING HINT = 'Verifique se seu usuário está ativo e tem role atribuído';
    END IF;
    
    -- CORREÇÃO: Buscar categorias permitidas da tabela ao invés de hardcode
    IF p_categorias IS NULL THEN
        -- Buscar categorias do role na tabela
        SELECT array_agg(categoria) INTO v_categorias_permitidas
        FROM public.role_categoria_denuncia
        WHERE role_type = v_role_record.role_type
        AND ativo = true;
    ELSE
        -- Validar categorias passadas contra as permitidas
        SELECT array_agg(DISTINCT c) INTO v_categorias_permitidas
        FROM unnest(p_categorias) c
        WHERE c IN (
            SELECT categoria 
            FROM public.role_categoria_denuncia
            WHERE role_type = v_role_record.role_type
            AND ativo = true
        );
    END IF;
    
    -- Se não tem categorias permitidas, retornar vazio
    IF v_categorias_permitidas IS NULL OR array_length(v_categorias_permitidas, 1) = 0 THEN
        RETURN;
    END IF;
    
    -- Rate limiting
    IF NOT public.check_rate_limit(v_user_id, 'dashboard_denuncias', 50, 5) THEN
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
        request_params
    ) VALUES (
        v_user_id,
        v_role_record.role_type,
        'denuncias',
        NOW(),
        'rpc_dashboard_denuncias',
        jsonb_build_object(
            'ano', p_ano,
            'categorias', v_categorias_permitidas
        )
    );
    
    -- Criar tabela temporária para resultados
    CREATE TEMP TABLE IF NOT EXISTS temp_denuncias_results (
        mes INTEGER,
        mes_nome TEXT,
        categoria VARCHAR,
        tratadas BIGINT,
        pendentes BIGINT,
        total BIGINT,
        schema_name TEXT,
        escola_nome TEXT,
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
            
            -- SEC_SEG_PUB: escolas municipais e estaduais do estado
            OR (v_role_record.role_type = 'SEC_SEG_PUB' 
                AND i.co_uf = v_role_record.uf_code 
                AND i.tp_dependencia IN ('2', '3'))
            
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
        -- PERFORMANCE: Usar CTE para melhor otimização
        v_sql := format($dynamic$
            WITH meses AS (
                SELECT generate_series(1, 12) as mes
            ),
            denuncias_mes AS (
                SELECT 
                    EXTRACT(MONTH FROM "Criado_Em")::INTEGER as mes,
                    "Categoria",
                    COUNT(*) FILTER (WHERE "Status" IN ('RESOLVIDA', 'ARQUIVADA', 'REJEITADA')) as tratadas,
                    COUNT(*) FILTER (WHERE "Status" IN ('PENDENTE', 'EM_ANALISE')) as pendentes,
                    COUNT(*) as total
                FROM %I.denuncias
                WHERE EXTRACT(YEAR FROM "Criado_Em") = %s
                AND "Categoria" = ANY(%L)
                GROUP BY EXTRACT(MONTH FROM "Criado_Em"), "Categoria"
            ),
            agregado AS (
                SELECT 
                    m.mes,
                    CASE m.mes
                        WHEN 1 THEN 'Janeiro'
                        WHEN 2 THEN 'Fevereiro'
                        WHEN 3 THEN 'Março'
                        WHEN 4 THEN 'Abril'
                        WHEN 5 THEN 'Maio'
                        WHEN 6 THEN 'Junho'
                        WHEN 7 THEN 'Julho'
                        WHEN 8 THEN 'Agosto'
                        WHEN 9 THEN 'Setembro'
                        WHEN 10 THEN 'Outubro'
                        WHEN 11 THEN 'Novembro'
                        WHEN 12 THEN 'Dezembro'
                    END as mes_nome,
                    cat.categoria,
                    COALESCE(dm.tratadas, 0) as tratadas,
                    COALESCE(dm.pendentes, 0) as pendentes,
                    COALESCE(dm.total, 0) as total,
                    jsonb_build_object(
                        'tempo_medio_resolucao_dias', (
                            SELECT EXTRACT(DAY FROM AVG("Atualizado_Em" - "Criado_Em"))::INTEGER
                            FROM %I.denuncias
                            WHERE "Status" IN ('RESOLVIDA', 'ARQUIVADA')
                            AND EXTRACT(YEAR FROM "Criado_Em") = %s
                            AND EXTRACT(MONTH FROM "Criado_Em") = m.mes
                            AND "Categoria" = cat.categoria
                        ),
                        'anonimas', (
                            SELECT COUNT(*)
                            FROM %I.denuncias
                            WHERE "Anonima" = true
                            AND EXTRACT(YEAR FROM "Criado_Em") = %s
                            AND EXTRACT(MONTH FROM "Criado_Em") = m.mes
                            AND "Categoria" = cat.categoria
                        ),
                        'taxa_resolucao', CASE
                            WHEN COALESCE(dm.total, 0) > 0
                            THEN ROUND((COALESCE(dm.tratadas, 0)::NUMERIC / dm.total) * 100, 2)
                            ELSE 0
                        END
                    ) as detalhes
                FROM meses m
                CROSS JOIN (SELECT UNNEST(%L::TEXT[]) as categoria) cat
                LEFT JOIN denuncias_mes dm ON dm.mes = m.mes AND dm."Categoria" = cat.categoria
            )
            SELECT 
                mes,
                mes_nome,
                categoria,
                tratadas,
                pendentes,
                total,
                %L as schema_name,
                %L as escola_nome,
                detalhes
            FROM agregado
            WHERE mes <= EXTRACT(MONTH FROM CURRENT_DATE)
            OR %s < EXTRACT(YEAR FROM CURRENT_DATE)
            ORDER BY mes, categoria
        $dynamic$,
            v_result.schema_name,  -- FROM denuncias
            p_ano,                  -- WHERE YEAR
            v_categorias_permitidas,-- AND Categoria IN
            v_result.schema_name,  -- FROM denuncias (tempo_medio)
            p_ano,                  -- WHERE YEAR (tempo_medio)
            v_result.schema_name,  -- FROM denuncias (anonimas)
            p_ano,                  -- WHERE YEAR (anonimas)
            v_categorias_permitidas,-- UNNEST categorias
            v_result.schema_name,  -- SELECT schema_name
            v_result.escola_nome,  -- SELECT escola_nome
            p_ano                   -- OR ano < current_year
        );
        
        -- Executar query e inserir resultados
        BEGIN
            FOR v_result IN EXECUTE v_sql
            LOOP
                INSERT INTO temp_denuncias_results VALUES (
                    v_result.mes,
                    v_result.mes_nome,
                    v_result.categoria,
                    v_result.tratadas,
                    v_result.pendentes,
                    v_result.total,
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
                'denuncias',
                NOW(),
                FALSE,
                format('Erro no schema %s: %s', v_result.schema_name, SQLERRM),
                'rpc_dashboard_denuncias'
            );
        END;
    END LOOP;
    
    -- Retornar resultados agregados
    RETURN QUERY
    SELECT * FROM temp_denuncias_results
    ORDER BY escola_nome, mes, categoria;
    
END;
$$ LANGUAGE plpgsql;

-- Conceder execução para usuários autenticados
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_denuncias(INTEGER, TEXT[]) TO authenticated;

-- Documentação
COMMENT ON FUNCTION public.rpc_dashboard_denuncias IS 
'Retorna agregação mensal de denúncias por categoria e status.
SEGURANÇA: Valida sessão, schema e categorias permitidas por role.
PERFORMANCE: Usa CTEs para otimização e índices apropriados.';

-- 2. Função para obter resumo de denúncias por status
-- ============================================
CREATE OR REPLACE FUNCTION public.rpc_dashboard_denuncias_resumo()
RETURNS TABLE (
    schema_name TEXT,
    escola_nome TEXT,
    categoria VARCHAR,
    status VARCHAR,
    quantidade BIGINT,
    percentual NUMERIC
) 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_role_record RECORD;
    v_categorias_permitidas TEXT[];
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
    
    -- Buscar categorias permitidas do role
    SELECT array_agg(categoria) INTO v_categorias_permitidas
    FROM public.role_categoria_denuncia
    WHERE role_type = v_role_record.role_type
    AND ativo = true;
    
    -- Rate limiting
    IF NOT public.check_rate_limit(v_user_id, 'dashboard_denuncias_resumo', 50, 5) THEN
        RAISE EXCEPTION 'Limite de requisições excedido';
    END IF;
    
    CREATE TEMP TABLE IF NOT EXISTS temp_resumo_results (
        schema_name TEXT,
        escola_nome TEXT,
        categoria VARCHAR,
        status VARCHAR,
        quantidade BIGINT,
        percentual NUMERIC
    ) ON COMMIT DROP;
    
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
            OR (v_role_record.role_type = 'SEC_SEG_PUB' 
                AND i.co_uf = v_role_record.uf_code 
                AND i.tp_dependencia IN ('2', '3'))
            OR (v_role_record.role_type IS NULL 
                AND sr.schema_name = v_role_record.user_schema)
        )
    LOOP
        -- SEGURANÇA: Validar schema
        IF NOT public.validate_schema_access(v_result.schema_name, v_user_id) THEN
            CONTINUE;
        END IF;
        
        v_sql := format($dynamic$
            WITH totais AS (
                SELECT 
                    "Categoria",
                    "Status",
                    COUNT(*) as quantidade,
                    SUM(COUNT(*)) OVER (PARTITION BY "Categoria") as total_categoria
                FROM %I.denuncias
                WHERE "Categoria" = ANY(%L)
                GROUP BY "Categoria", "Status"
            )
            SELECT 
                %L as schema_name,
                %L as escola_nome,
                "Categoria" as categoria,
                "Status"::VARCHAR as status,
                quantidade,
                ROUND((quantidade::NUMERIC / NULLIF(total_categoria, 0)) * 100, 2) as percentual
            FROM totais
        $dynamic$,
            v_result.schema_name,
            v_categorias_permitidas,
            v_result.schema_name,
            v_result.escola_nome
        );
        
        BEGIN
            FOR v_result IN EXECUTE v_sql
            LOOP
                INSERT INTO temp_resumo_results VALUES (
                    v_result.schema_name,
                    v_result.escola_nome,
                    v_result.categoria,
                    v_result.status,
                    v_result.quantidade,
                    v_result.percentual
                );
            END LOOP;
        EXCEPTION WHEN OTHERS THEN
            CONTINUE;
        END;
    END LOOP;
    
    RETURN QUERY
    SELECT * FROM temp_resumo_results
    ORDER BY escola_nome, categoria, status;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.rpc_dashboard_denuncias_resumo() TO authenticated;

-- 3. Trigger para notificação em tempo real de mudanças em denúncias
-- ============================================
CREATE OR REPLACE FUNCTION notify_denuncias_change()
RETURNS TRIGGER AS $$
DECLARE
    v_payload JSONB;
    v_old_status TEXT;
    v_new_status TEXT;
BEGIN
    -- Determinar status antigo e novo
    IF TG_OP = 'UPDATE' THEN
        v_old_status := OLD."Status";
        v_new_status := NEW."Status";
    ELSE
        v_old_status := NULL;
        v_new_status := NEW."Status";
    END IF;
    
    -- Construir payload
    v_payload := jsonb_build_object(
        'schema', TG_TABLE_SCHEMA,
        'action', TG_OP,
        'denuncia_id', NEW."ID",
        'categoria', NEW."Categoria",
        'status_anterior', v_old_status,
        'status_novo', v_new_status,
        'anonima', NEW."Anonima",
        'protocolo', NEW."Protocolo",
        'timestamp', NOW()
    );
    
    -- Enviar notificação
    PERFORM pg_notify(
        'dashboard_denuncias_update',
        v_payload::text
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Função para aplicar trigger em um schema específico
-- ============================================
-- CORREÇÃO: Verificar existência antes de criar
CREATE OR REPLACE FUNCTION public.setup_denuncias_trigger(p_schema_name TEXT)
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
        WHERE tgname = 'trg_notify_denuncias_change'
        AND tgrelid = format('%I.denuncias', p_schema_name)::regclass
    ) THEN
        EXECUTE format($dynamic$
            CREATE TRIGGER trg_notify_denuncias_change
            AFTER INSERT OR UPDATE ON %I.denuncias
            FOR EACH ROW
            EXECUTE FUNCTION notify_denuncias_change()
        $dynamic$, p_schema_name);
        
        RAISE NOTICE 'Trigger de denúncias criado para schema %', p_schema_name;
    ELSE
        RAISE NOTICE 'Trigger de denúncias já existe para schema %', p_schema_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.setup_denuncias_trigger(TEXT) TO postgres;

-- 5. Função para obter detalhes de denúncias específicas
-- ============================================
CREATE OR REPLACE FUNCTION public.rpc_dashboard_denuncias_detalhes(
    p_categoria TEXT DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_limite INTEGER DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    protocolo VARCHAR,
    categoria VARCHAR,
    status TEXT,
    descricao TEXT,
    anonima BOOLEAN,
    criado_em TIMESTAMPTZ,
    atualizado_em TIMESTAMPTZ,
    dias_aberto INTEGER,
    schema_name TEXT,
    escola_nome TEXT
) 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_role_record RECORD;
    v_categorias_permitidas TEXT[];
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
    
    -- Buscar categorias permitidas
    SELECT array_agg(categoria) INTO v_categorias_permitidas
    FROM public.role_categoria_denuncia
    WHERE role_type = v_role_record.role_type
    AND ativo = true;
    
    -- Se categoria específica solicitada, validar se permitida
    IF p_categoria IS NOT NULL AND NOT (p_categoria = ANY(v_categorias_permitidas)) THEN
        RETURN;
    END IF;
    
    -- Rate limiting
    IF NOT public.check_rate_limit(v_user_id, 'dashboard_denuncias_detalhes', 20, 5) THEN
        RAISE EXCEPTION 'Limite de requisições excedido';
    END IF;
    
    CREATE TEMP TABLE IF NOT EXISTS temp_detalhes_results (
        id UUID,
        protocolo VARCHAR,
        categoria VARCHAR,
        status TEXT,
        descricao TEXT,
        anonima BOOLEAN,
        criado_em TIMESTAMPTZ,
        atualizado_em TIMESTAMPTZ,
        dias_aberto INTEGER,
        schema_name TEXT,
        escola_nome TEXT
    ) ON COMMIT DROP;
    
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
            OR (v_role_record.role_type = 'SEC_SEG_PUB' 
                AND i.co_uf = v_role_record.uf_code 
                AND i.tp_dependencia IN ('2', '3'))
            OR (v_role_record.role_type IS NULL 
                AND sr.schema_name = v_role_record.user_schema)
        )
        LIMIT 10 -- Limitar número de escolas para performance
    LOOP
        -- SEGURANÇA: Validar schema
        IF NOT public.validate_schema_access(v_result.schema_name, v_user_id) THEN
            CONTINUE;
        END IF;
        
        v_sql := format($dynamic$
            SELECT 
                "ID" as id,
                "Protocolo" as protocolo,
                "Categoria" as categoria,
                "Status"::TEXT as status,
                CASE 
                    WHEN "Anonima" = true THEN '[Conteúdo protegido - Denúncia anônima]'
                    ELSE LEFT("Descricao", 200)
                END as descricao,
                "Anonima" as anonima,
                "Criado_Em" as criado_em,
                "Atualizado_Em" as atualizado_em,
                EXTRACT(DAY FROM (NOW() - "Criado_Em"))::INTEGER as dias_aberto,
                %L as schema_name,
                %L as escola_nome
            FROM %I.denuncias
            WHERE 1=1
            %s  -- Filtro de categoria
            %s  -- Filtro de status
            %s  -- Filtro de categorias permitidas
            ORDER BY "Criado_Em" DESC
            LIMIT %s
        $dynamic$,
            v_result.schema_name,
            v_result.escola_nome,
            v_result.schema_name,
            CASE WHEN p_categoria IS NOT NULL 
                THEN format('AND "Categoria" = %L', p_categoria) 
                ELSE '' 
            END,
            CASE WHEN p_status IS NOT NULL 
                THEN format('AND "Status" = %L', p_status) 
                ELSE '' 
            END,
            format('AND "Categoria" = ANY(%L)', v_categorias_permitidas),
            p_limite
        );
        
        BEGIN
            FOR v_result IN EXECUTE v_sql
            LOOP
                INSERT INTO temp_detalhes_results VALUES (
                    v_result.id,
                    v_result.protocolo,
                    v_result.categoria,
                    v_result.status,
                    v_result.descricao,
                    v_result.anonima,
                    v_result.criado_em,
                    v_result.atualizado_em,
                    v_result.dias_aberto,
                    v_result.schema_name,
                    v_result.escola_nome
                );
            END LOOP;
        EXCEPTION WHEN OTHERS THEN
            CONTINUE;
        END;
    END LOOP;
    
    RETURN QUERY
    SELECT * FROM temp_detalhes_results
    ORDER BY criado_em DESC
    LIMIT p_limite;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.rpc_dashboard_denuncias_detalhes(TEXT, TEXT, INTEGER) TO authenticated;

-- ============================================
-- FIM DO SCRIPT SQL 03
-- ============================================