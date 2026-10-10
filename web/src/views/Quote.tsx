import { useEffect, useRef, useState } from 'react'
import { IconCheck, IconLoader2, IconSparkles, IconX } from '@tabler/icons-react'
import type { QuoteData, QuoteItem, ViewProps } from '../types'
import { asArray, asResult, fetchNui } from '../lib/nui'
import { useToast } from '../lib/toast'
import { useUi } from '../lib/ui'
import './quote.css'

const clock = (seconds: number) => `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`

/** Customer approval of tuning outside their order – accept / decline before the timeout (ESC = decline). */
export default function Quote({ data, onClose }: ViewProps<QuoteData>) {
  const { t, fmt } = useUi()
  const push = useToast()
  const [busy, setBusy] = useState<'accept' | 'decline' | null>(null)

  const items = asArray<QuoteItem>(data.items)
  const extraTotal = Math.round(
    Number(data.extraTotal) || items.reduce((sum, i) => sum + (i.ordered ? 0 : Number(i.price) || 0), 0),
  )
  const total = Math.round(Number(data.total) || items.reduce((sum, i) => sum + (Number(i.price) || 0), 0))

  /* ---------------- countdown (the client resolves the quote as expired at the same time) */

  const timeout = Math.max(0, Number(data.timeout) || 0)
  const [startedAt] = useState(() => Date.now())
  const [now, setNow] = useState(startedAt)
  const left = timeout ? Math.max(0, timeout - (now - startedAt) / 1000) : 0
  const expired = timeout > 0 && left <= 0

  useEffect(() => {
    if (!timeout) return
    const id = window.setInterval(() => setNow(Date.now()), 250)
    return () => window.clearInterval(id)
  }, [timeout])

  /* ---------------- answer */

  // The client closes the view after the answer / timeout – fallback that releases the focus when it did not
  const mounted = useRef(true)
  const fallback = useRef<number>()
  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
      window.clearTimeout(fallback.current)
    }
  }, [])
  const closeLater = (ms: number) => {
    window.clearTimeout(fallback.current)
    fallback.current = window.setTimeout(() => mounted.current && onClose(), ms)
  }

  useEffect(() => {
    if (expired && !busy) closeLater(3000)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expired])

  const answer = async (accept: boolean) => {
    if (busy || expired) return
    setBusy(accept ? 'accept' : 'decline')
    const raw = await fetchNui(accept ? 'quote:accept' : 'quote:decline')
    if (!mounted.current) return
    const res = asResult(raw)
    if (raw !== null && !res.ok && res.message) push('error', res.message)
    closeLater(1500)
  }

  // ESC = decline (App leaves ESC of this view to it), after the timeout it just closes
  const keyState = useRef({ answer, expired, onClose })
  keyState.current = { answer, expired, onClose }
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      event.preventDefault()
      const s = keyState.current
      if (s.expired) s.onClose()
      else s.answer(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const seconds = Math.ceil(left)

  return (
    <div className="layer backdrop">
      <div className="qt">
        <div className="qt-paper">
          <div className="qt-head">
            <div className="qt-logo">
              <IconSparkles size="1.6rem" />
            </div>
            <div className="grow">
              <div className="qt-shop">{data.shop}</div>
              <div className="qt-sub">{t('ui_quote_sub', 'Tuning quote')}</div>
            </div>
            {timeout ? (
              <div className={`qt-timer${expired ? ' is-expired' : seconds <= 10 ? ' is-low' : ''}`}>
                <span>{expired ? t('ui_quote_expired', 'Expired') : t('ui_quote_expires', 'Expires in')}</span>
                <strong className="mono">{clock(seconds)}</strong>
              </div>
            ) : null}
          </div>
          {timeout ? (
            <div className="qt-bar">
              <div className="qt-bar__fill" style={{ width: `${(left / timeout) * 100}%` }} />
            </div>
          ) : null}

          <div className="qt-meta">
            <div>
              <span>{t('ui_bill_mechanic', 'Mechanic')}</span>
              <strong>{data.mechanic || '—'}</strong>
            </div>
            {data.plate ? (
              <div>
                <span>{t('ui_bill_plate', 'Plate')}</span>
                <strong className="mono">{data.plate.toUpperCase()}</strong>
              </div>
            ) : null}
          </div>

          <p className="qt-text">
            {t('ui_quote_text', 'The mechanic wants to install more than you ordered. Accept to allow the extra work, decline to keep only your order.')}
          </p>

          <table className="qt-lines">
            <thead>
              <tr>
                <th>{t('ui_bill_col_label', 'Description')}</th>
                <th />
                <th className="num">{t('ui_quote_col_price', 'Price')}</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item, index) => (
                <tr key={index} className={item.ordered ? undefined : 'is-extra'}>
                  <td>
                    <div className="qt-item">{item.label}</div>
                    <div className="qt-value">{String(item.value ?? '')}</div>
                  </td>
                  <td className="qt-lines__tag">
                    <span className={`qt-tag${item.ordered ? '' : ' qt-tag--extra'}`}>
                      {item.ordered ? t('ui_catalog_tag_ordered', 'Ordered') : t('ui_quote_tag_extra', 'Extra')}
                    </span>
                  </td>
                  <td className="num">{fmt.money(Number(item.price) || 0)}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <div className="qt-extra">
            <span>{t('ui_quote_extra_total', 'Extra work')}</span>
            <strong className="mono">{fmt.money(extraTotal)}</strong>
          </div>
          <div className="qt-total">
            <span>{t('ui_bill_total', 'Total')}</span>
            <strong className="mono">{fmt.money(total)}</strong>
          </div>

          <div className="qt-foot">{t('ui_quote_foot', 'The mechanic bills you after the installation.')}</div>
        </div>

        <div className="qt-actions">
          <button
            type="button"
            className="btn btn--success btn--lg"
            disabled={!!busy || expired}
            onClick={() => answer(true)}
          >
            {busy === 'accept' ? <IconLoader2 size="1.2rem" className="spin" /> : <IconCheck size="1.2rem" />}
            {t('ui_quote_accept', 'Accept')}
          </button>
          <button
            type="button"
            className="btn btn--danger btn--lg"
            disabled={!!busy || expired}
            onClick={() => answer(false)}
          >
            {busy === 'decline' ? <IconLoader2 size="1.1rem" className="spin" /> : <IconX size="1.1rem" />}
            {t('ui_bill_decline', 'Decline')}
            <span className="kbd">ESC</span>
          </button>
        </div>
      </div>
    </div>
  )
}
