import { Box, Text, useInput } from 'ink'
import Spinner from 'ink-spinner'
import TextInput from 'ink-text-input'
import React, { useEffect, useState } from 'react'

import { Tier, UserDetail as UD, api } from '../api.js'
import { formatBytes, tierBadge } from '../util/format.js'
import { TierSelect } from './TierSelect.js'

type Props = {
  email: string
  onBack: () => void
  onBrowse: (db: string) => void
  setStatus: (s: string) => void
  setError: (e: string | null) => void
}

type Mode =
  | { kind: 'view' }
  | { kind: 'tier' }
  | { kind: 'seed-trips' }
  | { kind: 'seed-expenses'; tripCount: number }

export const UserDetail: React.FC<Props> = ({
  email,
  onBack,
  onBrowse,
  setStatus,
  setError,
}) => {
  const [user, setUser] = useState<UD | null>(null)
  const [mode, setMode] = useState<Mode>({ kind: 'view' })
  const [tripsStr, setTripsStr] = useState('1')
  const [exStr, setExStr] = useState('10')

  const refresh = async () => {
    try {
      setStatus(`loading ${email}…`)
      const r = await api.getUser(email)
      setUser(r)
      setError(null)
      setStatus(email)
    } catch (e) {
      setError(String((e as Error).message))
    }
  }

  useEffect(() => {
    refresh()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [email])

  useInput((input, key) => {
    if (mode.kind !== 'view') return
    if (key.escape) onBack()
    if (key.return && user) onBrowse(user.personalDb)
    if (input === 't') setMode({ kind: 'tier' })
    if (input === 's') setMode({ kind: 'seed-trips' })
    if (input === 'r') refresh()
  })

  if (mode.kind === 'tier' && user) {
    return (
      <Box flexDirection="column">
        <Text>
          Set tier for <Text color="cyan">{user.email}</Text>
        </Text>
        <TierSelect
          current={user.tier}
          onSelect={async (tier: Tier) => {
            try {
              setStatus(`setting tier ${tier}…`)
              await api.setTier(email, tier)
              setStatus(`${email} → ${tier}`)
              setMode({ kind: 'view' })
              refresh()
            } catch (e) {
              setError(String((e as Error).message))
              setMode({ kind: 'view' })
            }
          }}
        />
      </Box>
    )
  }

  if (mode.kind === 'seed-trips') {
    return (
      <Box flexDirection="column">
        <Text>How many trips? (1-10)</Text>
        <TextInput
          value={tripsStr}
          onChange={setTripsStr}
          onSubmit={(v) => {
            const n = Math.max(1, Math.min(10, Number(v) || 1))
            setTripsStr(String(n))
            setMode({ kind: 'seed-expenses', tripCount: n })
          }}
        />
      </Box>
    )
  }

  if (mode.kind === 'seed-expenses') {
    return (
      <Box flexDirection="column">
        <Text>How many expenses per trip? (1-200)</Text>
        <TextInput
          value={exStr}
          onChange={setExStr}
          onSubmit={async (v) => {
            const n = Math.max(1, Math.min(200, Number(v) || 1))
            try {
              setStatus(`seeding ${mode.tripCount} × ${n}…`)
              const r = await api.seedExpenses(email, mode.tripCount, n)
              setStatus(`seeded ${r.written} docs into ${email}`)
              setMode({ kind: 'view' })
              refresh()
            } catch (e) {
              setError(String((e as Error).message))
              setMode({ kind: 'view' })
            }
          }}
        />
      </Box>
    )
  }

  if (!user) {
    return (
      <Text>
        <Spinner /> loading
      </Text>
    )
  }

  return (
    <Box flexDirection="column">
      <Text>
        <Text bold>{user.email}</Text> {tierBadge(user.tier)}
      </Text>
      <Text color="gray">personalDb: <Text color="white">{user.personalDb}</Text></Text>
      <Text color="gray">
        docs: <Text color="white">{user.docCount ?? '—'}</Text>   size:{' '}
        <Text color="white">{formatBytes(user.sizeBytes)}</Text>
      </Text>
      <Text color="gray">
        ownedSharedTrips:{' '}
        <Text color="white">{user.sharedTrips.length}</Text>
      </Text>
      {user.sharedTrips.map((st) => (
        <Text key={st.id} color="gray">
          {'   '}- {st.name} <Text color="gray">({st.id})</Text>
        </Text>
      ))}
      <Box marginTop={1}>
        <Text color="gray">
          [ Enter ] browse docs · [ t ] tier · [ s ] seed sample data · [ Esc ] back
        </Text>
      </Box>
    </Box>
  )
}
