# 🎨 Protótipos Dashboard MVP - Max Escola Segura

## 📋 **MVP APROVADO - SIMPLICIDADE COMO PRIORIDADE**

### **Referência Visual**: Simplicidade do `diretoria.html`
### **Gráficos**: shadcn/ui baseados em `chart-examples/`
### **Princípio**: Dados primeiro, interface simples, zero over-engineering

## 🎯 **DECISÕES FINAIS IMPLEMENTADAS**

### **✅ Indicadores por Role:**
- **DIRETORIA, SEC_EDUC_MUN, SEC_EDUC_EST**: Presença + Denúncias Educacionais + Socioemocional
- **SEC_SEG_PUB**: APENAS Denúncias de Segurança (sem educacionais)

### **✅ Gráficos shadcn/ui Obrigatórios:**
- **Presença**: `RadialBarChart` (chart-examples/radial-chart-shape)
- **Denúncias**: `BarChart Stacked` (chart-examples/barchart-stacked+legend)  
- **Socioemocional**: `RadarChart` (chart-examples/radarchart-grid-circle)

### **✅ Realtime para TODOS:**
- `presence_update`, `complaint_update`, `emotional_update`, `security_update`

### **✅ Drill-down Detalhes:**
- **Sentimentos**: Modal com tabela completa de registros
- **Denúncias**: APENAS não anônimas (`WHERE Anonima = false`)

---

## 🏫 **DIRETORIA - Dashboard Simplificado**

### **Layout MVP**: Baseado no `diretoria.html`

