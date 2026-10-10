// Browser-only dev switcher: opens every view with mock data and answers NUI callbacks.
import { useEffect, useRef, useState } from 'react'
import type { FocusView, Locales, NuiMessage, SupplierData, TuningData, View, WorkflowData, WorkflowStep } from '../types'
import { asArray, setMockHandlers } from '../lib/nui'
import uiLocales from '../../../locales/_src/ui.json'
import fetchLocales from '../../../locales/_src/nui_fetch.json'
import catalogLocales from '../../../locales/_src/catalog_ui.json'
import * as mocks from './mocks'
import './dev.css'

const MOCK: Record<FocusView, unknown> = {
  diagnostics: mocks.diagnostics,
  history: mocks.history,
  billCreate: mocks.billCreate,
  bill: mocks.bill,
  supplier: mocks.supplier,
  tuning: mocks.tuning,
  settings: mocks.settings,
  quote: mocks.quote,
}

// tuning variants of the catalog (mechanic-catalog-spec.md §5)
const TUNING_PRESETS = {
  tuningCustomer: mocks.tuningCustomer,
  tuningOrder: mocks.tuningOrder,
  tuningWaiting: mocks.tuningWaiting,
}
type Preset = View | 'workflowTuning' | keyof typeof TUNING_PRESETS

const VIEWS: { view: Preset; label: string }[] = [
  { view: 'diagnostics', label: 'Diagnostics' },
  { view: 'workflow', label: 'Workflow repair' },
  { view: 'workflowTuning', label: 'Workflow tuning' },
  { view: 'history', label: 'History' },
  { view: 'billCreate', label: 'Bill create' },
  { view: 'bill', label: 'Bill' },
  { view: 'supplier', label: 'Supplier' },
  { view: 'tuning', label: 'Tuning' },
  { view: 'tuningCustomer', label: 'Tuning catalog' },
  { view: 'tuningOrder', label: 'Tuning order' },
  { view: 'tuningWaiting', label: 'Tuning approval' },
  { view: 'quote', label: 'Quote' },
  { view: 'settings', label: 'Settings' },
]

type Lang = 'en' | 'cs'
// the lead merges the fragments into en.json / cs.json – the dev switcher merges them the same way
const LOCALES: Record<Lang, Locales> = {
  en: {
    ...(uiLocales as Record<Lang, Locales>).en,
    ...(fetchLocales as Record<Lang, Locales>).en,
    ...(catalogLocales as Record<Lang, Locales>).en,
  },
  cs: {
    ...(uiLocales as Record<Lang, Locales>).cs,
    ...(fetchLocales as Record<Lang, Locales>).cs,
    ...(catalogLocales as Record<Lang, Locales>).cs,
  },
}

// Lua hints of the waiting panel (fetch_hint_fetch / fetch_hint_ready live in locales/_src/fetch.json)
const WAIT_HINTS: Record<Lang, { fetch: string; ready: string }> = {
  en: {
    fetch: 'Take the parts from the workshop storage, then continue via the target on the vehicle.',
    ready: 'Everything ready – continue via the target on the vehicle.',
  },
  cs: {
    fetch: 'Vezmi díly ve skladu dílny a pokračuj přes target na vozidle.',
    ready: 'Vše připraveno – pokračuj přes target na vozidle.',
  },
}

const post = (msg: NuiMessage) => window.postMessage(msg, '*')

let supplierState: SupplierData = JSON.parse(JSON.stringify(mocks.supplier))
// last opened tuning mock – tuning:confirm plays the customer's approval when it has an order
let tuningState: TuningData | null = null

