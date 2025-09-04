import { igniter } from '@/igniter'
import { dashboardController } from '@/features/dashboard'

/**
 * @description Main application router configuration
 * @see https://github.com/felipebarcelospro/igniter-js
 */
export const AppRouter = igniter.router({
  controllers: {
    dashboard: dashboardController,
  }
})

export type AppRouterType = typeof AppRouter
