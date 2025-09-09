/**
 * Interfaces TypeScript para Dashboard Max Escola Segura
 * 
 * Define todos os tipos de dados para os 4 indicadores:
 * 1. Presença (Radial Chart)
 * 2. Denúncias Educacionais (Bar Chart Stacked)
 * 3. Socioemocional (Radar Chart)
 * 4. Denúncias de Segurança (Bar Chart Stacked)
 */

// ============================================
// 1. INDICADOR DE PRESENÇA (Radial Chart)
// ============================================

/**
 * Dados de presença para um período específico
 */
export interface PresenceData {
  /** Nome da escola */
  escola_nome: string;
  /** Código INEP da escola */
  codigo_inep: string;
  /** Schema da escola */
  schema_name: string;
  /** Código do estado */
  co_uf: string;
  /** Código do município */
  co_municipio: string;
  /** Número de alunos presentes */
  presentes: number;
  /** Total de alunos matriculados */
  total: number;
  /** Percentual de presença (0-100) */
  pct_presenca: number;
  /** Data de referência */
  data_referencia: string;
  /** Detalhes adicionais em JSON */
  detalhes?: Record<string, unknown>;
}

/**
 * Resposta da API de presença
 */
export interface PresenceApiResponse {
  data: PresenceData[];
  total_schools: number;
  avg_presence: number;
  durationMs: number;
  timestamp: string;
}

// ============================================
// 2. DENÚNCIAS EDUCACIONAIS (Bar Chart Stacked)
// ============================================

/**
 * Categorias de denúncias educacionais
 */
export type EducationalComplaintCategory = 'bullying' | 'infraestrutura' | 'outros';

/**
 * Status de denúncias
 */
export type ComplaintStatus = 'tratada' | 'pendente';

/**
 * Dados de denúncias por categoria e status
 */
export interface ComplaintCategoryData {
  tratadas: number;
  pendentes: number;
  total: number;
}

/**
 * Dados de denúncias educacionais por mês
 */
export interface EducationalComplaintData {
  /** Mês de referência (YYYY-MM) */
  mes: string;
  /** Nome da escola */
  escola_nome: string;
  /** Schema da escola */
  schema_name: string;
  /** Denúncias de bullying */
  bullying: ComplaintCategoryData;
  /** Denúncias de infraestrutura */
  infraestrutura: ComplaintCategoryData;
  /** Outras denúncias */
  outros: ComplaintCategoryData;
  /** Total geral */
  total_geral: ComplaintCategoryData;
}

/**
 * Resposta da API de denúncias educacionais
 */
export interface EducationalComplaintApiResponse {
  data: EducationalComplaintData[];
  period: {
    start: string;
    end: string;
  };
  summary: {
    total_complaints: number;
    resolved_percentage: number;
    most_common_category: EducationalComplaintCategory;
  };
  durationMs: number;
  timestamp: string;
}

// ============================================
// 3. SOCIOEMOCIONAL (Radar Chart)
// ============================================

/**
 * Dimensões socioemocionais baseadas na estrutura real do banco
 */
export type EmotionalDimension = 
  | 'Colegas'
  | 'Humor'
  | 'Professores'
  | 'Saúde';

/**
 * Dados socioemocionais por dimensão
 */
export interface EmotionalData {
  /** Nome da escola */
  escola_nome: string;
  /** Schema da escola */
  schema_name: string;
  /** Dimensão avaliada */
  dimensao: EmotionalDimension;
  /** Score atual (0-10) */
  score: number;
  /** Score máximo possível */
  max_score: number;
  /** Score do período anterior (para comparação) */
  periodo_anterior?: number;
  /** Número de alunos avaliados */
  alunos_avaliados: number;
  /** Data da última avaliação */
  ultima_avaliacao: string;
  /** Tendência: 'up', 'down', 'stable' */
  tendencia: 'up' | 'down' | 'stable';
}

/**
 * Dados consolidados socioemocionais por escola
 */
export interface EmotionalSchoolData {
  escola_nome: string;
  schema_name: string;
  dimensoes: EmotionalData[];
  score_geral: number;
  ranking_escola: number;
  total_escolas: number;
}

/**
 * Resposta da API socioemocional
 */
