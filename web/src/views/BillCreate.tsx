import { useMemo, useState } from 'react'
import { NumberInput, TextInput, Textarea } from '@mantine/core'
import {
  IconCircleCheck,
  IconCoins,
  IconFileInvoice,
  IconPlus,
  IconSearch,
  IconSend,
  IconTrash,
  IconUserCircle,
  IconUsers,
} from '@tabler/icons-react'
import type { BillCreateData, BillLine, ViewProps } from '../types'
import { Window } from '../components/Window'
import { Empty, Stepper } from '../components/Controls'
import { Plate } from '../components/Vehicle'
import { asArray } from '../lib/nui'
import { useNuiAction } from '../lib/useNuiAction'
import { useUi } from '../lib/ui'
import './billing.css'

interface EditLine extends BillLine {
  uid: number
}

// Server rules (server/billing.lua): label is cut to 60 characters, qty 1–99, whole prices
const LABEL_MAX = 60
const QTY_MAX = 99
// Fallbacks when the client doesn't send Config.Billing limits (note = default maxNoteLength)
const NOTE_MAX = 200
const PRICE_MAX = 10000000

let uidCounter = 1
const toEdit = (line: BillLine): EditLine => ({
  uid: uidCounter++,
  label: String(line.label ?? ''),
  qty: Math.min(QTY_MAX, Math.max(1, Math.floor(Number(line.qty) || 1))),
  price: Math.max(0, Math.round(Number(line.price) || 0)),
})

const initials = (name: string) =>
  (name || '?')
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]!.toUpperCase())
    .join('')

