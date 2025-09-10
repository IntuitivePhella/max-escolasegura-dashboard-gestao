"use client"

import { PolarAngleAxis, PolarGrid, Radar, RadarChart } from "recharts"

import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  ChartConfig,
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart"

const chartConfig = {
  score: {
    label: "Score",
    color: "var(--chart-1)",
  },
} satisfies ChartConfig

interface EmotionalData {
  dimensao: string
  score: number
}

interface EmotionalChartProps {
  data: EmotionalData[]
  onClick?: () => void
}

export function EmotionalChart({ data, onClick }: EmotionalChartProps) {
  const averageScore = data.length > 0
    ? Math.round(data.reduce((sum, item) => sum + item.score, 0) / data.length)
    : 0

  return (
    <Card className="cursor-pointer hover:shadow-md transition-shadow" onClick={onClick}>
      <CardHeader className="items-center pb-4">
        <CardTitle>Indicadores Socio-Emocionais</CardTitle>
        <CardDescription>
          Média das últimas 4 semanas por dimensão
        </CardDescription>
      </CardHeader>
      <CardContent className="pb-0">
        <ChartContainer
          config={chartConfig}
          className="mx-auto aspect-square max-h-[400px]"
        >
          <RadarChart data={data}>
            <ChartTooltip
              cursor={false}
              content={<ChartTooltipContent hideLabel />}
            />
            <PolarGrid gridType="circle" />
            <PolarAngleAxis dataKey="dimensao" />
            <Radar
              dataKey="score"
              fill="var(--color-score)"
              fillOpacity={0.6}
              dot={{
                r: 4,
                fillOpacity: 1,
              }}
            />
          </RadarChart>
        </ChartContainer>
      </CardContent>
      <CardFooter className="flex-col gap-2 text-sm">
        <div className="flex items-center gap-2 leading-none font-medium">
          Score Médio: {averageScore}/10
        </div>
        <div className="text-muted-foreground leading-none">
          Clique para ver detalhes por aluno
        </div>
      </CardFooter>
    </Card>
  )
}
