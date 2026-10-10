import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Checkbox, NumberInput, Slider, Switch } from '@mantine/core'
import {
  IconBolt,
  IconClockHour4,
  IconClipboardList,
  IconCoins,
  IconDeviceFloppy,
  IconLoader2,
  IconLock,
  IconPercentage,
  IconReceipt,
  IconSettings,
  IconShieldLock,
  IconSparkles,
  IconTool,
  IconTruckDelivery,
} from '@tabler/icons-react'
import type {
  BillRecord,
  BillsPage,
  Order,
  OrdersPage,
  PermissionMatrix,
  SettingsData,
  ShopSettings,
  SupplyMode,
  ViewProps,
} from '../types'
import { Window } from '../components/Window'
import { Empty, Pager, Tabs, type TabItem } from '../components/Controls'
import { OrdersTable } from '../components/Orders'
import { Plate } from '../components/Vehicle'
import { asArray, asRecord, fetchNui } from '../lib/nui'
import { useNuiAction } from '../lib/useNuiAction'
import { useUi, type TFunction } from '../lib/ui'
import './settings.css'

type TabKey = 'permissions' | 'prices' | 'supply' | 'bills' | 'orders'

const DEFAULT_SETTINGS: ShopSettings = {
  laborMultiplier: 1,
  partsMarkup: 20,
  tuningMarkup: 0,
  commission: 10,
  supplyModes: { instant: true, delayed: true, run: true },
}

function billStatus(t: TFunction, status: string): { label: string; chip: string } {
  switch (status) {
    case 'paid':
      return { label: t('ui_bill_status_paid', 'Paid'), chip: 'chip--ok' }
    case 'pending':
      return { label: t('ui_bill_status_pending', 'Pending'), chip: 'chip--warn' }
    case 'declined':
      return { label: t('ui_bill_status_declined', 'Declined'), chip: 'chip--bad' }
    case 'expired':
      return { label: t('ui_bill_status_expired', 'Expired'), chip: '' }
    case 'cancelled':
      return { label: t('ui_bill_status_cancelled', 'Cancelled'), chip: 'chip--bad' }
    default:
      return { label: status, chip: '' }
  }
}

const clone = <T,>(value: T): T => JSON.parse(JSON.stringify(value ?? null))

// job -> grade -> perm map; an empty Lua table (job without grades, shop without jobs) arrives as []
function toMatrix(value: unknown): PermissionMatrix {
  const matrix: PermissionMatrix = {}
  Object.entries(asRecord<unknown>(value)).forEach(([job, grades]) => {
    matrix[job] = {}
    Object.entries(asRecord<unknown>(grades)).forEach(([grade, perms]) => {
      matrix[job]![grade] = { ...asRecord<boolean>(perms) }
    })
  })
  return matrix
}

function toSettings(value: unknown): ShopSettings {
  const input = asRecord<unknown>(value) as Partial<ShopSettings>
  return {
    ...DEFAULT_SETTINGS,
    ...clone(input),
    supplyModes: { ...DEFAULT_SETTINGS.supplyModes, ...asRecord<boolean>(input.supplyModes) },
  }
}

/* ----------------------------------------------------------------- paged log (bills / orders) */

function usePaged<T>(
  name: string,
  shopId: number,
  active: boolean,
  pick: (res: unknown) => { rows: T[]; pages: number } | null,
) {
  const [page, setPage] = useState(1)
  const [rows, setRows] = useState<T[]>([])
  const [pages, setPages] = useState(0)
  const [loading, setLoading] = useState(false)
  const [loaded, setLoaded] = useState(false)

  const load = useCallback(
    async (target: number) => {
      setLoading(true)
      // shopId = fallback of the client when the settings window is not tracked
      const res = pick(await fetchNui(name, { page: target, shopId }))
      setLoading(false)
      setLoaded(true)
      setPage(target)
      setRows(res ? res.rows : [])
      setPages(res ? res.pages : 0)
    },
    // pick is a module-level function, stable for every call site
    [name, shopId, pick],
  )

  useEffect(() => {
    if (active && !loaded && !loading) load(1)
  }, [active, loaded, loading, load])

  return { page, rows, pages, loading, loaded, load }
}

