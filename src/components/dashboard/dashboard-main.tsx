"use client"

import { useState } from "react"
import { Phone, AlertTriangle } from "lucide-react"

import { PresenceChart } from "./presence-chart"
import { ComplaintsChart } from "./complaints-chart"
import { EmotionalChart } from "./emotional-chart"
import { useRealtimeUpdates } from "@/hooks/use-realtime-updates"

import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import {
  Alert,
  AlertDescription,
  AlertTitle,
} from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"

interface ComplaintsData {
  mes: string
  tratadas: number
  pendentes: number
}

interface EmotionalData {
  dimensao: string
  score: number
}

interface DashboardMainProps {
  role: 'DIRETORIA' | 'SEC_EDUC_MUN' | 'SEC_EDUC_EST' | 'SEC_SEG_PUB'
  schoolName?: string
  schemas: string[]
  totalStudents: number
  presentStudents: number
  complaintsData: ComplaintsData[]
  emotionalData: EmotionalData[]
  criticalAlerts?: Array<{
    id: string
    escola_nome: string
    tipo_incidente: string
    tempo_resposta: string
  }>
}

export function DashboardMain({
  role,
  schoolName,
  schemas,
  totalStudents,
  presentStudents,
  complaintsData,
  emotionalData,
  criticalAlerts = []
}: DashboardMainProps) {
  const [drillDownType, setDrillDownType] = useState<'presenca' | 'denuncias' | 'socioemocional' | null>(null)
  const [emergencyConfirmed, setEmergencyConfirmed] = useState(false)

  const { updates, isConnected } = useRealtimeUpdates(role, schemas)

  const handleEmergencyCall = () => {
    if (emergencyConfirmed) {
      window.location.href = 'tel:190'
    }
  }

  const openDrillDown = (type: 'presenca' | 'denuncias' | 'socioemocional') => {
    setDrillDownType(type)
  }

  const closeDrillDown = () => {
    setDrillDownType(null)
  }

  return (
    <div className="space-y-6">
      {/* Header específico por role */}
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold">
            {role === 'DIRETORIA' && schoolName
              ? `Dashboard - ${schoolName}`
              : role === 'SEC_EDUC_MUN'
              ? 'Secretaria Municipal de Educação'
              : role === 'SEC_EDUC_EST'
              ? 'Secretaria Estadual de Educação'
              : 'Segurança Pública Escolar'
            }
          </h1>
          <p className="text-muted-foreground">
            Painel de controle em tempo real
          </p>
        </div>

        <div className="flex gap-4 items-center">
          {/* Botão Emergência 190 - Apenas DIRETORIA */}
          {role === 'DIRETORIA' && (
            <Dialog>
              <DialogTrigger asChild>
                <Button variant="destructive">
                  <Phone className="h-4 w-4 mr-2" />
                  Emergência 190
                </Button>
              </DialogTrigger>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Confirmar Emergência</DialogTitle>
                  <DialogDescription>
                    Acionar serviço de emergência (190) para a escola?
                    Esta ação será registrada no sistema.
                  </DialogDescription>
                </DialogHeader>
                <DialogFooter>
                  <Button variant="outline" onClick={() => setEmergencyConfirmed(false)}>
                    Cancelar
                  </Button>
                  <Button
                    variant="destructive"
                    onClick={() => {
                      setEmergencyConfirmed(true)
                      setTimeout(() => window.location.href = 'tel:190', 500)
                    }}
                  >
                    Confirmar e Ligar
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          )}

          {/* Status de Conexão Realtime */}
          <div className="text-sm flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`}></div>
            {isConnected ? 'Tempo Real' : 'Offline'}
          </div>
        </div>
      </div>

      {/* Alertas Críticos - Apenas SEC_SEG_PUB */}
      {role === 'SEC_SEG_PUB' && criticalAlerts.length > 0 && (
        <Alert variant="destructive" className="border-l-4 border-red-500">
          <AlertTriangle className="h-5 w-5" />
          <AlertTitle className="flex items-center justify-between">
            <span>🚨 Alertas Críticos em Tempo Real</span>
            <Badge variant="destructive">{criticalAlerts.length}</Badge>
          </AlertTitle>
          <AlertDescription>
            <div className="space-y-2 mt-2">
              {criticalAlerts.slice(0, 3).map(alert => (
                <div key={alert.id} className="flex justify-between items-center text-sm">
                  <span>{alert.escola_nome} - {alert.tipo_incidente}</span>
                  <span className="text-xs">{alert.tempo_resposta}</span>
                </div>
              ))}
            </div>
          </AlertDescription>
        </Alert>
      )}

      {/* Cards KPI */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="pt-6">
            <div className="text-center">
              <div className="text-2xl font-bold">{totalStudents}</div>
              <div className="text-sm text-muted-foreground">Total Alunos</div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <div className="text-center">
              <div className="text-2xl font-bold text-green-600">{presentStudents}</div>
              <div className="text-sm text-muted-foreground">
                Presentes ({Math.round((presentStudents / totalStudents) * 100)}%)
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <div className="text-center">
              <div className="text-2xl font-bold text-orange-600">
                {complaintsData.reduce((sum, item) => sum + item.pendentes, 0)}
              </div>
              <div className="text-sm text-muted-foreground">Denúncias Pendentes</div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <div className="text-center">
              <div className="text-2xl font-bold text-blue-600">
                {emotionalData.length > 0
                  ? Math.round(emotionalData.reduce((sum, item) => sum + item.score, 0) / emotionalData.length)
                  : 0}
              </div>
              <div className="text-sm text-muted-foreground">Bem-estar Médio</div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Gráficos */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Presença - Sempre presente */}
        <PresenceChart
          totalStudents={totalStudents}
          presentStudents={presentStudents}
          onClick={() => openDrillDown('presenca')}
        />

        {/* Denúncias - Educacionais ou Segurança */}
        <ComplaintsChart
          data={complaintsData}
          type={role === 'SEC_SEG_PUB' ? 'seguranca' : 'educacionais'}
          onClick={() => openDrillDown('denuncias')}
        />
      </div>

      {/* Socioemocional - Apenas roles educacionais */}
      {role !== 'SEC_SEG_PUB' && (
        <EmotionalChart
          data={emotionalData}
          onClick={() => openDrillDown('socioemocional')}
        />
      )}

      {/* Modal de Drill-down */}
      <Dialog open={!!drillDownType} onOpenChange={closeDrillDown}>
        <DialogContent className="max-w-4xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              Detalhes - {drillDownType === 'presenca' ? 'Presença' :
                          drillDownType === 'denuncias' ? 'Denúncias' :
                          'Socioemocional'}
            </DialogTitle>
          </DialogHeader>

          {drillDownType === 'presenca' && (
            <div className="space-y-4">
              <p>Detalhes de presença por turma/aluno serão exibidos aqui.</p>
              <p>Implementar lista/tabela com dados detalhados.</p>
            </div>
          )}

          {drillDownType === 'denuncias' && (
            <div className="space-y-4">
              <p>Lista de denúncias (apenas não anônimas) será exibida aqui.</p>
              <p>Implementar tabela com filtros e paginação.</p>
            </div>
          )}

          {drillDownType === 'socioemocional' && (
            <div className="space-y-4">
              <p>Dados socioemocionais detalhados por aluno serão exibidos aqui.</p>
              <p>Implementar tabela com histórico e médias.</p>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
