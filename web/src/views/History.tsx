import { useMemo, useState } from 'react'
import { TextInput } from '@mantine/core'
import {
  IconBook2,
  IconCarCrash,
  IconDroplet,
  IconEngine,
  IconFirstAidKit,
  IconGasStation,
  IconHistory,
  IconRoad,
  IconSearch,
  IconSparkles,
  IconUser,
} from '@tabler/icons-react'
import type { HistoryData, HistoryEntry, HistoryType, ViewProps } from '../types'
import { Window } from '../components/Window'
import { Empty } from '../components/Controls'
import { Plate } from '../components/Vehicle'
import { asArray } from '../lib/nui'
import { useUi, type TFunction } from '../lib/ui'
import './history.css'

type Filter = HistoryType | 'all'

const TYPE_ICON: Record<HistoryType, typeof IconDroplet> = {
  service: IconDroplet,
  core: IconEngine,
  body: IconCarCrash,
  tuning: IconSparkles,
  kit: IconFirstAidKit,
  station: IconGasStation,
}

function typeLabel(t: TFunction, type: Filter): string {
  switch (type) {
    case 'service':
      return t('ui_hist_type_service', 'Service')
    case 'core':
      return t('ui_hist_type_core', 'Core part')
    case 'body':
      return t('ui_hist_type_body', 'Bodywork')
    case 'tuning':
      return t('ui_hist_type_tuning', 'Tuning')
    case 'kit':
      return t('ui_hist_type_kit', 'Repair kit')
    case 'station':
      return t('ui_hist_type_station', 'Repair station')
    default:
      return t('ui_hist_type_all', 'All')
  }
}

const TYPES: HistoryType[] = ['service', 'core', 'body', 'tuning', 'kit', 'station']

export default function History({ data, onClose }: ViewProps<HistoryData>) {
  const { t, fmt } = useUi()
  const [filter, setFilter] = useState<Filter>('all')
  const [search, setSearch] = useState('')

  // items of a record come from a JSON column – an empty list may arrive as {} too
  const entries = useMemo(
    () =>
      asArray<HistoryEntry>(data.entries)
        .map((e) => ({ ...e, items: asArray<HistoryEntry['items'][number]>(e.items) }))
        .sort((a, b) => (b.date || 0) - (a.date || 0) || (b.id || 0) - (a.id || 0)),
    [data.entries],
  )

  const counts = useMemo(() => {
    const result: Partial<Record<HistoryType, number>> = {}
    entries.forEach((e) => (result[e.type] = (result[e.type] ?? 0) + 1))
    return result
  }, [entries])

  const groups = useMemo(() => {
    const needle = search.trim().toLowerCase()
    const filtered = entries.filter((e) => {
      if (filter !== 'all' && e.type !== filter) return false
      if (!needle) return true
      const hay = [e.label, e.mechanic, e.shopName, ...e.items.map((i) => i.label)].join(' ').toLowerCase()
      return hay.indexOf(needle) !== -1
    })
    const result: { key: string; date: number; entries: HistoryEntry[] }[] = []
    filtered.forEach((entry) => {
      const key = fmt.dayKey(entry.date)
      const last = result[result.length - 1]
      if (last && last.key === key) last.entries.push(entry)
      else result.push({ key, date: entry.date, entries: [entry] })
    })
    return result
  }, [entries, filter, search, fmt])

  const lastVisit = entries[0]

  return (
    <Window
      className="hs"
      icon={<IconBook2 size="1.5rem" />}
      title={t('ui_hist_title', 'Service book')}
      subtitle={data.model || t('ui_hist_subtitle', 'Vehicle service history')}
      onClose={onClose}
    >
      <div className="hs-hero">
        <div className="col" style={{ gap: '0.45rem' }}>
          <Plate plate={data.plate} />
          {data.model ? <div className="hs-hero__model">{data.model}</div> : null}
        </div>
        <div className="hs-stats">
          <div className="hs-stat">
            <span className="section-label">{t('ui_mileage', 'Mileage')}</span>
            <span className="hs-stat__value mono">{fmt.km(data.mileage)}</span>
          </div>
          <div className="hs-stat">
            <span className="section-label">{t('ui_hist_records', 'Records')}</span>
            <span className="hs-stat__value mono">{fmt.number(entries.length)}</span>
          </div>
          <div className="hs-stat">
            <span className="section-label">{t('ui_hist_last_visit', 'Last visit')}</span>
            <span className="hs-stat__value">{lastVisit ? fmt.date(lastVisit.date) : '—'}</span>
          </div>
        </div>
      </div>

      <div className="hs-filters">
        <div className="hs-chips">
          {(['all', ...TYPES] as Filter[]).map((type) => {
            const count = type === 'all' ? entries.length : counts[type] ?? 0
            if (type !== 'all' && !count) return null
            const Icon = type === 'all' ? IconHistory : TYPE_ICON[type]
            return (
              <button
                key={type}
                type="button"
                className={`hs-chip hs-chip--${type}${filter === type ? ' is-active' : ''}`}
                onClick={() => setFilter(type)}
              >
                <Icon size="0.95rem" />
                {typeLabel(t, type)}
                <span className="count">{count}</span>
              </button>
            )
          })}
        </div>
        <TextInput
          className="inp hs-search"
          size="sm"
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          placeholder={t('ui_search', 'Search…')}
          leftSection={<IconSearch size="1rem" />}
        />
      </div>

      {groups.length ? (
        <div className="hs-timeline scroll">
          {groups.map((group) => (
            <section key={group.key} className="hs-day">
              <div className="hs-day__label">{fmt.date(group.date)}</div>
              {group.entries.map((entry) => {
                const Icon = TYPE_ICON[entry.type] ?? IconHistory
                return (
                  <article key={entry.id} className={`hs-entry hs-entry--${entry.type}`}>
                    <span className="hs-entry__node">
                      <Icon size="1rem" />
                    </span>
                    <div className="hs-entry__card">
                      <div className="hs-entry__top">
                        <div className="grow">
                          <div className="hs-entry__label">{entry.label}</div>
                          <div className="hs-entry__meta">
                            <span className={`hs-type hs-type--${entry.type}`}>{typeLabel(t, entry.type)}</span>
                            <span>
                              <IconRoad size="0.9rem" />
                              {fmt.km(entry.mileage)}
                            </span>
                            <span>
                              <IconUser size="0.9rem" />
                              {entry.mechanic || '—'}
                            </span>
                            <span className="mono dim">{fmt.time(entry.date)}</span>
                          </div>
                        </div>
                        {entry.shopName ? <span className="hs-stamp">{entry.shopName}</span> : null}
                      </div>
                      {entry.items.length ? (
                        <div className="hs-entry__items">
                          {entry.items.map((item, index) => (
                            <span key={`${item.label}-${index}`} className="chip">
                              <span className="mono t-accent">{item.count}×</span>
                              {item.label}
                            </span>
                          ))}
                        </div>
                      ) : null}
                    </div>
                  </article>
                )
              })}
            </section>
          ))}
        </div>
      ) : (
        <Empty
          icon={<IconBook2 size="1.6rem" />}
          text={entries.length ? t('ui_hist_no_match', 'No records match the filter.') : t('ui_hist_empty', 'The service book is empty.')}
        />
      )}
    </Window>
  )
}
