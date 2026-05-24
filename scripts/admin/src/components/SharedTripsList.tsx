import { Box, Text, useInput } from 'ink'
import Spinner from 'ink-spinner'
import React, { useEffect, useState } from 'react'

import { SharedTrip, api } from '../api.js'
import { truncate } from '../util/format.js'

type Props = {
  onPick: (db: string) => void
  setStatus: (s: string) => void
  setError: (e: string | null) => void
}

const statusColor = (s: string): 'green' | 'yellow' | 'red' | 'gray' => {
  if (s === 'active') return 'green'
  if (s === 'grace') return 'yellow'
  if (s === 'frozen') return 'red'
  return 'gray'
}

export const SharedTripsList: React.FC<Props> = ({
  onPick,
  setStatus,
  setError,
}) => {
  const [trips, setTrips] = useState<SharedTrip[] | null>(null)
  const [cursor, setCursor] = useState(0)

  const refresh = async () => {
    try {
      setStatus('loading shared trips…')
      const r = await api.listSharedTrips()
      setTrips(r.sharedTrips)
      setError(null)
      setStatus(`${r.sharedTrips.length} shared trips`)
    } catch (e) {
      setError(String((e as Error).message))
      setTrips([])
    }
  }

  useEffect(() => {
    refresh()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useInput((input, key) => {
    if (key.upArrow) setCursor((c) => Math.max(0, c - 1))
    if (key.downArrow) setCursor((c) => Math.min((trips?.length || 1) - 1, c + 1))
    if (key.return && trips && trips[cursor]) onPick(trips[cursor].dbName)
    if (input === 'r') refresh()
  })

  if (trips === null) {
    return (
      <Text>
        <Spinner /> loading
      </Text>
    )
  }

  if (trips.length === 0) {
    return <Text color="gray">no shared trips</Text>
  }

  return (
    <Box flexDirection="column">
      <Text color="gray">
        {trips.length} shared trips   [ Enter ] browse · [ r ] refresh
      </Text>
      {trips.slice(0, 30).map((t, i) => (
        <Text key={t.dbName}>
          {i === cursor ? '› ' : '  '}
          {truncate(t.name || t.dbName, 28).padEnd(28)}{' '}
          <Text color={statusColor(t.billingStatus)}>
            {(t.billingStatus || '?').padEnd(7)}
          </Text>{' '}
          <Text color="gray">{truncate(t.billingOwner || '', 30).padEnd(30)}</Text>{' '}
          <Text color="gray">{t.members?.length || 0} mbrs</Text>
        </Text>
      ))}
    </Box>
  )
}