const pickBills = (res: unknown) => {
  const r = res as BillsPage | null
  return r && typeof r === 'object' && 'bills' in r ? { rows: asArray<BillRecord>(r.bills), pages: Number(r.pages) || 1 } : null
}
const pickOrders = (res: unknown) => {
  const r = res as OrdersPage | null
  return r && typeof r === 'object' && 'orders' in r ? { rows: asArray<Order>(r.orders), pages: Number(r.pages) || 1 } : null
}

/* ----------------------------------------------------------------- price field */

function PriceField({
  icon,
  label,
  hint,
  value,
  min,
  max,
  step,
  decimals = 0,
  suffix,
  prefix,
  disabled,
  example,
  onChange,
}: {
  icon: ReactNode
  label: string
  hint: string
  value: number
  min: number
  max: number
  step: number
  decimals?: number
  suffix?: string
  prefix?: string
  disabled: boolean
  example: string
  onChange: (value: number) => void
}) {
  const round = (n: number) => Number(Math.max(min, Math.min(max, n)).toFixed(decimals))
  return (
    <div className="st-price">
      <div className="st-price__head">
        <span className="st-price__icon">{icon}</span>
        <div className="grow">
          <div className="st-price__label">{label}</div>
          <div className="st-price__hint">{hint}</div>
        </div>
        <NumberInput
          className="inp st-price__input"
          size="sm"
          value={value}
          min={min}
          max={max}
          step={step}
          decimalScale={decimals}
          fixedDecimalScale={decimals > 0}
          allowNegative={false}
          clampBehavior="strict"
          prefix={prefix}
          suffix={suffix}
          disabled={disabled}
          onChange={(v) => onChange(round(Number(v) || 0))}
        />
      </div>
      <Slider
        value={value}
        min={min}
        max={max}
        step={step}
        disabled={disabled}
        label={null}
        color="amber.6"
        size="sm"
        onChange={(v) => onChange(round(v))}
      />
      <div className="st-price__example">{example}</div>
    </div>
  )
}

/* ----------------------------------------------------------------- view */

