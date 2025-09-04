/**
 * @description Create the context of the Igniter.js application
 * @see https://github.com/felipebarcelospro/igniter-js
 */
export const createIgniterAppContext = () => {
  return {
    // Add shared resources here when needed (e.g., logger, telemetry)
  }
}

/**
 * @description The context of the Igniter.js application
 * @see https://github.com/felipebarcelospro/igniter-js
 */
export type IgniterAppContext = Awaited<ReturnType<typeof createIgniterAppContext>>
