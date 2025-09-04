import { api } from '@/igniter.client'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'

type SummaryRow = {
  schema_name: string
  total_eventos: number | null
  eventos_pendentes: number | null
  health_status: string | null
}

type SummaryResponse = { durationMs: number; rows: number; data: SummaryRow[] | unknown[] }

type EventsRow = {
  schema_name: string
  total_eventos: number | null
  eventos_pendentes: number | null
  health_status: string | null
}

type AlertsRow = { schema_name: string; total_alerts: number | null }

type SchemasResponse = { userId: string | null; schemas: string[]; roles: string[] }

export default async function Home() {
  let rows = 0
  let duration = 0
  let error: string | null = null
  let allowedSchemas: string[] = []
  let kpiTotal = 0
  let kpiPendentes = 0
  let kpiAlerts = 0
  let kpiHealth: string = 'UNKNOWN'

  try {
    const sch = await api.dashboard.schemas.query()
    const sPayload = (sch.data ?? { userId: null, schemas: [], roles: [] }) as SchemasResponse
    allowedSchemas = sPayload.schemas ?? []

    const ev = await api.dashboard.events.query()
    const evPayload = (ev.data ?? { data: [] }) as { data?: EventsRow[] }
    const evRows: EventsRow[] = evPayload.data ?? []

    const al = await api.dashboard.alerts.query()
    const alPayload = (al.data ?? { data: [] }) as { data?: AlertsRow[] }
    const alRows: AlertsRow[] = alPayload.data ?? []

    kpiTotal = evRows.reduce((acc, r) => acc + (r.total_eventos ?? 0), 0)
    kpiPendentes = evRows.reduce((acc, r) => acc + (r.eventos_pendentes ?? 0), 0)
    kpiAlerts = alRows.reduce((acc, r) => acc + (r.total_alerts ?? 0), 0)
    const healths = evRows.map(r => r.health_status || 'UNKNOWN')
    kpiHealth = healths.includes('WARNING') ? 'WARNING' : (healths.includes('ERROR') ? 'ERROR' : (healths.includes('HEALTHY') ? 'HEALTHY' : 'UNKNOWN'))

    const res = await api.dashboard.summary.query()
    const payload = (res.data ?? { durationMs: 0, rows: 0, data: [] }) as SummaryResponse
    rows = payload.rows ?? 0
    duration = payload.durationMs ?? 0
  } catch (e: unknown) {
    error = e instanceof Error ? e.message : 'Erro ao carregar'
  }

  return (
    <main className="flex min-h-screen flex-col items-center justify-start p-10 gap-8">
      <div className="container max-w-5xl mx-auto space-y-4">
        <h1 className="text-3xl font-bold tracking-tighter sm:text-5xl text-center">
          Dashboard Max Escola Segura
        </h1>
        {error ? (
          <p className="text-red-500 text-center">{error}</p>
        ) : (
          <>
            <p className="text-muted-foreground text-center">Escolas permitidas: {allowedSchemas.join(', ') || 'nenhuma'}</p>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-6">
              <Card>
                <CardHeader>
                  <CardTitle>Total de eventos</CardTitle>
                  <CardDescription>Somatório no(s) schema(s) autorizado(s)</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="text-3xl font-semibold">{kpiTotal}</div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader>
                  <CardTitle>Pendentes</CardTitle>
                  <CardDescription>Aguardando processamento</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="text-3xl font-semibold">{kpiPendentes}</div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader>
                  <CardTitle>Alertas</CardTitle>
                  <CardDescription>Registros de saúde</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="text-3xl font-semibold">{kpiAlerts}</div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader>
                  <CardTitle>Saúde</CardTitle>
                  <CardDescription>Status consolidado</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="text-3xl font-semibold">{kpiHealth}</div>
                </CardContent>
              </Card>
            </div>
            <div className="text-center mt-8 text-sm text-muted-foreground">
              <p>Registros no summary: {rows} • Tempo da consulta: {duration} ms</p>
            </div>
          </>
        )}
        </div>
      </main>
  )
}
