import type { ReactNode } from 'react'
import { IconChevronLeft, IconChevronRight, IconMinus, IconPlus } from '@tabler/icons-react'

/* ----------------------------------------------------------------- tabs */

export interface TabItem<K extends string> {
  key: K
  label: string
  icon?: ReactNode
  count?: number
  tone?: 'worn' | 'critical' | 'failed' | 'accent'
}

export function Tabs<K extends string>({
  items,
  active,
  onChange,
  right,
}: {
  items: TabItem<K>[]
  active: K
  onChange: (key: K) => void
  right?: ReactNode
}) {
  return (
    <nav className="tabs">
      {items.map((tab) => (
        <button
          key={tab.key}
          type="button"
          className={`tab${tab.key === active ? ' is-active' : ''}`}
          onClick={() => onChange(tab.key)}
        >
          {tab.icon}
          <span>{tab.label}</span>
          {tab.count !== undefined && tab.count > 0 ? (
            <span className={`count${tab.tone ? ` count--${tab.tone}` : ''}`}>{tab.count}</span>
          ) : null}
        </button>
      ))}
      {right ? <div className="tabs__right">{right}</div> : null}
    </nav>
  )
}

/* ----------------------------------------------------------------- pager */

export function Pager({ page, pages, onChange }: { page: number; pages: number; onChange: (page: number) => void }) {
  if (pages <= 1) return null
  const from = Math.max(1, Math.min(page - 2, pages - 4))
  const to = Math.min(pages, from + 4)
  const numbers: number[] = []
  for (let i = from; i <= to; i++) numbers.push(i)
  return (
    <div className="pager">
      <button type="button" className="pager__btn" disabled={page <= 1} onClick={() => onChange(page - 1)}>
        <IconChevronLeft size="1rem" />
      </button>
      {numbers.map((n) => (
        <button
          key={n}
          type="button"
          className={`pager__btn${n === page ? ' is-active' : ''}`}
          onClick={() => onChange(n)}
        >
          {n}
        </button>
      ))}
      <button type="button" className="pager__btn" disabled={page >= pages} onClick={() => onChange(page + 1)}>
        <IconChevronRight size="1rem" />
      </button>
    </div>
  )
}

/* ----------------------------------------------------------------- stepper */

export function Stepper({
  value,
  min = 0,
  max = 9999,
  onChange,
}: {
  value: number
  min?: number
  max?: number
  onChange: (value: number) => void
}) {
  const clamp = (n: number) => Math.max(min, Math.min(max, Math.floor(n)))
  return (
    <div className="stepper">
      <button type="button" disabled={value <= min} onClick={() => onChange(clamp(value - 1))}>
        <IconMinus size="0.85rem" stroke={2.2} />
      </button>
      <input
        value={value}
        inputMode="numeric"
        onChange={(e) => {
          const n = parseInt(e.target.value.replace(/\D/g, ''), 10)
          onChange(clamp(Number.isFinite(n) ? n : min))
        }}
      />
      <button type="button" disabled={value >= max} onClick={() => onChange(clamp(value + 1))}>
        <IconPlus size="0.85rem" stroke={2.2} />
      </button>
    </div>
  )
}

/* ----------------------------------------------------------------- empty */

export function Empty({ icon, text, children }: { icon: ReactNode; text: string; children?: ReactNode }) {
  return (
    <div className="empty">
      <div className="empty__icon">{icon}</div>
      <div className="empty__text">{text}</div>
      {children}
    </div>
  )
}
