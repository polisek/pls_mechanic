import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import {
  IconAlertTriangle,
  IconBuildingWarehouse,
  IconCheck,
  IconCircleCheck,
  IconCircleDashed,
  IconCircleX,
  IconClock,
  IconHandFinger,
  IconHourglassHigh,
  IconLoader2,
  IconPackage,
  IconPlayerSkipForward,
  IconSparkles,
  IconTool,
  IconWeight,
} from '@tabler/icons-react'
import type { StepStatus, WorkflowData, WorkflowPhase, WorkflowStep, WorkflowWaiting, WorkflowWaitingItem } from '../types'
import { Plate } from '../components/Vehicle'
import { asArray } from '../lib/nui'
import { useUi, type Formatters, type TFunction } from '../lib/ui'
import { phaseKey } from '../lib/workflow'
import './workflow.css'

/** Expand / collapse time of the phase block (keep in sync with workflow.css) + a small margin. */
const SETTLE_MS = 340

/** Same curve as --ease in global.css (the waiting panel height is animated from JS). */
const EASE = 'cubic-bezier(0.2, 0.8, 0.2, 1)'

/** Countdown turns red in the last minute. */
const LOW_SECONDS = 60

function StepIcon({ status }: { status: StepStatus }) {
  switch (status) {
    case 'active':
      return <IconLoader2 size="1.15rem" className="spin" />
    case 'waiting':
      return <IconPackage size="1.1rem" />
    case 'done':
      return <IconCircleCheck size="1.15rem" />
    case 'failed':
      return <IconCircleX size="1.15rem" />
    case 'skipped':
      return <IconPlayerSkipForward size="1.05rem" />
    default:
      return <IconCircleDashed size="1.15rem" />
  }
}

function statusText(t: TFunction, status: StepStatus, ready = false): string {
  switch (status) {
    case 'active':
      return t('ui_wf_status_active', 'In progress')
    case 'waiting':
      return ready ? t('ui_wf_status_ready', 'Ready') : t('ui_wf_status_waiting', 'Needs parts')
    case 'done':
      return t('ui_wf_status_done', 'Done')
    case 'failed':
      return t('ui_wf_status_failed', 'Failed')
    case 'skipped':
      return t('ui_wf_status_skipped', 'Skipped')
    default:
      return t('ui_wf_status_pending', 'Waiting')
  }
}

function modeTexts(t: TFunction, tuning: boolean) {
  return tuning
    ? {
        title: t('ui_wf_tuning_title', 'Installing tuning'),
        finished: t('ui_wf_tuning_finished', 'Tuning installed'),
        finishedErrors: t('ui_wf_tuning_finished_errors', 'Finished with errors'),
        cancel: t('ui_wf_tuning_cancel', 'Cancel installation'),
      }
    : {
        title: t('ui_wf_title', 'Repair in progress'),
        finished: t('ui_wf_finished', 'Repair finished'),
        finishedErrors: t('ui_wf_finished_errors', 'Finished with errors'),
        cancel: t('ui_wf_cancel', 'Cancel repair'),
      }
}

/**
 * Thin bar running 0 → 100 % over `duration` ms from the moment the phase arrived.
 * The parent keys it by phase, so it restarts exactly on a new phase; the elapsed time is read once on mount
 * (negative animation-delay) so a late render never makes the bar run longer than the phase.
 */
function PhaseBar({ duration, startedAt }: { duration: number; startedAt?: number }) {
  const [elapsed] = useState(() => (startedAt === undefined ? 0 : Math.max(0, performance.now() - startedAt)))

  if (!(duration > 0)) {
    return (
      <div className="wf-phase__bar is-indeterminate">
        <div className="wf-phase__fill" />
      </div>
    )
  }
  return (
    <div className="wf-phase__bar">
      <div
        className="wf-phase__fill"
        style={{ animationDuration: `${duration}ms`, animationDelay: `${-Math.min(elapsed, duration)}ms` }}
      />
    </div>
  )
}

