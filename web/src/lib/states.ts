import type { Location, PartState } from '../types'
import type { TFunction } from './ui'

// Thresholds match Config.PartStates / plan: optimal > 70, worn 40–70, critical 15–40, failed < 15
export function stateFromPercent(percent: number): PartState {
  if (percent > 70) return 'optimal'
  if (percent >= 40) return 'worn'
  if (percent >= 15) return 'critical'
  return 'failed'
}

export const STATE_RANK: Record<PartState, number> = { failed: 0, critical: 1, worn: 2, optimal: 3 }

export function stateLabel(t: TFunction, state: PartState): string {
  switch (state) {
    case 'optimal':
      return t('ui_state_optimal', 'Optimal')
    case 'worn':
      return t('ui_state_worn', 'Worn')
    case 'critical':
      return t('ui_state_critical', 'Critical')
    case 'failed':
      return t('ui_state_failed', 'Failed')
    default:
      return String(state)
  }
}

export function locationLabel(t: TFunction, location: Location): string {
  switch (location) {
    case 'bay':
      return t('ui_loc_bay', 'Bay / lift')
    case 'lift':
      return t('ui_loc_lift', 'Lift')
    case 'lift_or_jack':
      return t('ui_loc_lift_or_jack', 'Lift / jack')
    default:
      return t('ui_loc_anywhere', 'Anywhere')
  }
}

export function locationHint(t: TFunction, location: Location): string {
  switch (location) {
    case 'bay':
      return t('ui_loc_bay_hint', 'The vehicle must be in a repair bay or on a lift.')
    case 'lift':
      return t('ui_loc_lift_hint', 'The vehicle must be on a lift.')
    case 'lift_or_jack':
      return t('ui_loc_lift_or_jack_hint', 'The vehicle must be on a lift or jacked up at the right wheel.')
    default:
      return t('ui_loc_anywhere_hint', 'Can be done anywhere.')
  }
}

export const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value))
