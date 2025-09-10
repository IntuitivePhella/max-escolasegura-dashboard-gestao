"use client"

import { useState, useEffect } from 'react'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

export type RealtimeEventType = 'presence_update' | 'complaint_update' | 'emotional_update' | 'security_update'

export interface RealtimeEvent {
  id: string
  type: RealtimeEventType
  data: unknown
  timestamp: Date
}

export function useRealtimeUpdates(role: 'DIRETORIA' | 'SEC_EDUC_MUN' | 'SEC_EDUC_EST' | 'SEC_SEG_PUB', schemas: string[]) {
  const [updates, setUpdates] = useState<RealtimeEvent[]>([])
  const [isConnected, setIsConnected] = useState(false)

  useEffect(() => {
    // Cria uma lista de canais para cada schema
    const channels = schemas.map(schema => {
      const channel = supabase.channel(`dashboard-${role}-${schema}`)

      // Escuta mudanças em tempo real
      channel.on('postgres_changes', {
        event: '*',
        schema: schema,
        table: role === 'SEC_SEG_PUB' ? 'denuncias' : '*'
      }, (payload) => {
        const event: RealtimeEvent = {
          id: crypto.randomUUID(),
          type: determineEventType(payload, role),
          data: payload.new || payload.old,
          timestamp: new Date()
        }

        setUpdates(prev => [event, ...prev.slice(0, 9)]) // Mantém apenas os últimos 10
      })

      return channel
    })

    // Conecta todos os canais
    Promise.all(channels.map(channel => channel.subscribe()))
      .then(() => {
        setIsConnected(true)
        console.log(`Realtime connected for ${role}`)
      })
      .catch((error) => {
        console.error('Erro ao conectar realtime:', error)
        setIsConnected(false)
      })

    // Cleanup
    return () => {
      channels.forEach(channel => {
        supabase.removeChannel(channel)
      })
      setIsConnected(false)
    }
  }, [role, schemas])

  return {
    updates,
    isConnected,
    clearUpdates: () => setUpdates([])
  }
}

// Função auxiliar para determinar o tipo de evento
function determineEventType(payload: unknown, role: string): RealtimeEventType {
  if (role === 'SEC_SEG_PUB') {
    return 'security_update'
  }

  // Type guard para acessar propriedades do payload
  if (typeof payload === 'object' && payload !== null && 'table' in payload) {
    const table = (payload as { table: string }).table

    switch (table) {
      case 'eventos_acesso_diario':
        return 'presence_update'
      case 'denuncias':
        return 'complaint_update'
      case 'registro_sentimentos':
        return 'emotional_update'
      default:
        return 'presence_update'
    }
  }

  return 'presence_update'
}