export default function BillCreate({ data, onClose }: ViewProps<BillCreateData>) {
  const { t, fmt, config } = useUi()
  const action = useNuiAction()
  const maxLines = Math.max(1, data.maxLines || 20)
  const noteMax = Math.max(1, Number(data.maxNoteLength) || NOTE_MAX)
  const priceMax = Math.max(1, Number(data.maxLinePrice) || PRICE_MAX)
  const maxTotal = Number(data.maxTotal) || 0
  const customers = useMemo(() => asArray<BillCreateData['customers'][number]>(data.customers), [data.customers])

  const [target, setTarget] = useState<number | null>(customers.length === 1 ? customers[0]!.serverId : null)
  const [search, setSearch] = useState('')
  const [lines, setLines] = useState<EditLine[]>(() => {
    const initial = asArray<BillLine>(data.lines).slice(0, maxLines).map(toEdit)
    return initial.length ? initial : [toEdit({ label: '', qty: 1, price: 0 })]
  })
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const thousandSeparator = useMemo(() => fmt.number(1000000).replace(/\d/g, '').charAt(0) || ',', [fmt])
  const [sentTo, setSentTo] = useState<string | null>(null)

  const filteredCustomers = useMemo(() => {
    const needle = search.trim().toLowerCase()
    if (!needle) return customers
    return customers.filter((c) => c.name.toLowerCase().indexOf(needle) !== -1 || String(c.serverId).indexOf(needle) !== -1)
  }, [customers, search])

  const isBlank = (line: EditLine) => !line.label.trim() && line.price === 0
  const isInvalid = (line: EditLine) =>
    !isBlank(line) && (!line.label.trim() || line.qty < 1 || line.qty > QTY_MAX || line.price > priceMax)
  const validLines = lines.filter((l) => !isBlank(l) && !isInvalid(l))
  const hasInvalid = lines.some(isInvalid)
  const total = validLines.reduce((sum, l) => sum + l.qty * l.price, 0)
  const commissionPct = Number(data.commission) || 0
  const commissionAmount = Math.floor((total * commissionPct) / 100)

  const update = (uid: number, patch: Partial<BillLine>) =>
    setLines((prev) => prev.map((l) => (l.uid === uid ? { ...l, ...patch } : l)))
  const remove = (uid: number) =>
    setLines((prev) => {
      const next = prev.filter((l) => l.uid !== uid)
      return next.length ? next : [toEdit({ label: '', qty: 1, price: 0 })]
    })
  const add = () =>
    setLines((prev) => (prev.length >= maxLines ? prev : [...prev, toEdit({ label: '', qty: 1, price: 0 })]))

  const overTotal = maxTotal > 0 && total > maxTotal
  const canSend = target !== null && validLines.length > 0 && !hasInvalid && !overTotal && total > 0 && !busy
  const targetName = customers.find((c) => c.serverId === target)?.name ?? ''

  const send = async () => {
    if (!canSend || target === null) return
    setBusy(true)
    const res = await action('billCreate:send', {
      target,
      plate: data.plate,
      lines: validLines.map((l) => ({ label: l.label.trim(), qty: l.qty, price: l.price })),
      note: note.trim(),
    }, { notified: 'success' })
    setBusy(false)
    if (res.ok) setSentTo(targetName || `#${target}`)
  }

  const footer = sentTo ? null : (
    <>
      <span className="grow muted bc-foot-hint">{t('ui_bill_confirm_hint', 'The customer has to confirm the bill before paying.')}</span>
      <button type="button" className="btn btn--ghost" onClick={onClose}>
        {t('ui_cancel', 'Cancel')}
      </button>
      <button type="button" className="btn btn--primary btn--lg" disabled={!canSend} onClick={send}>
        <IconSend size="1.1rem" />
        {t('ui_bill_send', 'Send bill')}
      </button>
    </>
  )

  return (
    <Window
      className="bc"
      icon={<IconFileInvoice size="1.5rem" />}
      title={t('ui_bill_create_title', 'New bill')}
      subtitle={data.shopName}
      onClose={onClose}
      footer={footer}
      headerRight={data.plate ? <Plate plate={data.plate} /> : null}
    >
      {sentTo ? (
        <div className="bc-sent">
          <div className="bc-sent__icon">
            <IconCircleCheck size="3rem" stroke={1.4} />
          </div>
          <div className="bc-sent__title">{t('ui_bill_sent', 'Bill sent')}</div>
          <div className="muted">{t('ui_bill_sent_to', 'Waiting for %s to confirm the payment.', sentTo)}</div>
          <div className="bc-sent__total mono">{fmt.money(total)}</div>
          <button type="button" className="btn" onClick={onClose}>
            {t('ui_close', 'Close')}
          </button>
        </div>
      ) : (
        <div className="bc-body">
          <aside className="bc-side">
            <div className="section-label">{t('ui_bill_customer', 'Customer')}</div>
            {customers.length > 4 ? (
              <TextInput
                className="inp"
                size="sm"
                value={search}
                onChange={(e) => setSearch(e.currentTarget.value)}
                placeholder={t('ui_search', 'Search…')}
                leftSection={<IconSearch size="1rem" />}
              />
            ) : null}
            {customers.length ? (
              <div className="bc-customers scroll">
                {filteredCustomers.map((c) => (
                  <button
                    key={c.serverId}
                    type="button"
                    className={`bc-customer${target === c.serverId ? ' is-active' : ''}`}
                    onClick={() => setTarget(c.serverId)}
                  >
                    <span className="bc-customer__avatar">{initials(c.name)}</span>
                    <span className="grow bc-customer__name">{c.name}</span>
                    <span className="chip mono">ID {c.serverId}</span>
                  </button>
                ))}
              </div>
            ) : (
              <Empty icon={<IconUsers size="1.5rem" />} text={t('ui_bill_no_customers', 'No players nearby.')} />
            )}

            <div className="bc-commission">
              <IconCoins size="1.3rem" />
              <div className="grow">
                <div className="section-label">{t('ui_bill_commission', 'Your commission')}</div>
                <div className="bc-commission__value">
                  <span className="mono">{fmt.money(commissionAmount)}</span>
                  <span className="muted">({fmt.percent(commissionPct)})</span>
                </div>
              </div>
            </div>
          </aside>

          <div className="bc-main">
            <div className="bc-lines-head">
              <span className="section-label">{t('ui_bill_items', 'Items')}</span>
              <span className="muted mono bc-lines-count">
                {lines.length}/{maxLines}
              </span>
            </div>

            <div className="bc-lines scroll">
              <div className="bc-line bc-line--head">
                <span>#</span>
                <span>{t('ui_bill_col_label', 'Description')}</span>
                <span>{t('ui_bill_col_qty', 'Qty')}</span>
                <span>{t('ui_bill_col_price', 'Unit price')}</span>
                <span className="num">{t('ui_bill_col_total', 'Total')}</span>
                <span />
              </div>
              {lines.map((line, index) => (
                <div key={line.uid} className={`bc-line${isInvalid(line) ? ' is-invalid' : ''}`}>
                  <span className="mono dim">{index + 1}</span>
                  <TextInput
                    className="inp"
                    size="sm"
                    value={line.label}
                    maxLength={LABEL_MAX}
                    placeholder={t('ui_bill_label_placeholder', 'e.g. Oil change')}
                    onChange={(e) => update(line.uid, { label: e.currentTarget.value })}
                  />
                  <Stepper value={line.qty} min={1} max={QTY_MAX} onChange={(qty) => update(line.uid, { qty })} />
                  <NumberInput
                    className="inp"
                    size="sm"
                    value={line.price}
                    min={0}
                    max={priceMax}
                    allowDecimal={false}
                    allowNegative={false}
                    clampBehavior="strict"
                    hideControls
                    thousandSeparator={thousandSeparator}
                    leftSection={<span className="bc-currency">{config.currency}</span>}
                    onChange={(value) => update(line.uid, { price: Math.max(0, Math.round(Number(value) || 0)) })}
                  />
                  <span className="num mono">{fmt.money(line.qty * line.price)}</span>
                  <button
                    type="button"
                    className="btn btn--icon btn--sm btn--ghost bc-remove"
                    onClick={() => remove(line.uid)}
                    title={t('ui_remove', 'Remove')}
                  >
                    <IconTrash size="1rem" />
                  </button>
                </div>
              ))}
              <button type="button" className="bc-add" disabled={lines.length >= maxLines} onClick={add}>
                <IconPlus size="1rem" />
                {lines.length >= maxLines
                  ? t('ui_bill_max_lines', 'Maximum of %s lines reached', maxLines)
                  : t('ui_bill_add_line', 'Add line')}
              </button>
            </div>

            <div className="bc-bottom">
              <div className="bc-note">
                <div className="row" style={{ justifyContent: 'space-between' }}>
                  <label className="field-label">{t('ui_bill_note', 'Note for the customer')}</label>
                  <span className="dim mono bc-note__count">
                    {note.length}/{noteMax}
                  </span>
                </div>
                <Textarea
                  className="inp"
                  value={note}
                  maxLength={noteMax}
                  autosize
                  minRows={3}
                  maxRows={3}
                  placeholder={t('ui_bill_note_placeholder', 'Optional – warranty, recommendations…')}
                  onChange={(e) => setNote(e.currentTarget.value)}
                />
              </div>
              <div className="bc-totals">
                <div className="bc-totals__row">
                  <span className="muted">{t('ui_bill_subtotal', 'Subtotal')}</span>
                  <span className="mono">{fmt.money(total)}</span>
                </div>
                <div className="bc-totals__row">
                  <span className="muted">{t('ui_bill_lines', 'Lines')}</span>
                  <span className="mono">{validLines.length}</span>
                </div>
                <div className="divider" />
                <div className="bc-totals__row bc-totals__row--total">
                  <span>{t('ui_bill_total', 'Total')}</span>
                  <span className={`mono${overTotal ? ' t-failed' : ''}`}>{fmt.money(total)}</span>
                </div>
                {overTotal ? (
                  <div className="bc-totals__to t-failed">{t('ui_bill_total_max', 'Maximum total is %s', fmt.money(maxTotal))}</div>
                ) : null}
                {target !== null ? (
                  <div className="bc-totals__to">
                    <IconUserCircle size="1rem" />
                    {targetName}
                  </div>
                ) : (
                  <div className="bc-totals__to t-worn">{t('ui_bill_pick_customer', 'Pick a customer')}</div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </Window>
  )
}