export default function Settings({ data, onClose }: ViewProps<SettingsData>) {
  const { t, fmt } = useUi()
  const action = useNuiAction()
  const canEdit = !!data.canEdit
  const jobs = useMemo(() => asArray<SettingsData['jobs'][number]>(data.jobs), [data.jobs])
  const permissionList = useMemo(() => asArray<SettingsData['permissionList'][number]>(data.permissionList), [data.permissionList])

  const [tab, setTab] = useState<TabKey>('permissions')
  const [job, setJob] = useState<string>(jobs[0]?.name ?? '')
  const [permissions, setPermissions] = useState<PermissionMatrix>(() => toMatrix(data.permissions))
  const [settings, setSettings] = useState<ShopSettings>(() => toSettings(data.settings))
  const [baseline, setBaseline] = useState(() => JSON.stringify({ permissions, settings }))
  const [saving, setSaving] = useState(false)

  const dirty = JSON.stringify({ permissions, settings }) !== baseline

  const bills = usePaged<BillRecord>('settings:bills', data.shopId, tab === 'bills', pickBills)
  const orders = usePaged<Order>('settings:orders', data.shopId, tab === 'orders', pickOrders)

  const jobData = jobs.find((j) => j.name === job)
  const grades = useMemo(
    () => [...asArray<{ grade: number; label: string }>(jobData?.grades)].sort((a, b) => Number(a.grade) - Number(b.grade)),
    [jobData],
  )

  const has = (grade: number, perm: string) => !!permissions[job]?.[String(grade)]?.[perm]

  const setPerm = (grades: number[], perms: string[], value: boolean) => {
    if (!canEdit) return
    setPermissions((prev) => {
      const next = { ...prev, [job]: { ...(prev[job] ?? {}) } }
      grades.forEach((grade) => {
        const key = String(grade)
        const row = { ...(next[job]![key] ?? {}) }
        perms.forEach((perm) => (row[perm] = value))
        next[job]![key] = row
      })
      return next
    })
  }

  const allKeys = permissionList.map((p) => p.key)
  const columnFull = (grade: number) => allKeys.every((perm) => has(grade, perm))
  const rowFull = (perm: string) => grades.every((g) => has(g.grade, perm))

  const updateSetting = <K extends keyof ShopSettings>(key: K, value: ShopSettings[K]) =>
    setSettings((prev) => ({ ...prev, [key]: value }))

  const save = async () => {
    if (!canEdit || !dirty || saving) return
    setSaving(true)
    // the client shows the answer with Core.Notify
    const res = await action<{ permissions?: unknown; settings?: unknown }>(
      'settings:save',
      { permissions, settings },
      { success: t('ui_set_saved', 'Settings saved.'), notified: 'all' },
    )
    setSaving(false)
    if (!res.ok) return
    // the server sanitizes the values (e.g. keeps manage_shop of your own grade) – use them when it sends them back
    const savedPermissions = res.permissions && typeof res.permissions === 'object' ? toMatrix(res.permissions) : permissions
    const savedSettings = res.settings && typeof res.settings === 'object' ? toSettings(res.settings) : settings
    setPermissions(savedPermissions)
    setSettings(savedSettings)
    setBaseline(JSON.stringify({ permissions: savedPermissions, settings: savedSettings }))
  }

  const reset = () => {
    const base = JSON.parse(baseline) as { permissions: PermissionMatrix; settings: ShopSettings }
    setPermissions(base.permissions)
    setSettings(base.settings)
  }

  const tabs: TabItem<TabKey>[] = [
    { key: 'permissions', label: t('ui_set_tab_permissions', 'Permissions'), icon: <IconShieldLock size="1.1rem" /> },
    { key: 'prices', label: t('ui_set_tab_prices', 'Prices'), icon: <IconCoins size="1.1rem" /> },
    { key: 'supply', label: t('ui_set_tab_supply', 'Supply'), icon: <IconTruckDelivery size="1.1rem" /> },
    { key: 'bills', label: t('ui_set_tab_bills', 'Bills'), icon: <IconReceipt size="1.1rem" /> },
    { key: 'orders', label: t('ui_set_tab_orders', 'Orders'), icon: <IconClipboardList size="1.1rem" /> },
  ]

  const editable = tab === 'permissions' || tab === 'prices' || tab === 'supply'

  const footer = editable ? (
    <>
      <div className="grow row">
        {!canEdit ? (
          <span className="chip chip--warn">
            <IconLock size="0.9rem" />
            {t('ui_set_readonly', 'Read only – you cannot change the settings')}
          </span>
        ) : dirty ? (
          <span className="chip chip--accent">{t('ui_set_unsaved', 'Unsaved changes')}</span>
        ) : (
          <span className="muted st-foot-hint">{t('ui_set_saved_state', 'All changes are saved.')}</span>
        )}
      </div>
      {canEdit ? (
        <>
          <button type="button" className="btn btn--ghost" disabled={!dirty || saving} onClick={reset}>
            {t('ui_set_discard', 'Discard')}
          </button>
          <button type="button" className="btn btn--primary btn--lg" disabled={!dirty || saving} onClick={save}>
            <IconDeviceFloppy size="1.1rem" />
            {t('ui_save', 'Save')}
          </button>
        </>
      ) : null}
    </>
  ) : null

  const labor = Math.round(100 * settings.laborMultiplier)
  const part = Math.round(100 * (1 + settings.partsMarkup / 100))
  const tuning = Math.round(1000 * (1 + settings.tuningMarkup / 100))
  const commission = Math.floor((1000 * settings.commission) / 100)

  const supplyCards: { key: SupplyMode; icon: ReactNode; label: string; desc: string }[] = [
    {
      key: 'instant',
      icon: <IconBolt size="1.4rem" />,
      label: t('ui_mode_instant', 'Instant'),
      desc: t('ui_set_mode_instant_desc', 'Paid at once, items go straight to the workshop storage. Most expensive.'),
    },
    {
      key: 'delayed',
      icon: <IconClockHour4 size="1.4rem" />,
      label: t('ui_mode_delayed', 'Delivery'),
      desc: t('ui_set_mode_delayed_desc', 'Delivered to the storage after a few minutes, survives restarts.'),
    },
    {
      key: 'run',
      icon: <IconTruckDelivery size="1.4rem" />,
      label: t('ui_mode_run', 'Supply run'),
      desc: t('ui_set_mode_run_desc', 'Mechanics pick up the crates with a service van. Cheapest, can be stolen.'),
    },
  ]

  return (
    <Window
      className="st"
      icon={<IconSettings size="1.5rem" />}
      title={t('ui_set_title', 'Workshop settings')}
      subtitle={data.shopName}
      onClose={onClose}
      footer={footer}
    >
      <Tabs items={tabs} active={tab} onChange={setTab} />

      <div className="st-content" key={tab}>
        {tab === 'permissions' ? (
          jobs.length ? (
            <>
              {jobs.length > 1 ? (
                <div className="st-jobs">
                  {jobs.map((j) => (
                    <button
                      key={j.name}
                      type="button"
                      className={`st-job${job === j.name ? ' is-active' : ''}`}
                      onClick={() => setJob(j.name)}
                    >
                      {j.label || j.name}
                    </button>
                  ))}
                </div>
              ) : null}
              <div className="st-matrix-wrap scroll">
                <table className="st-matrix">
                  <thead>
                    <tr>
                      <th className="st-matrix__perm">{t('ui_set_permission', 'Permission')}</th>
                      {grades.map((g) => (
                        <th key={g.grade}>
                          <button
                            type="button"
                            className="st-grade"
                            disabled={!canEdit}
                            onClick={() => setPerm([g.grade], allKeys, !columnFull(g.grade))}
                            title={t('ui_set_toggle_column', 'Toggle whole grade')}
                          >
                            <span className="st-grade__label">{g.label}</span>
                            <span className="st-grade__num mono">{g.grade}</span>
                          </button>
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {permissionList.map((perm) => (
                      <tr key={perm.key}>
                        <td className="st-matrix__perm">
                          <button
                            type="button"
                            className="st-perm"
                            disabled={!canEdit}
                            onClick={() =>
                              setPerm(
                                grades.map((g) => g.grade),
                                [perm.key],
                                !rowFull(perm.key),
                              )
                            }
                            title={t('ui_set_toggle_row', 'Toggle for all grades')}
                          >
                            <span className="st-perm__label">{perm.label}</span>
                            <span className="st-perm__key mono">{perm.key}</span>
                          </button>
                        </td>
                        {grades.map((g) => (
                          <td key={g.grade} className="st-matrix__cell">
                            <Checkbox
                              checked={has(g.grade, perm.key)}
                              disabled={!canEdit}
                              onChange={(e) => setPerm([g.grade], [perm.key], e.currentTarget.checked)}
                              size="sm"
                            />
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          ) : (
            <Empty icon={<IconShieldLock size="1.6rem" />} text={t('ui_set_no_jobs', 'This workshop has no jobs assigned.')} />
          )
        ) : null}

        {tab === 'prices' ? (
          <div className="st-prices scroll">
            <PriceField
              icon={<IconTool size="1.2rem" />}
              label={t('ui_set_labor', 'Labor multiplier')}
              hint={t('ui_set_labor_hint', 'Multiplies the labor price of every repair.')}
              value={settings.laborMultiplier}
              min={0.1}
              max={5}
              step={0.05}
              decimals={2}
              prefix="×"
              disabled={!canEdit}
              example={t('ui_set_labor_example', 'Labor worth %s is billed as %s', fmt.money(100), fmt.money(labor))}
              onChange={(v) => updateSetting('laborMultiplier', v)}
            />
            <PriceField
              icon={<IconPercentage size="1.2rem" />}
              label={t('ui_set_parts_markup', 'Parts markup')}
              hint={t('ui_set_parts_markup_hint', 'Added to the supplier price of used parts.')}
              value={settings.partsMarkup}
              min={0}
              max={300}
              step={1}
              suffix=" %"
              disabled={!canEdit}
              example={t('ui_set_parts_example', 'Part bought for %s is billed as %s', fmt.money(100), fmt.money(part))}
              onChange={(v) => updateSetting('partsMarkup', v)}
            />
            <PriceField
              icon={<IconSparkles size="1.2rem" />}
              label={t('ui_set_tuning_markup', 'Tuning markup')}
              hint={t('ui_set_tuning_markup_hint', 'Added to the tuning price list.')}
              value={settings.tuningMarkup}
              min={0}
              max={300}
              step={1}
              suffix=" %"
              disabled={!canEdit}
              example={t('ui_set_tuning_example', 'Tuning worth %s costs %s', fmt.money(1000), fmt.money(tuning))}
              onChange={(v) => updateSetting('tuningMarkup', v)}
            />
            <PriceField
              icon={<IconCoins size="1.2rem" />}
              label={t('ui_set_commission', 'Mechanic commission')}
              hint={t('ui_set_commission_hint', 'Share of every paid bill that goes to the mechanic.')}
              value={settings.commission}
              min={0}
              max={100}
              step={1}
              suffix=" %"
              disabled={!canEdit}
              example={t('ui_set_commission_example', 'From a bill of %s the mechanic gets %s', fmt.money(1000), fmt.money(commission))}
              onChange={(v) => updateSetting('commission', v)}
            />
          </div>
        ) : null}

        {tab === 'supply' ? (
          <div className="st-supply scroll">
            {supplyCards.map((card) => {
              const enabled = !!settings.supplyModes[card.key]
              return (
                <div key={card.key} className={`st-mode${enabled ? ' is-enabled' : ''}`}>
                  <span className="st-mode__icon">{card.icon}</span>
                  <div className="grow">
                    <div className="st-mode__label">{card.label}</div>
                    <div className="st-mode__desc">{card.desc}</div>
                  </div>
                  <Switch
                    checked={enabled}
                    disabled={!canEdit}
                    onChange={(e) =>
                      updateSetting('supplyModes', { ...settings.supplyModes, [card.key]: e.currentTarget.checked })
                    }
                  />
                </div>
              )
            })}
            <div className="st-note muted">
              {t('ui_set_supply_note', 'Prices of the modes are set by the server owner. Disabled modes cannot be used for new orders.')}
            </div>
          </div>
        ) : null}

        {tab === 'bills' ? (
          <div className="st-log">
            <div className="st-log__table scroll">
              {bills.loading && !bills.rows.length ? (
                <div className="loader">
                  <IconLoader2 size="1.6rem" className="spin" />
                </div>
              ) : bills.rows.length ? (
                <table className="tbl">
                  <thead>
                    <tr>
                      <th>#</th>
                      <th>{t('ui_col_date', 'Date')}</th>
                      <th>{t('ui_col_mechanic', 'Mechanic')}</th>
                      <th>{t('ui_col_customer', 'Customer')}</th>
                      <th>{t('ui_col_plate', 'Plate')}</th>
                      <th className="num">{t('ui_col_total', 'Total')}</th>
                      <th>{t('ui_col_status', 'Status')}</th>
                    </tr>
                  </thead>
                  <tbody className={bills.loading ? 'is-loading' : undefined}>
                    {bills.rows.map((bill) => {
                      const status = billStatus(t, bill.status)
                      return (
                        <tr key={bill.id}>
                          <td className="mono dim">{bill.id}</td>
                          <td className="nowrap">{fmt.dateTime(bill.date)}</td>
                          <td>{bill.mechanic}</td>
                          <td>{bill.customer}</td>
                          <td>{bill.plate ? <Plate plate={bill.plate} small /> : <span className="dim">—</span>}</td>
                          <td className="num">{fmt.money(bill.total)}</td>
                          <td>
                            <span className={`chip ${status.chip}`}>{status.label}</span>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              ) : (
                <Empty icon={<IconReceipt size="1.6rem" />} text={t('ui_set_no_bills', 'No bills yet.')} />
              )}
            </div>
            <Pager page={bills.page} pages={bills.pages} onChange={bills.load} />
          </div>
        ) : null}

        {tab === 'orders' ? (
          <div className="st-log">
            <div className="st-log__table scroll">
              {orders.loading && !orders.rows.length ? (
                <div className="loader">
                  <IconLoader2 size="1.6rem" className="spin" />
                </div>
              ) : orders.rows.length ? (
                <OrdersTable orders={orders.rows} />
              ) : (
                <Empty icon={<IconTruckDelivery size="1.6rem" />} text={t('ui_set_no_orders', 'No orders yet.')} />
              )}
            </div>
            <Pager page={orders.page} pages={orders.pages} onChange={orders.load} />
          </div>
        ) : null}
      </div>
    </Window>
  )
}
