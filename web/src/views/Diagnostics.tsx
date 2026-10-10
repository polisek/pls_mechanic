import { useEffect, useMemo, useState } from 'react'
import { Checkbox, Tooltip } from '@mantine/core'
import {
  IconAlertTriangle,
  IconArrowsUp,
  IconBolt,
  IconCar,
  IconCarCrash,
  IconCarGarage,
  IconChecks,
  IconDeselect,
  IconDroplet,
  IconEngine,
  IconGasStation,
  IconHelpHexagon,
  IconMapPin,
  IconPlayerPlay,
  IconRosetteDiscountCheck,
  IconSparkles,
  IconStethoscope,
} from '@tabler/icons-react'
import type {
  BodyPart,
  CorePart,
  DiagnosticsData,
  FaultCode,
  ItemReq,
  Location,
  PartState,
  RepairStep,
  ServicePart,
  StepKind,
  ViewProps,
} from '../types'
import { Window } from '../components/Window'
import { Empty, Tabs, type TabItem } from '../components/Controls'
import { ItemChip, ItemImage, aggregateReqs } from '../components/Items'
import { Gauge, Plate, StateBar, StateLabel } from '../components/Vehicle'
import { asArray } from '../lib/nui'
import { STATE_RANK, locationHint, locationLabel } from '../lib/states'
import { useNuiAction } from '../lib/useNuiAction'
import { useUi } from '../lib/ui'
import './diagnostics.css'

type TabKey = 'service' | 'core' | 'body' | 'faults' | 'tuning'
type AnyPart = ServicePart | CorePart | BodyPart

const selKey = (kind: StepKind, key: string) => `${kind}:${key}`
const isIssue = (state: PartState) => state !== 'optimal'

function worstTone(states: PartState[]): TabItem<TabKey>['tone'] {
  if (states.some((s) => s === 'failed')) return 'failed'
  if (states.some((s) => s === 'critical')) return 'critical'
  if (states.length) return 'worn'
  return undefined
}

const LOCATION_ICON: Record<Location, typeof IconMapPin> = {
  anywhere: IconMapPin,
  bay: IconCarGarage,
  lift: IconArrowsUp,
  lift_or_jack: IconArrowsUp,
}

function Odometer({ value }: { value: number }) {
  const digits = String(Math.max(0, Math.floor(Number(value) || 0))).padStart(6, '0').split('')
  return (
    <span className="odo">
      {digits.map((d, i) => (
        <span key={i} className="odo__digit">
          {d}
        </span>
      ))}
    </span>
  )
}

