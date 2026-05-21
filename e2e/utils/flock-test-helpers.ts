/**
 * Helpers for the join-flock E2E spec (#73).
 *
 * The harness's mock Resend can't capture the real outbound invite email —
 * `RESEND_BASE_URL` isn't wired to the Worker SDK (per #71's report). To
 * avoid blocking on that, we mint invite JWTs directly here using the same
 * HS256 + secret the auth server uses (`server/jwt.js`). The Worker
 * verifies signatures against `SERVER_SECRET`; as long as both sides use
 * the same secret, our minted tokens are indistinguishable from
 * Worker-minted ones.
 *
 * Similarly, the auth-server's HTTP Basic check derives the expected
 * password from `HMAC-SHA256("couch:" + email, SERVER_SECRET)` truncated
 * to 32 hex chars. The default fixture uses a placeholder
 * (`e2e-stub-password`); when a test needs to call /flocks/* endpoints
 * we override the IndexedDB stub with the real derived password via
 * `stubAuthCreds`.
 */
import { createHmac } from 'node:crypto'

import { stubAuthCreds } from './auth-stub'

import type { BrowserContext } from '@playwright/test'
import type { CouchClient } from './couch'

const base64UrlEncode = (buf: Buffer | Uint8Array): string =>
  Buffer.from(buf)
    .toString('base64')
    .replace(/=+$/, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')

const base64UrlEncodeString = (s: string): string => base64UrlEncode(Buffer.from(s, 'utf8'))

/**
 * Compute the server-side derived CouchDB password for an email. Mirrors
 * `derivePassword` in `server/flocks.js`.
 */
export const deriveCouchPassword = (email: string, serverSecret: string): string => {
  const hmac = createHmac('sha256', serverSecret)
  hmac.update('couch:' + email.toLowerCase())
  return hmac.digest('hex').slice(0, 32)
}

export const personalDbName = (email: string): string =>
  'ternpike-' + email.toLowerCase().replace(/[^a-z0-9_$()+/-]/g, '-')

export const flockDbName = (flockId: string): string => `flock-${flockId}`

export type InviteClaims = {
  flockId: string
  flockName?: string
  inviteeEmail: string
  inviterEmail: string
  /** Seconds-from-epoch override for the iat. Defaults to now. */
  iat?: number
  /** Seconds-from-epoch override for the exp. Defaults to now + 7d. */
  exp?: number
}

/**
 * Mint an HS256 JWT that the auth server's `verifyJwt` accepts.
 * Includes display claims (`flockName`, `inviterEmail`) so the Elm join
 * page renders the right copy without an extra round trip.
 */
export const signInviteJwt = (claims: InviteClaims, serverSecret: string): string => {
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    flockId: claims.flockId,
    flockName: claims.flockName,
    inviteeEmail: claims.inviteeEmail.toLowerCase(),
    inviter: claims.inviterEmail.toLowerCase(),
    inviterEmail: claims.inviterEmail.toLowerCase(),
    iat: claims.iat ?? now,
    exp: claims.exp ?? now + 7 * 24 * 60 * 60,
  }
  const header = { alg: 'HS256', typ: 'JWT' }
  const headerPart = base64UrlEncodeString(JSON.stringify(header))
  const payloadPart = base64UrlEncodeString(JSON.stringify(payload))
  const data = `${headerPart}.${payloadPart}`
  const sig = createHmac('sha256', serverSecret).update(data).digest()
  return `${data}.${base64UrlEncode(sig)}`
}

const FLOCK_VALIDATOR_SOURCE = `
function (newDoc, oldDoc, userCtx, secObj) {
  function reject(reason) { throw({ forbidden: reason }); }
  function unauthorized(reason) { throw({ unauthorized: reason }); }

  if (!userCtx || !userCtx.name) {
    unauthorized('login required');
  }

  var isAdmin = false;
  if (userCtx.roles) {
    for (var i = 0; i < userCtx.roles.length; i++) {
      if (userCtx.roles[i] === '_admin') { isAdmin = true; break; }
    }
  }

  if (newDoc._id && newDoc._id.indexOf('_design/') === 0) {
    if (!isAdmin) reject('design docs are admin-only');
    return;
  }

  if (newDoc._id === 'flock:meta') {
    if (!isAdmin) reject('flock:meta is admin-only');
    return;
  }

  var flockMeta = (secObj && secObj.flock) || null;

  if (flockMeta && flockMeta.billingStatus && flockMeta.billingStatus !== 'active') {
    reject('flock billing not active (' + flockMeta.billingStatus + ')');
  }

  if (newDoc._deleted) {
    return;
  }
}
`.trim()

const FLOCK_DESIGN_DOC_ID = '_design/flock_validator'

/**
 * Create or reset a flock CouchDB:
 *   - `flock-<flockId>` db
 *   - `_security` listing the owner as a member
 *   - `flock:meta` doc
 *   - the design doc carrying the per-flock validator
 *
 * Idempotent: removes a prior db with the same name first.
 */
