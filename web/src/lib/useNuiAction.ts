import { useCallback } from 'react'
import type { Result } from '../types'
import { asResult, fetchNui } from './nui'
import { useToast } from './toast'
import { useUi } from './ui'

export interface NuiActionOptions {
  /** Toast text on success when the callback sends no message. */
  success?: string
  /**
   * Answers the Lua client already shows with Core.Notify – no toast for them (no double notification):
   * "success" = ok answers, "all" = every answer with a message. A missing answer is always reported.
   */
  notified?: 'success' | 'all'
}

/**
 * Calls a NUI callback that answers with Result and shows a toast:
 * error (server message or generic) when not ok, success message when given.
 */
export function useNuiAction() {
  const push = useToast()
  const { t } = useUi()

  return useCallback(
    async <T extends object = Result>(name: string, payload: unknown, options: NuiActionOptions = {}) => {
      const raw = await fetchNui(name, payload)
      const res = asResult<T>(raw)
      const notified = raw !== null && (options.notified === 'all' || (options.notified === 'success' && res.ok))
      if (!res.ok) {
        if (!(notified && res.message)) push('error', res.message || t('ui_error_generic', 'Something went wrong, try again.'))
      } else if (!notified && (res.message || options.success)) {
        push('success', res.message || options.success || '')
      }
      return res
    },
    [push, t],
  )
}
