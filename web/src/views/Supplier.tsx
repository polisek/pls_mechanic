import { useEffect, useMemo, useState } from 'react'
import { TextInput, Tooltip } from '@mantine/core'
import {
  IconBuildingWarehouse,
  IconLayoutGrid,
  IconPackage,
  IconPlus,
  IconRefresh,
  IconSearch,
  IconShoppingCart,
  IconShoppingCartPlus,
  IconTrash,
  IconTruckDelivery,
  IconWallet,
} from '@tabler/icons-react'
import type { CatalogItem, Order, SupplierData, SupplierMode, SupplyMode, ViewProps } from '../types'
import { Window } from '../components/Window'
import { Empty, Stepper, Tabs } from '../components/Controls'
import { ItemImage } from '../components/Items'
import { MODE_ICON, OrdersTable, modeLabel } from '../components/Orders'
import { asArray, fetchNui } from '../lib/nui'
import { useNuiAction } from '../lib/useNuiAction'
import { useUi, type TFunction } from '../lib/ui'
import './supplier.css'

type TabKey = 'catalog' | 'orders'

function categoryLabel(t: TFunction, category: string): string {
  switch (category) {
    case 'service':
      return t('ui_cat_service', 'Service parts')
    case 'core':
      return t('ui_cat_core', 'Core parts')
    case 'ev':
      return t('ui_cat_ev', 'Electric vehicles')
    case 'body':
      return t('ui_cat_body', 'Bodywork')
    case 'tools':
      return t('ui_cat_tools', 'Tools')
    case 'kits':
      return t('ui_cat_kits', 'Repair kits')
    case 'materials':
      return t('ui_cat_materials', 'Materials')
    case 'props':
      return t('ui_cat_props', 'Props')
    case 'performance':
      return t('ui_cat_performance', 'Performance tuning')
    case 'visual':
      return t('ui_cat_visual', 'Visual tuning')
    case 'tuning':
      return t('ui_cat_tuning', 'Tuning')
    case 'other':
      return t('ui_cat_other', 'Other')
    default: {
      const text = String(category || '')
      if (/[A-Z\s]/.test(text)) return text
      const spaced = text.replace(/[_-]+/g, ' ')
      return spaced.charAt(0).toUpperCase() + spaced.slice(1)
    }
  }
}

// "supplier:refresh" answers {} (encoded as []) when the window is no longer open
const isSupplierData = (value: unknown): value is SupplierData =>
  !!value && typeof value === 'object' && !Array.isArray(value) && 'catalog' in value

