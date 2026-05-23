import { spawn, type ChildProcess } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

import { startCouch, type CouchHandle } from './utils/couch'
import { startResendMock, type ResendMockHandle } from './utils/resend'
import { writeHarnessState } from './utils/state'

const ROOT = resolve(__dirname, '..')
const PIDFILE = resolve(ROOT, 'e2e/.state/processes.json')

type ProcessRecord = { name: string; pid: number }

const writePids = (records: ProcessRecord[]): void => {
  mkdirSync(dirname(PIDFILE), { recursive: true })
  writeFileSync(PIDFILE, JSON.stringify(records, null, 2))
}

const waitForHttp = async (
  url: string,
  label: string,
  timeoutMs = 60_000,
): Promise<void> => {
  const start = Date.now()
  let lastErr: unknown = null
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url)
      // Accept any response status — we just need the listener to answer.
      if (res.status >= 0) return
    } catch (err) {
      lastErr = err
    }
    await new Promise((r) => setTimeout(r, 500))
  }
  throw new Error(`${label} did not become ready at ${url} in ${timeoutMs}ms: ${String(lastErr)}`)
}

let viteProcess: ChildProcess | null = null
let wranglerProcess: ChildProcess | null = null
let couchHandle: CouchHandle | null = null
let resendHandle: ResendMockHandle | null = null

const spawnService = (
  name: string,
  cmd: string,
  args: string[],
  cwd: string,
  env: NodeJS.ProcessEnv,
): ChildProcess => {
  // detached:true puts the child in its own process group so we can kill the
  // entire tree (wrangler + workerd, vite + esbuild) with one signal in
  // teardown.
  const child = spawn(cmd, args, {
    cwd,
    detached: true,
    env,
    stdio: ['ignore', 'inherit', 'inherit'],
  })
  child.on('exit', (code, signal) => {
    if (code !== 0 && code !== null) {
      // eslint-disable-next-line no-console
      console.error(`[e2e] ${name} exited unexpectedly with code=${code} signal=${signal}`)
    }
  })
  return child
}

export default async function globalSetup(): Promise<void> {
  // eslint-disable-next-line no-console
  console.log('[e2e] starting harness …')

  resendHandle = await startResendMock()
  // eslint-disable-next-line no-console
  console.log(`[e2e] mock Resend  → ${resendHandle.baseUrl}`)

  couchHandle = await startCouch()
  // eslint-disable-next-line no-console
  console.log(`[e2e] CouchDB      → ${couchHandle.url}`)

  const serverSecret = 'e2e-server-secret'
  // Allow per-process port overrides via env so concurrent worktree
  // agents can share the host without colliding on port 3000 / 4000.
  // CI keeps the historical defaults.
  const wranglerPort = Number(process.env.E2E_AUTH_PORT || 4000)
  const vitePort = Number(process.env.E2E_VITE_PORT || 3000)

  wranglerProcess = spawnService(
    'wrangler',
    'npx',
    [
      'wrangler',
      'dev',
      '--port',
      String(wranglerPort),
      '--config',
      'wrangler.toml',
      '--var',
      `COUCH_URL:${couchHandle.url}`,
      '--var',
      `COUCH_ADMIN_USER:${couchHandle.user}`,
      '--var',
      `COUCH_ADMIN_PASS:${couchHandle.password}`,
      '--var',
      `SERVER_SECRET:${serverSecret}`,
      '--var',
      `RESEND_API_KEY:mock-key`,
      '--var',
      `RESEND_BASE_URL:${resendHandle.baseUrl}`,
      '--var',
      `TIER_WEBHOOK_SECRET:e2e-webhook-secret`,
      '--local',
    ],
    resolve(ROOT, 'server'),
    process.env,
  )

  viteProcess = spawnService(
    'vite',
    'npx',
    // Bind explicitly to 127.0.0.1: on Node 22 CI runners, `localhost`
    // resolves to `::1` first, vite preview ends up listening on IPv6
    // only, and `waitForHttp(http://127.0.0.1:…)` below can never connect.
    [
      'vite',
      'preview',
      '--port',
      String(vitePort),
      '--strictPort',
      '--host',
      '127.0.0.1',
    ],
    ROOT,
    process.env,
  )

  await waitForHttp(`http://127.0.0.1:${wranglerPort}/`, 'auth server')
  await waitForHttp(`http://127.0.0.1:${vitePort}/`, 'vite dev server')
  // eslint-disable-next-line no-console
  console.log(`[e2e] auth server  → http://127.0.0.1:${wranglerPort}`)
  // eslint-disable-next-line no-console
  console.log(`[e2e] vite         → http://127.0.0.1:${vitePort}`)

  writeHarnessState({
    couchAdminPassword: couchHandle.password,
    couchAdminUser: couchHandle.user,
    couchUrl: couchHandle.url,
    resendMockUrl: resendHandle.baseUrl,
    serverPort: wranglerPort,
    serverSecret,
    vitePort,
  })

  const records: ProcessRecord[] = []
  if (viteProcess.pid) records.push({ name: 'vite', pid: viteProcess.pid })
  if (wranglerProcess.pid) records.push({ name: 'wrangler', pid: wranglerProcess.pid })
  if (couchHandle.containerId) {
    records.push({ name: `couch:${couchHandle.containerId}`, pid: 0 })
  }
  writePids(records)
}
