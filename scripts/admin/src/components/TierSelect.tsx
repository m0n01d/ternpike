import SelectInput from 'ink-select-input'
import React from 'react'

import { Tier } from '../api.js'

type Props = {
  current?: Tier
  onSelect: (tier: Tier) => void
}

const ITEMS = [
  { label: 'Tern (free)', value: 'tern' as Tier },
  { label: 'Osprey ($2.99/mo)', value: 'osprey' as Tier },
  { label: 'Trailblazer ($79 one-time)', value: 'trailblazer' as Tier },
]

export const TierSelect: React.FC<Props> = ({ current, onSelect }) => {
  const initialIndex = current
    ? Math.max(
        0,
        ITEMS.findIndex((i) => i.value === current),
      )
    : 0
  return (
    <SelectInput
      items={ITEMS}
      initialIndex={initialIndex}
      onSelect={(item) => onSelect(item.value)}
    />
  )
}
