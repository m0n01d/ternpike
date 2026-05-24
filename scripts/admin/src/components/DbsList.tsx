import { Box, Text, useInput } from 'ink'
import Spinner from 'ink-spinner'
import TextInput from 'ink-text-input'
import React, { useEffect, useState } from 'react'

import { Db, api } from '../api.js'
import { formatBytes, truncate } from '../util/format.js'

type Props = {
  onPick: (db: string) => void
  setStatus: (s: string) => void
  setError: (e: string | null) => void
}

export const DbsList: React.FC<Props> = ({ onPick, setStatus, setError }) => {
  const [dbs, setDbs] = useState<Db[] | null>(null)
  const [cursor, setCursor] = useState(0)
  const [filter, setFilter] = useState('')
  const [filterMode, setFilterMode] = useState(false)

  const refresh = async () => {
    try {
      setStatus('loading dbs…')
      const r = await api.listDbs()
      setDbs(r.dbs)
      setError(null)
      setStatus(`${r.dbs.length} dbs`)
    } catch (e) {
      setError(String((e as Error).message))
      setDbs([])
    }
  }

  useEffect(() => {
    refresh()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const filtered = (dbs || []).filter((d) =>
    d.name.toLowerCase().includes(filter.toLowerCase()),
  )

  useInput((input, key) => {
    if (filterMode) return
    if (key.upArrow) setCursor((c) => Math.max(0, c - 1))
    if (key.downArrow) setCursor((c) => Math.min(filtered.length - 1, c + 1))
    if (key.return && filtered[cursor]) onPick(filtered[cursor].name)
    if (input === '/') setFilterMode(true)
    if (input === 'r') refresh()
  })

  if (filterMode) {
    return (
      <Box>
        <Text>filter: </Text>
        <TextInput
          value={filter}
          onChange={setFilter}
          onSubmit={() => setFilterMode(false)}
        />
      </Box>
    )
  }

  if (dbs === null) {
    return (
      <Text>
        <Spinner /> loading
      </Text>
    )
  }

  if (filtered.length === 0) {
    return <Text color="gray">no databases</Text>
  }

  return (
    <Box flexDirection="column">
      <Text color="gray">
        {filtered.length} dbs   [ Enter ] browse · [ / ] filter · [ r ] refresh
      </Text>
      <Box marginTop={1}>
        <Text color="cyan" bold>
          {'  '}{'name'.padEnd(48)}{'docs'.padStart(8)}{'  '}{'size'.padStart(10)}
        </Text>
      </Box>
      {filtered.slice(0, 30).map((d, i) => (
        <Text key={d.name}>
          {i === cursor ? '› ' : '  '}
          {truncate(d.name, 48).padEnd(48)}
          {String(d.docCount ?? '—').padStart(8)}
          {'  '}
          {formatBytes(d.sizeBytes).padStart(10)}
        </Text>
      ))}
      {filtered.length > 30 && (
        <Text color="gray">… {filtered.length - 30} more</Text>
      )}
    </Box>
  )
}
