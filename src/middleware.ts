import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import type { UserRole } from './types/dashboard'

// Rate limiting simple em memória (para produção usar Redis)
const rateLimitMap = new Map<string, { count: number; lastReset: number }>()

// Configurações de rate limiting
const RATE_LIMIT_WINDOW = 60 * 1000 // 1 minuto
const RATE_LIMIT_MAX_REQUESTS = 100 // 100 requests por minuto por usuário

// Rotas que requerem autenticação
const PROTECTED_ROUTES = [
  '/dashboard',
  '/api/dashboard',
  '/api/v1/dashboard'
]

// Rotas públicas que não precisam de autenticação
const PUBLIC_ROUTES = [
  '/login',
  '/auth',
  '/_next',
  '/favicon.ico'
]

// Mapeamento de roles para rotas permitidas
const ROLE_ROUTE_PERMISSIONS: Record<UserRole, string[]> = {
  'DIRETORIA': [
    '/dashboard',
    '/api/dashboard/presence',
    '/api/dashboard/complaints',
    '/api/dashboard/emotional',
    '/api/v1/dashboard/summary',
    '/api/v1/dashboard/events',
    '/api/v1/dashboard/schemas'
  ],
  'SEC_EDUC_MUN': [
    '/dashboard',
    '/api/dashboard/presence',
    '/api/dashboard/complaints', 
    '/api/dashboard/emotional',
    '/api/v1/dashboard/summary',
    '/api/v1/dashboard/events',
    '/api/v1/dashboard/schemas'
  ],
  'SEC_EDUC_EST': [
    '/dashboard',
    '/api/dashboard/presence',
    '/api/dashboard/complaints',
    '/api/dashboard/emotional', 
    '/api/v1/dashboard/summary',
    '/api/v1/dashboard/events',
    '/api/v1/dashboard/schemas'
  ],
  'SEC_SEG_PUB': [
    '/dashboard',
    '/api/dashboard/security',
    '/api/v1/dashboard/summary',
    '/api/v1/dashboard/alerts',
    '/api/v1/dashboard/schemas'
  ]
}

/**
 * Verifica se a rota é pública
 */
function isPublicRoute(pathname: string): boolean {
  return PUBLIC_ROUTES.some(route => pathname.startsWith(route))
}

/**
 * Verifica se a rota requer autenticação
 */
function isProtectedRoute(pathname: string): boolean {
  return PROTECTED_ROUTES.some(route => pathname.startsWith(route))
}

/**
 * Rate limiting simples
 */
function checkRateLimit(userId: string): boolean {
  const now = Date.now()
  const userLimit = rateLimitMap.get(userId)
  
  if (!userLimit || now - userLimit.lastReset > RATE_LIMIT_WINDOW) {
    // Reset ou primeira requisição
    rateLimitMap.set(userId, { count: 1, lastReset: now })
    return true
  }
  
  if (userLimit.count >= RATE_LIMIT_MAX_REQUESTS) {
    return false // Rate limit excedido
  }
  
  userLimit.count++
  return true
}

/**
 * Busca informações do usuário e role via RPC
 */
async function getUserRoleInfo(supabase: ReturnType<typeof createServerClient>, userId: string) {
  try {
    // Usar RPC para buscar role e permissões do usuário
    const { data: userInfo, error } = await supabase.rpc('get_user_role_info', {
      p_user_id: userId
    })
    
    if (error) {
      console.error('Erro ao buscar role do usuário:', error)
      return null
    }
    
    return userInfo?.[0] || null
  } catch (error) {
    console.error('Erro na consulta de role:', error)
    return null
  }
}

/**
 * Verifica se o usuário tem permissão para acessar a rota
 */
function hasRoutePermission(userRole: UserRole, pathname: string): boolean {
  const allowedRoutes = ROLE_ROUTE_PERMISSIONS[userRole] || []
  
  // Verifica se a rota exata ou um prefixo está permitido
  return allowedRoutes.some(route => {
    if (pathname === route) return true
    if (pathname.startsWith(route + '/')) return true
    return false
  })
}