export default function DevTools() {
  const [lang, setLang] = useState<Lang>('en')
  const [collapsed, setCollapsed] = useState(false)
  // Config.Fetch.enabled – workflow steps pause for parts, tuning cart shows the fetch hint instead of the red error
  const [fetchParts, setFetchParts] = useState(true)
  const langRef = useRef(lang)
  langRef.current = lang
  const fetchRef = useRef(fetchParts)
  fetchRef.current = fetchParts
  const timer = useRef<number>()

  const open = (view: View, data: unknown) =>
    post({
      action: 'open',
      view,
      data,
      locales: LOCALES[langRef.current],
      config: {
        currency: '$',
        imagePath: 'nui://ox_inventory/web/images/%s.png',
        fetchParts: fetchRef.current,
      },
    })

  // Plays the workflow like client/repair.lua + client/tuning.lua do: an update on every phase start
  // (full state, phase only on the active step), then active → done/failed, next pending → active.
  // With "Fetch" on, steps listed in mocks.workflowWaiting pause first like Fetch.Wait (mechanic-fetch-spec.md §4-6).
  const runWorkflow = (initial: WorkflowData) => {
    window.clearTimeout(timer.current)
    const tuning = initial.mode === 'tuning'
    const fetch = fetchRef.current
    let state: WorkflowData = {
      ...JSON.parse(JSON.stringify(initial)),
      cancelHint: langRef.current === 'cs' ? 'nebo použij target na vozidle' : 'or use the target on the vehicle',
    }
    const phasesOf = (step: WorkflowStep) =>
      mocks.workflowPhases[step.key] ?? mocks.workflowPhases[tuning ? '_tuning' : '_repair']!
    const waitOf = (step: WorkflowStep | undefined) => (fetch && step ? mocks.workflowWaiting[step.key] : undefined)

    const send = () => post({ action: 'update', view: 'workflow', data: state })

    // Fetch.Wait: the step is "waiting" until every part is carried (the mechanic takes them one by one, an empty
    // storage gets restocked), then ready – "Continue" on the vehicle resumes it as active. Updates are sent only
    // on a change (like the Lua re-count), `remaining` counts down in the NUI in between.
    const waitStep = (index: number, opening: boolean) => {
      const step = state.steps[index]!
      const mock = waitOf(step)!
      const items = mock.items.map((i) => ({ ...i }))
      const timeout = mock.timeout ?? 600
      const started = Date.now()
      const hints = WAIT_HINTS[langRef.current]

      const push = (first: boolean): boolean => {
        const ready = items.every((i) => i.have >= i.need)
        const steps = state.steps.map((s, i) => {
          if (i !== index) return s
          const waiting: WorkflowStep = { ...s, status: 'waiting' }
          delete waiting.phase
          return waiting
        })
        state = {
          ...state,
          steps,
          current: step.id,
          waiting: {
            label: step.label,
            items: items.map((i) => ({ ...i })),
            ready,
            hint: ready ? hints.ready : hints.fetch,
            remaining: Math.max(0, Math.round(timeout - (Date.now() - started) / 1000)),
          },
        }
        if (first && opening) open('workflow', state)
        else send()
        return ready
      }

      const resume = () => {
        const steps = state.steps.map((s, i) => (i === index ? { ...s, status: 'active' as const } : s))
        const next: WorkflowData = { ...state, steps }
        delete next.waiting // Lua leaves the field out -> the panel must go away
        state = next
        phaseIndex = 0
        send()
        timer.current = window.setTimeout(tick, 600) // walking back to the work spot
      }

      const take = () => {
        const next = items.find((i) => i.have < i.need && i.stock !== 0)
        if (next) {
          const missing = next.need - next.have
          const count = typeof next.stock === 'number' ? Math.min(next.stock, missing) : missing
          next.have += count
          if (typeof next.stock === 'number') next.stock -= count
        } else {
          const empty = items.find((i) => i.have < i.need)
          if (empty) empty.stock = empty.need - empty.have + 2 // a delivery arrived in the storage
        }
        timer.current = push(false) ? window.setTimeout(resume, 5000) : window.setTimeout(take, 2600)
      }

      push(true)
      timer.current = window.setTimeout(take, 4000)
    }

    const firstIndex = state.steps.findIndex((s) => s.status === 'active')
    const first = state.steps[firstIndex]
    let phaseIndex = first?.phase ? first.phase.index : 0

    const tick = () => {
      const steps: WorkflowStep[] = state.steps.map((s) => ({ ...s }))
      const active = steps.findIndex((s) => s.status === 'active')
      if (active < 0) return
      const step = steps[active]!
      const phases = phasesOf(step)

      if (phaseIndex < phases.length) {
        const phase = phases[phaseIndex]!
        phaseIndex += 1
        step.phase = { label: phase.label, index: phaseIndex, count: phases.length, duration: phase.duration }
        state = { ...state, steps, current: step.id }
        send()
        timer.current = window.setTimeout(tick, phase.duration > 0 ? phase.duration : 1800)
        return
      }

      delete step.phase
      step.status = Math.random() < 0.12 ? 'failed' : 'done'
      if (step.status === 'failed') step.message = tuning ? 'The part does not fit this vehicle.' : 'Missing tool: Impact wrench'
      else delete step.message
      const next = steps.findIndex((s) => s.status === 'pending')
      if (next >= 0) steps[next]!.status = 'active'
      phaseIndex = 0
      state = { ...state, steps, current: next >= 0 ? steps[next]!.id : null }
      // the next step lacks parts -> it goes straight to "waiting" (one update with the finished step)
      if (next >= 0 && waitOf(steps[next])) {
        waitStep(next, false)
        return
      }
      send()
      timer.current =
        next >= 0
          ? window.setTimeout(tick, 500) // "walking to the next spot" – active step without a phase
          : window.setTimeout(() => post({ action: 'close', view: 'workflow' }), 4000)
    }

    if (firstIndex >= 0 && waitOf(first)) {
      waitStep(firstIndex, true)
      return
    }
    open('workflow', state)
    timer.current = window.setTimeout(tick, first?.phase ? first.phase.duration : 600)
  }

  useEffect(() => {
    document.body.classList.add('dev-bg')
    setMockHandlers({
      'diagnostics:start': (payload: { steps: { kind: string; key: string }[] }) => {
        const all = [...mocks.diagnostics.service, ...mocks.diagnostics.core, ...mocks.diagnostics.body]
        const steps: WorkflowStep[] = payload.steps.map((s, i) => ({
          id: i + 1,
          kind: s.kind,
          key: s.key,
          label: all.find((p) => p.key === s.key)?.label ?? s.key,
          status: i === 0 ? 'active' : 'pending',
        }))
        post({ action: 'close', view: 'diagnostics' })
        runWorkflow({ mode: 'repair', plate: mocks.diagnostics.plate, cancelKey: 'X', current: 1, steps })
        return { ok: true }
      },
      'billCreate:send': () => ({ ok: true }),
      'bill:pay': (payload: { method: string }) => ({ ok: true, message: `Paid by ${payload.method}.` }),
      'bill:decline': () => ({ ok: true }),
      'supplier:refresh': () => supplierState,
      'supplier:order': (payload: { mode: string; items: { item: string; count: number }[] }) => {
        const mode = supplierState.modes.find((m) => m.key === payload.mode)!
        const items = payload.items.map((i) => {
          const entry = supplierState.catalog.find((c) => c.item === i.item)!
          return { item: i.item, label: entry.label, count: i.count, price: entry.price }
        })
        const total = Math.round(items.reduce((s, i) => s + i.price * i.count, 0) * mode.multiplier)
        const now = Math.floor(Date.now() / 1000)
        supplierState = {
          ...supplierState,
          balance: supplierState.balance - total,
          catalog: supplierState.catalog.map((c) => {
            const bought = payload.items.find((i) => i.item === c.item)
            return bought && typeof c.remaining === 'number' ? { ...c, remaining: c.remaining - bought.count } : c
          }),
          orders: [
            {
              id: Math.max(...supplierState.orders.map((o) => o.id)) + 1,
              date: now,
              name: 'You',
              items: items.map(({ item, label, count }) => ({ item, label, count })),
              total,
              mode: mode.key,
              status: mode.key === 'instant' ? 'delivered' : mode.key === 'run' ? 'awaiting_pickup' : 'pending',
              deliverAt: mode.key === 'delayed' ? now + (mode.minutes ?? 15) * 60 : mode.key === 'instant' ? now : undefined,
            },
            ...supplierState.orders,
          ],
        }
        return { ok: true, message: 'Order placed.', data: supplierState }
      },
      'tuning:preview': (payload: unknown) => {
        console.log('[dev] tuning:preview', payload)
        return { ok: true }
      },
      'tuning:focus': (payload: unknown) => {
        console.log('[dev] tuning:focus', payload)
        return { ok: true }
      },
      'tuning:camera': (payload: unknown) => {
        console.log('[dev] tuning:camera', payload)
        return { ok: true }
      },
      'tuning:confirm': async (payload: { changes: { key: string; value: unknown }[] }) => {
        // client tuning:approve: changes outside the order wait for the customer's answer to the quote
        const order = tuningState?.order && tuningState.approvalEnabled ? asArray<{ key: string; value: unknown }>(tuningState.order.changes) : null
        const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)
        if (order && payload.changes.some((c) => !order.some((o) => o.key === c.key && same(o.value, c.value)))) {
          post({ action: 'update', view: 'tuning', data: { approvalState: 'waiting' } })
          await new Promise((r) => setTimeout(r, 4000))
          post({ action: 'update', view: 'tuning', data: { approvalState: false } })
        }
        return { ok: true, message: `${payload.changes.length} changes installed.` }
      },
      // client: on ok the catalog closes (preview reverted) and the customer gets a notify
      'catalog:submit': (payload: { changes: unknown[] }) => {
        console.log('[dev] catalog:submit', payload)
        post({ action: 'close', view: 'tuning' })
        return { ok: true }
      },
      'quote:accept': () => {
        post({ action: 'close', view: 'quote' })
        return { ok: true }
      },
      'quote:decline': () => {
        post({ action: 'close', view: 'quote' })
        return { ok: true }
      },
      'settings:save': () => ({ ok: true }),
      'settings:bills': (payload: { page: number }) => mocks.billsPage(payload.page),
      'settings:orders': (payload: { page: number }) => mocks.ordersPage(payload.page),
      close: () => ({ ok: true }),
    })
    // ?mock=<preset>&lang=cs&dev=0 opens a mock right away (headless screenshots), e.g. ?mock=tuningCustomer
    const params = new URLSearchParams(window.location.search)
    if (params.get('lang') === 'cs') {
      langRef.current = 'cs'
      setLang('cs')
    }
    if (params.get('dev') === '0') setCollapsed(true)
    const preset = params.get('mock')
    const auto = preset && VIEWS.some((v) => v.view === preset) ? window.setTimeout(() => click(preset as Preset), 50) : undefined
    return () => {
      document.body.classList.remove('dev-bg')
      window.clearTimeout(timer.current)
      window.clearTimeout(auto)
    }
  }, [])

  const click = (view: Preset) => {
    if (view === 'workflow') runWorkflow(mocks.workflow)
    else if (view === 'workflowTuning') runWorkflow(mocks.workflowTuning)
    else if (view === 'supplier') open(view, supplierState)
    else if (view === 'tuning' || view in TUNING_PRESETS) {
      tuningState = view === 'tuning' ? mocks.tuning : TUNING_PRESETS[view as keyof typeof TUNING_PRESETS]
      open('tuning', tuningState)
    } else open(view as FocusView, MOCK[view as FocusView])
  }

  return (
    <div className={`dev${collapsed ? ' is-collapsed' : ''}`}>
      <button type="button" className="dev__toggle" onClick={() => setCollapsed((c) => !c)}>
        DEV
      </button>
      {!collapsed ? (
        <>
          {VIEWS.map((v) => (
            <button key={v.view} type="button" className="dev__btn" onClick={() => click(v.view)}>
              {v.label}
            </button>
          ))}
          <span className="dev__sep" />
          <button
            type="button"
            className={`dev__btn${fetchParts ? ' is-on' : ''}`}
            title="Config.Fetch.enabled – workflow steps wait for parts, tuning cart fetch hint"
            onClick={() => setFetchParts((f) => !f)}
          >
            Fetch {fetchParts ? 'ON' : 'OFF'}
          </button>
          <button type="button" className="dev__btn" onClick={() => setLang((l) => (l === 'en' ? 'cs' : 'en'))}>
            {lang.toUpperCase()}
          </button>
          <button
            type="button"
            className="dev__btn"
            onClick={() => {
              window.clearTimeout(timer.current)
              post({ action: 'close', view: 'workflow' })
              post({ action: 'close' })
            }}
          >
            Close all
          </button>
        </>
      ) : null}
    </div>
  )
}
