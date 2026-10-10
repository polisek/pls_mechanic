import { useState } from 'react'
import { Tooltip } from '@mantine/core'
import { IconPackage, IconTool } from '@tabler/icons-react'
import type { ItemReq } from '../types'
import { useUi } from '../lib/ui'

/** Inventory image with a fallback icon when the file doesn't exist. */
export function ItemImage({ item, size = '1.1rem', tool = false }: { item: string; size?: string; tool?: boolean }) {
  const { itemImage } = useUi()
  const [failed, setFailed] = useState(false)
  if (failed || !item) {
    const Icon = tool ? IconTool : IconPackage
    return <Icon size={size} stroke={1.6} />
  }
  return <img src={itemImage(item)} alt="" draggable={false} onError={() => setFailed(true)} />
}

/** Required item / tool with have / need counter (red when missing). */
export function ItemChip({ req, tool = false, showLabel = true }: { req: ItemReq; tool?: boolean; showLabel?: boolean }) {
  const { t } = useUi()
  const missing = (req.have ?? 0) < (req.count ?? 0)
  const tip = `${req.label} – ${t('ui_have_need', 'have %s / need %s', req.have ?? 0, req.count ?? 0)}`
  return (
    <Tooltip label={tip}>
      <span className={`item${missing ? ' is-missing' : ''}${tool ? ' is-tool' : ''}`}>
        <span className="item__img">
          <ItemImage item={req.item} tool={tool} />
        </span>
        {showLabel ? <span className="item__label">{req.label}</span> : null}
        <span className="item__qty">
          {tool ? (missing ? '✕' : '✓') : `${req.have ?? 0}/${req.count ?? 0}`}
        </span>
      </span>
    </Tooltip>
  )
}

export interface AggregatedReq extends ItemReq {
  tool: boolean
}

/** Sums the same items (count) of many requirements; tools are counted once. */
export function aggregateReqs(items: ItemReq[], tools: ItemReq[] = []): AggregatedReq[] {
  const map = new Map<string, AggregatedReq>()
  for (const req of items) {
    if (!req || !req.item) continue
    const prev = map.get(req.item)
    if (prev && !prev.tool) {
      prev.count += req.count || 0
      prev.have = Math.max(prev.have, req.have || 0)
    } else if (!prev) {
      map.set(req.item, { ...req, count: req.count || 0, have: req.have || 0, tool: false })
    }
  }
  for (const req of tools) {
    if (!req || !req.item) continue
    const key = `tool:${req.item}`
    const prev = map.get(key)
    if (prev) {
      prev.count = Math.max(prev.count, req.count || 1)
    } else {
      map.set(key, { ...req, count: req.count || 1, have: req.have || 0, tool: true })
    }
  }
  return [...map.values()]
}
