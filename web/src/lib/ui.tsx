import { createContext, useCallback, useContext, useMemo, type ReactNode } from 'react'
import type { Locales, UiConfig } from '../types'

export type TFunction = (key: string, fallback: string, ...args: (string | number)[]) => string

export interface Formatters {
  localeCode: string
  number: (n: number, decimals?: number) => string
  money: (n: number) => string
  /** Distance given in km, shown in the configured unit with its label */
  km: (n: number) => string
  /** km -> number in the configured unit */
  mileage: (km: number) => number
  mileageUnit: string
  percent: (n: number, decimals?: number) => string
  date: (unix: number) => string
  dateTime: (unix: number) => string
  time: (unix: number) => string
  dayKey: (unix: number) => string
}

interface UiContextValue {
  t: TFunction
  fmt: Formatters
  config: UiConfig
  itemImage: (item: string) => string
}

export const DEFAULT_CONFIG: UiConfig = {
  currency: '$',
  imagePath: 'nui://ox_inventory/web/images/%s.png',
}

const UiContext = createContext<UiContextValue | null>(null)

/** Replaces %s / %d placeholders in order (same convention as ox_lib locale()). */
export function interpolate(text: string, args: (string | number)[]): string {
  if (!args.length) return text
  let i = 0
  return text.replace(/%[sd]/g, (m) => (i < args.length ? String(args[i++]) : m))
}

function safeLocale(code: string | undefined): string {
  if (!code) return 'en-US'
  try {
    new Intl.NumberFormat(code)
    return code
  } catch {
    return 'en-US'
  }
}

const KM_TO_MI = 0.621371

function buildFormatters(localeCode: string, config: UiConfig, t: TFunction): Formatters {
  const currency = config.currency
  const intCache: Record<number, Intl.NumberFormat> = {}
  const nf = (decimals: number) =>
    (intCache[decimals] ||= new Intl.NumberFormat(localeCode, {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals,
    }))
  const dateF = new Intl.DateTimeFormat(localeCode, { day: 'numeric', month: 'short', year: 'numeric' })
  const dateTimeF = new Intl.DateTimeFormat(localeCode, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
  const timeF = new Intl.DateTimeFormat(localeCode, { hour: '2-digit', minute: '2-digit' })
  const toDate = (unix: number) => new Date((Number(unix) || 0) * 1000)

  // A single character currency ($, €, £) goes before the amount, words/codes (Kč, USD) after it
  const symbolFirst = [...(currency || '')].length <= 1
  const miles = config.mileageUnit === 'mi'
  const mileage = (km: number) => (Number(km) || 0) * (miles ? KM_TO_MI : 1)
  const mileageUnit = miles ? t('ui_unit_mi', 'mi') : t('ui_unit_km', 'km')

  return {
    localeCode,
    number: (n, decimals = 0) => nf(decimals).format(Number.isFinite(n) ? n : 0),
    money: (n) => {
      const value = Math.round(Number(n) || 0)
      const abs = nf(0).format(Math.abs(value))
      const sign = value < 0 ? '-' : ''
      return symbolFirst ? `${sign}${currency}${abs}` : `${sign}${abs} ${currency}`
    },
    km: (n) => `${nf(0).format(Math.round(mileage(n)))} ${mileageUnit}`,
    mileage,
    mileageUnit,
    percent: (n, decimals = 0) => `${nf(decimals).format(Number(n) || 0)} %`,
    date: (unix) => dateF.format(toDate(unix)),
    dateTime: (unix) => dateTimeF.format(toDate(unix)),
    time: (unix) => timeF.format(toDate(unix)),
    dayKey: (unix) => {
      const d = toDate(unix)
      return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
    },
  }
}

export function UiProvider({
  locales,
  config,
  children,
}: {
  locales: Locales
  config: UiConfig
  children: ReactNode
}) {
  const t = useCallback<TFunction>(
    (key, fallback, ...args) => {
      const value = locales[key]
      return interpolate(typeof value === 'string' && value !== '' ? value : fallback, args)
    },
    [locales],
  )

  const value = useMemo<UiContextValue>(() => {
    const localeCode = safeLocale(locales.ui_locale_code)
    return {
      t,
      config,
      fmt: buildFormatters(localeCode, config, t),
      itemImage: (item: string) => (config.imagePath || DEFAULT_CONFIG.imagePath).replace('%s', item),
    }
  }, [t, config, locales.ui_locale_code])

  return <UiContext.Provider value={value}>{children}</UiContext.Provider>
}

export function useUi(): UiContextValue {
  const ctx = useContext(UiContext)
  if (!ctx) throw new Error('useUi outside UiProvider')
  return ctx
}