function PhaseInfo({ stepId, phase, phaseWord }: { stepId: number; phase: WorkflowPhase; phaseWord: string }) {
  const key = phaseKey(stepId, phase)
  const count = phase.count
  const index = Math.min(Math.max(phase.index, 1), Math.max(count, 1))
  return (
    <div className="wf-phase">
      <div key={key} className="wf-phase__label">
        {phase.label}
      </div>
      <div className="wf-phase__row">
        <PhaseBar key={key} duration={phase.duration} startedAt={phase.startedAt} />
        {count > 0 ? (
          <span className="wf-phase__count">
            {phaseWord}
            <span key={key} className="wf-phase__num mono">
              {index}
            </span>
            <span className="mono dim">/ {count}</span>
          </span>
        ) : null}
      </div>
    </div>
  )
}

function StepRow({ step, ready, t }: { step: WorkflowStep; ready: boolean; t: TFunction }) {
  const phase = step.status === 'active' ? step.phase : undefined
  // keep the last phase rendered while the block collapses (step finished / phase cleared), drop it afterwards
  const [lastPhase, setLastPhase] = useState<WorkflowPhase | undefined>(phase)
  useEffect(() => {
    if (phase) {
      setLastPhase(phase)
      return
    }
    const timer = window.setTimeout(() => setLastPhase(undefined), SETTLE_MS)
    return () => window.clearTimeout(timer)
  }, [phase])
  const shown = phase ?? lastPhase

  return (
    <li className={`wf-step wf-step--${step.status}${ready ? ' is-ready' : ''}`}>
      {/* keyed by status (+ parts ready) -> the icon pops in on every status change */}
      <span key={`${step.status}:${ready}`} className="wf-step__icon">
        <StepIcon status={step.status} />
      </span>
      <div className="grow">
        <div className="wf-step__label">{step.label}</div>
        {step.message && step.status !== 'done' ? <div className="wf-step__msg">{step.message}</div> : null}
      </div>
      <span className="wf-step__status">{statusText(t, step.status, ready)}</span>
      {/* full-width row under label + status (the li wraps), aligned with the label */}
      <div className={`wf-step__detail${phase ? ' is-open' : ''}`}>
        {shown ? <PhaseInfo stepId={step.id} phase={shown} phaseWord={t('ui_wf_phase', 'Phase')} /> : null}
      </div>
    </li>
  )
}

/* ------------------------------------------------------------------ waiting for parts (mechanic-fetch-spec.md §6) */

