import { Box, Text, useInput } from 'ink'
import TextInput from 'ink-text-input'
import React, { useState } from 'react'

import { Tier, api } from '../api.js'
import { TierSelect } from './TierSelect.js'

type Props = {
  setStatus: (s: string) => void
  setError: (e: string | null) => void
}

type Mode =
  | { kind: 'menu' }
  | { kind: 'quick-tier'; email: string }
  | { kind: 'custom-email' }
  | { kind: 'custom-tier'; email: string }

const QUICK_USERS = [
  'alice@test.ternpike.com',
  'bob@test.ternpike.com',
  'carol@test.ternpike.com',
  'eve@test.ternpike.com',
]

export const SeedScreen: React.FC<Props> = ({ setStatus, setError }) => {
  const [mode, setMode] = useState<Mode>({ kind: 'menu' })
  const [cursor, setCursor] = useState(0)
  const [email, setEmail] = useState('')

  useInput((input, key) => {
    if (mode.kind !== 'menu') return
    if (key.upArrow) setCursor((c) => Math.max(0, c - 1))
    if (key.downArrow)
      setCursor((c) => Math.min(QUICK_USERS.length, c + 1))
    if (key.return) {
      if (cursor < QUICK_USERS.length) {
        setMode({ kind: 'quick-tier', email: QUICK_USERS[cursor] })
      } else {
        setEmail('')
        setMode({ kind: 'custom-email' })
      }
    }
  })

  const create = async (e: string, tier: Tier) => {
    try {
      setStatus(`creating ${e}…`)
      await api.createUser(e, tier)
      setStatus(`created ${e} (${tier})`)
      setMode({ kind: 'menu' })
    } catch (err) {
      setError(String((err as Error).message))
      setMode({ kind: 'menu' })
    }
  }

  if (mode.kind === 'quick-tier') {
    return (
      <Box flexDirection="column">
        <Text>
          Create <Text color="cyan">{mode.email}</Text> at tier:
        </Text>
        <TierSelect onSelect={(t) => create(mode.email, t)} />
      </Box>
    )
  }

  if (mode.kind === 'custom-email') {
    return (
      <Box flexDirection="column">
        <Text>Email:</Text>
        <TextInput
          value={email}
          onChange={setEmail}
          onSubmit={(v) => {
            if (!v.includes('@')) {
              setMode({ kind: 'menu' })
              return
            }
            setMode({ kind: 'custom-tier', email: v })
          }}
        />
      </Box>
    )
  }

  if (mode.kind === 'custom-tier') {
    return (
      <Box flexDirection="column">
        <Text>
          Tier for <Text color="cyan">{mode.email}</Text>:
        </Text>
        <TierSelect onSelect={(t) => create(mode.email, t)} />
      </Box>
    )
  }

  return (
    <Box flexDirection="column">
      <Text color="gray">Quick-seed a user. Pick one or "Custom…".</Text>
      <Box marginTop={1} flexDirection="column">
        {QUICK_USERS.map((e, i) => (
          <Text key={e}>
            {i === cursor ? '› ' : '  '}
            {e}
          </Text>
        ))}
        <Text>
          {cursor === QUICK_USERS.length ? '› ' : '  '}
          <Text color="cyan">Custom…</Text>
        </Text>
      </Box>
    </Box>
  )
}