export const provisionFlockDb = async (
  couch: CouchClient,
  args: {
    flockId: string
    name: string
    ownerEmail: string
  },
): Promise<void> => {
  const dbName = flockDbName(args.flockId)
  await requestWithRetry(couch, `/${dbName}`, { method: 'DELETE' }).catch(
    () => {},
  )
  const put = await requestWithRetry(couch, `/${dbName}`, { method: 'PUT' })
  if (!put.ok && put.status !== 412) {
    throw new Error(`PUT /${dbName} failed: ${put.status} ${await put.text()}`)
  }

  const owner = args.ownerEmail.toLowerCase()
  const meta = {
    _id: 'flock:meta',
    type: 'flock',
    name: args.name,
    members: [owner],
    billingOwner: owner,
    billingStatus: 'active',
    billingLapsedAt: null,
    createdBy: owner,
    createdAt: new Date().toISOString(),
  }
  const security = {
    admins: { names: [], roles: [] },
    members: { names: [owner], roles: [] },
    flock: { billingOwner: owner, billingStatus: 'active' },
  }
  const sec = await requestWithRetry(couch, `/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(security),
  })
  if (!sec.ok) {
    throw new Error(`PUT _security failed: ${sec.status} ${await sec.text()}`)
  }
  const design = await requestWithRetry(
    couch,
    `/${dbName}/${encodeURIComponent(FLOCK_DESIGN_DOC_ID)}`,
    {
      method: 'PUT',
      body: JSON.stringify({
        _id: FLOCK_DESIGN_DOC_ID,
        language: 'javascript',
        validate_doc_update: FLOCK_VALIDATOR_SOURCE,
      }),
    },
  )
  if (!design.ok) {
    throw new Error(`PUT design failed: ${design.status} ${await design.text()}`)
  }
  const metaPut = await requestWithRetry(couch, `/${dbName}/flock%3Ameta`, {
    method: 'PUT',
    body: JSON.stringify(meta),
  })
  if (!metaPut.ok) {
    throw new Error(`PUT flock:meta failed: ${metaPut.status} ${await metaPut.text()}`)
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/**
 * Issue a request against the admin couch with a small retry. The
 * harness's CouchDB is in a Docker container, and on a busy host the
 * port mapping has been observed to refuse a connection for a brief
 * moment between rapid operations.
 */
const requestWithRetry = async (
  couch: CouchClient,
  path: string,
  init: RequestInit | undefined,
  attempts = 4,
): Promise<Response> => {
  let lastErr: unknown = null
  for (let i = 0; i < attempts; i++) {
    try {
      return await couch.request(path, init)
    } catch (err) {
      lastErr = err
      await sleep(250 * (i + 1))
    }
  }
  throw lastErr
}

/**
 * Create a user's personal CouchDB if missing. Required because the
 * join handler writes `user:flocks` there and 500s if the db doesn't
 * exist. The real signup flow creates this at email-code verification.
 *
 * Idempotent: re-running against an existing db is a no-op.
 */
export const provisionPersonalDb = async (
  couch: CouchClient,
  email: string,
): Promise<void> => {
  const dbName = personalDbName(email)
  const put = await requestWithRetry(couch, `/${dbName}`, { method: 'PUT' })
  if (!put.ok && put.status !== 412 && put.status !== 401) {
    throw new Error(`PUT /${dbName} failed: ${put.status} ${await put.text()}`)
  }
}

/**
 * Remove the `user:flocks` doc from a user's personal db so the next
 * join lands on a clean slate. Tolerates 404 (the doc may not exist).
 */
export const purgeUserFlocks = async (
  couch: CouchClient,
  email: string,
): Promise<void> => {
  const dbName = personalDbName(email)
  const url = `/${dbName}/user%3Aflocks`
  const get = await requestWithRetry(couch, url, undefined)
  if (get.status === 404) return
  if (!get.ok) {
    throw new Error(`GET user:flocks failed: ${get.status} ${await get.text()}`)
  }
  const doc = (await get.json()) as { _rev: string }
  const del = await requestWithRetry(
    couch,
    `${url}?rev=${encodeURIComponent(doc._rev)}`,
    { method: 'DELETE' },
  )
  if (!del.ok && del.status !== 404) {
    throw new Error(`DELETE user:flocks failed: ${del.status} ${await del.text()}`)
  }
}

/** Read the user's `user:flocks` doc via admin; null if absent. */
export const readUserFlocksDoc = async (
  couch: CouchClient,
  email: string,
): Promise<{ flocks: Array<{ id: string; name: string; dbName: string }> } | null> => {
  const res = await requestWithRetry(
    couch,
    `/${personalDbName(email)}/user%3Aflocks`,
    undefined,
  )
  if (res.status === 404) return null
  if (!res.ok) {
    throw new Error(`GET user:flocks failed: ${res.status} ${await res.text()}`)
  }
  return (await res.json()) as { flocks: Array<{ id: string; name: string; dbName: string }> }
}

/**
 * Re-stub `auth_creds` with the server-derived password so HTTP Basic
 * against the auth server succeeds. The default fixture password is a
 * placeholder.
 */
export const stubRealAuthCreds = async (
  context: BrowserContext,
  email: string,
  serverSecret: string,
): Promise<void> => {
  await stubAuthCreds(context, {
    dbName: personalDbName(email),
    email,
    password: deriveCouchPassword(email, serverSecret),
  })
}

/**
 * Reroute the hardcoded `https://api.ternpike.com/**` host in the Elm
 * build to the locally running auth server. The Elm bundle ships the
 * production hostname; intercepting at the context level avoids
 * patching the build.
 */
export const proxyApiToLocal = async (
  context: BrowserContext,
  serverPort: number,
): Promise<void> => {
  await context.route('**://api.ternpike.com/**', async (route) => {
    const original = new URL(route.request().url())
    const target = `http://127.0.0.1:${serverPort}${original.pathname}${original.search}`
    const req = route.request()
    const body = req.postData() || undefined
    const headers = { ...req.headers() }
    try {
      const res = await fetch(target, {
        method: req.method(),
        headers,
        body,
      })
      const buf = Buffer.from(await res.arrayBuffer())
      const respHeaders: Record<string, string> = {}
      res.headers.forEach((v, k) => {
        respHeaders[k] = v
      })
      await route.fulfill({ status: res.status, headers: respHeaders, body: buf })
    } catch (err) {
      await route.abort()
    }
  })
}
