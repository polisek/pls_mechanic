import { useCallback, useEffect, useMemo, useRef, useState, type MouseEvent, type ReactNode } from 'react'
import { ColorPicker, TextInput, Tooltip } from '@mantine/core'
import {
  IconAlertTriangle,
  IconArmchair,
  IconArrowLeft,
  IconBuildingWarehouse,
  IconBulb,
  IconCar,
  IconCheck,
  IconChevronRight,
  IconClipboardList,
  IconDots,
  IconFocus2,
  IconGauge,
  IconInfoCircle,
  IconLoader2,
  IconPaint,
  IconRotate,
  IconRotateClockwise,
  IconSend,
  IconShoppingCart,
  IconSparkles,
  IconTrash,
  IconWheel,
  IconX,
  IconZoomIn,
  IconZoomOut,
} from '@tabler/icons-react'
import type {
  CameraAction,
  ItemReq,
  Rgb,
  TuningCategory,
  TuningData,
  TuningGroup,
  TuningOption,
  TuningValue,
  ViewProps,
} from '../types'
import { ItemChip, ItemImage, aggregateReqs } from '../components/Items'
import { Plate } from '../components/Vehicle'
import { asArray, asResult, fetchNui } from '../lib/nui'
import { useToast } from '../lib/toast'
import { useUi, type TFunction } from '../lib/ui'
import './tuning.css'

const GROUPS: TuningGroup[] = ['performance', 'body', 'wheels', 'paint', 'lights', 'interior', 'other']

// tuning:confirm waits for the customer's answer to the quote (data.approvalTimeout = Config.Tuning.Catalog.approvalTimeout s)
// + margin for the server (its own timeout is approvalTimeout + 5 s) and the parts check
const APPROVAL_DEFAULT_S = 60
const APPROVAL_MARGIN_S = 20

const GROUP_ICON: Record<TuningGroup, typeof IconGauge> = {
  performance: IconGauge,
  body: IconCar,
  wheels: IconWheel,
  paint: IconPaint,
  lights: IconBulb,
  interior: IconArmchair,
  other: IconDots,
}

function groupLabel(t: TFunction, group: TuningGroup): string {
  switch (group) {
    case 'performance':
      return t('ui_tun_group_performance', 'Performance')
    case 'body':
      return t('ui_tun_group_body', 'Body')
    case 'wheels':
      return t('ui_tun_group_wheels', 'Wheels')
    case 'paint':
      return t('ui_tun_group_paint', 'Paint')
    case 'lights':
      return t('ui_tun_group_lights', 'Lights')
    case 'interior':
      return t('ui_tun_group_interior', 'Interior')
    default:
      return t('ui_tun_group_other', 'Other')
  }
}

/* ----------------------------------------------------------------- value helpers */

const clamp255 = (n: number) => Math.max(0, Math.min(255, Math.round(Number(n) || 0)))

// Accepts {r,g,b} and Lua arrays [r, g, b]
function toRgb(value: unknown): Rgb {
  if (Array.isArray(value)) return { r: clamp255(value[0]), g: clamp255(value[1]), b: clamp255(value[2]) }
  if (value && typeof value === 'object') {
    const v = value as Partial<Rgb>
    return { r: clamp255(v.r ?? 0), g: clamp255(v.g ?? 0), b: clamp255(v.b ?? 0) }
  }
  return { r: 0, g: 0, b: 0 }
}

const rgbToHex = ({ r, g, b }: Rgb) => `#${[r, g, b].map((n) => n.toString(16).padStart(2, '0')).join('')}`