/**
 * Cria resposta de erro com headers de segurança
 */
function createErrorResponse(
  request: NextRequest, 
  status: number, 
  message: string,
  redirectTo?: string
): NextResponse {
  if (redirectTo) {
    const response = NextResponse.redirect(new URL(redirectTo, request.url))
    addSecurityHeaders(response)
    return response
  }
  
  const response = NextResponse.json(
    { error: message, timestamp: new Date().toISOString() },
    { status }
  )
  addSecurityHeaders(response)
  return response
}

/**
 * Adiciona headers de segurança
 */
function addSecurityHeaders(response: NextResponse): void {
  response.headers.set('X-Content-Type-Options', 'nosniff')
  response.headers.set('X-Frame-Options', 'DENY')
  response.headers.set('X-XSS-Protection', '1; mode=block')
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin')
  response.headers.set(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self' 'unsafe-eval' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://*.supabase.co wss://*.supabase.co;"
  )
}

export async function middleware(request: NextRequest) {
  const pathname = request.nextUrl.pathname
  
  // Permitir rotas públicas
  if (isPublicRoute(pathname)) {
    const response = NextResponse.next()
    addSecurityHeaders(response)
    return response
  }
  
  // Configurar cliente Supabase
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          request.cookies.set({
            name,
            value,
            ...options,
          })
          response = NextResponse.next({
            request: {
              headers: request.headers,
            },
          })
          response.cookies.set({
            name,
            value,
            ...options,
          })
        },
        remove(name: string, options: CookieOptions) {
          request.cookies.set({
            name,
            value: '',
            ...options,
          })
          response = NextResponse.next({
            request: {
              headers: request.headers,
            },
          })
          response.cookies.set({
            name,
            value: '',
            ...options,
          })
        },
      },
    }
  )

  // Verificar autenticação
  const {
    data: { user },
  } = await supabase.auth.getUser()

  // Redirecionar para login se não autenticado em rota protegida
  if (!user && isProtectedRoute(pathname)) {
    return createErrorResponse(request, 401, 'Não autenticado', '/login')
  }
  
  // Se usuário autenticado, verificar permissões para rotas protegidas
  if (user && isProtectedRoute(pathname)) {
    // Rate limiting
    if (!checkRateLimit(user.id)) {
      return createErrorResponse(request, 429, 'Rate limit excedido. Tente novamente em 1 minuto.')
    }
    
    // Buscar informações de role do usuário
    const userRoleInfo = await getUserRoleInfo(supabase, user.id)
    
    if (!userRoleInfo) {
      console.error(`Usuário ${user.id} não tem role definido`)
      return createErrorResponse(request, 403, 'Usuário sem permissões definidas', '/login')
    }
    
    const userRole = userRoleInfo.role_type as UserRole
    
    // Verificar se o role é válido para o dashboard
    const validDashboardRoles: UserRole[] = ['DIRETORIA', 'SEC_EDUC_MUN', 'SEC_EDUC_EST', 'SEC_SEG_PUB']
    if (!validDashboardRoles.includes(userRole)) {
      return createErrorResponse(request, 403, 'Role não autorizado para dashboard', '/login')
    }
    
    // Verificar permissão específica da rota
    if (!hasRoutePermission(userRole, pathname)) {
      return createErrorResponse(request, 403, `Role ${userRole} não tem permissão para acessar ${pathname}`)
    }
    
    // Adicionar informações do usuário aos headers para uso nas APIs
    response.headers.set('x-user-id', user.id)
    response.headers.set('x-user-role', userRole)
    response.headers.set('x-user-email', user.email || '')
    
    // Adicionar schemas permitidos se disponível
    if (userRoleInfo.allowed_schemas) {
      response.headers.set('x-user-schemas', JSON.stringify(userRoleInfo.allowed_schemas))
    }
  }
  
  // Adicionar headers de segurança
  addSecurityHeaders(response)
  
  return response
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * Feel free to modify this pattern to include more paths.
     */
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
