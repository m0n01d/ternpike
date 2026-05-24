import { Box, Text, useApp, useInput } from 'ink'
import Spinner from 'ink-spinner'
import TextInput from 'ink-text-input'
import React, { useEffect, useState } from 'react'

import { Doc, api } from '../api.js'
import { editJson } from '../util/editor.js'
import { truncate } from '../util/format.js'
import { Confirm } from './Confirm.js'

type Props = {
  db: string
  onBack: () => void
  setStatus: (s: string) => void
  setError: (e: string | null) => void
}

type Mode =
  | { kind: 'list' }
  | { kind: 'filter' }
  | { kind: 'preview'; doc: Doc }
  | { kind: 'void'; doc: Doc }
  | { kind: 'delete'; doc: Doc }

const summary = (d: Doc): string => {
  const date = (d as any).date || (d as any).createdAt || ''
  const type = (d as any).type || ''
  const name = (d as any).name || (d as any).merchant || (d as any).amount || ''
  return [type, name, date].filter(Boolean).join(' · ')
}

export const DocBrowser: React.FC<Props> = ({
  db,
  onBack,
  setStatus,
  setError,
}) => {
  const { exit: _exit } = useApp()
  const [docs, setDocs] = useState<Doc[] | null>(null)
  const [cursor, setCursor] = useState(0)
  const [filter, setFilter] = useState('')
  const [mode, setMode] = useState<Mode>({ kind: 'list' })

  const refresh = async () => {
    try {
      setStatus(`loading ${db}…`)
      const r = await api.listDocs(db, { prefix: filter, limit: 200 })
      setDocs(r.docs)
      setError(null)
      setStatus(`${db}: ${r.docs.length} docs${r.total ? ` of ${r.total}` : ''}`)
    } catch (e) {
      setError(String((e as Error).message))
      setDocs([])
    }
  }

  useEffect(() => {
    refresh()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [db, filter])

  useInput(async (input, key) => {
    if (mode.kind !== 'list') return
    if (key.escape) onBack()
    if (key.upArrow) setCursor((c) => Math.max(0, c - 1))
    if (key.downArrow) setCursor((c) => Math.min((docs?.length || 1) - 1, c + 1))
    if ((key.return || input === 'p') && docs && docs[cursor]) {
      setMode({ kind: 'preview', doc: docs[cursor] })
    }
    if (input === '/') setMode({ kind: 'filter' })
    if (input === 'r') refresh()
    if (input === 'e' && docs && docs[cursor]) {
      await editFlow(docs[cursor])
    }
    if (input === 'v' && docs && docs[cursor]) {
      setMode({ kind: 'void', doc: docs[cursor] })
    }
    if (input === 'd' && docs && docs[cursor]) {
      setMode({ kind: 'delete', doc: docs[cursor] })
    }
  })

  const editFlow = async (doc: Doc) => {
    try {
      setStatus(`editing ${doc._id}…`)
      const edited = (await editJson(doc, 'doc')) as Doc
      if (edited._id !== doc._id) {
        setError('_id changed in editor — refusing to write')
        return
      }
      if (edited._rev !== doc._rev) {
        setError('_rev changed in editor — refusing to write')
        return
      }
      const r = await api.putDoc(db, doc._id, edited)
      setStatus(`saved ${doc._id} → rev ${r.rev}`)
      setError(null)
      refresh()
    } catch (e) {
      setError(String((e as Error).message))
    }
  }

  if (mode.kind === 'filter') {
    return (
      <Box>
        <Text>id prefix: </Text>
        <TextInput
          value={filter}
          onChange={setFilter}
          onSubmit={() => setMode({ kind: 'list' })}
        />
      </Box>
    )
  }

  if (mode.kind === 'preview') {
    return (
      <PreviewDoc
        doc={mode.doc}
        onBack={() => setMode({ kind: 'list' })}
        onEdit={() => editFlow(mode.doc).then(() => setMode({ kind: 'list' }))}
      />
    )
  }

  if (mode.kind === 'void') {
    return (
      <Confirm
        prompt={`Void ${mode.doc._id}? Writes a soft-delete tombstone (void::…::del).`}
        onCancel={() => setMode({ kind: 'list' })}
        onConfirm={async () => {
          try {
            const r = await api.voidDoc(db, mode.doc._id)
            setStatus(`voided → ${r.voidId}`)
            setError(null)
          } catch (e) {
            setError(String((e as Error).message))
          }
          setMode({ kind: 'list' })
          refresh()
        }}
      />
    )
  }

  if (mode.kind === 'delete') {
    return (
      <Confirm
        prompt={`HARD delete ${mode.doc._id}? Skips the tombstone — sync may resurrect via conflict.`}
        expectedAnswer="delete"
        onCancel={() => setMode({ kind: 'list' })}
        onConfirm={async () => {
          try {
            await api.deleteDoc(db, mode.doc._id, mode.doc._rev || '')
            setStatus(`deleted ${mode.doc._id}`)
            setError(null)
          } catch (e) {
            setError(String((e as Error).message))
          }
          setMode({ kind: 'list' })
          refresh()
        }}
      />
    )
  }

  if (docs === null) {
    return (
      <Text>
        <Spinner /> loading
      </Text>
    )
  }

  if (docs.length === 0) {
    return (
      <Box flexDirection="column">
        <Text color="gray">no docs (prefix: "{filter}")</Text>
        <Text color="gray">[ / ] filter · [ Esc ] back</Text>
      </Box>
    )
  }

  return (
    <Box flexDirection="column">
      <Text color="gray">
        {db}{filter ? `   prefix: ${filter}` : ''}
      </Text>
      {docs.slice(0, 30).map((d, i) => (
        <Text key={d._id}>
          {i === cursor ? '› ' : '  '}
          {truncate(d._id, 50).padEnd(50)} {summary(d)}
        </Text>
      ))}
      {docs.length > 30 && (
        <Text color="gray">… {docs.length - 30} more (use filter)</Text>
      )}
    </Box>
  )
}

const PreviewDoc: React.FC<{
  doc: Doc
  onBack: () => void
  onEdit: () => void
}> = ({ doc, onBack, onEdit }) => {
  useInput((input, key) => {
    if (key.escape) onBack()
    if (input === 'e') onEdit()
  })
  const json = JSON.stringify(doc, null, 2)
  const lines = json.split('\n').slice(0, 40)
  return (
    <Box flexDirection="column">
      <Text color="cyan">{doc._id}</Text>
      {lines.map((l, i) => (
        <Text key={i} color="white">
          {l}
        </Text>
      ))}
      {json.split('\n').length > 40 && (
        <Text color="gray">… (truncated; use e to open in $EDITOR)</Text>
      )}
      <Box marginTop={1}>
        <Text color="gray">[ e ] edit in $EDITOR · [ Esc ] back</Text>
      </Box>
    </Box>
  )
}