export interface EmotionalApiResponse {
  data: EmotionalSchoolData[];
  period: {
    start: string;
    end: string;
  };
  summary: {
    avg_score: number;
    best_dimension: EmotionalDimension;
    worst_dimension: EmotionalDimension;
    total_students_evaluated: number;
  };
  durationMs: number;
  timestamp: string;
}

// ============================================
// 4. DENÚNCIAS DE SEGURANÇA (Bar Chart Stacked)
// ============================================

/**
 * Categorias de denúncias de segurança
 */
export type SecurityComplaintCategory = 
  | 'trafico'
  | 'assedio'
  | 'discriminacao'
  | 'violencia'
  | 'outros';

/**
 * Dados de denúncias de segurança por mês
 */
export interface SecurityComplaintData {
  /** Mês de referência (YYYY-MM) */
  mes: string;
  /** Estado */
  co_uf: string;
  /** Município (para SEC_EDUC_MUN) */
  co_municipio?: string;
  /** Denúncias de tráfico */
  trafico: ComplaintCategoryData;
  /** Denúncias de assédio */
  assedio: ComplaintCategoryData;
  /** Denúncias de discriminação */
  discriminacao: ComplaintCategoryData;
  /** Denúncias de violência */
  violencia: ComplaintCategoryData;
  /** Outras denúncias */
  outros: ComplaintCategoryData;
  /** Total geral */
  total_geral: ComplaintCategoryData;
  /** Escolas afetadas */
  escolas_afetadas: number;
}

/**
 * Resposta da API de denúncias de segurança
 */
export interface SecurityComplaintApiResponse {
  data: SecurityComplaintData[];
  period: {
    start: string;
    end: string;
  };
  summary: {
    total_complaints: number;
    resolved_percentage: number;
    most_critical_category: SecurityComplaintCategory;
    affected_schools: number;
  };
  durationMs: number;
  timestamp: string;
}

// ============================================
// 5. TIPOS COMUNS E UTILITÁRIOS
// ============================================

/**
 * Roles de usuário do sistema
 */
export type UserRole = 
  | 'DIRETORIA'
  | 'SEC_EDUC_MUN'
  | 'SEC_EDUC_EST'
  | 'SEC_SEG_PUB';

/**
 * Informações do usuário autenticado
 */
export interface AuthenticatedUser {
  id: string;
  email: string;
  role: UserRole;
  allowed_schemas: string[];
  permissions: Record<string, boolean>;
  uf_code?: string;
  municipio_code?: string;
  escola_code?: string;
}

/**
 * Filtros de período para dashboards
 */
export interface PeriodFilter {
  start_date: string;
  end_date: string;
  period_type: 'day' | 'week' | 'month' | 'quarter' | 'year';
}

/**
 * Filtros de escola
 */
export interface SchoolFilter {
  schema_names?: string[];
  co_uf?: string;
  co_municipio?: string;
  codigo_inep?: string[];
}

/**
 * Parâmetros comuns de API
 */
export interface DashboardApiParams {
  period?: PeriodFilter;
  schools?: SchoolFilter;
  user_id?: string;
}

/**
 * Resposta padrão de erro da API
 */
export interface ApiErrorResponse {
  error: {
    message: string;
    code: string;
    details?: Record<string, unknown>;
  };
  data: null;
  timestamp: string;
}

/**
 * Resposta de sucesso genérica da API
 */
export interface ApiSuccessResponse<T> {
  data: T;
  error: null;
  durationMs: number;
  timestamp: string;
  metadata?: Record<string, unknown>;
}

/**
 * Union type para todas as respostas de API
 */
export type ApiResponse<T> = ApiSuccessResponse<T> | ApiErrorResponse;

// ============================================
// 6. TIPOS PARA COMPONENTES DE GRÁFICOS
// ============================================

/**
 * Props para componente de gráfico radial (presença)
 */
export interface RadialChartProps {
  data: PresenceData[];
  title?: string;
  showLegend?: boolean;
  animate?: boolean;
  colors?: {
    present: string;
    absent: string;
  };
}

/**
 * Props para componente de gráfico de barras empilhadas
 */
