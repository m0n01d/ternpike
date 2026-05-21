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

// CouchDB-direct fetch authenticated as a specific user (not admin). Mirrors
// the way the browser PouchDB client talks to CouchDB — Basic auth with the
// user's HMAC-derived password. Used by #66 to exercise `validate_doc_update`
// (admin writes bypass it) and by #70 to assert cross-tenant invisibility.
export function couchUserFetch(couch, email, password, path, init = {}) {
  const auth =
    'Basic ' + Buffer.from(`${email}:${password}`).toString('base64')
  return fetch(`${couch.baseUrl}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: auth,
      ...(init.headers || {}),
    },
  })
}

// Assert that `docId` is NOT present in `dbName` from `userFetch`'s perspective.
// Uses GET .../docId and expects 404. Treats 403 ("not a member of this db")
// the same as 404 — the doc is absent as far as this user is concerned. Any
// other status (200, 500, etc.) is a hard failure.
//
// `userFetch` is a partially-applied fetcher: `(path, init?) => Promise<Response>`.
// Build it with `(p, i) => couchUserFetch(couch, email, password, p, i)` or
// `(p, i) => couchAdminFetch(couch, p, i)` depending on which lens you want.
export async function assertDocAbsent(userFetch, dbName, docId) {
  const r = await userFetch(`/${dbName}/${encodeURIComponent(docId)}`)
  if (r.status === 404 || r.status === 403) return
  const text = await r.text()
  throw new Error(
    `assertDocAbsent: expected 404/403 for ${dbName}/${docId}, got ${r.status}: ${text}`,
  )
}
