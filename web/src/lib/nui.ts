import type { Result } from '../types'

declare global {
  interface Window {
    GetParentResourceName?: () => string
    invokeNative?: unknown
  }
}

/** True when the page runs in a normal browser (vite dev / preview), not inside FiveM CEF. */
export const isEnvBrowser = (): boolean =>
  typeof window.GetParentResourceName !== 'function' && !window.invokeNative

const resourceName = (): string =>
  typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'pls_mechanic'

type MockHandler = (payload: any) => unknown

// Browser-only responses, filled by src/dev (never used in game)
const mockHandlers: Record<string, MockHandler> = {}

export function setMockHandlers(handlers: Record<string, MockHandler>) {
  Object.assign(mockHandlers, handlers)
}

const TIMEOUT_MS = 20000

/**
 * POSTs to a RegisterNUICallback handler and returns its JSON response.
 * Resolves null on network error, timeout or empty response – callers must handle it.
 * `timeout` (ms) only for callbacks that wait for another player (tuning confirm waits for the customer's quote answer).
 */
export async function fetchNui<T = unknown>(name: string, payload: unknown = {}, timeout = TIMEOUT_MS): Promise<T | null> {
  if (isEnvBrowser()) {
    const handler = mockHandlers[name]
    await new Promise((r) => setTimeout(r, 180))
    return handler ? ((await handler(payload)) as T) : ({ ok: true } as T)
  }

  const request = fetch(`https://${resourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload ?? {}),
  })
    .then(async (res) => {
      const text = await res.text()
      if (!text) return null
      try {
        return JSON.parse(text) as T
      } catch {
        return null
      }
    })
    .catch(() => null)

  const expire = new Promise<null>((resolve) => setTimeout(() => resolve(null), timeout))
  return Promise.race([request, expire])
}

/**
 * Lua list -> array. An empty Lua table is encoded as `[]` or `{}` and a list with holes as an object,
 * so anything that is not an array is read as its values.
 */
export function asArray<T>(value: unknown): T[] {
  if (Array.isArray(value)) return value as T[]
  if (value && typeof value === 'object') return Object.values(value) as T[]
  return []
}

/** Lua map -> object. An empty Lua table arrives as `[]`, which is read as an empty object. */
export function asRecord<T>(value: unknown): Record<string, T> {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value as Record<string, T>
  return {}
}

/** Normalizes any callback answer to a Result (missing answer = failure). */
export function asResult<T extends object = Result>(value: unknown): Result & Partial<T> {
  if (value && typeof value === 'object' && 'ok' in (value as Record<string, unknown>)) {
    return value as Result & Partial<T>
  }
  if (value === true) return { ok: true } as Result & Partial<T>
  return { ok: false } as Result & Partial<T>
}