export interface StackedBarChartProps {
  data: EducationalComplaintData[] | SecurityComplaintData[];
  title?: string;
  showLegend?: boolean;
  animate?: boolean;
  colors?: {
    tratada: string;
    pendente: string;
  };
}

/**
 * Props para componente de gráfico radar (socioemocional)
 */
export interface RadarChartProps {
  data: EmotionalSchoolData[];
  title?: string;
  showComparison?: boolean;
  animate?: boolean;
  colors?: string[];
}

/**
 * Props para seletor de escolas
 */
export interface SchoolSelectorProps {
  availableSchools: Array<{
    schema_name: string;
    escola_nome: string;
    codigo_inep: string;
  }>;
  selectedSchools: string[];
  onSelectionChange: (selected: string[]) => void;
  userRole: UserRole;
  maxSelections?: number;
}

// ============================================
// 7. TIPOS PARA REALTIME UPDATES
// ============================================

/**
 * Tipos de eventos realtime
 */
export type RealtimeEventType = 
  | 'presence_update'
  | 'complaint_update'
  | 'emotional_update'
  | 'security_update';

/**
 * Payload de evento realtime
 */
export interface RealtimeEvent {
  type: RealtimeEventType;
  schema_name: string;
  timestamp: string;
  data: unknown;
  user_id?: string;
}

/**
 * Configuração de subscriptions realtime
 */
export interface RealtimeSubscriptionConfig {
  events: RealtimeEventType[];
  schemas: string[];
  callback: (event: RealtimeEvent) => void;
}

// ============================================
// 8. VALIDAÇÃO COM ZOD
// ============================================

import { z } from 'zod';

/**
 * Schema Zod para validação de dados de presença
 */
export const PresenceDataSchema = z.object({
  escola_nome: z.string().min(1),
  codigo_inep: z.string().length(8),
  schema_name: z.string().regex(/^escola_[0-9]{8}$/),
  co_uf: z.string().length(2),
  co_municipio: z.string().min(1),
  presentes: z.number().int().min(0),
  total: z.number().int().min(0),
  pct_presenca: z.number().min(0).max(100),
  data_referencia: z.string().datetime(),
  detalhes: z.record(z.any()).optional(),
});

/**
 * Schema Zod para validação de parâmetros da API
 */
export const DashboardApiParamsSchema = z.object({
  period: z.object({
    start_date: z.string().datetime(),
    end_date: z.string().datetime(),
    period_type: z.enum(['day', 'week', 'month', 'quarter', 'year']),
  }).optional(),
  schools: z.object({
    schema_names: z.array(z.string()).optional(),
    co_uf: z.string().length(2).optional(),
    co_municipio: z.string().optional(),
    codigo_inep: z.array(z.string().length(8)).optional(),
  }).optional(),
  user_id: z.string().uuid().optional(),
});

/**
 * Schema Zod para validação de roles
 */
export const UserRoleSchema = z.enum(['DIRETORIA', 'SEC_EDUC_MUN', 'SEC_EDUC_EST', 'SEC_SEG_PUB']);

// ============================================
// 9. CONSTANTES
// ============================================

/**
 * Cores padrão para gráficos
 */
export const CHART_COLORS = {
  presence: {
    present: '#22c55e', // green-500
    absent: '#6b7280',  // gray-500
  },
  complaints: {
    tratada: '#3b82f6', // blue-500
    pendente: '#f97316', // orange-500
  },
  security: {
    tratada: '#22c55e', // green-500
    pendente: '#ef4444', // red-500
  },
  emotional: [
    '#8b5cf6', // violet-500
    '#06b6d4', // cyan-500
    '#10b981', // emerald-500
    '#f59e0b', // amber-500
    '#ef4444', // red-500
    '#8b5cf6', // violet-500
  ],
} as const;

/**
 * Configurações padrão de período
 */
export const DEFAULT_PERIODS = {
  last_7_days: {
    start_date: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
    end_date: new Date().toISOString(),
    period_type: 'day' as const,
  },
  last_30_days: {
    start_date: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
    end_date: new Date().toISOString(),
    period_type: 'day' as const,
  },
  current_month: {
    start_date: new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString(),
    end_date: new Date().toISOString(),
    period_type: 'day' as const,
  },
} as const;

