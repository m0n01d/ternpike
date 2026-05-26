import { spawn } from 'node:child_process'
import { platform } from 'node:os'
import { Box, Text, useInput } from 'ink'
import Spinner from 'ink-spinner'
import TextInput from 'ink-text-input'
import React, { useEffect, useState } from 'react'

import { QR_TEMPLATES, QrSlug, QrTemplate, api, qrPrintUrl } from '../api.js'

type Props = {
  setError: (e: string | null) => void
  setStatus: (s: string) => void
}

type Mode =
  | { kind: 'loading' }
  | { kind: 'list'; cursor: number; slugs: QrSlug[]; template: QrTemplate }
  | { kind: 'new'; slugs: QrSlug[]; template: QrTemplate; value: string }
  | { kind: 'opened'; slugs: QrSlug[]; template: QrTemplate; url: string }

const SLUG_RE = /^[a-z0-9-]{1,32}$/

const openInBrowser = (url: string) => {
  const cmd =
    platform() === 'darwin'
      ? 'open'
      : platform() === 'win32'
        ? 'cmd'
        : 'xdg-open'
  const args = platform() === 'win32' ? ['/c', 'start', '""', url] : [url]
  const child = spawn(cmd, args, { detached: true, stdio: 'ignore' })
  child.unref()
}

const topN = (record: Record<string, number>, n: number): string => {
  const entries = Object.entries(record).sort((a, b) => b[1] - a[1])
  if (entries.length === 0) return '—'
  return entries
    .slice(0, n)
    .map(([k, v]) => `${k}:${v}`)
    .join(' ')
}

const dateOnly = (iso: string | null): string => {
  if (!iso) return '—'
  return iso.slice(0, 10)
}

export const QrList: React.FC<Props> = ({ setError, setStatus }) => {
  const [mode, setMode] = useState<Mode>({ kind: 'loading' })
  const [reloadTick, setReloadTick] = useState(0)

  useEffect(() => {
    if (mode.kind !== 'loading') return
    let cancelled = false
    api
      .listQrSlugs()
      .then((r) => {
        if (cancelled) return
        setStatus(`${r.slugs.length} slug${r.slugs.length === 1 ? '' : 's'}`)
        setError(null)
        setMode({
          cursor: 0,
          kind: 'list',
          slugs: r.slugs,
          template: 'trailhead',
        })
      })
      .catch((e) => {
        if (cancelled) return
        setError(String((e as Error).message))
        setMode({
          cursor: 0,
          kind: 'list',
          slugs: [],
          template: 'trailhead',
        })
      })
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode.kind, reloadTick])

  useInput((input, key) => {
    if (mode.kind === 'list') {
      const { cursor, slugs, template } = mode
      if (key.upArrow && slugs.length > 0) {
        setMode({ ...mode, cursor: Math.max(0, cursor - 1) })
      }
      if (key.downArrow && slugs.length > 0) {
        setMode({ ...mode, cursor: Math.min(slugs.length - 1, cursor + 1) })
      }
      if (input === 'r') {
        setMode({ kind: 'loading' })
        setReloadTick((t) => t + 1)
      }
      if (input === 't') {
        const i = QR_TEMPLATES.indexOf(template)
        const next = QR_TEMPLATES[(i + 1) % QR_TEMPLATES.length]
        setMode({ ...mode, template: next })
        setStatus(`template: ${next}`)
      }
      if (input === 'n') {
        setMode({ kind: 'new', slugs, template, value: '' })
      }
      if (input === 'p' && slugs.length > 0) {
        const slug = slugs[cursor].slug
        const url = qrPrintUrl([slug], template)
        openInBrowser(url)
        setStatus(`opened print page for ${slug}`)
        setMode({ kind: 'opened', slugs, template, url })
      }
      if (input === 'P' && slugs.length > 0) {
        // Shift-P: print all visible slugs as a batch.
        const all = slugs.map((s) => s.slug)
        const url = qrPrintUrl(all, template)
        openInBrowser(url)
        setStatus(`opened print page for ${all.length} slugs`)
        setMode({ kind: 'opened', slugs, template, url })
      }
    }
    if (mode.kind === 'opened') {
      if (key.return || key.escape) {
        setMode({
          cursor: 0,
          kind: 'list',
          slugs: mode.slugs,
          template: mode.template,
        })
      }
    }
    if (mode.kind === 'new' && key.escape) {
      setMode({
        cursor: 0,
        kind: 'list',
        slugs: mode.slugs,
        template: mode.template,
      })
    }
  })

  if (mode.kind === 'loading') {
    return (
      <Text>
        <Spinner /> loading QR slugs…
      </Text>
    )
  }

  if (mode.kind === 'new') {
    return (
      <Box flexDirection="column">
        <Text>
          New slug (template: <Text color="cyan">{mode.template}</Text>):
        </Text>
        <TextInput
          value={mode.value}
          onChange={(v) => setMode({ ...mode, value: v })}
          onSubmit={(v) => {
            const slug = v.toLowerCase().trim()
            if (!SLUG_RE.test(slug)) {
              setError('slug must match [a-z0-9-]{1,32}')
              return
            }
            const url = qrPrintUrl([slug], mode.template)
            openInBrowser(url)
            setStatus(`opened print page for ${slug} (first scan creates it)`)
            setError(null)
            setMode({
              kind: 'opened',
              slugs: mode.slugs,
              template: mode.template,
              url,
            })
          }}
        />
        <Text color="gray">
          [ enter ] open print page · [ esc ] cancel · pattern: [a-z0-9-]&#123;1,32&#125;
        </Text>
      </Box>
    )
  }

  if (mode.kind === 'opened') {
    return (
      <Box flexDirection="column">
        <Text color="green">opened in default browser:</Text>
        <Text color="gray">{mode.url}</Text>
        <Box marginTop={1}>
          <Text color="gray">
            [ enter / esc ] back · paste this URL into your phone to print from there
          </Text>
        </Box>
      </Box>
    )
  }

  // list mode
  const { cursor, slugs, template } = mode
  if (slugs.length === 0) {
    return (
      <Box flexDirection="column">
        <Text color="gray">no slugs yet — first scan creates one.</Text>
        <Text color="gray">[ n ] new · [ t ] template ({template}) · [ r ] refresh</Text>
      </Box>
    )
  }

  return (
    <Box flexDirection="column">
      <Text color="gray">
        {slugs.length} slug{slugs.length === 1 ? '' : 's'} · template:{' '}
        <Text color="cyan">{template}</Text>
      </Text>
      <Box marginTop={1} flexDirection="column">
        <Text color="gray">
          {'  '}
          {'slug'.padEnd(22)}
          {'count'.padStart(6)}
          {'  '}
          {'first'.padEnd(11)}
          {'last'.padEnd(11)}
          top regions
        </Text>
        {slugs.slice(0, 30).map((s, i) => (
          <Text key={s.slug}>
            {i === cursor ? '› ' : '  '}
            {s.slug.padEnd(22)}
            <Text color="yellow">{String(s.count).padStart(6)}</Text>
            {'  '}
            <Text color="gray">{dateOnly(s.firstAt).padEnd(11)}</Text>
            <Text color="gray">{dateOnly(s.lastAt).padEnd(11)}</Text>
            <Text color="green">{topN(s.byRegion, 3)}</Text>
          </Text>
        ))}
      </Box>
      <Box marginTop={1}>
        <Text color="gray">
          [ p ] print selected · [ shift-P ] print all · [ n ] new slug · [ t ]
          template · [ r ] refresh
        </Text>
      </Box>
    </Box>
  )
}
