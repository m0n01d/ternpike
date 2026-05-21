import { spawn, spawnSync } from 'node:child_process'

const CONTAINER_NAME = 'ternpike-e2e-couch'
const IMAGE = 'couchdb:3.3'

export type CouchHandle = {
  admin: CouchClient
  containerId: string
  password: string
  port: number
  stop: () => Promise<void>
  url: string
  user: string
}

export type CouchClient = {
  allDbs: () => Promise<string[]>
  request: (path: string, init?: RequestInit) => Promise<Response>
  url: string
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

const detectPort = (containerId: string): number => {
  const out = spawnSync('docker', ['port', containerId, '5984/tcp'], {
    encoding: 'utf8',
  })
  if (out.status !== 0) {
    throw new Error(`docker port failed: ${out.stderr}`)
  }
  const match = out.stdout.match(/0\.0\.0\.0:(\d+)/)
  if (!match) throw new Error(`could not parse docker port output: ${out.stdout}`)
  return Number(match[1])
}

const waitForCouch = async (url: string, auth: string, timeoutMs = 60_000) => {
  const start = Date.now()
  let lastErr: unknown = null
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`${url}/_up`, {
        headers: { Authorization: auth },
      })
      if (res.ok) return
    } catch (err) {
      lastErr = err
    }
    await sleep(500)
  }
  throw new Error(`CouchDB did not become ready within ${timeoutMs}ms: ${String(lastErr)}`)
}

const makeClient = (url: string, auth: string): CouchClient => {
  const request: CouchClient['request'] = (path, init = {}) =>
    fetch(`${url}${path}`, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        Authorization: auth,
        ...(init.headers || {}),
      },
    })
  return {
    url,
    request,
    allDbs: async () => {
      const res = await request('/_all_dbs')
      if (!res.ok) {
        throw new Error(`/_all_dbs failed: ${res.status} ${await res.text()}`)
      }
      return (await res.json()) as string[]
    },
  }
}

export const startCouch = async (): Promise<CouchHandle> => {
  // Best-effort: remove any leftover container from a previous crashed run.
  spawnSync('docker', ['rm', '-f', CONTAINER_NAME], { stdio: 'ignore' })

  const user = 'admin'
  const password = 'e2e-password'
  const run = spawnSync(
    'docker',
    [
      'run',
      '-d',
      '--rm',
      '--name',
      CONTAINER_NAME,
      '-p',
      '0:5984',
      '-e',
      `COUCHDB_USER=${user}`,
      '-e',
      `COUCHDB_PASSWORD=${password}`,
      IMAGE,
    ],
    { encoding: 'utf8' },
  )
  if (run.status !== 0) {
    throw new Error(`docker run couchdb failed: ${run.stderr}`)
  }
  const containerId = run.stdout.trim()
  const port = detectPort(containerId)
  const url = `http://127.0.0.1:${port}`
  const auth = 'Basic ' + Buffer.from(`${user}:${password}`).toString('base64')

  await waitForCouch(url, auth)

  // Single-node CouchDB needs the system databases created explicitly.
  const setup = async (db: string) => {
    const res = await fetch(`${url}/${db}`, {
      method: 'PUT',
      headers: { Authorization: auth },
    })
    if (!res.ok && res.status !== 412) {
      throw new Error(`failed to create ${db}: ${res.status} ${await res.text()}`)
    }
  }
  await setup('_users')
  await setup('_replicator')

  const admin = makeClient(url, auth)
  return {
    admin,
    containerId,
    password,
    port,
    stop: async () => {
      spawnSync('docker', ['rm', '-f', containerId], { stdio: 'ignore' })
    },
    url,
    user,
  }
}

// Detach-safe runner used when launching auxiliary processes that should die
// with the parent. Not used directly here but kept available for future
// fixtures that boot more services.
export const spawnDetached = (cmd: string, args: string[]) =>
  spawn(cmd, args, { detached: false, stdio: 'inherit' })