export default function Supplier({
  data,
  onClose,
  onData,
}: ViewProps<SupplierData> & { onData: (data: SupplierData) => void }) {
  const { t, fmt } = useUi()
  const action = useNuiAction()

  const catalog = useMemo(() => asArray<CatalogItem>(data.catalog), [data.catalog])
  const modes = useMemo(() => asArray<SupplierMode>(data.modes), [data.modes])
  const orders = useMemo(() => [...asArray<Order>(data.orders)].sort((a, b) => b.date - a.date || b.id - a.id), [data.orders])

  const [tab, setTab] = useState<TabKey>('catalog')
  const [category, setCategory] = useState<string>('all')
  const [search, setSearch] = useState('')
  const [cart, setCart] = useState<Record<string, number>>({})
  const [mode, setMode] = useState<SupplyMode | null>(() => modes.find((m) => m.enabled)?.key ?? null)
  const [busy, setBusy] = useState(false)
  const [refreshing, setRefreshing] = useState(false)

  const byItem = useMemo(() => {
    const map = new Map<string, CatalogItem>()
    catalog.forEach((c) => map.set(c.item, c))
    return map
  }, [catalog])

  const categories = useMemo(() => {
    const list: string[] = []
    catalog.forEach((c) => list.indexOf(c.category) === -1 && list.push(c.category))
    return list
  }, [catalog])

  const visible = useMemo(() => {
    const needle = search.trim().toLowerCase()
    return catalog.filter(
      (c) =>
        (category === 'all' || c.category === category) &&
        (!needle || c.label.toLowerCase().indexOf(needle) !== -1 || c.item.toLowerCase().indexOf(needle) !== -1),
    )
  }, [catalog, category, search])

  const maxFor = (c: CatalogItem) => {
    if (typeof c.remaining === 'number') return Math.max(0, c.remaining)
    if (typeof c.limit === 'number') return Math.max(0, c.limit)
    return 999
  }

  // Keep cart valid after data refresh (removed items, lowered limits, disabled mode)
  useEffect(() => {
    setCart((prev) => {
      let changed = false
      const next: Record<string, number> = {}
      Object.keys(prev).forEach((item) => {
        const entry = byItem.get(item)
        const count = entry ? Math.min(prev[item]!, maxFor(entry)) : 0
        if (count > 0) next[item] = count
        if (count !== prev[item]) changed = true
      })
      return changed ? next : prev
    })
    setMode((prev) => (prev && modes.some((m) => m.key === prev && m.enabled) ? prev : modes.find((m) => m.enabled)?.key ?? null))
  }, [byItem, modes])

  const setCount = (item: string, count: number) =>
    setCart((prev) => {
      const next = { ...prev }
      if (count <= 0) delete next[item]
      else next[item] = count
      return next
    })

  const cartLines = Object.keys(cart)
    .map((item) => ({ entry: byItem.get(item), count: cart[item]! }))
    .filter((l): l is { entry: CatalogItem; count: number } => !!l.entry)
  const subtotal = cartLines.reduce((sum, l) => sum + l.entry.price * l.count, 0)
  const activeMode = modes.find((m) => m.key === mode)
  const multiplier = activeMode ? Number(activeMode.multiplier) || 1 : 1
  // Same as the server: round(Σ price × count × multiplier), rounded once on the sum
  const total = Math.round(cartLines.reduce((sum, l) => sum + l.entry.price * l.count * multiplier, 0))
  const balance = Number(data.balance) || 0
  const cartCount = cartLines.reduce((sum, l) => sum + l.count, 0)
  const canOrder = cartLines.length > 0 && !!activeMode && activeMode.enabled && total <= balance && !busy

  const refresh = async () => {
    if (refreshing) return
    setRefreshing(true)
    const res = await fetchNui<SupplierData>('supplier:refresh', {})
    setRefreshing(false)
    if (isSupplierData(res)) onData(res)
  }

  const order = async () => {
    if (!canOrder || !activeMode) return
    setBusy(true)
    const res = await action<{ data?: SupplierData }>('supplier:order', {
      mode: activeMode.key,
      items: cartLines.map((l) => ({ item: l.entry.item, count: l.count })),
    })
    setBusy(false)
    if (!res.ok) return
    setCart({})
    setTab('orders')
    if (isSupplierData(res.data)) onData(res.data)
    else refresh()
  }

  const activeOrders = orders.filter((o) => o.status !== 'delivered' && o.status !== 'cancelled').length

  const multiplierText = (value: number) => {
    const pct = Math.round((value - 1) * 100)
    if (pct === 0) return t('ui_sup_base_price', 'Base price')
    return `${pct > 0 ? '+' : '−'}${Math.abs(pct)} %`
  }

  return (
    <Window
      className="sp"
      icon={<IconBuildingWarehouse size="1.5rem" />}
      title={t('ui_sup_title', 'Parts supplier')}
      subtitle={data.shopName}
      onClose={onClose}
      headerRight={
        <>
          <div className="sp-balance">
            <IconWallet size="1.2rem" />
            <div>
              <div className="section-label">
                {data.payFrom === 'player'
                  ? t('ui_sup_balance_player', 'Your money')
                  : t('ui_sup_balance_society', 'Workshop account')}
              </div>
              <div className="sp-balance__value mono">{fmt.money(balance)}</div>
            </div>
          </div>
          <Tooltip label={t('ui_refresh', 'Refresh')}>
            <button type="button" className="btn btn--icon" onClick={refresh} disabled={refreshing}>
              <IconRefresh size="1.1rem" className={refreshing ? 'spin' : undefined} />
            </button>
          </Tooltip>
        </>
      }
    >
      <Tabs
        items={[
          { key: 'catalog', label: t('ui_sup_tab_catalog', 'Catalog'), icon: <IconLayoutGrid size="1.1rem" /> },
          {
            key: 'orders',
            label: t('ui_sup_tab_orders', 'Orders'),
            icon: <IconTruckDelivery size="1.1rem" />,
            count: activeOrders,
            tone: 'accent',
          },
        ]}
        active={tab}
        onChange={setTab}
      />

      {tab === 'catalog' ? (
        <div className="sp-body">
          <aside className="sp-cats scroll">
            <button
              type="button"
              className={`sp-cat${category === 'all' ? ' is-active' : ''}`}
              onClick={() => setCategory('all')}
            >
              <span className="grow">{t('ui_sup_all', 'All items')}</span>
              <span className="count">{catalog.length}</span>
            </button>
            {categories.map((cat) => (
              <button
                key={cat}
                type="button"
                className={`sp-cat${category === cat ? ' is-active' : ''}`}
                onClick={() => setCategory(cat)}
              >
                <span className="grow">{categoryLabel(t, cat)}</span>
                <span className="count">{catalog.filter((c) => c.category === cat).length}</span>
              </button>
            ))}
          </aside>

          <section className="sp-catalog">
            <div className="sp-search">
              <TextInput
                className="inp"
                value={search}
                onChange={(e) => setSearch(e.currentTarget.value)}
                placeholder={t('ui_sup_search', 'Search parts…')}
                leftSection={<IconSearch size="1rem" />}
              />
            </div>
            {visible.length ? (
              <div className="sp-grid scroll">
                {visible.map((c) => {
                  const inCart = cart[c.item] ?? 0
                  const max = maxFor(c)
                  const soldOut = max <= 0
                  return (
                    <div key={c.item} className={`sp-card${inCart ? ' is-in-cart' : ''}${soldOut ? ' is-sold-out' : ''}`}>
                      {typeof c.limit === 'number' ? (
                        <Tooltip label={t('ui_sup_limit_tip', 'Daily limit of the supplier')}>
                          <span className={`sp-card__limit${soldOut ? ' t-failed' : ''}`}>
                            {t('ui_sup_left', '%s / %s left', typeof c.remaining === 'number' ? c.remaining : c.limit, c.limit)}
                          </span>
                        </Tooltip>
                      ) : null}
                      <div className="sp-card__img">
                        <ItemImage item={c.item} size="2.4rem" />
                      </div>
                      <div className="sp-card__label" title={c.label}>
                        {c.label}
                      </div>
                      <div className="sp-card__price mono">{fmt.money(c.price)}</div>
                      <div className="sp-card__action">
                        {soldOut ? (
                          <span className="chip chip--bad">{t('ui_sup_sold_out', 'Sold out')}</span>
                        ) : inCart ? (
                          <Stepper value={inCart} min={0} max={max} onChange={(n) => setCount(c.item, n)} />
                        ) : (
                          <button type="button" className="btn btn--sm sp-card__add" onClick={() => setCount(c.item, 1)}>
                            <IconPlus size="0.95rem" />
                            {t('ui_sup_add', 'Add')}
                          </button>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            ) : (
              <Empty icon={<IconSearch size="1.5rem" />} text={t('ui_sup_no_items', 'No items found.')} />
            )}
          </section>

          <aside className="sp-cart">
            <div className="sp-cart__head">
              <IconShoppingCart size="1.2rem" />
              <span className="grow sp-cart__title">{t('ui_sup_cart', 'Order')}</span>
              {cartLines.length ? (
                <button type="button" className="btn btn--sm btn--ghost" onClick={() => setCart({})}>
                  <IconTrash size="0.95rem" />
                  {t('ui_clear', 'Clear')}
                </button>
              ) : null}
            </div>

            <div className="sp-cart__lines scroll">
              {cartLines.length ? (
                cartLines.map(({ entry, count }) => (
                  <div key={entry.item} className="sp-line">
                    <span className="item__img sp-line__img">
                      <ItemImage item={entry.item} />
                    </span>
                    <div className="grow">
                      <div className="sp-line__label">{entry.label}</div>
                      <div className="mono dim sp-line__price">{fmt.money(entry.price * count)}</div>
                    </div>
                    <Stepper value={count} min={0} max={maxFor(entry)} onChange={(n) => setCount(entry.item, n)} />
                  </div>
                ))
              ) : (
                <Empty icon={<IconShoppingCartPlus size="1.4rem" />} text={t('ui_sup_cart_empty', 'Add parts from the catalog.')} />
              )}
            </div>

            <div className="sp-modes">
              <div className="section-label">{t('ui_sup_mode', 'Delivery mode')}</div>
              {modes.map((m) => {
                const Icon = MODE_ICON[m.key] ?? IconPackage
                const card = (
                  <button
                    key={m.key}
                    type="button"
                    className={`sp-mode${mode === m.key ? ' is-active' : ''}`}
                    disabled={!m.enabled}
                    onClick={() => setMode(m.key)}
                  >
                    <span className="sp-mode__icon">
                      <Icon size="1.1rem" />
                    </span>
                    <span className="grow">
                      <span className="sp-mode__label">{m.label || modeLabel(t, m.key)}</span>
                      <span className="sp-mode__desc">
                        {m.key === 'instant'
                          ? t('ui_sup_mode_instant_desc', 'Straight to the workshop storage')
                          : m.key === 'delayed'
                            ? t('ui_sup_mode_delayed_desc', 'Delivered to storage in %s min', m.minutes ?? 0)
                            : t('ui_sup_mode_run_desc', 'Pick up the crates with a service van')}
                      </span>
                    </span>
                    <span className={`sp-mode__mult mono${m.multiplier < 1 ? ' t-optimal' : m.multiplier > 1 ? ' t-critical' : ''}`}>
                      {multiplierText(m.multiplier)}
                    </span>
                  </button>
                )
                return m.enabled ? (
                  card
                ) : (
                  <Tooltip key={m.key} label={t('ui_sup_mode_disabled', 'Disabled by the workshop')}>
                    <span>{card}</span>
                  </Tooltip>
                )
              })}
            </div>

            <div className="sp-sum">
              <div className="sp-sum__row">
                <span className="muted">{t('ui_sup_items_count', 'Items (%s pcs)', cartCount)}</span>
                <span className="mono">{fmt.money(subtotal)}</span>
              </div>
              <div className="sp-sum__row">
                <span className="muted">{t('ui_sup_multiplier', 'Mode price')}</span>
                <span className="mono">×{fmt.number(multiplier, 2)}</span>
              </div>
              <div className="sp-sum__row sp-sum__row--total">
                <span>{t('ui_total', 'Total')}</span>
                <span className="mono">{fmt.money(total)}</span>
              </div>
              <div className="sp-sum__row">
                <span className="muted">{t('ui_sup_after', 'Balance after order')}</span>
                <span className={`mono${balance - total < 0 ? ' t-failed' : ''}`}>{fmt.money(balance - total)}</span>
              </div>
              <button type="button" className="btn btn--primary btn--lg sp-order" disabled={!canOrder} onClick={order}>
                <IconTruckDelivery size="1.2rem" />
                {total > balance && cartLines.length ? t('ui_sup_no_money', 'Not enough money') : t('ui_sup_order', 'Place order')}
              </button>
            </div>
          </aside>
        </div>
      ) : (
        <div className="sp-orders-wrap scroll">
          {orders.length ? (
            <OrdersTable orders={orders} />
          ) : (
            <Empty icon={<IconTruckDelivery size="1.6rem" />} text={t('ui_sup_no_orders', 'No orders yet.')} />
          )}
        </div>
      )}
    </Window>
  )
}