/** m:ss (h:mm:ss from an hour up). */
function clock(seconds: number): string {
  const s = Math.max(0, Math.ceil(seconds))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = String(s % 60).padStart(2, '0')
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`
}

/** Ticks `remaining` down locally. Every Lua update restamps `receivedAt` -> the countdown resets to the sent value. */
function Countdown({ remaining, receivedAt }: { remaining: number; receivedAt?: number }) {
  const [mountedAt] = useState(() => performance.now())
  const [now, setNow] = useState(() => performance.now())
  const base = receivedAt ?? mountedAt

  useEffect(() => {
    setNow(performance.now())
    const timer = window.setInterval(() => setNow(performance.now()), 500)
    return () => window.clearInterval(timer)
  }, [remaining, base])

  const left = Math.max(0, Math.ceil(remaining - Math.max(0, now - base) / 1000))
  return (
    <span className={`wf-wait__timer${left <= LOW_SECONDS ? ' is-low' : ''}`}>
      <IconClock size="0.85rem" />
      <span className="mono">{clock(left)}</span>
    </span>
  )
}

/** Per-piece weight, "each" when more than one piece is needed. */
function weightText(t: TFunction, fmt: Formatters, item: WorkflowWaitingItem): string | null {
  const w = item.weight
  if (!w || !(w > 0)) return null
  const tenths = w * 10
  const decimals = Number.isInteger(w) || w >= 10 ? 0 : Math.abs(tenths - Math.round(tenths)) < 1e-6 ? 1 : 2
  const value = fmt.number(w, decimals)
  return item.need > 1 ? t('ui_wf_wait_weight_each', '%s kg each', value) : t('ui_wf_wait_weight', '%s kg', value)
}

/** Workshop storage count: nothing when unknown, red when empty, amber when it cannot cover the rest. */
function StockInfo({ item, t }: { item: WorkflowWaitingItem; t: TFunction }) {
  if (item.stock === null || item.stock === undefined) return null
  if (item.stock <= 0) {
    return <span className="wf-wait__stock is-empty">{t('ui_wf_wait_no_stock', 'Not in storage')}</span>
  }
  const low = item.stock < item.need - item.have
  return (
    <span className={`wf-wait__stock${low ? ' is-low' : ''}`}>
      <IconBuildingWarehouse size="0.75rem" />
      {t('ui_wf_wait_stock', 'In storage: %s', item.stock)}
    </span>
  )
}

function WaitingItemRow({ item, index, t, fmt }: { item: WorkflowWaitingItem; index: number; t: TFunction; fmt: Formatters }) {
  const ok = item.have >= item.need
  // carried already -> weight / storage do not matter any more, the row collapses to one line
  const weight = ok ? null : weightText(t, fmt, item)
  const stock = ok || item.stock === null || item.stock === undefined ? null : <StockInfo item={item} t={t} />

  return (
    <li
      className={`wf-wait__item${ok ? ' is-ok' : ''}${item.tool ? ' is-tool' : ''}`}
      style={{ animationDelay: `${Math.min(index, 8) * 45}ms` }}
    >
      {/* keyed -> the mark pops when the item gets complete */}
      <span key={String(ok)} className="wf-wait__mark">
        {ok ? <IconCheck size="0.9rem" stroke={2.6} /> : item.tool ? <IconTool size="0.9rem" /> : <IconPackage size="0.9rem" />}
      </span>
      <div className="grow">
        <div className="wf-wait__name">
          <span className="wf-wait__label">{item.label}</span>
          {item.tool ? <span className="wf-wait__tag">{t('ui_wf_wait_tool', 'Tool')}</span> : null}
        </div>
        {weight || stock ? (
          <div className="wf-wait__meta">
            {weight ? (
              <span className="wf-wait__weight">
                <IconWeight size="0.75rem" />
                {weight}
              </span>
            ) : null}
            {stock}
          </div>
        ) : null}
      </div>
      <span className="wf-wait__qty mono">
        <b key={item.have}>{Math.min(item.have, item.need)}</b>
        <span className="dim">/{item.need}</span>
      </span>
    </li>
  )
}

function WaitingPanel({ waiting, t, fmt }: { waiting: WorkflowWaiting; t: TFunction; fmt: Formatters }) {
  const ready = waiting.ready
  const hint =
    waiting.hint ||
    (ready
      ? t('ui_wf_wait_hint_ready', 'Everything ready – continue via the target on the vehicle.')
      : t('ui_wf_wait_hint_fetch', 'Take the parts from the workshop storage.'))

  return (
    <div className={`wf-wait${ready ? ' is-ready' : ''}`}>
      <div className="wf-wait__head">
        <span key={String(ready)} className="wf-wait__icon">
          {ready ? <IconCircleCheck size="1.1rem" /> : <IconHourglassHigh size="1.1rem" />}
        </span>
        <div className="grow">
          <div className="wf-wait__title">
            {ready ? t('ui_wf_wait_ready_title', 'Parts ready') : t('ui_wf_wait_title', 'Waiting for parts')}
          </div>
          {waiting.label ? <div className="wf-wait__step">{waiting.label}</div> : null}
        </div>
        {waiting.remaining !== undefined ? <Countdown remaining={waiting.remaining} receivedAt={waiting.receivedAt} /> : null}
      </div>

      {waiting.items.length ? (
        <ul className="wf-wait__items">
          {waiting.items.map((item, i) => (
            <WaitingItemRow key={item.key || i} item={item} index={i} t={t} fmt={fmt} />
          ))}
        </ul>
      ) : null}

      {/* keyed by ready -> the new hint fades in */}
      <div key={String(ready)} className="wf-wait__hint">
        {ready ? <IconHandFinger size="0.95rem" /> : <IconBuildingWarehouse size="0.95rem" />}
        <span>{hint}</span>
      </div>
    </div>
  )
}

/**
 * Holds the waiting panel: keeps the last payload while it collapses (step resumed / workflow cancelled) and animates
 * the height in / out. `height: auto` cannot be transitioned in CSS, so it is measured and run with Web Animations.
 */
function WaitingSlot({ waiting, t, fmt }: { waiting: WorkflowWaiting | null; t: TFunction; fmt: Formatters }) {
  const [last, setLast] = useState<WorkflowWaiting | null>(waiting)
  const ref = useRef<HTMLDivElement>(null)
  const anim = useRef<Animation | null>(null)
  const open = !!waiting

  useEffect(() => {
    if (waiting) setLast(waiting)
  }, [waiting])

  useLayoutEffect(() => {
    const el = ref.current
    if (!el || typeof el.animate !== 'function') {
      if (!open) setLast(null)
      return
    }
    anim.current?.cancel()
    const frames: Keyframe[] = [
      { height: '0px', opacity: 0 },
      { height: `${el.scrollHeight}px`, opacity: 1 },
    ]
    if (open) {
      anim.current = el.animate(frames, { duration: 320, easing: EASE })
      return
    }
    const leave = el.animate(frames.reverse(), { duration: 260, easing: EASE, fill: 'forwards' })
    leave.onfinish = () => setLast(null)
    anim.current = leave
  }, [open])

  useEffect(() => () => anim.current?.cancel(), [])

  const shown = waiting ?? last
  if (!shown) return null
  return (
    <div ref={ref} className="wf-wait-slot">
      <div className="wf-wait-slot__pad">
        <WaitingPanel waiting={shown} t={t} fmt={fmt} />
      </div>
    </div>
  )
}

/** Repair workflow / tuning installation overlay – no NUI focus, pointer events disabled. */
export default function Workflow({ data }: { data: WorkflowData }) {
  const { t, fmt } = useUi()
  const steps = asArray<WorkflowStep>(data.steps)
  const waiting = data.waiting ?? null
  const listRef = useRef<HTMLOListElement>(null)
  const mounted = useRef(false)

  const tuning = data.mode === 'tuning'
  const texts = modeTexts(t, tuning)

  let done = 0
  let failed = 0
  let skipped = 0
  for (const s of steps) {
    if (s.status === 'done') done++
    else if (s.status === 'failed') failed++
    else if (s.status === 'skipped') skipped++
  }
  const processed = done + failed + skipped
  // a step waiting for parts is the current one as well (kept centred above the waiting panel)
  const activeIndex = steps.findIndex((s) => s.status === 'active' || s.status === 'waiting')
  const currentIndex =
    activeIndex >= 0 ? activeIndex : data.current !== null && data.current !== undefined ? steps.findIndex((s) => s.id === data.current) : -1
  const hasPhase = currentIndex >= 0 && !!steps[currentIndex]?.phase
  const finished = steps.length > 0 && processed === steps.length
  const pct = steps.length ? (processed / steps.length) * 100 : 0
  const waitingOpen = !!waiting

  const [overflow, setOverflow] = useState({ top: false, bottom: false })

  // Keep the current step centred (smooth), fade the edges when the list is longer than the card.
  // Steps expand / collapse with a transition (and the list shrinks while the waiting panel is open),
  // so the position is settled once more when it is over.
  useEffect(() => {
    const list = listRef.current
    if (!list) return
    const sync = (smooth: boolean) => {
      const max = Math.max(0, list.scrollHeight - list.clientHeight)
      let top = list.scrollTop
      const el = currentIndex >= 0 ? (list.children[currentIndex] as HTMLElement | undefined) : undefined
      if (el) {
        top = Math.max(0, Math.min(el.offsetTop - list.clientHeight / 2 + el.offsetHeight / 2, max))
        if (Math.abs(top - list.scrollTop) > 1) {
          if (smooth) list.scrollTo({ top, behavior: 'smooth' })
          else list.scrollTop = top
        }
      }
      const next = { top: top > 2, bottom: top < max - 2 }
      setOverflow((prev) => (prev.top === next.top && prev.bottom === next.bottom ? prev : next))
    }
    sync(mounted.current)
    mounted.current = true
    const timer = window.setTimeout(() => sync(true), SETTLE_MS)
    return () => window.clearTimeout(timer)
  }, [currentIndex, steps.length, hasPhase, waitingOpen])

  const HeadIcon = finished ? (failed ? IconAlertTriangle : IconCircleCheck) : tuning ? IconSparkles : IconTool
  const state = finished ? (failed ? ' is-errors' : ' is-finished') : ''
  const hint = data.cancelHint ? ' has-hint' : ''
  // is-waiting shrinks the step list, is-fetching tints the head amber until the parts are carried
  const wait = waiting && !finished ? ` is-waiting${waiting.ready ? '' : ' is-fetching'}` : ''

  return (
    <div className={`wf wf--${tuning ? 'tuning' : 'repair'}${state}${wait}`}>
      <div className="wf__head">
        <div className="wf__icon">
          <HeadIcon key={`${finished}:${failed > 0}`} size="1.35rem" />
        </div>
        <div className="grow">
          <div className="wf__title">{finished ? (failed ? texts.finishedErrors : texts.finished) : texts.title}</div>
          <div className="row" style={{ marginTop: '0.3rem' }}>
            <Plate plate={data.plate} small />
          </div>
        </div>
        <div className="wf__count">
          <span className="mono">{processed}</span>
          <span className="dim mono">/{steps.length}</span>
        </div>
      </div>

      <div className="wf__bar">
        <div className={`wf__bar-fill${failed ? ' has-errors' : ''}`} style={{ width: `${pct}%` }} />
      </div>

      <ol
        className={`wf__steps${overflow.top ? ' fade-top' : ''}${overflow.bottom ? ' fade-bottom' : ''}`}
        ref={listRef}
      >
        {steps.map((step) => (
          <StepRow key={step.id} step={step} ready={step.status === 'waiting' && !!waiting?.ready} t={t} />
        ))}
      </ol>

      <WaitingSlot waiting={waiting} t={t} fmt={fmt} />

      {finished ? (
        <div className={`wf__foot wf__foot--summary${hint}`}>
          <span className="wf-sum wf-sum--done">
            <IconCircleCheck size="0.95rem" />
            {statusText(t, 'done')}
            <b className="mono">{done}</b>
          </span>
          {failed ? (
            <span className="wf-sum wf-sum--failed">
              <IconCircleX size="0.95rem" />
              {statusText(t, 'failed')}
              <b className="mono">{failed}</b>
            </span>
          ) : null}
          {skipped ? (
            <span className="wf-sum wf-sum--skipped">
              <IconPlayerSkipForward size="0.9rem" />
              {statusText(t, 'skipped')}
              <b className="mono">{skipped}</b>
            </span>
          ) : null}
        </div>
      ) : data.cancelKey || data.cancelHint ? (
        <div className={`wf__foot${hint}`}>
          {data.cancelKey ? <span className="kbd">{data.cancelKey}</span> : null}
          <div className="wf__foot-text">
            <span>{texts.cancel}</span>
            {data.cancelHint ? <span className="wf__hint">{data.cancelHint}</span> : null}
          </div>
        </div>
      ) : null}
    </div>
  )
}
