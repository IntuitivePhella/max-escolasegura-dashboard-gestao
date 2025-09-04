import { igniter } from '@/igniter'
import { z } from 'zod'
import { createClient as createSupabaseClient } from '@supabase/supabase-js'
import { createServerClient } from '@supabase/ssr'

type RequestCookies = { get?: (name: string) => { value?: string } | undefined }
interface IgniterLikeHeaders { get?: (name: string) => string | null; cookie?: string }
interface IgniterLikeRequest { cookies?: RequestCookies; headers?: IgniterLikeHeaders }

const summaryItemSchema = z.object({
  schema_name: z.string(),
  total_eventos: z.number().nullable().optional(),
  eventos_24h: z.number().nullable().optional(),
  eventos_1h: z.number().nullable().optional(),
  eventos_pendentes: z.number().nullable().optional(),
  notif_falhas: z.number().nullable().optional(),
  evento_mais_antigo: z.string().nullable().optional(),
  evento_mais_recente: z.string().nullable().optional(),
  dias_agregados: z.number().nullable().optional(),
  total_movimentacoes: z.number().nullable().optional(),
  ultima_agregacao: z.string().nullable().optional(),
  media_diaria: z.number().nullable().optional(),
  eventos_arquivados: z.number().nullable().optional(),
  arquivo_mais_antigo: z.string().nullable().optional(),
  arquivo_mais_recente: z.string().nullable().optional(),
  tamanho_eventos: z.number().nullable().optional(),
  tamanho_diario: z.number().nullable().optional(),
  tamanho_arquivo: z.number().nullable().optional(),
  health_status: z.string().nullable().optional(),
  alerta: z.string().nullable().optional(),
  taxa_processamento: z.number().nullable().optional(),
  taxa_notificacao: z.number().nullable().optional(),
})

const alertsItemSchema = z.object({
  schema_name: z.string(),
  total_alerts: z.number().nullable().optional(),
  latest_alert: z.string().nullable().optional(),
})

const mappingRowSchema = z.object({ schema_name: z.string(), role: z.string().nullable().optional() })

function parseCookieHeader(header: string | null | undefined): Record<string, string> {
  const map: Record<string, string> = {}
  if (!header) return map
  const parts = header.split(/;\s*/)
  for (const part of parts) {
    const idx = part.indexOf('=')
    if (idx > 0) {
      const k = decodeURIComponent(part.substring(0, idx))
      const v = decodeURIComponent(part.substring(idx + 1))
      map[k] = v
    }
  }
  return map
}

function createSSRClientFromRequest(request: IgniterLikeRequest) {
  const cookieHeader = request?.headers?.get?.('cookie') ?? request?.headers?.cookie ?? null
  const cookieMap = parseCookieHeader(cookieHeader)
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL as string,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string,
    {
      cookies: {
        get(name: string) {
          const v = cookieMap[name]
          return v ? v : undefined
        },
        set() {},
        remove() {},
      },
    }
  )
}

async function getUserSchemas(request: IgniterLikeRequest) {
  const supabase = createSSRClientFromRequest(request)
  const { data: userData } = await supabase.auth.getUser()
  if (!userData?.user) {
    return { userId: null as string | null, schemas: [] as string[], roles: [] as string[] }
  }
  const userId = userData.user.id
  const { data } = await supabase
    .from('user_tenant_mapping')
    .select('schema_name, role')
    .eq('user_id', userId)

  const rows = z.array(mappingRowSchema).parse(data ?? [])
  const schemas = rows.map(r => r.schema_name)
  const roles = rows.map(r => r.role ?? '').filter(Boolean)
  return { userId, schemas, roles }
}

