// Spin up a disposable couchdb:3 via `docker run`. Returns admin client
// helpers and a stop function. We shell out to docker directly instead of
// pulling in `testcontainers` because the dependency is heavy (~MBs of
// transitive deps, including dockerode) and our needs are trivial: one
// container, one health check, one teardown.

import { execFile, spawn } from 'node:child_process'
import { promisify } from 'node:util'
import { setTimeout as sleep } from 'node:timers/promises'

const execFileP = promisify(execFile)

const IMAGE = 'couchdb:3'
const ADMIN_USER = 'admin'
const ADMIN_PASS = 'testpass'

const randomPort = () => 20000 + Math.floor(Math.random() * 20000)
const randomName = () =>
  `ternpike-test-couch-${Date.now()}-${Math.floor(Math.random() * 1e6)}`

export async function startCouch({ maxAttempts = 60 } = {}) {
  const port = randomPort()
  const name = randomName()

  const args = [
    'run',
    '-d',
    '--rm',
    '--name',
    name,
    '-p',
    `${port}:5984`,
    '-e',
    `COUCHDB_USER=${ADMIN_USER}`,
    '-e',
    `COUCHDB_PASSWORD=${ADMIN_PASS}`,
    IMAGE,
  ]
  const { stdout } = await execFileP('docker', args)
  const containerId = stdout.trim()

  const baseUrl = `http://127.0.0.1:${port}`
  const adminAuth =
    'Basic ' + Buffer.from(`${ADMIN_USER}:${ADMIN_PASS}`).toString('base64')

  await waitForUp(baseUrl, adminAuth, maxAttempts)
  await ensureSystemDbs(baseUrl, adminAuth)

  return {
    baseUrl,
    adminUser: ADMIN_USER,
    adminPass: ADMIN_PASS,
    containerId,
    name,
    stop: async () => {
      try {
        await execFileP('docker', ['stop', name])
      } catch {
        // best effort — container may already be gone
      }
    },
  }
}

async function waitForUp(baseUrl, adminAuth, maxAttempts) {
  let lastErr
  for (let i = 0; i < maxAttempts; i++) {
    try {
      const r = await fetch(`${baseUrl}/_up`, {
        headers: { Authorization: adminAuth },
      })
      if (r.ok) {
        const body = await r.json()
        if (body.status === 'ok') return
      }
    } catch (err) {
      lastErr = err
    }
    await sleep(500)
  }
  throw new Error(
    `couchdb did not become ready in ${maxAttempts * 500}ms: ${lastErr}`,
  )
}

async function ensureSystemDbs(baseUrl, adminAuth) {
  for (const db of ['_users', '_replicator', '_global_changes']) {
    const r = await fetch(`${baseUrl}/${db}`, {
      method: 'PUT',
      headers: { Authorization: adminAuth },
    })
    if (!r.ok && r.status !== 412) {
      throw new Error(`system db PUT ${db} ${r.status}`)
    }
  }
}

export function couchAdminFetch(couch, path, init = {}) {
  const auth =
    'Basic ' +
    Buffer.from(`${couch.adminUser}:${couch.adminPass}`).toString('base64')
  return fetch(`${couch.baseUrl}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: auth,
      ...(init.headers || {}),
    },
  })
}

// Hit CouchDB directly authenticated as a real seeded user — this exercises
// `validate_doc_update` because admin writes bypass it. Caller provides the
// already-derived password (see `fixtures/auth.js#derivePassword`).
export function couchUserFetch(couch, email, password, path, init = {}) {
  const auth = 'Basic ' + Buffer.from(`${email}:${password}`).toString('base64')
  return fetch(`${couch.baseUrl}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: auth,
      ...(init.headers || {}),
    },
  })
}
