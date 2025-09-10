"use client"

import { TrendingUp } from "lucide-react"
import {
  Label,
  PolarGrid,
  PolarRadiusAxis,
  RadialBar,
  RadialBarChart,
} from "recharts"

import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { ChartConfig, ChartContainer } from "@/components/ui/chart"

const chartConfig = {
  presentes: {
    label: "Presentes",
    color: "var(--chart-1)",
  },
} satisfies ChartConfig

interface PresenceChartProps {
  totalStudents: number
  presentStudents: number
  onClick?: () => void
}

export function PresenceChart({ totalStudents, presentStudents, onClick }: PresenceChartProps) {
  const percentage = totalStudents > 0 ? Math.round((presentStudents / totalStudents) * 100) : 0

  const chartData = [
    {
      presentes: presentStudents,
      total: totalStudents,
      fill: `var(--color-presentes)`,
    },
  ]

  return (
    <Card className="flex flex-col cursor-pointer hover:shadow-md transition-shadow" onClick={onClick}>
      <CardHeader className="items-center pb-0">
        <CardTitle>Presença Escolar</CardTitle>
        <CardDescription>Taxa atual de presença</CardDescription>
      </CardHeader>
      <CardContent className="flex-1 pb-0">
        <ChartContainer
          config={chartConfig}
          className="mx-auto aspect-square max-h-[250px]"
        >
          <RadialBarChart
            data={chartData}
            endAngle={100}
            innerRadius={80}
            outerRadius={140}
          >
            <PolarGrid
              gridType="circle"
              radialLines={false}
              stroke="none"
              className="first:fill-muted last:fill-background"
              polarRadius={[86, 74]}
            />
            <RadialBar dataKey="presentes" background />
            <PolarRadiusAxis tick={false} tickLine={false} axisLine={false}>
              <Label
                content={({ viewBox }) => {
                  if (viewBox && "cx" in viewBox && "cy" in viewBox) {
                    return (
                      <text
                        x={viewBox.cx}
                        y={viewBox.cy}
                        textAnchor="middle"
                        dominantBaseline="middle"
                      >
                        <tspan
                          x={viewBox.cx}
                          y={viewBox.cy}
                          className="fill-foreground text-4xl font-bold"
                        >
                          {percentage}%
                        </tspan>
                        <tspan
                          x={viewBox.cx}
                          y={(viewBox.cy || 0) + 24}
                          className="fill-muted-foreground"
                        >
                          Presença
                        </tspan>
                      </text>
                    )
                  }
                }}
              />
            </PolarRadiusAxis>
          </RadialBarChart>
        </ChartContainer>
      </CardContent>
      <CardFooter className="flex-col gap-2 text-sm">
        <div className="flex items-center gap-2 leading-none font-medium">
          {presentStudents}/{totalStudents} alunos presentes
        </div>
        <div className="text-muted-foreground leading-none">
          Clique para ver detalhes por turma
        </div>
      </CardFooter>
    </Card>
  )
}