export const dashboardController = igniter.controller({
  name: 'dashboard',
  path: '/dashboard',
  actions: {
    schemas: igniter.query({
      path: '/schemas',
      handler: async ({ request, response }) => {
        const info = await getUserSchemas(request as IgniterLikeRequest)
        if (!info.userId) return response.unauthorized('Not authenticated')
        return response.success({ userId: info.userId, schemas: info.schemas, roles: info.roles })
      },
    }),

    summary: igniter.query({
      path: '/summary',
      handler: async ({ request, response }) => {
        const info = await getUserSchemas(request as IgniterLikeRequest)
        if (!info.userId) return response.unauthorized('Not authenticated')
        const finalSchemas = info.schemas

        const supabase = createSupabaseClient(
          process.env.NEXT_PUBLIC_SUPABASE_URL as string,
          process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string
        )

        let dbq = supabase.from('dashboard_consolidado').select('*')
        if (finalSchemas.length > 0) {
          dbq = dbq.in('schema_name', finalSchemas)
        }

        const t0 = performance.now()
        const { data: initialData, error: initialError } = await dbq

        if (initialError) {
          return response.badRequest('Supabase error', initialError)
        }

        let dataOut: Array<z.infer<typeof summaryItemSchema>> = (initialData as any[]) ?? []

        // Fallback: se view consolidada vazia, compor a partir de eventos
        if (!dataOut || dataOut.length === 0) {
          let evq = supabase.from('eventos_acesso_dashboard').select('*')
          if (finalSchemas.length > 0) {
            evq = evq.in('schema_name', finalSchemas)
          }
          const { data: evData, error: evErr } = await evq
          if (evErr) return response.badRequest('Supabase error', evErr)
          const mapped: Array<z.infer<typeof summaryItemSchema>> = (evData ?? []).map((r: Record<string, any>) => ({
            schema_name: String(r.schema_name),
            total_eventos: r.total_eventos ?? null,
            eventos_24h: r.eventos_24h ?? null,
            eventos_1h: r.eventos_1h ?? null,
            eventos_pendentes: r.eventos_pendentes ?? null,
            notif_falhas: r.notif_falhas ?? null,
            evento_mais_antigo: r.evento_mais_antigo ?? null,
            evento_mais_recente: r.evento_mais_recente ?? null,
            dias_agregados: r.dias_agregados ?? null,
            total_movimentacoes: r.total_movimentacoes ?? null,
            ultima_agregacao: r.ultima_agregacao ?? null,
            health_status: r.health_status ?? null,
            media_diaria: null,
            eventos_arquivados: null,
            arquivo_mais_antigo: null,
            arquivo_mais_recente: null,
            tamanho_eventos: null,
            tamanho_diario: null,
            tamanho_arquivo: null,
            alerta: null,
            taxa_processamento: null,
            taxa_notificacao: null,
          }))
          dataOut = mapped
        }
        const t1 = performance.now()

        const parsed = z.array(summaryItemSchema).safeParse(dataOut ?? [])
        if (!parsed.success) {
          return response.badRequest('Invalid response shape', parsed.error)
        }

        return response.success({ durationMs: +(t1 - t0).toFixed(2), rows: parsed.data.length, data: parsed.data })
      },
    }),

    events: igniter.query({
      path: '/events',
      handler: async ({ request, response }) => {
        const info = await getUserSchemas(request as IgniterLikeRequest)
        if (!info.userId) return response.unauthorized('Not authenticated')
        const finalSchemas = info.schemas

        const supabase = createSupabaseClient(
          process.env.NEXT_PUBLIC_SUPABASE_URL as string,
          process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string
        )

        let dbq = supabase.from('eventos_acesso_dashboard').select('*')
        if (finalSchemas.length > 0) {
          dbq = dbq.in('schema_name', finalSchemas)
        } else {
          return response.success({ durationMs: 0, rows: 0, data: [] })
        }

        const t0 = performance.now()
        const { data, error } = await dbq
        const t1 = performance.now()

        if (error) {
          return response.badRequest('Supabase error', error)
        }

        return response.success({ durationMs: +(t1 - t0).toFixed(2), rows: data?.length ?? 0, data })
      },
    }),

    alerts: igniter.query({
      path: '/alerts',
      handler: async ({ request, response }) => {
        const info = await getUserSchemas(request as IgniterLikeRequest)
        if (!info.userId) return response.unauthorized('Not authenticated')
        const finalSchemas = info.schemas

        const supabase = createSupabaseClient(
          process.env.NEXT_PUBLIC_SUPABASE_URL as string,
          process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string
        )

        let dbq = supabase.from('v_health_alerts_monitor').select('*')
        if (finalSchemas.length > 0) {
          dbq = dbq.in('schema_name', finalSchemas)
        } else {
          return response.success({ durationMs: 0, rows: 0, data: [] })
        }

        const t0 = performance.now()
        const { data, error } = await dbq
        const t1 = performance.now()

        if (error) {
          return response.badRequest('Supabase error', error)
        }

        const parsed = z.array(alertsItemSchema).safeParse(data ?? [])
        if (!parsed.success) {
          return response.badRequest('Invalid response shape', parsed.error)
        }

        return response.success({ durationMs: +(t1 - t0).toFixed(2), rows: parsed.data.length, data: parsed.data })
      },
    }),
  },
})