export default function Diagnostics({ data, onClose }: ViewProps<DiagnosticsData>) {
  const { t, fmt } = useUi()
  const action = useNuiAction()

  const service = useMemo(() => asArray<ServicePart>(data.service), [data.service])
  const core = useMemo(() => asArray<CorePart>(data.core), [data.core])
  const body = useMemo(() => asArray<BodyPart>(data.body), [data.body])
  const faults = useMemo(() => asArray<FaultCode>(data.faultCodes), [data.faultCodes])
  const tuning = useMemo(() => asArray<{ label: string; value: string }>(data.tuning), [data.tuning])

  const serviceIssues = service.filter((p) => isIssue(p.state))
  const coreIssues = core.filter((p) => isIssue(p.state))
  // parts installed from stolen items (origin "unknown")
  const unknownOrigin = service.filter((p) => p.unknownOrigin).length + core.filter((p) => p.unknownOrigin).length

  const [tab, setTab] = useState<TabKey>(() => {
    if (serviceIssues.length) return 'service'
    if (coreIssues.length) return 'core'
    if (body.length) return 'body'
    return 'service'
  })
  const [selected, setSelected] = useState<Set<string>>(() => new Set())
  const [busy, setBusy] = useState(false)

  // Repairable lookup for every kind
  const lookup = useMemo(() => {
    const map = new Map<string, { kind: StepKind; part: AnyPart }>()
    service.forEach((part) => map.set(selKey('service', part.key), { kind: 'service', part }))
    core.forEach((part) => map.set(selKey('core', part.key), { kind: 'core', part }))
    body.forEach((part) => map.set(selKey('body', part.key), { kind: 'body', part }))
    return map
  }, [service, core, body])

  // Data update from client may remove parts / change canRepair
  useEffect(() => {
    setSelected((prev) => {
      const next = new Set([...prev].filter((key) => lookup.get(key)?.part.canRepair))
      return next.size === prev.size ? prev : next
    })
  }, [lookup])

  const toggle = (kind: StepKind, part: AnyPart) => {
    if (!part.canRepair) return
    const key = selKey(kind, part.key)
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  const selectMany = (kind: StepKind, parts: AnyPart[]) => {
    setSelected((prev) => {
      const next = new Set(prev)
      parts.filter((p) => p.canRepair).forEach((p) => next.add(selKey(kind, p.key)))
      return next
    })
  }

  const clearKind = (kind: StepKind) => {
    setSelected((prev) => new Set([...prev].filter((key) => !key.startsWith(`${kind}:`))))
  }

  // Steps in workflow order: service → core → body (bodywork deformation last)
  const steps: RepairStep[] = useMemo(() => {
    const result: RepairStep[] = []
    service.forEach((p) => selected.has(selKey('service', p.key)) && result.push({ kind: 'service', key: p.key }))
    core.forEach((p) => selected.has(selKey('core', p.key)) && result.push({ kind: 'core', key: p.key }))
    body.forEach((p) => selected.has(selKey('body', p.key)) && result.push({ kind: 'body', key: p.key }))
    return result
  }, [selected, service, core, body])

  const needs = useMemo(() => {
    const items = steps.flatMap((s) => asArray<ItemReq>(lookup.get(selKey(s.kind, s.key))?.part.items))
    const tools = steps.flatMap((s) => asArray<ItemReq>(lookup.get(selKey(s.kind, s.key))?.part.tools))
    return aggregateReqs(items, tools)
  }, [steps, lookup])
  const missing = needs.filter((n) => n.have < n.count)

  const start = async () => {
    if (!steps.length || busy) return
    setBusy(true)
    await action('diagnostics:start', { netId: data.netId, steps })
    setBusy(false)
  }

  const sortBySeverity = <T extends { state: PartState }>(list: T[]) =>
    list
      .map((p, i) => ({ p, i }))
      .sort((a, b) => STATE_RANK[a.p.state] - STATE_RANK[b.p.state] || a.i - b.i)
      .map((x) => x.p)

  const tabs: TabItem<TabKey>[] = [
    {
      key: 'service',
      label: t('ui_diag_tab_service', 'Service parts'),
      icon: <IconDroplet size="1.1rem" />,
      count: serviceIssues.length,
      tone: worstTone(serviceIssues.map((p) => p.state)),
    },
    {
      key: 'core',
      label: t('ui_diag_tab_core', 'Core parts'),
      icon: <IconEngine size="1.1rem" />,
      count: coreIssues.length,
      tone: worstTone(coreIssues.map((p) => p.state)),
    },
    {
      key: 'body',
      label: t('ui_diag_tab_body', 'Bodywork'),
      icon: <IconCarCrash size="1.1rem" />,
      count: body.length,
      tone: 'critical',
    },
    {
      key: 'faults',
      label: t('ui_diag_tab_faults', 'Fault codes'),
      icon: <IconAlertTriangle size="1.1rem" />,
      count: faults.length,
      tone: 'failed',
    },
    {
      key: 'tuning',
      label: t('ui_diag_tab_tuning', 'Tuning'),
      icon: <IconSparkles size="1.1rem" />,
      count: tuning.length,
    },
  ]

  const renderRow = (kind: StepKind, part: AnyPart) => {
    const key = selKey(kind, part.key)
    const isSelected = selected.has(key)
    const value = kind === 'service' ? (part as ServicePart).life : kind === 'core' ? (part as CorePart).health : null
    const state = 'state' in part ? part.state : null
    const LocIcon = LOCATION_ICON[part.location] ?? IconMapPin
    const checkbox = (
      <Checkbox
        checked={isSelected}
        disabled={!part.canRepair}
        onChange={() => toggle(kind, part)}
        onClick={(e) => e.stopPropagation()}
        size="sm"
      />
    )

    return (
      <div
        key={key}
        className={`dg-row${isSelected ? ' is-selected' : ''}${part.canRepair ? '' : ' is-locked'}${state ? ` dg-row--${state}` : ' dg-row--damaged'}`}
        onClick={() => toggle(kind, part)}
      >
        <div className="dg-row__check">
          {part.canRepair ? (
            checkbox
          ) : (
            <Tooltip label={part.reason || t('ui_diag_cannot_repair', 'You cannot repair this part.')}>
              <span>{checkbox}</span>
            </Tooltip>
          )}
        </div>

        <div className="dg-row__name">
          <div className="dg-row__label">
            <span>{part.label}</span>
            {'obd' in part && part.obd && state !== 'optimal' ? <span className="chip chip--code">{part.obd}</span> : null}
            {'unknownOrigin' in part && part.unknownOrigin ? (
              <Tooltip label={t('ui_diag_origin_hint', 'Not a genuine part – installed outside an authorised workshop. It wears out faster.')}>
                <span className="chip chip--warn dg-origin">
                  <IconHelpHexagon size="0.85rem" />
                  {t('ui_diag_origin_unknown', 'Unknown origin')}
                </span>
              </Tooltip>
            ) : null}
          </div>
          <div className="dg-row__sub">
            {kind === 'service' ? (
              (part as ServicePart).nextServiceKm > 0 ? (
                <span>{t('ui_diag_next_service', 'Next service in %s', fmt.km((part as ServicePart).nextServiceKm))}</span>
              ) : (
                <span className="t-failed">{t('ui_diag_service_due', 'Service due now')}</span>
              )
            ) : kind === 'core' ? (
              <span>{t('ui_diag_core_hint', 'Damaged by collisions and neglected service')}</span>
            ) : (
              <span>{t('ui_diag_body_hint', 'Damaged body part')}</span>
            )}
            {!part.canRepair && part.reason ? <span className="dg-row__reason">{part.reason}</span> : null}
          </div>
        </div>

        <div className="dg-row__health">
          {value !== null && state ? (
            <>
              <div className="dg-row__health-top">
                <StateLabel state={state} />
                <span className="mono dg-row__pct">{fmt.number(value)}%</span>
              </div>
              <StateBar value={value} state={state} />
            </>
          ) : (
            <span className="state t-critical">{t('ui_diag_damaged', 'Damaged')}</span>
          )}
        </div>

        <div className="dg-row__loc">
          <Tooltip label={locationHint(t, part.location)}>
            <span className={`chip dg-loc dg-loc--${part.location}`}>
              <LocIcon size="0.9rem" />
              {locationLabel(t, part.location)}
            </span>
          </Tooltip>
        </div>

        <div className="dg-row__items">
          {asArray<ItemReq>(part.items).map((req) => (
            <ItemChip key={`i-${req.item}`} req={req} />
          ))}
          {asArray<ItemReq>(part.tools).map((req) => (
            <ItemChip key={`t-${req.item}`} req={req} tool showLabel={false} />
          ))}
        </div>
      </div>
    )
  }

  const renderPartList = (kind: StepKind, parts: AnyPart[], helper: string, emptyText: string) => {
    const issues = kind === 'body' ? parts : (parts as (ServicePart | CorePart)[]).filter((p) => isIssue(p.state))
    const kindSelected = [...selected].filter((k) => k.startsWith(`${kind}:`)).length
    return (
      <>
        <div className="dg-toolbar">
          <span className="dg-toolbar__text">{helper}</span>
          <button
            type="button"
            className="btn btn--sm"
            disabled={!issues.some((p) => p.canRepair)}
            onClick={() => selectMany(kind, issues)}
          >
            <IconChecks size="1rem" />
            {kind === 'body' ? t('ui_diag_select_all', 'Select all') : t('ui_diag_select_worn', 'Select worn & critical')}
          </button>
          <button type="button" className="btn btn--sm btn--ghost" disabled={!kindSelected} onClick={() => clearKind(kind)}>
            <IconDeselect size="1rem" />
            {t('ui_diag_clear', 'Clear')}
          </button>
        </div>
        {parts.length ? (
          <div className="dg-list scroll">
            {kind === 'body'
              ? parts.map((p) => renderRow(kind, p))
              : sortBySeverity(parts as (ServicePart | CorePart)[]).map((p) => renderRow(kind, p))}
          </div>
        ) : (
          <Empty icon={<IconRosetteDiscountCheck size="1.6rem" />} text={emptyText} />
        )}
      </>
    )
  }

  const findPart = (name: string) => {
    const needle = (name || '').toLowerCase()
    const inService = service.find((p) => p.key.toLowerCase() === needle || p.label.toLowerCase() === needle)
    if (inService) return { kind: 'service' as StepKind, part: inService as AnyPart }
    const inCore = core.find((p) => p.key.toLowerCase() === needle || p.label.toLowerCase() === needle)
    if (inCore) return { kind: 'core' as StepKind, part: inCore as AnyPart }
    return null
  }

  const renderFaults = () =>
    faults.length ? (
      <div className="dg-list scroll">
        {faults.map((fault, index) => {
          const match = findPart(fault.part)
          const isSelected = match ? selected.has(selKey(match.kind, match.part.key)) : false
          const severity = fault.severity
          return (
            <div key={`${fault.code}-${index}`} className={`dg-fault${severity ? ` dg-fault--${severity}` : ''}`}>
              <span className="dg-fault__code mono">{fault.code}</span>
              <div className="grow">
                <div className="dg-fault__desc">{fault.description}</div>
                {fault.part ? (
                  <div className="dg-fault__part muted">
                    {t('ui_diag_fault_part', 'Part')}: <strong>{match ? match.part.label : fault.part}</strong>
                  </div>
                ) : severity ? (
                  <div className="dg-fault__part muted">
                    {severity === 'critical'
                      ? t('ui_diag_fault_critical', 'Serious deviation from the factory state')
                      : t('ui_diag_fault_warning', 'Deviation from the factory state')}
                  </div>
                ) : null}
              </div>
              {match ? (
                <Tooltip
                  label={match.part.reason || t('ui_diag_cannot_repair', 'You cannot repair this part.')}
                  disabled={match.part.canRepair}
                >
                  <span>
                    <button
                      type="button"
                      className={`btn btn--sm${isSelected ? ' btn--primary' : ''}`}
                      disabled={!match.part.canRepair}
                      onClick={() => toggle(match.kind, match.part)}
                    >
                      <IconChecks size="1rem" />
                      {isSelected ? t('ui_diag_selected', 'Selected') : t('ui_diag_select_part', 'Select part')}
                    </button>
                  </span>
                </Tooltip>
              ) : null}
            </div>
          )
        })}
      </div>
    ) : (
      <Empty icon={<IconRosetteDiscountCheck size="1.6rem" />} text={t('ui_diag_no_faults', 'No fault codes stored.')} />
    )

  const renderTuning = () =>
    tuning.length ? (
      <div className="dg-tuning scroll">
        {tuning.map((mod, index) => (
          <div key={`${mod.label}-${index}`} className="dg-tuning__card">
            <span className="section-label">{mod.label}</span>
            <span className="dg-tuning__value">{mod.value}</span>
          </div>
        ))}
      </div>
    ) : (
      <Empty icon={<IconSparkles size="1.6rem" />} text={t('ui_diag_no_tuning', 'No modifications installed.')} />
    )

  const footer = (
    <>
      <div className="dg-summary">
        <span className="dg-summary__count">
          <span className="mono">{steps.length}</span>
          {t('ui_diag_selected_count', 'selected')}
        </span>
        {needs.length ? (
          <div className="dg-needs">
            {needs.slice(0, 10).map((req) => (
              <Tooltip
                key={`${req.tool ? 't' : 'i'}-${req.item}`}
                label={`${req.label} – ${t('ui_have_need', 'have %s / need %s', req.have, req.count)}`}
              >
                <span className={`dg-need${req.have < req.count ? ' is-missing' : ''}${req.tool ? ' is-tool' : ''}`}>
                  <span className="item__img">
                    <ItemImage item={req.item} tool={req.tool} />
                  </span>
                  <span className="mono">{req.tool ? (req.have < req.count ? '✕' : '✓') : `${req.have}/${req.count}`}</span>
                </span>
              </Tooltip>
            ))}
            {needs.length > 10 ? <span className="chip">+{needs.length - 10}</span> : null}
          </div>
        ) : (
          <span className="muted dg-summary__hint">{t('ui_diag_pick_hint', 'Pick the parts you want to replace.')}</span>
        )}
        {missing.length ? (
          <span className="chip chip--bad">
            <IconAlertTriangle size="0.9rem" />
            {t('ui_diag_missing', 'Missing %s', missing.length)}
          </span>
        ) : null}
      </div>
      <button type="button" className="btn btn--ghost" disabled={!steps.length} onClick={() => setSelected(new Set())}>
        {t('ui_diag_clear_all', 'Clear selection')}
      </button>
      <button type="button" className="btn btn--primary btn--lg" disabled={!steps.length || busy} onClick={start}>
        <IconPlayerPlay size="1.1rem" />
        {t('ui_diag_start', 'Start repair')}
      </button>
    </>
  )

  const health = data.health ?? { engine: 1000, body: 1000, tank: 1000 }

  return (
    <Window
      className="dg"
      icon={<IconStethoscope size="1.5rem" />}
      title={t('ui_diag_title', 'Vehicle diagnostics')}
      subtitle={t('ui_diag_subtitle', 'OBD scanner report')}
      onClose={onClose}
      footer={footer}
    >
      <div className="dg-hero">
        <div className="dg-hero__car">
          <div className="dg-hero__icon">
            <IconCar size="2rem" stroke={1.4} />
          </div>
          <div className="col" style={{ gap: '0.4rem', minWidth: 0 }}>
            <div className="row">
              <Plate plate={data.plate} />
              {data.ev ? (
                <span className="chip chip--ev">
                  <IconBolt size="0.9rem" />
                  {t('ui_ev', 'Electric')}
                </span>
              ) : null}
            </div>
            <div className="dg-hero__model">{data.model}</div>
            <div className="row">
              {data.vehicleClass ? <span className="chip">{data.vehicleClass}</span> : null}
              {unknownOrigin ? (
                <Tooltip label={t('ui_diag_origin_hint', 'Not a genuine part – installed outside an authorised workshop. It wears out faster.')}>
                  <span className="chip chip--warn">
                    <IconHelpHexagon size="0.9rem" />
                    {t('ui_diag_origin_count', 'Unknown origin: %s', unknownOrigin)}
                  </span>
                </Tooltip>
              ) : null}
            </div>
          </div>
        </div>

        <div className="dg-hero__odo">
          <span className="section-label">{t('ui_mileage', 'Mileage')}</span>
          <div className="row" style={{ gap: '0.45rem' }}>
            <Odometer value={fmt.mileage(data.mileage)} />
            <span className="muted">{fmt.mileageUnit}</span>
          </div>
        </div>

        <div className="dg-hero__gauges">
          <Gauge value={health.engine} label={t('ui_health_engine', 'Engine')} icon={<IconEngine size="1rem" />} />
          <Gauge value={health.body} label={t('ui_health_body', 'Body')} icon={<IconCar size="1rem" />} />
          <Gauge value={health.tank} label={t('ui_health_tank', 'Fuel tank')} icon={<IconGasStation size="1rem" />} />
        </div>
      </div>

      <Tabs items={tabs} active={tab} onChange={setTab} />

      <div className="dg-content" key={tab}>
        {tab === 'service'
          ? renderPartList(
              'service',
              service,
              t('ui_diag_service_help', 'Wear parts – replaced by mileage interval.'),
              t('ui_diag_no_service', 'No service parts for this vehicle.'),
            )
          : null}
        {tab === 'core'
          ? renderPartList(
              'core',
              core,
              t('ui_diag_core_help', 'Main components – damaged by collisions and neglected service.'),
              t('ui_diag_no_core', 'No core parts for this vehicle.'),
            )
          : null}
        {tab === 'body'
          ? renderPartList(
              'body',
              body,
              t('ui_diag_body_help', 'Visible damage – bodywork is repaired as the last step.'),
              t('ui_diag_no_body', 'The bodywork is in perfect condition.'),
            )
          : null}
        {tab === 'faults' ? renderFaults() : null}
        {tab === 'tuning' ? renderTuning() : null}
      </div>
    </Window>
  )
}
