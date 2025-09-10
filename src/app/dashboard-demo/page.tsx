import { DashboardMain } from '@/components/dashboard'

export default function DashboardDemoPage() {
  // Dados mockados - substituir por dados reais do Supabase
  const mockDataDiretoria = {
    role: 'DIRETORIA' as const,
    schoolName: 'EMEB Educar',
    schemas: ['schema_escola_123'], // Schema da escola
    totalStudents: 342,
    presentStudents: 289,
    complaintsData: [
      { mes: 'Janeiro', tratadas: 12, pendentes: 3 },
      { mes: 'Fevereiro', tratadas: 15, pendentes: 2 },
      { mes: 'Março', tratadas: 8, pendentes: 5 },
      { mes: 'Abril', tratadas: 18, pendentes: 1 },
    ],
    emotionalData: [
      { dimensao: 'Colegas', score: 8.2 },
      { dimensao: 'Humor', score: 7.8 },
      { dimensao: 'Professores', score: 8.5 },
      { dimensao: 'Saúde', score: 7.9 },
    ]
  }

  return (
    <div className="container mx-auto p-6">
      <DashboardMain {...mockDataDiretoria} />
    </div>
  )
}
