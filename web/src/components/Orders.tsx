import { useEffect, useState } from 'react'
import { Tooltip } from '@mantine/core'
import { IconBolt, IconClockHour4, IconPackage, IconTruckDelivery } from '@tabler/icons-react'
import type { Order, OrderStatus, SupplyMode } from '../types'
import { asArray } from '../lib/nui'
import { useUi, type TFunction } from '../lib/ui'
import { ItemImage } from './Items'
import './orders.css'

export const MODE_ICON: Record<SupplyMode, typeof IconBolt> = {
  instant: IconBolt,
  delayed: IconClockHour4,
  run: IconTruckDelivery,
}

export function modeLabel(t: TFunction, mode: SupplyMode): string {
  switch (mode) {
    case 'instant':
      return t('ui_mode_instant', 'Instant')
    case 'delayed':
      return t('ui_mode_delayed', 'Delivery')
    case 'run':
      return t('ui_mode_run', 'Supply run')
    default:
      return String(mode)
  }
}

export function orderStatusLabel(t: TFunction, status: OrderStatus): string {
  switch (status) {
    case 'pending':
      return t('ui_order_pending', 'Pending')
    case 'awaiting_pickup':
      return t('ui_order_awaiting_pickup', 'Awaiting pickup')
    case 'in_transit':
      return t('ui_order_in_transit', 'In transit')
    case 'delivered':
      return t('ui_order_delivered', 'Delivered')
    case 'cancelled':
      return t('ui_order_cancelled', 'Cancelled')
    default:
      return String(status)
  }
}

const STATUS_CHIP: Record<OrderStatus, string> = {
  pending: 'chip--warn',
  awaiting_pickup: 'chip--accent',
  in_transit: 'chip--info',
  delivered: 'chip--ok',
  cancelled: 'chip--bad',
}

/** Current unix time, refreshed every intervalMs (delivery countdowns). */
export function useNow(intervalMs = 15000) {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000))
  useEffect(() => {
    const id = window.setInterval(() => setNow(Math.floor(Date.now() / 1000)), intervalMs)
    return () => window.clearInterval(id)
  }, [intervalMs])
  return now
}

/** Orders table used by the supplier (orders tab) and workshop settings (orders log). */
export function OrdersTable({ orders }: { orders: Order[] }) {
  const { t, fmt } = useUi()
  const now = useNow()

  const deliveryText = (order: Order) => {
    if (order.status === 'delivered') return order.deliverAt ? fmt.dateTime(order.deliverAt) : t('ui_order_done', 'Done')
    if (order.status === 'cancelled') return '—'
    if (order.mode === 'run' && order.status === 'awaiting_pickup') return t('ui_order_pickup_hint', 'Pick up at the supplier')
    if (order.deliverAt) {
      const minutes = Math.ceil((order.deliverAt - now) / 60)
      if (minutes <= 0) return t('ui_order_any_moment', 'Any moment')
      if (minutes < 120) return t('ui_order_in_minutes', 'in %s min', minutes)
      return fmt.dateTime(order.deliverAt)
    }
    return '—'
  }

  return (
    <table className="tbl orders-tbl">
      <thead>
        <tr>
          <th>#</th>
          <th>{t('ui_col_date', 'Date')}</th>
          <th>{t('ui_col_items', 'Items')}</th>
          <th>{t('ui_col_mode', 'Mode')}</th>
          <th className="num">{t('ui_col_total', 'Total')}</th>
          <th>{t('ui_col_status', 'Status')}</th>
          <th>{t('ui_col_delivery', 'Delivery')}</th>
        </tr>
      </thead>
      <tbody>
        {orders.map((order) => {
          const Icon = MODE_ICON[order.mode] ?? IconPackage
          const items = asArray<Order['items'][number]>(order.items)
          return (
            <tr key={order.id}>
              <td className="mono dim">{order.id}</td>
              <td className="nowrap">
                <div>{fmt.dateTime(order.date)}</div>
                {order.name ? <div className="dim orders-tbl__by">{order.name}</div> : null}
              </td>
              <td>
                <div className="orders-tbl__items">
                  {items.slice(0, 3).map((item, index) => (
                    <Tooltip key={`${item.item}-${index}`} label={item.label}>
                      <span className="orders-tbl__item">
                        <span className="item__img">
                          <ItemImage item={item.item} />
                        </span>
                        <span className="mono">{item.count}×</span>
                      </span>
                    </Tooltip>
                  ))}
                  {items.length > 3 ? (
                    <Tooltip label={items.slice(3).map((i) => `${i.count}× ${i.label}`).join(', ')}>
                      <span className="chip">+{items.length - 3}</span>
                    </Tooltip>
                  ) : null}
                </div>
              </td>
              <td>
                <span className="orders-tbl__mode">
                  <Icon size="0.95rem" />
                  {modeLabel(t, order.mode)}
                </span>
              </td>
              <td className="num">{fmt.money(order.total)}</td>
              <td>
                <span className={`chip ${STATUS_CHIP[order.status] ?? ''}`}>{orderStatusLabel(t, order.status)}</span>
              </td>
              <td className="nowrap muted">{deliveryText(order)}</td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}
