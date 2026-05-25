import { Box, Text, useInput } from 'ink'
import Spinner from 'ink-spinner'
import TextInput from 'ink-text-input'
import React, { useEffect, useState } from 'react'

import { NotificationDevice, NotificationUser, api } from '../api.js'
import { truncate } from '../util/format.js'

type Props = {
  setError: (e: string | null) => void
  setStatus: (s: string) => void
}

type Mode =
  | { kind: 'menu' }
  | { kind: 'test-push-email' }
  | { kind: 'test-push-loading'; email: string }
  | { kind: 'test-push-result'; email: string; result: string; ok: boolean }
  | { kind: 'list-loading' }
  | { kind: 'list'; users: NotificationUser[] }
  | { kind: 'detail'; device: NotificationDevice; email: string; users: NotificationUser[]; cursor: number }

const MENU_ITEMS = [
  { label: 'Test push (prompt for email)', value: 'test-push' },
  { label: 'List subscribers', value: 'list' },
]

const tierColor = (tier: string): 'green' | 'yellow' | 'gray' => {
  if (tier === 'osprey') return 'green'
  if (tier === 'trailblazer') return 'yellow'
  return 'gray'
}

export const NotificationsList: React.FC<Props> = ({ setError, setStatus }) => {
  const [mode, setMode] = useState<Mode>({ kind: 'menu' })
  const [menuCursor, setMenuCursor] = useState(0)
  const [email, setEmail] = useState('')

  // Fetch the subscriber list when entering list mode.
  useEffect(() => {
    if (mode.kind !== 'list-loading') return
    let cancelled = false
    api
      .listNotificationUsers()
      .then((r) => {
        if (cancelled) return
        setStatus(`${r.users.length} subscriber${r.users.length === 1 ? '' : 's'}`)
        setError(null)
        setMode({ kind: 'list', users: r.users })
      })
      .catch((e) => {
        if (cancelled) return
        setError(String((e as Error).message))
        setMode({ kind: 'menu' })
      })
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode.kind])

  // Fire the test-push call when entering test-push-loading mode.
  useEffect(() => {
    if (mode.kind !== 'test-push-loading') return
    let cancelled = false
    const { email: target } = mode
    api
      .testPush(target)
      .then((r) => {
        if (cancelled) return
        const ok = r.ok === true
        const result = ok
          ? `sent to ${r.sent} device${(r.sent ?? 0) === 1 ? '' : 's'}`
          : `failed: ${r.reason ?? 'unknown'}`
        setStatus(ok ? `test push sent — ${result}` : `test push failed`)
        setMode({ kind: 'test-push-result', email: target, ok, result })
      })
      .catch((e) => {
        if (cancelled) return
        const msg = String((e as Error).message)
        setError(msg)
        setMode({ kind: 'test-push-result', email: target, ok: false, result: msg })
      })
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode.kind])

  useInput((_input, key) => {
    // Menu navigation.
    if (mode.kind === 'menu') {
      if (key.upArrow) setMenuCursor((c) => Math.max(0, c - 1))
      if (key.downArrow) setMenuCursor((c) => Math.min(MENU_ITEMS.length - 1, c + 1))
      if (key.return) {
        const selected = MENU_ITEMS[menuCursor].value
        if (selected === 'test-push') {
          setEmail('')
          setMode({ kind: 'test-push-email' })
        } else {
          setMode({ kind: 'list-loading' })
        }
      }
    }

    // Back from test-push result to menu.
    if (mode.kind === 'test-push-result') {
      if (key.escape || key.return) {
        setMode({ kind: 'menu' })
        setError(null)
      }
    }

    // List navigation + drill-in.
    if (mode.kind === 'list') {
      const { users } = mode
      if (key.escape) setMode({ kind: 'menu' })
      if (users.length === 0) return
    }

    // Back from device detail to list.
    if (mode.kind === 'detail') {
      const { users, cursor } = mode
      if (key.escape) setMode({ kind: 'list', users })
      if (key.return) setMode({ kind: 'list', users })
      void cursor
    }
  })

  // ----- menu -----
  if (mode.kind === 'menu') {
    return (
      <Box flexDirection="column">
        <Text color="gray">Notifications — choose an action:</Text>
        <Box marginTop={1} flexDirection="column">
          {MENU_ITEMS.map((item, i) => (
            <Text key={item.value}>
              {i === menuCursor ? '› ' : '  '}
              {item.label}
            </Text>
          ))}
        </Box>
      </Box>
    )
  }

  // ----- test-push: email prompt -----
  if (mode.kind === 'test-push-email') {
    return (
      <Box flexDirection="column">
        <Text>Email to test push:</Text>
        <TextInput
          value={email}
          onChange={setEmail}
          onSubmit={(v) => {
            if (!v.includes('@')) {
              setMode({ kind: 'menu' })
              return
            }
            setMode({ kind: 'test-push-loading', email: v })
          }}
        />
        <Text color="gray">[ esc ] cancel</Text>
      </Box>
    )
  }

  // ----- test-push: loading -----
  if (mode.kind === 'test-push-loading') {
    return (
      <Text>
        <Spinner /> Sending test push to {mode.email}…
      </Text>
    )
  }

  // ----- test-push: result -----
  if (mode.kind === 'test-push-result') {
    return (
      <Box flexDirection="column">
        <Text>
          Test push to <Text color="cyan">{mode.email}</Text>:{' '}
          <Text color={mode.ok ? 'green' : 'red'}>{mode.result}</Text>
        </Text>
        <Text color="gray">[ enter / esc ] back</Text>
      </Box>
    )
  }

  // ----- list: loading -----
  if (mode.kind === 'list-loading') {
    return (
      <Text>
        <Spinner /> loading subscribers…
      </Text>
    )
  }

  // ----- list: subscriber list -----
  if (mode.kind === 'list') {
    const { users } = mode

    if (users.length === 0) {
      return (
        <Box flexDirection="column">
          <Text color="gray">no push subscribers</Text>
          <Text color="gray">[ esc ] back</Text>
        </Box>
      )
    }

    return <UserList users={users} onBack={() => setMode({ kind: 'menu' })} />
  }

  // ----- detail: per-device info -----
  if (mode.kind === 'detail') {
    const { device, email: detailEmail } = mode
    const endpointSuffix = device.endpoint.slice(-20)
    return (
      <Box flexDirection="column">
        <Text>
          <Text color="cyan">{detailEmail}</Text> — device detail
        </Text>
        <Box marginTop={1} flexDirection="column">
          <Text>
            endpoint:{' '}
            <Text color="gray">…{endpointSuffix}</Text>
          </Text>
          <Text>
            createdAt: <Text color="gray">{device.createdAt}</Text>
          </Text>
          <Text>
            weeklyScanReminder:{' '}
            <Text color={device.prefs.weeklyScanReminder ? 'green' : 'red'}>
              {device.prefs.weeklyScanReminder ? 'on' : 'off'}
            </Text>
          </Text>
        </Box>
        <Box marginTop={1}>
          <Text color="gray">[ esc / enter ] back to list</Text>
        </Box>
      </Box>
    )
  }

  return null
}

