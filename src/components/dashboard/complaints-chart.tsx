"use client"

import { Bar, BarChart, CartesianGrid, XAxis } from "recharts"

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  ChartConfig,
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart"

const chartConfig = {
  tratadas: {
    label: "Tratadas",
    color: "var(--chart-1)",
  },
  pendentes: {
    label: "Pendentes",
    color: "var(--chart-2)",
  },
} satisfies ChartConfig

interface ComplaintsData {
  mes: string
  tratadas: number
  pendentes: number
}

interface ComplaintsChartProps {
  data: ComplaintsData[]
  type: 'educacionais' | 'seguranca'
  onClick?: () => void
}

export function ComplaintsChart({ data, type, onClick }: ComplaintsChartProps) {
  const totalTratadas = data.reduce((sum, item) => sum + item.tratadas, 0)
  const totalPendentes = data.reduce((sum, item) => sum + item.pendentes, 0)

  return (
    <Card className="cursor-pointer hover:shadow-md transition-shadow" onClick={onClick}>
      <CardHeader>
        <CardTitle>
          Denúncias {type === 'educacionais' ? 'Educacionais' : 'de Segurança'}
        </CardTitle>
        <CardDescription>
          Tratadas vs Pendentes - Últimos {data.length} meses
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig}>
          <BarChart accessibilityLayer data={data}>
            <CartesianGrid vertical={false} />
            <XAxis
              dataKey="mes"
              tickLine={false}
              tickMargin={10}
              axisLine={false}
              tickFormatter={(value) => value.slice(0, 3)}
            />
            <ChartTooltip content={<ChartTooltipContent hideLabel />} />
            <ChartLegend content={<ChartLegendContent />} />
            <Bar
              dataKey="tratadas"
              stackId="a"
              fill="var(--color-tratadas)"
              radius={[0, 0, 4, 4]}
            />
            <Bar
              dataKey="pendentes"
              stackId="a"
              fill="var(--color-pendentes)"
              radius={[4, 4, 0, 0]}
            />
          </BarChart>
        </ChartContainer>
      </CardContent>
      <div className="px-6 pb-4">
        <div className="flex justify-between text-sm">
          <span className="text-green-600 font-medium">{totalTratadas} Tratadas</span>
          <span className="text-orange-600 font-medium">{totalPendentes} Pendentes</span>
        </div>
        <div className="text-muted-foreground text-xs mt-1">
          Clique para ver detalhes das denúncias
        </div>
      </div>
    </Card>
  )
}