function parseColor(text: string): Rgb | null {
  const hex = text.trim().match(/^#?([0-9a-f]{6})$/i)
  if (hex) {
    const n = parseInt(hex[1]!, 16)
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }
  }
  const rgb = text.match(/rgba?\((\d+)[,\s]+(\d+)[,\s]+(\d+)/i)
  if (rgb) return { r: clamp255(+rgb[1]!), g: clamp255(+rgb[2]!), b: clamp255(+rgb[3]!) }
  return null
}

function normalize(cat: TuningCategory, value: unknown): TuningValue {
  switch (cat.kind) {
    case 'toggle':
      return value === true || value === 1 || value === '1' || value === 'true'
    case 'rgb':
      return toRgb(value)
    default: {
      const n = Number(value)
      return Number.isFinite(n) ? n : -1
    }
  }
}

function sameValue(cat: TuningCategory, a: unknown, b: unknown): boolean {
  const x = normalize(cat, a)
  const y = normalize(cat, b)
  if (cat.kind === 'rgb') {
    const p = x as Rgb
    const q = y as Rgb
    return p.r === q.r && p.g === q.g && p.b === q.b
  }
  return x === y
}

const valueKey = (value: TuningValue) => (typeof value === 'object' ? rgbToHex(value) : String(value))

// Rims are split into wheels_<type> categories – only one of them can be installed / in the cart
const isWheels = (key: string) => key.indexOf('wheels_') === 0
// Baseline of a wheels_* category whose wheel type is not installed (no option matches)
const OTHER_WHEEL_TYPE = -2

type PaletteEntry = NonNullable<TuningCategory['palette']>[number]
const paletteOf = (cat: TuningCategory) => asArray<PaletteEntry>(cat.palette)

// Returning to stock / turning off consumes no material (server: isRemoval)
const isRemoval = (cat: TuningCategory, value: TuningValue) =>
  (cat.kind === 'list' && value === -1) || (cat.kind === 'toggle' && value === false)

/* ----------------------------------------------------------------- camera button (hold to repeat) */

function CamButton({ action, icon, label, repeat = true }: { action: CameraAction; icon: ReactNode; label: string; repeat?: boolean }) {
  const timers = useRef<{ delay?: number; interval?: number }>({})
  const stop = () => {
    window.clearTimeout(timers.current.delay)
    window.clearInterval(timers.current.interval)
    timers.current = {}
  }
  useEffect(() => stop, [])
  const send = () => fetchNui('tuning:camera', { action })
  return (
    <Tooltip label={label}>
      <button
        type="button"
        className="tn-cam__btn"
        onMouseDown={(e) => {
          if (e.button !== 0) return
          send()
          if (!repeat) return
          stop()
          timers.current.delay = window.setTimeout(() => {
            timers.current.interval = window.setInterval(send, 90)
          }, 320)
        }}
        onMouseUp={stop}
        onMouseLeave={stop}
      >
        {icon}
      </button>
    </Tooltip>
  )
}

/* ----------------------------------------------------------------- rgb editor */

const RGB_SWATCHES = [
  '#ffffff', '#0b0b0b', '#c0c0c0', '#d10000', '#ff7a00', '#ffd400',
  '#1fb141', '#00b3ff', '#1d4ed8', '#8b2cff', '#ff2d95', '#6b3e1e',
]

function RgbEditor({
  committed,
  installed,
  price,
  onPreview,
  onSelect,
}: {
  committed: Rgb
  installed: Rgb
  price: number
  onPreview: (rgb: Rgb) => void
  onSelect: (rgb: Rgb) => void
}) {
  const { t, fmt } = useUi()
  const [draft, setDraft] = useState(rgbToHex(committed))
  const [hexText, setHexText] = useState(rgbToHex(committed).toUpperCase())
  const draftRgb = parseColor(draft) ?? committed
  const isInstalled = committed.r === installed.r && committed.g === installed.g && committed.b === installed.b

  const apply = (rgb: Rgb, commit: boolean) => {
    setDraft(rgbToHex(rgb))
    setHexText(rgbToHex(rgb).toUpperCase())
    if (commit) onSelect(rgb)
    else onPreview(rgb)
  }

  return (
    <div className="tn-rgb">
      <ColorPicker
        format="hex"
        value={draft}
        fullWidth
        size="lg"
        swatches={RGB_SWATCHES}
        swatchesPerRow={12}
        onChange={(value) => {
          const rgb = parseColor(value)
          if (rgb) apply(rgb, false)
        }}
        onChangeEnd={(value) => {
          const rgb = parseColor(value)
          if (rgb) apply(rgb, true)
        }}
      />
      <div className="tn-rgb__row">
        <span className="tn-dot tn-dot--lg" style={{ background: draft }} />
        <TextInput
          className="inp grow"
          size="sm"
          value={hexText}
          maxLength={7}
          onChange={(e) => {
            const text = e.currentTarget.value
            setHexText(text)
            const rgb = parseColor(text)
            if (rgb && text.replace('#', '').length === 6) {
              setDraft(rgbToHex(rgb))
              onSelect(rgb)
            }
          }}
        />
        <span className="mono tn-rgb__vals dim">{`${draftRgb.r} · ${draftRgb.g} · ${draftRgb.b}`}</span>
      </div>
      <div className="tn-rgb__foot">
        <button type="button" className="btn btn--sm btn--ghost" disabled={isInstalled} onClick={() => apply(installed, true)}>
          <IconArrowLeft size="0.95rem" />
          {t('ui_tun_revert', 'Revert to installed')}
        </button>
        <span className="mono tn-opt__price">{isInstalled ? t('ui_tun_installed', 'Installed') : fmt.money(price)}</span>
      </div>
    </div>
  )
}

/* ----------------------------------------------------------------- view */

type Level = { level: 'groups' } | { level: 'categories'; group: TuningGroup } | { level: 'detail'; group: TuningGroup; key: string }

export default function Tuning({ data, onClose }: ViewProps<TuningData>) {
  const { t, fmt, config } = useUi()
  // Tuning catalog (client Tuning.OpenCatalog): no requirements, no draft, the cart is sent to the mechanics as an order
  const customer = data.mode === 'customer'
  const categories = useMemo(() => asArray<TuningCategory>(data.categories), [data.categories])
  const byKey = useMemo(() => {
    const map = new Map<string, TuningCategory>()
    categories.forEach((c) => map.set(c.key, c))
    return map
  }, [categories])

  const [nav, setNav] = useState<Level>({ level: 'groups' })
  const [cart, setCart] = useState<Record<string, TuningValue>>({})
  const [cursor, setCursor] = useState(0)
  const [hoverLabel, setHoverLabel] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  /* ---------------- installed state */

  // wheels_* category that holds the installed rims (installed flag first, then non-stock current)
  const installedWheelsKey = useMemo(() => {
    const wheels = categories.filter((c) => isWheels(c.key))
    const flagged = wheels.find((c) => asArray<TuningOption>(c.options).some((o) => o.installed && o.value !== -1))
    if (flagged) return flagged.key
    return wheels.find((c) => normalize(c, c.current) !== -1)?.key ?? null
  }, [categories])

  // Installed value of a category (what the car has without any change)
  const baseline = useCallback(
    (cat: TuningCategory): TuningValue =>
      isWheels(cat.key) && installedWheelsKey && installedWheelsKey !== cat.key ? OTHER_WHEEL_TYPE : normalize(cat, cat.current),
    [installedWheelsKey],
  )

  // "Stock" of a wheel type that is not installed equals the current state for the client + server (never applied),
  // only the installed wheel type can go back to stock rims
  const optionsOf = (cat: TuningCategory): TuningOption[] => {
    const options = asArray<TuningOption>(cat.options)
    return baseline(cat) === OTHER_WHEEL_TYPE ? options.filter((o) => o.value !== -1) : options
  }

  const isInstalledOption = (cat: TuningCategory, value: number, flag?: boolean) => {
    if (flag !== undefined) return flag
    return sameValue(cat, value, baseline(cat))
  }

  /* ---------------- customer order (catalog) */

  const order = data.order && typeof data.order === 'object' ? data.order : undefined
  const orderChanges = useMemo(() => asArray<{ key: string; value: TuningValue }>(order?.changes), [order])

  // Exactly what the customer ordered (another value of an ordered category is an extra)
  const isOrdered = (cat: TuningCategory, value: TuningValue) =>
    orderChanges.some((c) => c && c.key === cat.key && sameValue(cat, c.value, value))

  /* ---------------- preview (debounced, skips duplicates) */

  const push = useToast()
  const lastPreview = useRef<Record<string, string>>({})
  const lastError = useRef({ message: '', at: 0 })
  const previewTimer = useRef<number>()

  const sendPreview = useCallback(
    (key: string, value: TuningValue) => {
      // Another wheel type replaces the rims – its old preview state is no longer on the car
      if (isWheels(key)) Object.keys(lastPreview.current).forEach((k) => isWheels(k) && k !== key && delete lastPreview.current[k])
      lastPreview.current[key] = valueKey(value)
      fetchNui('tuning:preview', { key, value }).then((raw) => {
        const res = asResult(raw)
        if (res.ok || !res.message) return
        const now = Date.now()
        if (lastError.current.message === res.message && now - lastError.current.at < 3000) return
        lastError.current = { message: res.message, at: now }
        push('error', res.message)
      })
    },
    [push],
  )

  const preview = useCallback(
    (key: string, value: TuningValue, immediate = false) => {
      const run = () => {
        if (lastPreview.current[key] === valueKey(value)) return
        sendPreview(key, value)
      }
      window.clearTimeout(previewTimer.current)
      if (immediate) run()
      else previewTimer.current = window.setTimeout(run, 60)
    },
    [sendPreview],
  )
  useEffect(() => () => window.clearTimeout(previewTimer.current), [])

  // Values the car shows when nothing is hovered = selection in cart or installed
  const effective = useCallback(
    (cat: TuningCategory): TuningValue => (cat.key in cart ? cart[cat.key]! : baseline(cat)),
    [cart, baseline],
  )

  // Puts the car back to what the cart says for this category (or the installed rims for wheels)
  const restore = (cat: TuningCategory, immediate = false, cartState = cart) => {
    if (isWheels(cat.key)) {
      const inCart = Object.keys(cartState).find(isWheels)
      if (inCart) return preview(inCart, cartState[inCart]!, immediate)
      const installed = installedWheelsKey ? byKey.get(installedWheelsKey) : undefined
      const target = installed ?? cat
      return preview(target.key, normalize(target, target.current), immediate)
    }
    preview(cat.key, cat.key in cartState ? cartState[cat.key]! : baseline(cat), immediate)
  }

  /* ---------------- sync with client data (open + update after every confirm) */

  const cartRef = useRef(cart)
  cartRef.current = cart
  useEffect(() => {
    // Installed values are the new baseline of what the car shows
    categories.forEach((c) => {
      lastPreview.current[c.key] = valueKey(baseline(c))
    })
    // Drop cart entries that are installed now or no longer exist, re-apply the rest
    const prev = cartRef.current
    const next: Record<string, TuningValue> = {}
    Object.keys(prev).forEach((key) => {
      const cat = byKey.get(key)
      if (cat && !sameValue(cat, prev[key], baseline(cat))) next[key] = prev[key]!
    })
    if (Object.keys(next).length !== Object.keys(prev).length) setCart(next)
    Object.keys(next).forEach((key) => sendPreview(key, next[key]!))
  }, [categories, byKey, baseline, sendPreview])

  /* ---------------- unconfirmed cart saved per vehicle (restored when tuning is opened again) */

  const draftReady = useRef(false)
  const draftTimer = useRef<number>()
  const plateRef = useRef(data.plate)
  plateRef.current = data.plate

  const draftPayload = (state: Record<string, TuningValue>) => ({
    plate: plateRef.current,
    changes: Object.keys(state).map((key) => ({ key, value: state[key]! })),
  })

  // open: prefill the cart – the customer order first (priority), then the saved cart of the mechanic on other categories
  // (only values that still differ from the installed state; the catalog never saves or restores a draft)
  useEffect(() => {
    const next: Record<string, TuningValue> = {}
    const fill = (list: unknown, keep: boolean) => {
      let added = 0
      asArray<{ key: string; value: TuningValue }>(list).forEach((entry) => {
        const cat = entry && typeof entry.key === 'string' ? byKey.get(entry.key) : undefined
        if (!cat) return
        if (keep && (cat.key in next || (isWheels(cat.key) && Object.keys(next).some(isWheels)))) return
        const value = normalize(cat, entry.value)
        if (value === null || sameValue(cat, value, baseline(cat))) return
        if (isWheels(cat.key)) Object.keys(next).forEach((k) => isWheels(k) && delete next[k])
        next[cat.key] = value
        added += 1
      })
      return added
    }
    const fromOrder = fill(order?.changes, false)
    const fromDraft = customer ? 0 : fill(data.draft, true)
    draftReady.current = !customer
    if (!fromOrder && !fromDraft) return
    setCart(next)
    Object.keys(next).forEach((key) => sendPreview(key, next[key]!))
    if (fromOrder) {
      push(
        'info',
        customer
          ? t('ui_catalog_order_restored', 'Your pending order was loaded')
          : t('ui_catalog_order_loaded', 'Customer order loaded'),
      )
    } else {
      push('info', t('ui_tun_draft_restored', 'Unfinished tuning of this vehicle was restored'))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // every cart change is saved (debounced)
  useEffect(() => {
    if (!draftReady.current) return
    window.clearTimeout(draftTimer.current)
    draftTimer.current = window.setTimeout(() => fetchNui('tuning:draft', draftPayload(cart)), 300)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cart])

  // closing the menu saves the last state immediately
  useEffect(
    () => () => {
      window.clearTimeout(draftTimer.current)
      if (draftReady.current) fetchNui('tuning:draft', draftPayload(cartRef.current))
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  )

  const select = (cat: TuningCategory, value: TuningValue) => {
    const v = normalize(cat, value)
    setCart((prev) => {
      const next = { ...prev }
      if (isWheels(cat.key)) Object.keys(next).forEach((k) => isWheels(k) && k !== cat.key && delete next[k])
      if (sameValue(cat, v, baseline(cat))) delete next[cat.key]
      else next[cat.key] = v
      return next
    })
    preview(cat.key, v, true)
  }

  const removeFromCart = (key: string) => {
    const cat = byKey.get(key)
    const next = { ...cart }
    delete next[key]
    setCart(next)
    if (cat) restore(cat, true, next)
  }

  /* ---------------- pricing & requirements */

  const optionFor = (cat: TuningCategory, value: TuningValue) =>
    cat.kind === 'list' ? asArray<TuningOption>(cat.options).find((o) => o.value === value) : undefined

  const priceOf = (cat: TuningCategory, value: TuningValue) => {
    if (sameValue(cat, value, baseline(cat))) return 0
    if (cat.kind === 'list') return Number(optionFor(cat, value)?.price) || 0
    return Number(cat.price) || 0
  }

  const valueLabel = (cat: TuningCategory, value: TuningValue): string => {
    switch (cat.kind) {
      case 'list': {
        const option = optionFor(cat, value)
        if (option) return option.label
        if (value === OTHER_WHEEL_TYPE) return '—'
        return value === -1 ? t('ui_tun_stock', 'Stock') : `#${value}`
      }
      case 'toggle':
        return value ? t('ui_tun_on', 'On') : t('ui_tun_off', 'Off')
      case 'color': {
        // -1 = custom (RGB) paint that is not in the palette
        const entry = paletteOf(cat).find((p) => p.value === value)
        return entry ? entry.label : Number(value) < 0 ? '—' : `#${value}`
      }
      case 'rgb':
        return rgbToHex(value as Rgb).toUpperCase()
      default:
        return String(value)
    }
  }

  const changes = Object.keys(cart)
    .map((key) => ({ cat: byKey.get(key), value: cart[key]! }))
    .filter((c): c is { cat: TuningCategory; value: TuningValue } => !!c.cat)
  const total = changes.reduce((sum, c) => sum + priceOf(c.cat, c.value), 0)

  const needs = (() => {
    const items: ItemReq[] = []
    const tools: ItemReq[] = []
    // the customer only orders – the mechanic brings the parts
    if (customer) return aggregateReqs(items, tools)
    changes.forEach(({ cat, value }) => {
      const option = optionFor(cat, value)
      if (option?.item) items.push(option.item)
      if (cat.item && !isRemoval(cat, value) && !option?.removal) items.push(cat.item)
      if (cat.tool) tools.push(cat.tool)
    })
    return aggregateReqs(items, tools)
  })()
  const missing = needs.filter((n) => n.have < n.count)

  // Order items not installed yet – categories are re-sent after every confirm, data.order only on open
  const orderLeft = orderChanges.filter((c) => {
    const cat = c && typeof c.key === 'string' ? byKey.get(c.key) : undefined
    return !!cat && !sameValue(cat, c.value, baseline(cat))
  })
  const hasOrder = orderLeft.length > 0
  const orderTotal =
    orderLeft.length === orderChanges.length
      ? Number(order?.total) || 0
      : orderLeft.reduce((sum, c) => sum + priceOf(byKey.get(c.key)!, c.value), 0)
  // the client sends "waiting" while the customer decides about the changes outside the order (quote)
  const waiting = !customer && data.approvalState === 'waiting'
  const waitingRef = useRef(waiting)
  waitingRef.current = waiting
  // ESC / close buttons are blocked while the customer decides (App leaves ESC to this view meanwhile)
  const requestClose = () => {
    if (waitingRef.current) {
      push('info', t('ui_catalog_waiting_esc', 'The customer is deciding about the quote, wait for the answer.'))
      return
    }
    onClose()
  }
  // customer: an empty cart withdraws the pending order
  const cancelOrder = customer && !changes.length && hasOrder

  // Customer: the cart is the order (replaces the pending one, empty = cancel it)
  const submitOrder = async () => {
    if (busy || (!changes.length && !hasOrder)) return
    setBusy(true)
    const res = asResult(
      await fetchNui('catalog:submit', { changes: changes.map((c) => ({ key: c.cat.key, value: c.value })) }),
    )
    setBusy(false)
    // success is announced by the client, which closes the catalog (the preview is reverted)
    if (!res.ok) push('error', res.message || t('ui_error_generic', 'Something went wrong, try again.'))
  }

  const confirm = async () => {
    if (customer) return submitOrder()
    if (!changes.length || busy || waiting) return
    setBusy(true)
    const sent: Record<string, string> = {}
    changes.forEach((c) => (sent[c.cat.key] = valueKey(c.value)))
    const approvalTimeout = Number(data.approvalTimeout) > 0 ? Number(data.approvalTimeout) : APPROVAL_DEFAULT_S
    const raw = await fetchNui(
      'tuning:confirm',
      { changes: changes.map((c) => ({ key: c.cat.key, value: c.value })) },
      data.approvalEnabled ? (approvalTimeout + APPROVAL_MARGIN_S) * 1000 : undefined,
    )
    const res = asResult<{ total?: number }>(raw)
    setBusy(false)
    if (!res.ok) {
      // no answer yet while the customer still decides – the client finishes the confirm (update + notify)
      if (raw === null && waitingRef.current) return
      push('error', res.message || t('ui_error_generic', 'Something went wrong, try again.'))
      return
    }
    // success is announced by the client (Core.Notify with the price), the update message already refreshed the data
    // Clear only what was confirmed (the user may have picked more while waiting)
    setCart((prev) => {
      const next = { ...prev }
      Object.keys(sent).forEach((key) => {
        if (key in next && valueKey(next[key]!) === sent[key]) delete next[key]
      })
      return next
    })
  }

  /* ---------------- navigation */

  const groups = GROUPS.filter((g) => categories.some((c) => c.group === g))
  const groupCats = (group: TuningGroup) => categories.filter((c) => c.group === group)
  const current = nav.level === 'detail' ? byKey.get(nav.key) : undefined

  const openGroup = (group: TuningGroup) => {
    setNav({ level: 'categories', group })
    setCursor(0)
  }

  const openCategory = (cat: TuningCategory) => {
    setNav({ level: 'detail', group: cat.group, key: cat.key })
    const index =
      cat.kind === 'list'
        ? optionsOf(cat).findIndex((o) => sameValue(cat, o.value, effective(cat)))
        : cat.kind === 'toggle' && effective(cat)
          ? 1
          : 0
    setCursor(Math.max(0, index))
    setHoverLabel(null)
    fetchNui('tuning:focus', { key: cat.key })
  }

  const back = () => {
    if (nav.level === 'detail') {
      const cat = byKey.get(nav.key)
      if (cat) restore(cat, true)
      const index = groupCats(nav.group).findIndex((c) => c.key === nav.key)
      setNav({ level: 'categories', group: nav.group })
      setCursor(Math.max(0, index))
    } else if (nav.level === 'categories') {
      setCursor(Math.max(0, groups.indexOf(nav.group)))
      setNav({ level: 'groups' })
      // unknown key = default camera, closes the opened door and turns the lights off ("reset" keeps the part preset)
      fetchNui('tuning:focus', { key: '' })
    }
  }

  // Keyboard: arrows move, Enter selects / opens, Backspace goes back (ESC closes – handled by App, here only while waiting)
  const keyState = useRef({ nav, cursor, back, openGroup, openCategory, select, groups, current, optionsOf, requestClose })
  keyState.current = { nav, cursor, back, openGroup, openCategory, select, groups, current, optionsOf, requestClose }
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        if (waitingRef.current) {
          event.preventDefault()
          keyState.current.requestClose()
        }
        return
      }
      const target = event.target as HTMLElement | null
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')) return
      const s = keyState.current
      const length =
        s.nav.level === 'groups'
          ? s.groups.length
          : s.nav.level === 'categories'
            ? categories.filter((c) => c.group === (s.nav as { group: TuningGroup }).group).length
            : s.current?.kind === 'list'
              ? s.optionsOf(s.current).length
              : s.current?.kind === 'toggle'
                ? 2
                : 0
      if (event.key === 'Backspace') {
        event.preventDefault()
        s.back()
      } else if ((event.key === 'ArrowDown' || event.key === 'ArrowUp') && length) {
        event.preventDefault()
        const next = (s.cursor + (event.key === 'ArrowDown' ? 1 : -1) + length) % length
        setCursor(next)
        if (s.nav.level === 'detail' && s.current) {
          const value = s.current.kind === 'list' ? s.optionsOf(s.current)[next]?.value : next === 1
          if (value !== undefined) preview(s.current.key, normalize(s.current, value))
        }
      } else if (event.key === 'Enter' && length) {
        event.preventDefault()
        if (s.nav.level === 'groups') {
          const g = s.groups[s.cursor]
          if (g) s.openGroup(g)
        } else if (s.nav.level === 'categories') {
          const cat = categories.filter((c) => c.group === (s.nav as { group: TuningGroup }).group)[s.cursor]
          if (cat) s.openCategory(cat)
        } else if (s.current) {
          const value = s.current.kind === 'list' ? s.optionsOf(s.current)[s.cursor]?.value : s.cursor === 1
          if (value !== undefined) s.select(s.current, normalize(s.current, value))
        }
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [categories, preview])

  // Keep the keyboard cursor visible
  const listRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const el = listRef.current?.querySelector<HTMLElement>('[data-cursor="true"]')
    if (el) el.scrollIntoView({ block: 'nearest' })
  }, [cursor, nav])

  /* ---------------- render helpers */

  const changedInGroup = (group: TuningGroup) => changes.filter((c) => c.cat.group === group).length

  const renderGroups = () => (
    <div className="tn-list" ref={listRef}>
      {groups.map((group, index) => {
        const Icon = GROUP_ICON[group]
        const changed = changedInGroup(group)
        return (
          <button
            key={group}
            type="button"
            data-cursor={cursor === index}
            className={`tn-row tn-row--group${cursor === index ? ' is-cursor' : ''}`}
            onMouseEnter={() => setCursor(index)}
            onClick={() => openGroup(group)}
          >
            <span className="tn-row__icon">
              <Icon size="1.25rem" />
            </span>
            <span className="grow">
              <span className="tn-row__label">{groupLabel(t, group)}</span>
              <span className="tn-row__sub">{t('ui_tun_categories', 'Categories: %s', groupCats(group).length)}</span>
            </span>
            {changed ? <span className="count count--accent">{changed}</span> : null}
            <IconChevronRight size="1.1rem" className="tn-row__chev" />
          </button>
        )
      })}
    </div>
  )

  const renderCategories = (group: TuningGroup) => (
    <div className="tn-list" ref={listRef}>
      {groupCats(group).map((cat, index) => {
        const inCart = cat.key in cart
        const value = effective(cat)
        return (
          <button
            key={cat.key}
            type="button"
            data-cursor={cursor === index}
            className={`tn-row${cursor === index ? ' is-cursor' : ''}${inCart ? ' is-changed' : ''}`}
            onMouseEnter={() => setCursor(index)}
            onClick={() => openCategory(cat)}
          >
            <span className="grow">
              <span className="tn-row__label">{cat.label}</span>
              <span className="tn-row__sub">
                {cat.kind === 'rgb' || cat.kind === 'color' ? (
                  <span
                    className="tn-dot"
                    style={{
                      background:
                        cat.kind === 'rgb'
                          ? rgbToHex(value as Rgb)
                          : paletteOf(cat).find((p) => p.value === value)?.hex ?? 'transparent',
                    }}
                  />
                ) : null}
                {valueLabel(cat, value)}
              </span>
            </span>
            {inCart ? <span className="chip chip--accent">{t('ui_tun_changed', 'Changed')}</span> : null}
            <IconChevronRight size="1.1rem" className="tn-row__chev" />
          </button>
        )
      })}
    </div>
  )

  const renderRequirement = (cat: TuningCategory) =>
    (cat.item || cat.tool) && !customer ? (
      <div className="tn-req">
        {cat.item ? <ItemChip req={cat.item} /> : null}
        {cat.tool ? <ItemChip req={cat.tool} tool /> : null}
      </div>
    ) : null

  const renderList = (cat: TuningCategory) => {
    const options = optionsOf(cat)
    const selectedValue = effective(cat)
    return (
      <div className="tn-list" ref={listRef} onMouseLeave={() => restore(cat)}>
        {options.map((option, index) => {
          const installed = isInstalledOption(cat, option.value, option.installed)
          const isSelected = sameValue(cat, option.value, selectedValue)
          const price = installed ? 0 : Number(option.price) || 0
          return (
            <button
              key={option.value}
              type="button"
              data-cursor={cursor === index}
              className={`tn-opt${cursor === index ? ' is-cursor' : ''}${isSelected ? ' is-selected' : ''}`}
              onMouseEnter={() => {
                setCursor(index)
                preview(cat.key, option.value)
              }}
              onClick={() => select(cat, option.value)}
            >
              <span className="tn-opt__radio">{isSelected ? <IconCheck size="0.8rem" stroke={3} /> : null}</span>
              <span className="grow tn-opt__label">
                {option.value === -1 && !option.label ? t('ui_tun_stock', 'Stock') : option.label}
              </span>
              {option.item && !installed && !customer ? (
                <Tooltip label={`${option.item.label} – ${t('ui_have_need', 'have %s / need %s', option.item.have, option.item.count)}`}>
                  <span className={`tn-opt__item${option.item.have < option.item.count ? ' is-missing' : ''}`}>
                    <span className="item__img">
                      <ItemImage item={option.item.item} />
                    </span>
                    <span className="mono">
                      {option.item.have}/{option.item.count}
                    </span>
                  </span>
                </Tooltip>
              ) : null}
              {installed ? (
                <span className="chip chip--ok">{t('ui_tun_installed', 'Installed')}</span>
              ) : (
                <span className="tn-opt__price mono">{price ? fmt.money(price) : t('ui_tun_free', 'Free')}</span>
              )}
            </button>
          )
        })}
      </div>
    )
  }

  const renderToggle = (cat: TuningCategory) => {
    const selectedValue = effective(cat) as boolean
    const installed = baseline(cat) as boolean
    return (
      <div className="tn-toggle" onMouseLeave={() => restore(cat)}>
        {[false, true].map((value, index) => (
          <button
            key={String(value)}
            type="button"
            data-cursor={cursor === index}
            className={`tn-toggle__btn${selectedValue === value ? ' is-selected' : ''}${cursor === index ? ' is-cursor' : ''}`}
            onMouseEnter={() => {
              setCursor(index)
              preview(cat.key, value)
            }}
            onClick={() => select(cat, value)}
          >
            <span className="tn-toggle__label">{value ? t('ui_tun_on', 'On') : t('ui_tun_off', 'Off')}</span>
            {installed === value ? (
              <span className="chip chip--ok">{t('ui_tun_installed', 'Installed')}</span>
            ) : (
              <span className="mono tn-opt__price">{cat.price ? fmt.money(cat.price) : t('ui_tun_free', 'Free')}</span>
            )}
          </button>
        ))}
      </div>
    )
  }

  const renderPalette = (cat: TuningCategory) => {
    const palette = paletteOf(cat)
    const selectedValue = effective(cat)
    const installed = baseline(cat)
    const selectedEntry = palette.find((p) => p.value === selectedValue)
    return (
      <div className="tn-palette-wrap">
        <div className="tn-palette-info">
          <span className="tn-dot tn-dot--lg" style={{ background: selectedEntry?.hex ?? 'transparent' }} />
          <span className="grow">{hoverLabel ?? valueLabel(cat, selectedValue)}</span>
          <span className="mono tn-opt__price">
            {sameValue(cat, selectedValue, installed) ? t('ui_tun_installed', 'Installed') : fmt.money(cat.price ?? 0)}
          </span>
        </div>
        <div
          className="tn-palette"
          onMouseLeave={() => {
            setHoverLabel(null)
            restore(cat)
          }}
        >
          {palette.map((entry) => (
            <button
              key={entry.value}
              type="button"
              className={`tn-swatch${entry.value === selectedValue ? ' is-selected' : ''}${entry.value === installed ? ' is-installed' : ''}`}
              style={{ background: entry.hex }}
              onMouseEnter={() => {
                setHoverLabel(entry.label)
                preview(cat.key, entry.value)
              }}
              onClick={() => select(cat, entry.value)}
              aria-label={entry.label}
            />
          ))}
        </div>
      </div>
    )
  }

  const renderDetail = (cat: TuningCategory) => (
    <>
      {renderRequirement(cat)}
      {cat.kind === 'list' ? renderList(cat) : null}
      {cat.kind === 'toggle' ? renderToggle(cat) : null}
      {cat.kind === 'color' ? renderPalette(cat) : null}
      {cat.kind === 'rgb' ? (
        <RgbEditor
          key={cat.key}
          committed={effective(cat) as Rgb}
          installed={baseline(cat) as Rgb}
          price={Number(cat.price) || 0}
          onPreview={(rgb) => preview(cat.key, rgb)}
          onSelect={(rgb) => select(cat, rgb)}
        />
      ) : null}
    </>
  )

  // Mechanic with a customer order: ordered (same value) or waiting for the customer's approval
  const renderTag = (cat: TuningCategory, value: TuningValue) => {
    if (customer || !hasOrder) return null
    if (isOrdered(cat, value)) return <span className="tn-tag tn-tag--ok">{t('ui_catalog_tag_ordered', 'Ordered')}</span>
    if (data.approvalEnabled) return <span className="tn-tag tn-tag--warn">{t('ui_catalog_tag_approval', 'Needs approval')}</span>
    return null
  }

  const renderOrder = (o: NonNullable<TuningData['order']>) => {
    const minutes = Number(o.minutes)
    const meta = [t('ui_catalog_order_items', 'Items: %s', orderLeft.length)]
    if (o.minutes !== undefined && o.minutes !== null && Number.isFinite(minutes)) {
      meta.push(minutes < 1 ? t('ui_catalog_order_now', 'just now') : t('ui_catalog_order_ago', '%s min ago', Math.floor(minutes)))
    }
    return (
      <div className="tn-order">
        <IconClipboardList size="1.2rem" className="tn-order__icon" />
        <div className="grow">
          <div className="tn-order__title">
            {customer
              ? t('ui_catalog_your_order', 'Your pending order')
              : o.customer
                ? t('ui_catalog_order_from', 'Order from %s', o.customer)
                : t('ui_catalog_order_customer', 'Customer order')}
          </div>
          <div className="tn-order__meta">{meta.join(' · ')}</div>
        </div>
        <span className="mono tn-order__total">{fmt.money(orderTotal)}</span>
      </div>
    )
  }

  const renderConfirm = () => {
    if (waiting) {
      return (
        <button type="button" className="btn btn--primary grow tn-cart__waiting" disabled>
          <IconLoader2 size="1.1rem" className="spin" />
          <span>{t('ui_catalog_waiting', "Waiting for the customer's approval…")}</span>
        </button>
      )
    }
    if (cancelOrder) {
      return (
        <button type="button" className="btn btn--danger grow" disabled={busy} onClick={confirm}>
          <IconTrash size="1.1rem" />
          {t('ui_catalog_cancel_order', 'Cancel order')}
        </button>
      )
    }
    return (
      <button type="button" className="btn btn--primary grow" disabled={!changes.length || busy} onClick={confirm}>
        {customer ? <IconSend size="1.1rem" /> : <IconCheck size="1.1rem" />}
        {customer ? t('ui_catalog_send', 'Send order') : t('ui_tun_confirm', 'Confirm')}
      </button>
    )
  }

  // Buttons never take focus, so Enter / arrows always drive the keyboard cursor
  const keepButtonsUnfocused = (e: MouseEvent) => {
    if ((e.target as HTMLElement).closest('button')) e.preventDefault()
  }

  const crumbs: string[] = [t('ui_tun_title', 'Tuning')]
  if (nav.level !== 'groups') crumbs.push(groupLabel(t, nav.group))
  if (nav.level === 'detail' && current) crumbs.push(current.label)

  return (
    <div className="layer tn-layer">
      <aside className="tn-panel" onMouseDown={keepButtonsUnfocused}>
        <header className="tn-head">
          <div className="win__icon">
            <IconSparkles size="1.4rem" />
          </div>
          <div className="grow" style={{ minWidth: 0 }}>
            <div className="tn-head__title">
              {customer ? t('ui_catalog_title', 'Tuning catalog') : data.model || t('ui_tun_title', 'Tuning')}
            </div>
            <div className="row" style={{ marginTop: '0.3rem' }}>
              <Plate plate={data.plate} small />
              {customer ? <span className="tn-head__meta">{[data.model, data.shop].filter(Boolean).join(' · ')}</span> : null}
            </div>
          </div>
          <button type="button" className="win__close" onClick={requestClose} title={t('ui_close', 'Close')}>
            <span className="kbd">ESC</span>
            <IconX size="1.1rem" />
          </button>
        </header>

        {order && hasOrder ? renderOrder(order) : null}

        <nav className="tn-crumbs">
          <button type="button" className="btn btn--icon btn--sm" disabled={nav.level === 'groups'} onClick={back}>
            <IconArrowLeft size="1rem" />
          </button>
          <div className="tn-crumbs__path">
            {crumbs.map((c, i) => (
              <span key={i} className={i === crumbs.length - 1 ? 'is-last' : undefined}>
                {c}
              </span>
            ))}
          </div>
        </nav>

        <div className="tn-content scroll" key={nav.level === 'detail' ? nav.key : nav.level === 'categories' ? nav.group : 'groups'}>
          {nav.level === 'groups' ? renderGroups() : null}
          {nav.level === 'categories' ? renderCategories(nav.group) : null}
          {nav.level === 'detail' && current ? renderDetail(current) : null}
        </div>

        <div className="tn-keys">
          <span>
            <span className="kbd">↑</span>
            <span className="kbd">↓</span> {t('ui_tun_key_move', 'Move')}
          </span>
          <span>
            <span className="kbd">Enter</span> {t('ui_tun_key_select', 'Select')}
          </span>
          <span>
            <span className="kbd">⌫</span> {t('ui_tun_key_back', 'Back')}
          </span>
        </div>

        <footer className="tn-cart">
          <div className="tn-cart__head">
            <IconShoppingCart size="1.1rem" />
            <span className="grow tn-cart__title">{t('ui_tun_cart', 'Changes')}</span>
            <span className="count count--accent">{changes.length}</span>
          </div>
          {changes.length ? (
            <div className="tn-cart__list scroll">
              {changes.map(({ cat, value }) => (
                <div key={cat.key} className="tn-cart__line">
                  <div className="grow" style={{ minWidth: 0 }}>
                    <div className="tn-cart__label">
                      {cat.label}
                      {renderTag(cat, value)}
                    </div>
                    <div className="tn-cart__value">{valueLabel(cat, value)}</div>
                  </div>
                  <span className="mono tn-cart__price">{fmt.money(priceOf(cat, value))}</span>
                  <button type="button" className="btn btn--icon btn--sm btn--ghost" onClick={() => removeFromCart(cat.key)}>
                    <IconX size="0.9rem" />
                  </button>
                </div>
              ))}
            </div>
          ) : (
            <div className="tn-cart__empty muted">{t('ui_tun_cart_empty', 'Hover to preview, click to add a change.')}</div>
          )}
          {customer ? (
            <div className="tn-cart__hint">
              <IconInfoCircle size="1rem" />
              <span className="grow">
                {t('ui_catalog_hint', 'A mechanic of the workshop installs your order, you pay the bill afterwards.')}
              </span>
            </div>
          ) : null}
          {/* parts fetching on: missing parts do not block, the installation pauses and they are taken from the storage */}
          {missing.length ? (
            <div className={`tn-cart__missing${config.fetchParts ? ' is-fetch' : ''}`}>
              {config.fetchParts ? <IconBuildingWarehouse size="1rem" /> : <IconAlertTriangle size="1rem" />}
              <span className="grow">
                {config.fetchParts
                  ? t('ui_tun_missing_fetch', 'Some parts are not in your inventory – you will fetch them from the storage during the installation')
                  : t('ui_tun_missing', 'Missing materials or tools')}
              </span>
              {missing.slice(0, 4).map((req) => (
                <ItemChip key={`${req.tool ? 't' : 'i'}-${req.item}`} req={req} tool={req.tool} showLabel={false} />
              ))}
            </div>
          ) : null}
          <div className="tn-cart__total">
            <span>{t('ui_total', 'Total')}</span>
            <span className="mono">{fmt.money(total)}</span>
          </div>
          <div className="tn-cart__actions">
            <button type="button" className="btn" onClick={requestClose}>
              {customer ? t('ui_close', 'Close') : t('ui_cancel', 'Cancel')}
            </button>
            {renderConfirm()}
          </div>
        </footer>
      </aside>

      <div className="tn-cam">
        <CamButton action="rotateLeft" icon={<IconRotate size="1.2rem" />} label={t('ui_cam_rotate_left', 'Rotate left')} />
        <CamButton action="zoomIn" icon={<IconZoomIn size="1.2rem" />} label={t('ui_cam_zoom_in', 'Zoom in')} />
        <CamButton action="reset" icon={<IconFocus2 size="1.2rem" />} label={t('ui_cam_reset', 'Reset camera')} repeat={false} />
        <CamButton action="zoomOut" icon={<IconZoomOut size="1.2rem" />} label={t('ui_cam_zoom_out', 'Zoom out')} />
        <CamButton action="rotateRight" icon={<IconRotateClockwise size="1.2rem" />} label={t('ui_cam_rotate_right', 'Rotate right')} />
      </div>
    </div>
  )
}