// ----- internal sub-component for the scrollable user list -----

type UserListProps = {
  onBack: () => void
  users: NotificationUser[]
}

const UserList: React.FC<UserListProps> = ({ onBack, users }) => {
  const [cursor, setCursor] = useState(0)
  const [deviceCursor, setDeviceCursor] = useState(0)
  const [mode, setMode] = useState<'users' | 'devices' | 'detail'>('users')
  const [selectedUser, setSelectedUser] = useState<NotificationUser | null>(null)

  useInput((_input, key) => {
    if (mode === 'users') {
      if (key.upArrow) setCursor((c) => Math.max(0, c - 1))
      if (key.downArrow) setCursor((c) => Math.min(users.length - 1, c + 1))
      if (key.escape) onBack()
      if (key.return) {
        setSelectedUser(users[cursor])
        setDeviceCursor(0)
        setMode('devices')
      }
    }

    if (mode === 'devices' && selectedUser) {
      if (key.upArrow) setDeviceCursor((c) => Math.max(0, c - 1))
      if (key.downArrow)
        setDeviceCursor((c) =>
          Math.min(selectedUser.devices.length - 1, c + 1),
        )
      if (key.escape) setMode('users')
      if (key.return) setMode('detail')
    }

    if (mode === 'detail') {
      if (key.escape || key.return) setMode('devices')
    }
  })

  if (mode === 'users') {
    return (
      <Box flexDirection="column">
        <Text color="gray">
          {users.length} subscriber{users.length === 1 ? '' : 's'}{' '}
          &nbsp;&nbsp;[ enter ] select · [ esc ] back
        </Text>
        {users.slice(0, 30).map((u, i) => (
          <Text key={u.email}>
            {i === cursor ? '› ' : '  '}
            {truncate(u.email, 36).padEnd(36)}{' '}
            <Text color="gray">
              {u.devices.length} dev{u.devices.length === 1 ? '' : 's'}
            </Text>{' '}
            <Text color={tierColor(u.tier)}>{u.tier}</Text>
          </Text>
        ))}
      </Box>
    )
  }

  if (mode === 'devices' && selectedUser) {
    return (
      <Box flexDirection="column">
        <Text>
          <Text color="cyan">{selectedUser.email}</Text>{' '}
          <Text color={tierColor(selectedUser.tier)}>({selectedUser.tier})</Text>
          {' — '}
          {selectedUser.devices.length} device{selectedUser.devices.length === 1 ? '' : 's'}
        </Text>
        <Box marginTop={1} flexDirection="column">
          {selectedUser.devices.map((d, i) => (
            <Text key={d.endpoint}>
              {i === deviceCursor ? '› ' : '  '}
              <Text color="gray">…{d.endpoint.slice(-20)}</Text>{' '}
              <Text color={d.prefs.weeklyScanReminder ? 'green' : 'red'}>
                {d.prefs.weeklyScanReminder ? 'reminder:on' : 'reminder:off'}
              </Text>
            </Text>
          ))}
        </Box>
        <Box marginTop={1}>
          <Text color="gray">[ enter ] detail · [ esc ] back</Text>
        </Box>
      </Box>
    )
  }

  if (mode === 'detail' && selectedUser) {
    const device = selectedUser.devices[deviceCursor]
    if (!device) return null
    return (
      <Box flexDirection="column">
        <Text>
          <Text color="cyan">{selectedUser.email}</Text> — device detail
        </Text>
        <Box marginTop={1} flexDirection="column">
          <Text>
            endpoint: <Text color="gray">…{device.endpoint.slice(-20)}</Text>
          </Text>
          <Text>
            createdAt: <Text color="gray">{device.createdAt}</Text>
          </Text>
          <Text>
            weeklyScanReminder:{' '}
            <Text color={device.prefs.weeklyScanReminder ? 'green' : 'red'}>
              {device.prefs.weeklyScanReminder ? 'on' : 'off'}
            </Text>
          </Text>
        </Box>
        <Box marginTop={1}>
          <Text color="gray">[ esc / enter ] back</Text>
        </Box>
      </Box>
    )
  }

  return null
}
