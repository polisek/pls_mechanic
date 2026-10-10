import { useState } from 'react'
import { Tooltip } from '@mantine/core'
import { IconBuildingBank, IconCash, IconTool, IconX } from '@tabler/icons-react'
import type { BillData, BillLine, PayMethod, ViewProps } from '../types'
import { asArray, asRecord } from '../lib/nui'
import { useNuiAction } from '../lib/useNuiAction'
import { useUi } from '../lib/ui'
import './billing.css'

/** Customer invoice – paper style, pay by cash / bank or decline. */
export default function Bill({ data, onClose }: ViewProps<BillData>) {
  const { t, fmt } = useUi()
  const action = useNuiAction()
  const [busy, setBusy] = useState<PayMethod | 'decline' | null>(null)
  const [stamp, setStamp] = useState<'paid' | 'declined' | null>(null)

  const lines = asArray<BillLine>(data.lines)
  const total = Math.round(Number(data.total) || lines.reduce((sum, l) => sum + l.qty * l.price, 0))
  const methods = data.methods === undefined ? ['cash', 'bank'] : asArray<PayMethod>(data.methods)
  const balances = asRecord<number>(data.balances)

  const pay = async (method: PayMethod) => {
    if (busy || stamp) return
    setBusy(method)
    // client notifies + closes the bill on success
    const res = await action('bill:pay', { id: data.id, method }, { notified: 'success' })
    setBusy(null)
    if (res.ok) setStamp('paid')
  }

  const decline = async () => {
    if (busy || stamp) return
    setBusy('decline')
    const res = await action('bill:decline', { id: data.id }, { notified: 'success' })
    setBusy(null)
    if (res.ok) setStamp('declined')
  }

  const payButton = (method: PayMethod) => {
    const allowed = methods.indexOf(method) !== -1
    const balance = Number(balances[method]) || 0
    const enough = balance >= total
    const disabled = !allowed || !enough || !!busy || !!stamp
    const Icon = method === 'cash' ? IconCash : IconBuildingBank
    const reason = !allowed
      ? t('ui_bill_method_unavailable', 'This payment method is not available.')
      : !enough
        ? t('ui_bill_not_enough', 'Not enough money.')
        : ''
    return (
      <Tooltip label={reason} disabled={!reason}>
        <span className="bl-pay">
          <button type="button" className="btn btn--success btn--lg" disabled={disabled} onClick={() => pay(method)}>
            <Icon size="1.2rem" />
            {method === 'cash' ? t('ui_bill_pay_cash', 'Pay cash') : t('ui_bill_pay_bank', 'Pay from bank')}
          </button>
          <span className={`bl-pay__balance mono${enough ? '' : ' t-failed'}`}>
            {method === 'cash' ? t('ui_bill_wallet', 'Wallet') : t('ui_bill_account', 'Account')}: {fmt.money(balance)}
          </span>
        </span>
      </Tooltip>
    )
  }

  return (
    <div className="layer backdrop">
      <div className="bl">
        <button type="button" className="bl-close" onClick={onClose} title={t('ui_close', 'Close')}>
          <span className="kbd">ESC</span>
          <IconX size="1.1rem" />
        </button>

        <div className="bl-paper">
          <div className="bl-paper__head">
            <div className="bl-logo">
              <IconTool size="1.6rem" />
            </div>
            <div className="grow">
              <div className="bl-shop">{data.shopName}</div>
              <div className="bl-sub">{t('ui_bill_invoice_sub', 'Service & repair invoice')}</div>
            </div>
            <div className="bl-no">
              <span>{t('ui_bill_invoice', 'Invoice')}</span>
              <strong className="mono">#{data.id}</strong>
            </div>
          </div>

          <div className="bl-meta">
            <div>
              <span>{t('ui_bill_mechanic', 'Mechanic')}</span>
              <strong>{data.mechanicName || '—'}</strong>
            </div>
            {data.plate ? (
              <div>
                <span>{t('ui_bill_plate', 'Plate')}</span>
                <strong className="mono">{data.plate.toUpperCase()}</strong>
              </div>
            ) : null}
          </div>

          <table className="bl-lines">
            <thead>
              <tr>
                <th>{t('ui_bill_col_label', 'Description')}</th>
                <th className="num">{t('ui_bill_col_qty', 'Qty')}</th>
                <th className="num">{t('ui_bill_col_price', 'Unit price')}</th>
                <th className="num">{t('ui_bill_col_total', 'Total')}</th>
              </tr>
            </thead>
            <tbody>
              {lines.map((line, index) => (
                <tr key={index}>
                  <td>{line.label}</td>
                  <td className="num">{fmt.number(line.qty)}</td>
                  <td className="num">{fmt.money(line.price)}</td>
                  <td className="num">{fmt.money(line.qty * line.price)}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <div className="bl-total">
            <span>{t('ui_bill_total', 'Total')}</span>
            <strong className="mono">{fmt.money(total)}</strong>
          </div>

          {data.note ? (
            <div className="bl-note">
              <span>{t('ui_bill_note_label', 'Note')}</span>
              <p>{data.note}</p>
            </div>
          ) : null}

          <div className="bl-thanks">{t('ui_bill_thanks', 'Thank you for your visit!')}</div>

          {stamp ? (
            <div className={`bl-stamp bl-stamp--${stamp}`}>
              {stamp === 'paid' ? t('ui_bill_stamp_paid', 'Paid') : t('ui_bill_stamp_declined', 'Declined')}
            </div>
          ) : null}
        </div>

        <div className="bl-actions">
          {payButton('cash')}
          {payButton('bank')}
          <button
            type="button"
            className="btn btn--danger btn--lg"
            disabled={!!busy || !!stamp}
            onClick={decline}
          >
            <IconX size="1.1rem" />
            {t('ui_bill_decline', 'Decline')}
          </button>
        </div>
      </div>
    </div>
  )
}
