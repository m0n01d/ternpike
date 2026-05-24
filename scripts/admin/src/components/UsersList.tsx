import { Box, Text, useInput } from 'ink'
import Spinner from 'ink-spinner'
import TextInput from 'ink-text-input'
import React, { useEffect, useState } from 'react'

import { Tier, User, api } from '../api.js'
import { tierColor, truncate } from '../util/format.js'
import { Confirm } from './Confirm.js'
import { TierSelect } from './TierSelect.js'

type Props = {
  onPick: (email: string) => void
  setStatus: (s: string) => void
  setError: (e: string | null) => void
}

type Mode =
  | { kind: 'list' }
  | { kind: 'filter' }
  | { kind: 'tier'; user: User }
  | { kind: 'new-email' }
  | { kind: 'new-tier'; email: string }
  | { kind: 'delete'; user: User }

export const UsersList: React.FC<Props> = ({ onPick, setStatus, setError }) => {
  const [users, setUsers] = useState<User[] | null>(null)
  const [filter, setFilter] = useState('')
  const [cursor, setCursor] = useState(0)
  const [mode, setMode] = useState<Mode>({ kind: 'list' })
  const [newEmail, setNewEmail] = useState('')

  const refresh = async () => {
    try {
      setStatus('loading users…')
      const r = await api.listUsers()
      setUsers(r.users)
      setError(null)
      setStatus(`${r.users.length} users`)
    } catch (e) {
      setError(String((e as Error).message))
      setUsers([])
    }
  }

  useEffect(() => {
    refresh()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const filtered = (users || []).filter((u) =>
    u.email.toLowerCase().includes(filter.toLowerCase()),
  )

  useInput((input, key) => {
    if (mode.kind !== 'list') return
    if (key.upArrow) setCursor((c) => Math.max(0, c - 1))
    if (key.downArrow) setCursor((c) => Math.min(filtered.length - 1, c + 1))
    if (key.return && filtered[cursor]) onPick(filtered[cursor].email)
    if (input === '/') setMode({ kind: 'filter' })
    if (input === 't' && filtered[cursor]) {
      setMode({ kind: 'tier', user: filtered[cursor] })
    }
    if (input === 'd' && filtered[cursor]) {
      setMode({ kind: 'delete', user: filtered[cursor] })
    }
    if (input === 'n') {
      setNewEmail('')
      setMode({ kind: 'new-email' })
    }
    if (input === 'r') refresh()
  })

  if (mode.kind === 'filter') {
    return (
      <Box>
        <Text>filter: </Text>
        <TextInput
          value={filter}
          onChange={setFilter}
          onSubmit={() => setMode({ kind: 'list' })}
        />
      </Box>
    )
  }

  if (mode.kind === 'tier') {
    return (
      <Box flexDirection="column">
        <Text>
          Set tier for <Text color="cyan">{mode.user.email}</Text>
        </Text>
        <TierSelect
          current={mode.user.tier}
          onSelect={async (tier: Tier) => {
            try {
              setStatus(`setting tier ${tier}…`)
              await api.setTier(mode.user.email, tier)
              setStatus(`${mode.user.email} → ${tier}`)
              setMode({ kind: 'list' })
              refresh()
            } catch (e) {
              setError(String((e as Error).message))
              setMode({ kind: 'list' })
            }
          }}
        />
      </Box>
    )
  }

  if (mode.kind === 'new-email') {
    return (
      <Box flexDirection="column">
        <Text>New user email:</Text>
        <TextInput
          value={newEmail}
          onChange={setNewEmail}
          onSubmit={(v) => {
            if (!v.includes('@')) {
              setMode({ kind: 'list' })
              return
            }
            setMode({ kind: 'new-tier', email: v })
          }}
        />
      </Box>
    )
  }

  if (mode.kind === 'new-tier') {
    return (
      <Box flexDirection="column">
        <Text>
          Initial tier for <Text color="cyan">{mode.email}</Text>:
        </Text>
        <TierSelect
          onSelect={async (tier: Tier) => {
            try {
              setStatus(`creating ${mode.email}…`)
              await api.createUser(mode.email, tier)
              setStatus(`created ${mode.email} (${tier})`)
              setMode({ kind: 'list' })
              refresh()
            } catch (e) {
              setError(String((e as Error).message))
              setMode({ kind: 'list' })
            }
          }}
        />
      </Box>
    )
  }

  if (mode.kind === 'delete') {
    return (
      <Confirm
        prompt={`Delete ${mode.user.email}? This drops their CouchDB user, personal DB, and tier key.`}
        expectedAnswer={mode.user.email}
        onCancel={() => setMode({ kind: 'list' })}
        onConfirm={async () => {
          try {
            setStatus(`deleting ${mode.user.email}…`)
            await api.deleteUser(mode.user.email)
            setStatus(`deleted ${mode.user.email}`)
            setMode({ kind: 'list' })
            refresh()
          } catch (e) {
            setError(String((e as Error).message))
            setMode({ kind: 'list' })
          }
        }}
      />
    )
  }

  if (users === null) {
    return (
      <Text>
        <Spinner /> loading
      </Text>
    )
  }

  if (filtered.length === 0) {
    return <Text color="gray">no users</Text>
  }

  return (
    <Box flexDirection="column">
      {filter && (
        <Text color="gray">
          filter: <Text color="white">{filter}</Text>  (press / to edit)
        </Text>
      )}
      {filtered.slice(0, 30).map((u, i) => (
        <Text key={u.email}>
          {i === cursor ? '› ' : '  '}
          {truncate(u.email, 48).padEnd(48)} {tierColor(u.tier)}
        </Text>
      ))}
      {filtered.length > 30 && (
        <Text color="gray">… {filtered.length - 30} more</Text>
      )}
    </Box>
  )
}
