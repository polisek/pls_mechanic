// Normalizes / merges the "workflow" overlay data (mechanic-anim-spec.md §2, mechanic-fetch-spec.md §6).
import type {
  StepStatus,
  WorkflowData,
  WorkflowMode,
  WorkflowPhase,
  WorkflowStep,
  WorkflowWaiting,
  WorkflowWaitingItem,
} from '../types'
import { asArray } from './nui'

const STATUSES: StepStatus[] = ['pending', 'active', 'waiting', 'done', 'failed', 'skipped']
const MODES: WorkflowMode[] = ['repair', 'tuning']

const isObject = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === 'object' && !Array.isArray(value)

const num = (value: unknown, fallback = 0): number => {
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

const str = (value: unknown): string => (value === null || value === undefined ? '' : String(value))

/** Identity of a running phase – a new key restarts the progress bar. */
export const phaseKey = (stepId: number, phase: WorkflowPhase): string => `${stepId}:${phase.index}:${phase.label}`

function readPhase(raw: unknown): WorkflowPhase | undefined {
  // an empty Lua table arrives as [] -> no phase
  if (!isObject(raw)) return undefined
  return {
    label: str(raw.label),
    index: Math.floor(num(raw.index)),
    count: Math.max(0, Math.floor(num(raw.count))),
    duration: Math.max(0, num(raw.duration)),
  }
}

function readStep(raw: unknown, i: number): WorkflowStep | null {
  if (!isObject(raw)) return null
  const status = STATUSES.includes(raw.status as StepStatus) ? (raw.status as StepStatus) : 'pending'
  const step: WorkflowStep = {
    id: num(raw.id, i + 1),
    kind: str(raw.kind),
    key: str(raw.key),
    label: str(raw.label),
    status,
  }
  if (typeof raw.message === 'string' && raw.message !== '') step.message = raw.message
  // phase belongs to the active step only
  const phase = status === 'active' ? readPhase(raw.phase) : undefined
  if (phase) step.phase = phase
  return step
}

function readWaitingItem(raw: unknown): WorkflowWaitingItem | null {
  if (!isObject(raw)) return null
  const key = str(raw.key ?? raw.item)
  const item: WorkflowWaitingItem = {
    key,
    label: str(raw.label) || key,
    need: Math.max(0, Math.floor(num(raw.need))),
    have: Math.max(0, Math.floor(num(raw.have))),
  }
  // stock: nil = unknown (storage not supported) -> no storage line at all
  const stock = raw.stock === null || raw.stock === undefined ? NaN : num(raw.stock, NaN)
  if (!Number.isNaN(stock)) item.stock = Math.max(0, Math.floor(stock))
  if (raw.tool === true) item.tool = true
  const weight = num(raw.weight, NaN)
  if (weight > 0) item.weight = weight
  return item
}

/** Missing / null / empty Lua table ([]) = not waiting. `remaining` is stamped with its arrival time for the local countdown. */
function readWaiting(raw: unknown, now: number): WorkflowWaiting | null {
  if (!isObject(raw)) return null
  const items: WorkflowWaitingItem[] = []
  for (const entry of asArray(raw.items)) {
    const item = readWaitingItem(entry)
    if (item) items.push(item)
  }
  const waiting: WorkflowWaiting = {
    label: str(raw.label),
    items,
    ready: raw.ready === true,
    hint: str(raw.hint),
  }
  const remaining = num(raw.remaining, NaN)
  if (!Number.isNaN(remaining)) {
    waiting.remaining = Math.max(0, remaining)
    waiting.receivedAt = now
  }
  return waiting
}

/**
 * open: `prev = null`. update: Lua sends the full state every time, so `steps` (with their `phase`) are replaced
 * and a missing `current` / `phase` / `waiting` means none – a stale "waiting for parts" panel is never kept.
 * `mode` and `cancelHint` stay from open unless sent again.
 * A phase keeps its arrival time while its key (step id + index + label) is unchanged, a new phase is stamped `now`.
 */
export function mergeWorkflow(prev: WorkflowData | null, data: Record<string, unknown>, now: number): WorkflowData {
  const started = new Map<string, number>()
  for (const step of prev?.steps ?? []) {
    if (step.phase?.startedAt !== undefined) started.set(phaseKey(step.id, step.phase), step.phase.startedAt)
  }

  const rawSteps: unknown[] = 'steps' in data ? asArray(data.steps) : prev?.steps ?? []
  const steps: WorkflowStep[] = []
  rawSteps.forEach((raw, i) => {
    const step = readStep(raw, i)
    if (!step) return
    if (step.phase) step.phase.startedAt = started.get(phaseKey(step.id, step.phase)) ?? now
    steps.push(step)
  })

  const mode = MODES.includes(data.mode as WorkflowMode) ? (data.mode as WorkflowMode) : prev?.mode ?? 'repair'
  const cancelHint = typeof data.cancelHint === 'string' ? data.cancelHint : prev?.cancelHint
  const current = data.current === null || data.current === undefined ? null : num(data.current, NaN)

  return {
    mode,
    plate: 'plate' in data ? str(data.plate) : prev?.plate ?? '',
    cancelKey: 'cancelKey' in data ? str(data.cancelKey) : prev?.cancelKey ?? '',
    cancelHint: cancelHint || undefined,
    current: Number.isNaN(current) ? null : current,
    steps,
    waiting: readWaiting(data.waiting, now),
  }
}
