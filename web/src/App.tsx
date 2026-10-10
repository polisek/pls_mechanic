import { lazy, Suspense, useCallback, useEffect, useRef, useState } from 'react'
import { MantineProvider } from '@mantine/core'
import { theme } from './theme'
import { DEFAULT_CONFIG, UiProvider } from './lib/ui'
import { ToastProvider } from './lib/toast'
import { fetchNui, isEnvBrowser } from './lib/nui'
import { mergeWorkflow } from './lib/workflow'
import { FOCUS_VIEWS, type FocusView, type Locales, type NuiMessage, type UiConfig, type WorkflowData } from './types'
import Diagnostics from './views/Diagnostics'
import Workflow from './views/Workflow'
import History from './views/History'
import BillCreate from './views/BillCreate'
import Bill from './views/Bill'
import Supplier from './views/Supplier'
import Tuning from './views/Tuning'
import Settings from './views/Settings'
import Quote from './views/Quote'

// Browser-only dev switcher with mock data (separate chunk, never loaded in game)
const DevTools = lazy(() => import('./dev/DevTools'))

interface FocusState {
  view: FocusView
  data: any
  openId: number
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === 'object' && !Array.isArray(value)

export default function App() {
  const [focus, setFocus] = useState<FocusState | null>(null)
  const [workflow, setWorkflow] = useState<WorkflowData | null>(null)
  // every "open" of the overlay is a new workflow -> fresh component (scroll, cached phases, slide-in)
  const [workflowId, setWorkflowId] = useState(0)
  const [locales, setLocales] = useState<Locales>({})
  const [config, setConfig] = useState<UiConfig>(DEFAULT_CONFIG)
  const openCounter = useRef(0)
  const focusRef = useRef<FocusState | null>(null)
  focusRef.current = focus

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      const msg = event.data as NuiMessage
      if (!isObject(msg) || typeof msg.action !== 'string') return
      if (isObject(msg.locales)) setLocales(msg.locales as Locales)
      if (isObject(msg.config)) setConfig((prev) => ({ ...prev, ...(msg.config as Partial<UiConfig>) }))

      const view = msg.view
      const data = isObject(msg.data) ? msg.data : {}

      // arrival time of the message – a newly started workflow phase runs its progress bar from here
      const receivedAt = performance.now()

      if (msg.action === 'open') {
        if (view === 'workflow') {
          openCounter.current += 1
          setWorkflowId(openCounter.current)
          setWorkflow(mergeWorkflow(null, data, receivedAt))
        } else if (view && FOCUS_VIEWS.includes(view as FocusView)) {
          openCounter.current += 1
          setFocus({ view: view as FocusView, data, openId: openCounter.current })
        }
      } else if (msg.action === 'update') {
        if (view === 'workflow') {
          // Lua always sends the full state: steps + phase are replaced, current / phase = nil is left out of the
          // JSON -> reset, not keep the old one; mode / cancelHint stay from open unless sent again
          setWorkflow((prev) => mergeWorkflow(prev, data, receivedAt))
        } else {
          setFocus((prev) => (prev && prev.view === view ? { ...prev, data: { ...prev.data, ...data } } : prev))
        }
      } else if (msg.action === 'close') {
        if (view === 'workflow') {
          setWorkflow(null)
        } else {
          setFocus((prev) => (!view || (prev && prev.view === view) ? null : prev))
        }
      }
    }
    window.addEventListener('message', onMessage)
    return () => window.removeEventListener('message', onMessage)
  }, [])

  // ESC / close button: hide immediately, core (client/main.lua) releases focus + runs OnClose handlers
  const closeFocused = useCallback(() => {
    const current = focusRef.current
    if (!current) return
    setFocus(null)
    fetchNui('close', { view: current.view })
  }, [])

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const current = focusRef.current
      // the quote answers ESC itself (= decline), the tuning menu while the customer decides about a quote (blocked)
      const ownEscape = current && (current.view === 'quote' || (current.view === 'tuning' && current.data?.approvalState === 'waiting'))
      if (event.key === 'Escape' && current && !ownEscape) {
        event.preventDefault()
        closeFocused()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [closeFocused])

  // Lets a view replace its own data after a callback answered with fresh data
  const replaceData = useCallback((view: FocusView, data: unknown) => {
    setFocus((prev) => (prev && prev.view === view && isObject(data) ? { ...prev, data: { ...prev.data, ...data } } : prev))
  }, [])

  const renderFocus = () => {
    if (!focus) return null
    const common = { key: focus.openId, onClose: closeFocused }
    switch (focus.view) {
      case 'diagnostics':
        return <Diagnostics {...common} data={focus.data} />
      case 'history':
        return <History {...common} data={focus.data} />
      case 'billCreate':
        return <BillCreate {...common} data={focus.data} />
      case 'bill':
        return <Bill {...common} data={focus.data} />
      case 'supplier':
        return <Supplier {...common} data={focus.data} onData={(d) => replaceData('supplier', d)} />
      case 'tuning':
        return <Tuning {...common} data={focus.data} />
      case 'settings':
        return <Settings {...common} data={focus.data} />
      case 'quote':
        return <Quote {...common} data={focus.data} />
      default:
        return null
    }
  }

  return (
    <MantineProvider theme={theme} forceColorScheme="dark">
      <UiProvider locales={locales} config={config}>
        <ToastProvider>
          {workflow ? <Workflow key={workflowId} data={workflow} /> : null}
          {renderFocus()}
          {isEnvBrowser() ? (
            <Suspense fallback={null}>
              <DevTools />
            </Suspense>
          ) : null}
        </ToastProvider>
      </UiProvider>
    </MantineProvider>
  )
}
