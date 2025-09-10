// Componentes principais do Dashboard MVP
export { DashboardMain } from './dashboard-main'
export { PresenceChart } from './presence-chart'
export { ComplaintsChart } from './complaints-chart'
export { EmotionalChart } from './emotional-chart'

// Hook para realtime
export { useRealtimeUpdates } from '@/hooks/use-realtime-updates'
export type { RealtimeEvent, RealtimeEventType } from '@/hooks/use-realtime-updates'
