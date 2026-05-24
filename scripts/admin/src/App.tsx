import { Text, useApp, useInput } from 'ink'
import React, { useState } from 'react'

import { Layout } from './components/Layout.js'
import { DbsList } from './components/DbsList.js'
import { DocBrowser } from './components/DocBrowser.js'
import { SeedScreen } from './components/SeedScreen.js'
import { SharedTripsList } from './components/SharedTripsList.js'
import { UserDetail } from './components/UserDetail.js'
import { UsersList } from './components/UsersList.js'

type Section = 'users' | 'dbs' | 'sharedtrips' | 'seed'

type View =
  | { kind: 'users' }
  | { kind: 'user-detail'; email: string }
  | { kind: 'dbs' }
  | { kind: 'doc-browser'; db: string; from: Section }
  | { kind: 'sharedtrips' }
  | { kind: 'seed' }

const sectionFor = (view: View): Section => {
  if (view.kind === 'users' || view.kind === 'user-detail') return 'users'
  if (view.kind === 'dbs') return 'dbs'
  if (view.kind === 'sharedtrips') return 'sharedtrips'
  if (view.kind === 'seed') return 'seed'
  return view.from
}

const baseHints = '↑↓ navigate · enter select · esc back · q quit'

export const App: React.FC = () => {
  const { exit } = useApp()
  const [view, setView] = useState<View>({ kind: 'users' })
  const [status, setStatus] = useState<string>('ready')
  const [error, setError] = useState<string | null>(null)

  useInput((input, key) => {
    if (input === 'q' || (key.ctrl && input === 'c')) exit()
    if (key.tab) {
      const order: Section[] = ['users', 'dbs', 'sharedtrips', 'seed']
      const cur = sectionFor(view)
      const next = order[(order.indexOf(cur) + 1) % order.length]
      setView({ kind: next as any })
    }
  })

  let content: React.ReactNode = null
  let hints = baseHints

  if (view.kind === 'users') {
    hints = `${baseHints} · t tier · n new · d delete · / filter · r refresh · tab switch`
    content = (
      <UsersList
        onPick={(email) => setView({ kind: 'user-detail', email })}
        setStatus={setStatus}
        setError={setError}
      />
    )
  } else if (view.kind === 'user-detail') {
    hints = `${baseHints} · t tier · s seed data`
    content = (
      <UserDetail
        email={view.email}
        onBack={() => setView({ kind: 'users' })}
        onBrowse={(db) =>
          setView({ kind: 'doc-browser', db, from: 'users' })
        }
        setStatus={setStatus}
        setError={setError}
      />
    )
  } else if (view.kind === 'dbs') {
    hints = `${baseHints} · / filter · r refresh · tab switch`
    content = (
      <DbsList
        onPick={(db) => setView({ kind: 'doc-browser', db, from: 'dbs' })}
        setStatus={setStatus}
        setError={setError}
      />
    )
  } else if (view.kind === 'doc-browser') {
    hints = `${baseHints} · e edit · v void · d hard-delete · / filter · r refresh`
    content = (
      <DocBrowser
        db={view.db}
        onBack={() => {
          if (view.from === 'dbs') setView({ kind: 'dbs' })
          else setView({ kind: 'users' })
        }}
        setStatus={setStatus}
        setError={setError}
      />
    )
  } else if (view.kind === 'sharedtrips') {
    hints = `${baseHints} · r refresh · tab switch`
    content = (
      <SharedTripsList
        onPick={(db) => setView({ kind: 'doc-browser', db, from: 'sharedtrips' })}
        setStatus={setStatus}
        setError={setError}
      />
    )
  } else if (view.kind === 'seed') {
    hints = `${baseHints} · enter create · tab switch`
    content = <SeedScreen setStatus={setStatus} setError={setError} />
  }

  return (
    <Layout
      section={sectionFor(view)}
      hints={hints}
      status={status}
      error={error}
    >
      {content || <Text>—</Text>}
    </Layout>
  )
}