```
┌──────────────────────────────────────────────────────────────┐
│ 🏫 EMEB EDUCAR (12345678) │ 🚨 EMERGÊNCIA 190 │ 🟢 TEMPO REAL │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│ FILTROS: [📅 Período▼] [🔄Temporal/Por Aluno] [📋Tipo Denúncia▼] │
│                                                              │
├─────────────┬─────────────┬─────────────┬─────────────────────┤
│📊 TOTAL     │✅ PRESENTES │📋 DENÚNCIAS │😊 BEM-ESTAR         │
│   342       │   289       │   3 PEND.   │   8.2/10           │
│ alunos      │ (84.5%)     │             │                    │
├─────────────┴─────────────┴─────────────┴─────────────────────┤
│                                                              │
│ 📈 PRESENÇA (RadialBar)      📊 DENÚNCIAS (StackedBar)       │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│ 🧠 SOCIOEMOCIONAL (Radar) - Full Width                       │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### **Funcionalidades Específicas DIRETORIA:**
- **🚨 Botão Emergência 190**: Modal confirmação → `tel:190`
- **🔄 Visão Temporal/Por Aluno**: Alterna agregação de dados  
- **📋 Filtro Tipo Denúncia**: Bullying/Infraestrutura/Outros/Todas
- **🔍 Drill-down**: Click nos gráficos abre modais com detalhes

### **Componentes shadcn/ui MVP**

```tsx
// DIRETORIA - Layout simplificado baseado em diretoria.html
<div className="space-y-6">
  {/* Header com filtros específicos DIRETORIA */}
  <div className="flex justify-between items-center">
    <h1>EMEB Educar (12345678)</h1>
    <div className="flex gap-4">
      {/* Botão Emergência 190 - EXCLUSIVO DIRETORIA */}
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
            <DialogDescription>Acionar 190 para emergência na escola?</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline">Cancelar</Button>
            <Button variant="destructive" asChild>
              <a href="tel:190">Ligar 190</a>
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      
      <div className="text-sm flex items-center gap-2">
        <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
        Tempo Real
      </div>
    </div>
  </div>

  {/* Filtros DIRETORIA */}
  <div className="flex gap-4">
    <Select value={period} onValueChange={setPeriod}>
      <SelectTrigger className="w-48">
        <SelectValue placeholder="Período" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="today">Hoje</SelectItem>
        <SelectItem value="week">Esta Semana</SelectItem>
        <SelectItem value="month">Este Mês</SelectItem>
      </SelectContent>
    </Select>
    
    {/* EXCLUSIVO DIRETORIA: Temporal vs Por Aluno */}
    <Tabs value={viewMode} onValueChange={setViewMode}>
      <TabsList>
        <TabsTrigger value="temporal">Temporal</TabsTrigger>
        <TabsTrigger value="por-aluno">Por Aluno</TabsTrigger>
      </TabsList>
    </Tabs>
    
    {/* EXCLUSIVO DIRETORIA: Filtro tipo denúncia */}
    <Select value={complaintType} onValueChange={setComplaintType}>
      <SelectTrigger className="w-48">
        <SelectValue placeholder="Tipo de denúncia" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="todas">Todas</SelectItem>
        <SelectItem value="bullying">Bullying</SelectItem>
        <SelectItem value="infraestrutura">Infraestrutura</SelectItem>
        <SelectItem value="outros">Outros</SelectItem>
      </SelectContent>
    </Select>
  </div>

  {/* Cards KPI */}
  <div className="grid grid-cols-4 gap-4">
    <Card><CardContent className="pt-6"><div className="text-center"><div className="text-2xl font-bold">342</div><div className="text-sm text-muted-foreground">Total Alunos</div></div></CardContent></Card>
    <Card><CardContent className="pt-6"><div className="text-center"><div className="text-2xl font-bold">289</div><div className="text-sm text-muted-foreground">Presentes (84.5%)</div></div></CardContent></Card>
    <Card><CardContent className="pt-6"><div className="text-center"><div className="text-2xl font-bold">3</div><div className="text-sm text-muted-foreground">Denúncias Pendentes</div></div></CardContent></Card>
    <Card><CardContent className="pt-6"><div className="text-center"><div className="text-2xl font-bold">8.2</div><div className="text-sm text-muted-foreground">Bem-estar Médio</div></div></CardContent></Card>
  </div>

  {/* Gráficos - Layout 2x1 + 1 Full Width */}
  <div className="grid grid-cols-2 gap-6">
    {/* Presença - RadialBarChart */}
    <Card onClick={() => openDrillDown('presenca')}>
      <CardHeader>
        <CardTitle>Presença vs Total</CardTitle>
        <CardDescription>Alunos presentes hoje</CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig} className="mx-auto aspect-square max-h-[250px]">
          <RadialBarChart data={presenceData} endAngle={100} innerRadius={80} outerRadius={140}>
            <PolarGrid gridType="circle" radialLines={false} stroke="none" />
            <RadialBar dataKey="presentes" background />
            <PolarRadiusAxis tick={false} axisLine={false}>
              <Label content={({ viewBox }) => (
                <text x={viewBox.cx} y={viewBox.cy} textAnchor="middle">
                  <tspan className="fill-foreground text-4xl font-bold">84.5%</tspan>
                  <tspan className="fill-muted-foreground">Presença</tspan>
                </text>
              )} />
            </PolarRadiusAxis>
          </RadialBarChart>
        </ChartContainer>
      </CardContent>
    </Card>

    {/* Denúncias - StackedBarChart */}
    <Card onClick={() => openDrillDown('denuncias')}>
      <CardHeader>
        <CardTitle>Denúncias por Categoria</CardTitle>
        <CardDescription>Tratadas vs Pendentes</CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig}>
          <BarChart data={complaintsData}>
            <CartesianGrid vertical={false} />
            <XAxis dataKey="mes" tickFormatter={(value) => value.slice(0, 3)} />
            <ChartTooltip content={<ChartTooltipContent hideLabel />} />
            <ChartLegend content={<ChartLegendContent />} />
            <Bar dataKey="tratadas" stackId="a" fill="var(--color-tratadas)" radius={[0, 0, 4, 4]} />
            <Bar dataKey="pendentes" stackId="a" fill="var(--color-pendentes)" radius={[4, 4, 0, 0]} />
          </BarChart>
        </ChartContainer>
      </CardContent>
    </Card>
  </div>

  {/* Socioemocional - RadarChart Full Width */}
  <Card onClick={() => openDrillDown('socioemocional')}>
    <CardHeader>
      <CardTitle>Indicadores Socio-Emocionais</CardTitle>
      <CardDescription>Média dos últimos 30 dias por dimensão</CardDescription>
    </CardHeader>
    <CardContent>
      <ChartContainer config={chartConfig} className="mx-auto aspect-square max-h-[400px]">
        <RadarChart data={emotionalData}>
          <ChartTooltip cursor={false} content={<ChartTooltipContent hideLabel />} />
          <PolarGrid gridType="circle" />
          <PolarAngleAxis dataKey="dimensao" />
          <Radar dataKey="score" fill="var(--color-score)" fillOpacity={0.6} dot={{ r: 4 }} />
        </RadarChart>
      </ChartContainer>
    </CardContent>
  </Card>
 </div>

