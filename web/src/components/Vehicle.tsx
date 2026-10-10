import type { ReactNode } from 'react'
import type { PartState } from '../types'
import { clamp, stateFromPercent, stateLabel } from '../lib/states'
import { useUi } from '../lib/ui'

export function Plate({ plate, small = false }: { plate: string; small?: boolean }) {
  return <span className={`plate${small ? ' plate--sm' : ''}`}>{(plate || '').toUpperCase() || '—'}</span>
}

export function StateLabel({ state }: { state: PartState }) {
  const { t } = useUi()
  return <span className={`state t-${state}`}>{stateLabel(t, state)}</span>
}

/** Horizontal life / health bar with ticks at the state thresholds. */
export function StateBar({ value, state }: { value: number; state?: PartState }) {
  const pct = clamp(Number(value) || 0, 0, 100)
  const s = state || stateFromPercent(pct)
  return (
    <div className={`hbar t-${s}`}>
      <div className="hbar__fill" style={{ width: `${pct}%` }} />
      <span className="hbar__tick" style={{ left: '15%' }} />
      <span className="hbar__tick" style={{ left: '40%' }} />
      <span className="hbar__tick" style={{ left: '70%' }} />
    </div>
  )
}

/** Semi-circular gauge for native health values (0..1000). */
export function Gauge({ value, max = 1000, label, icon }: { value: number; max?: number; label: string; icon: ReactNode }) {
  const { fmt } = useUi()
  const pct = clamp(((Number(value) || 0) / max) * 100, 0, 100)
  const state = stateFromPercent(pct)
  // Arc length of r=40 half circle = PI * 40
  const length = Math.PI * 40
  return (
    <div className={`gauge t-${state}`}>
      <svg viewBox="0 0 100 58" className="gauge__svg">
        <path d="M10 52 A40 40 0 0 1 90 52" className="gauge__track" />
        <path
          d="M10 52 A40 40 0 0 1 90 52"
          className="gauge__value"
          style={{ strokeDasharray: `${length}`, strokeDashoffset: `${length * (1 - pct / 100)}` }}
        />
      </svg>
      <div className="gauge__center">
        <span className="gauge__icon">{icon}</span>
        <span className="gauge__num mono">{fmt.number(pct)}%</span>
      </div>
      <div className="gauge__label">{label}</div>
    </div>
  )
}