{/* Modais de Drill-down */}
<Dialog open={drillDownOpen} onOpenChange={setDrillDownOpen}>
  <DialogContent className="max-w-4xl">
    <DialogHeader>
      <DialogTitle>Detalhes - {drillDownType}</DialogTitle>
    </DialogHeader>
    
    {drillDownType === 'sentimentos' && (
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Data</TableHead>
            <TableHead>Aluno</TableHead>
            <TableHead>Dimensão</TableHead>
            <TableHead>Score</TableHead>
            <TableHead>Observações</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {emotionalRecords.map(record => (
            <TableRow key={record.ID}>
              <TableCell>{record.Data_Registro}</TableCell>
              <TableCell>{record.nome_aluno}</TableCell>
              <TableCell>{record.dimensao}</TableCell>
              <TableCell>{record.score}</TableCell>
              <TableCell>{record.Observacoes_Gerais}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    )}
    
    {drillDownType === 'denuncias' && (
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Protocolo</TableHead>
            <TableHead>Aluno</TableHead> {/* Só não anônimas */}
            <TableHead>Categoria</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Data</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {complaintsData.filter(d => !d.Anonima).map(complaint => (
            <TableRow key={complaint.ID}>
              <TableCell>{complaint.Protocolo}</TableCell>
              <TableCell>{complaint.nome_aluno}</TableCell>
              <TableCell>
                <Badge variant={complaint.Status === 'TRATADA' ? 'default' : 'destructive'}>
                  {complaint.Status}
                </Badge>
              </TableCell>
              <TableCell>{formatDate(complaint.Criado_Em)}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    )}
  </DialogContent>
</Dialog>
```

---

## 🏛️ **SEC_EDUC_MUN & SEC_EDUC_EST - Dashboards Regionais MVP**

### **Diferença dos roles educacionais:**
- **SEC_EDUC_MUN**: Escolas municipais do município (dados agregados)
- **SEC_EDUC_EST**: Escolas estaduais do estado (dados agregados)
- **Layout**: IDÊNTICO ao DIRETORIA, apenas escopo de dados muda

### **Componentes iguais ao DIRETORIA:**
- Mesmo layout de cards KPI + 3 gráficos
- Mesmos gráficos shadcn/ui (RadialBar + StackedBar + Radar)  
- Realtime updates (presence_update, complaint_update, emotional_update)
- Drill-down com modais de detalhes

### **Diferenças específicas:**
```tsx
// Header sem botão 190, dados agregados
<div className="flex justify-between items-center">
  <h1>{role === 'SEC_EDUC_MUN' ? 'Secretaria Municipal' : 'Secretaria Estadual'}</h1>
  <div className="text-sm flex items-center gap-2">
    <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
    Tempo Real
  </div>
</div>

// Filtros simplificados (sem visão temporal/por aluno)
<div className="flex gap-4">
  <Select value={period} onValueChange={setPeriod}>
    <SelectTrigger><SelectValue placeholder="Período" /></SelectTrigger>
    <SelectContent>
      <SelectItem value="week">Esta Semana</SelectItem>
      <SelectItem value="month">Este Mês</SelectItem>
      <SelectItem value="quarter">Trimestre</SelectItem>
    </SelectContent>
  </Select>
  
  {/* Seletor de escolas (multi-select simples) */}
  <MultiSelect
    value={selectedSchools} 
    onValueChange={setSelectedSchools}
    placeholder="Selecione escolas..."
    options={schoolOptions}
  />
</div>
```

**Resultado**: Layout IDÊNTICO ao DIRETORIA, apenas dados agregados por escopo regional.

---

## 🚨 **SEC_SEG_PUB - Dashboard de Segurança MVP**

### **Funcionalidades específicas:**
- **🚨 Ticker de alertas críticos** (realtime updates via `security_update`)
- **📊 APENAS gráfico de segurança** (sem educacionais)
- **🔍 Drill-down detalhes** (apenas denúncias não anônimas)

### **Layout simplificado:**

```tsx
<div className="space-y-6">
  {/* Ticker de Alertas Críticos - EXCLUSIVO SEC_SEG_PUB */}
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
        {criticalAlerts.length === 0 && (
          <div className="text-sm text-green-700">✅ Nenhum alerta crítico no momento</div>
        )}
      </div>
    </AlertDescription>
  </Alert>

  {/* Filtros */}
  <div className="flex gap-4">
    <Select value={period} onValueChange={setPeriod}>
      <SelectTrigger className="w-48">
        <SelectValue placeholder="Período" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="today">Últimas 24h</SelectItem>
        <SelectItem value="week">Esta Semana</SelectItem>
        <SelectItem value="month">Este Mês</SelectItem>
      </SelectContent>
    </Select>
    
    <Select value={incidentType} onValueChange={setIncidentType}>
      <SelectTrigger className="w-48">
        <SelectValue placeholder="Tipo de incidente" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="todos">Todos</SelectItem>
        <SelectItem value="trafico">Tráfico</SelectItem>
        <SelectItem value="violencia">Violência</SelectItem>
        <SelectItem value="assedio">Assédio</SelectItem>
        <SelectItem value="discriminacao">Discriminação</SelectItem>
      </SelectContent>
    </Select>
    
    <div className="text-sm flex items-center gap-2">
      <div className="w-2 h-2 bg-red-500 rounded-full animate-pulse"></div>
      Tempo Real
    </div>
  </div>

  {/* Cards KPI de Segurança */}
  <div className="grid grid-cols-4 gap-4">
    <Card><CardContent className="pt-6"><div className="text-center"><div className="text-2xl font-bold text-red-600">{totalIncidents}</div><div className="text-sm text-muted-foreground">Total Incidentes</div></div></CardContent></Card>
    <Card><CardContent className="pt-6"><div className="text-center"><div className="text-2xl font-bold text-orange-600">{pendingIncidents}</div><div className="text-sm text-muted-foreground">Pendentes</div></div></CardContent></Card>
    <Card><CardContent className="pt-6"><div className="text-center"><div className="text-2xl font-bold text-green-600">{resolvedIncidents}</div><div className="text-sm text-muted-foreground">Resolvidos</div></div></CardContent></Card>
    <Card><CardContent className="pt-6"><div className="text-center"><div className="text-2xl font-bold">{affectedSchools}</div><div className="text-sm text-muted-foreground">Escolas Afetadas</div></div></CardContent></Card>
  </div>

  {/* Gráfico ÚNICO de Segurança */}
  <Card onClick={() => openDrillDown('seguranca')}>
    <CardHeader>
      <CardTitle className="flex items-center gap-2 text-red-600">
        <Shield className="h-5 w-5" />
        Denúncias de Segurança
      </CardTitle>
      <CardDescription>Tratadas vs Pendentes por categoria</CardDescription>
    </CardHeader>
    <CardContent>
      <ChartContainer config={chartConfig}>
        <BarChart data={securityComplaints}>
          <CartesianGrid vertical={false} />
          <XAxis dataKey="categoria" />
          <ChartTooltip content={<ChartTooltipContent hideLabel />} />
          <ChartLegend content={<ChartLegendContent />} />
          <Bar dataKey="tratadas" stackId="a" fill="var(--color-tratadas)" radius={[0, 0, 4, 4]} />
          <Bar dataKey="pendentes" stackId="a" fill="var(--color-pendentes)" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ChartContainer>
    </CardContent>
  </Card>
</div>
```

---

## 📱 **IMPLEMENTAÇÃO MVP - 2-3 DIAS**

### **Gráficos shadcn/ui (Baseados em chart-examples/)**
- **Presença**: `RadialBarChart` (radial-chart-shape)
- **Denúncias**: `BarChart Stacked` (barchart-stacked+legend)
- **Socioemocional**: `RadarChart` (radarchart-grid-circle)

### **Hook Realtime Universal**
```tsx
const useRealtimeUpdates = (role: UserRole, schemas: string[]) => {
  const [updates, setUpdates] = useState<RealtimeEvent[]>([])
  
  useEffect(() => {
    const eventTypes: RealtimeEventType[] = 
      role === 'SEC_SEG_PUB' 
        ? ['security_update'] 
        : ['presence_update', 'complaint_update', 'emotional_update']
    
    const subscription = supabase
      .channel('dashboard-updates')
      .on('postgres_changes', { 
        event: '*', 
        schema: schemas[0],
        table: role === 'SEC_SEG_PUB' ? 'denuncias' : '*'
      }, (payload) => {
        setUpdates(prev => [payload as RealtimeEvent, ...prev.slice(0, 9)])
      })
      .subscribe()

    return () => subscription.unsubscribe()
  }, [role, schemas])
  
  return updates
}
```

### **Layout Universal (4 roles):**
- **Header**: Nome + realtime indicator + botão específico por role
- **Filtros**: Mínimos, específicos por necessidade
- **Cards KPI**: 4 cards simples com números
- **Gráficos**: shadcn/ui com drill-down em modais
- **Responsivo**: Mobile-first, stack vertical

### **Diferenciação por Role:**
- **DIRETORIA**: + Botão 190 + Visão Temporal/Aluno + Filtro denúncia
- **SEC_EDUC_***: Dados agregados, multi-select escolas simples
- **SEC_SEG_PUB**: Ticker alertas + APENAS gráfico segurança

### **Drill-down Detalhes:**
- **Sentimentos**: Modal com tabela completa
- **Denúncias**: APENAS não anônimas (`WHERE Anonima = false`)

---

## 🎯 **MVP FINAL - SIMPLICIDADE TOTAL**

**Princípio**: Dashboards são sobre DADOS, não interfaces complexas.

**✅ Aceite do MVP:**
- Layout simples como `diretoria.html`
- 4 cards KPI + 3 gráficos shadcn/ui
- Realtime em todos os roles
- Drill-down funcional
- Filtros essenciais por role
- Zero over-engineering

**🚀 Desenvolvimento**: 2-3 dias vs 2-3 semanas da proposta original
