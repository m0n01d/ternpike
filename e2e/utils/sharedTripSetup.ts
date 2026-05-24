import { createHmac } from 'node:crypto'

import { readHarnessState } from './state'

import type { CouchClient } from './couch'

/**
 * Helpers for seeding a multi-user shared trip state directly via the CouchDB
 * admin client, mirroring what `server/sharedTrips.js` would do via its HTTP
 * endpoints.
 *
 * Used by the leave/remove spec where the pre-state (a shared trip with two
 * members and a trip with expenses from both) is needed before any UI
 * interaction. Driving the same setup through `/auth/request-code` +
 * `/sharedtrips` + `/sharedtrips/:id/invite` + `/sharedtrips/join` would work
 * end-to-end but balloons the setup to a half-dozen email round-trips per
 * spec.
 */

const SERVER_SECRET = 'e2e-server-secret'

/**
 * Derives the CouchDB password the auth server would hand the client. Must
 * match `derivePassword` in `server/index.js` exactly.
 */
export const derivePassword = (email: string): string => {
  const mac = createHmac('sha256', SERVER_SECRET)
  mac.update('couch:' + email.toLowerCase())
  return mac.digest('hex').slice(0, 32)
}

/**
 * Personal-DB name. Mirrors `sanitizeDb` in `server/index.js`.
 */
export const personalDbName = (email: string): string =>
  'ternpike-' + email.toLowerCase().replace(/[^a-z0-9_$()+/-]/g, '-')

/**
 * Shared-trip DB name. Mirrors `sharedTripDbName` in `server/sharedTrips.js`.
 */
export const sharedTripDbName = (sharedTripId: string): string => `sharedtrip-${sharedTripId}`

const ensureUser = async (
  couch: CouchClient,
  email: string,
  password: string,
): Promise<void> => {
  const id = `org.couchdb.user:${email}`
  const url = `/_users/${encodeURIComponent(id)}`
  const cur = await couch.request(url)
  const rev = cur.ok ? ((await cur.json()) as { _rev: string })._rev : null
  const body = {
    _id: id,
    name: email,
    password,
    roles: [],
    type: 'user',
    ...(rev ? { _rev: rev } : {}),
  }
  const put = await couch.request(url, {
    method: 'PUT',
    body: JSON.stringify(body),
  })
  if (!put.ok) {
    throw new Error(`_users PUT ${put.status}: ${await put.text()}`)
  }
}

const ensurePersonalDb = async (
  couch: CouchClient,
  email: string,
): Promise<string> => {
  const dbName = personalDbName(email)
  const create = await couch.request(`/${dbName}`, { method: 'PUT' })
  if (!create.ok && create.status !== 412) {
    throw new Error(`db PUT ${dbName} ${create.status}: ${await create.text()}`)
  }
  const security = {
    admins: { names: [], roles: [] },
    members: { names: [email], roles: [] },
  }
  const sec = await couch.request(`/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(security),
  })
  if (!sec.ok) {
    throw new Error(`_security PUT ${dbName} ${sec.status}: ${await sec.text()}`)
  }
  return dbName
}

export type ProvisionedUser = {
  dbName: string
  email: string
  password: string
}

/**
 * Provisions a CouchDB user + per-user database the way `/auth/verify-code`
 * would. Idempotent. Returns credentials the harness can stub into IndexedDB.
 */
export const provisionUser = async (
  couch: CouchClient,
  email: string,
): Promise<ProvisionedUser> => {
  const password = derivePassword(email)
  await ensureUser(couch, email, password)
  const dbName = await ensurePersonalDb(couch, email)
  return { dbName, email, password }
}

const upsertDoc = async (
  couch: CouchClient,
  dbName: string,
  docId: string,
  body: Record<string, unknown>,
): Promise<void> => {
  const path = `/${dbName}/${encodeURIComponent(docId)}`
  const cur = await couch.request(path)
  let rev: string | null = null
  if (cur.ok) rev = ((await cur.json()) as { _rev: string })._rev
  const put = await couch.request(path, {
    method: 'PUT',
    body: JSON.stringify({ ...body, _id: docId, ...(rev ? { _rev: rev } : {}) }),
  })
  if (!put.ok) {
    throw new Error(`doc PUT ${dbName}/${docId} ${put.status}: ${await put.text()}`)
  }
}

const appendUserSharedTrips = async (
  couch: CouchClient,
  email: string,
  entry: { dbName: string; id: string; name: string },
): Promise<void> => {
  const dbName = personalDbName(email)
  const docId = 'user:sharedtrips'
  const path = `/${dbName}/${encodeURIComponent(docId)}`
  const cur = await couch.request(path)
  let doc: { _rev?: string; flocks: typeof entry[] }
  if (cur.ok) {
    const existing = (await cur.json()) as {
      _rev: string
      flocks?: typeof entry[]
    }
    const without = (existing.flocks || []).filter((f) => f.id !== entry.id)
    doc = { _rev: existing._rev, flocks: [...without, entry] }
  } else if (cur.status === 404) {
    doc = { flocks: [entry] }
  } else {
    throw new Error(`user:sharedtrips GET ${dbName} ${cur.status}`)
  }
  const put = await couch.request(path, {
    method: 'PUT',
    body: JSON.stringify({
      _id: docId,
      type: 'userFlocks',
      flocks: doc.flocks,
      ...(doc._rev ? { _rev: doc._rev } : {}),
    }),
  })
  if (!put.ok) {
    throw new Error(`user:sharedtrips PUT ${put.status}: ${await put.text()}`)
  }
}

export type SharedTripSeedExpense = {
  amount: number
  category: string
  createdBy: string
  date: string
  merchant?: string
  note?: string
}

export type SharedTripSeed = {
  expenses?: SharedTripSeedExpense[]
  sharedTripId: string
  members: string[]
  name: string
  owner: string
  tripBudget?: number
  tripName: string
}

/**
 * Provisions a shared trip CouchDB database with `sharedtrip:meta`,
 * `_security` listing every member, one trip, and any expenses attributed via
 * `createdBy`. Adds a matching `user:sharedtrips` entry to every member's
 * personal DB so the client-side `reconcileSharedTrips` opens the handle on
 * next change-feed update.
 */
export const seedSharedTrip = async (
  couch: CouchClient,
  seed: SharedTripSeed,
): Promise<{ dbName: string; tripId: string }> => {
  const dbName = sharedTripDbName(seed.sharedTripId)
  const create = await couch.request(`/${dbName}`, { method: 'PUT' })
  if (!create.ok && create.status !== 412) {
    throw new Error(`db PUT ${dbName} ${create.status}: ${await create.text()}`)
  }
  const meta = {
    billingLapsedAt: null as string | null,
    billingOwner: seed.owner.toLowerCase(),
    billingStatus: 'active',
    createdAt: new Date().toISOString(),
    createdBy: seed.owner.toLowerCase(),
    flockId: seed.sharedTripId,
    members: seed.members.map((m) => m.toLowerCase()),
    name: seed.name,
    type: 'sharedtrip:meta',
  }
  const security = {
    admins: { names: [], roles: [] },
    flock: {
      billingOwner: meta.billingOwner,
      billingStatus: meta.billingStatus,
    },
    members: { names: meta.members, roles: [] },
  }
  const secRes = await couch.request(`/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(security),
  })
  if (!secRes.ok) {
    throw new Error(
      `_security PUT ${dbName} ${secRes.status}: ${await secRes.text()}`,
    )
  }
  await upsertDoc(couch, dbName, 'sharedtrip:meta', meta)

  const tripIso = new Date('2026-03-01T00:00:00Z').toISOString()
  const tripId = `trip::${tripIso}::${seed.sharedTripId.slice(0, 8)}`
  await upsertDoc(couch, dbName, tripId, {
    budget: seed.tripBudget ?? 0,
    coverPhotoUrl: '',
    description: '',
    endDate: '2026-03-14',
    name: seed.tripName,
    startDate: '2026-03-01',
    type: 'trip',
  })

  let seq = 0
  for (const exp of seed.expenses || []) {
    const iso = new Date(exp.date).toISOString()
    const id = `expense::${iso}::${(Date.now() + seq).toString(36).slice(-8)}`
    seq += 1
    await upsertDoc(couch, dbName, id, {
      amount: exp.amount,
      category: exp.category,
      createdAt: iso,
      createdBy: exp.createdBy.toLowerCase(),
      date: exp.date,
      lat: null,
      lon: null,
      longNote: '',
      merchant: exp.merchant || '',
      note: exp.note || '',
      tripId,
      type: 'expense',
    })
  }

  for (const member of meta.members) {
    await appendUserSharedTrips(couch, member, {
      dbName,
      id: seed.sharedTripId,
      name: seed.name,
    })
  }

  return { dbName, tripId }
}

/**
 * Reads the current `sharedtrip:meta` doc — useful when a spec needs to
 * confirm the server-side state after a leave/remove HTTP call.
 */
export const readSharedTripMeta = async (
  couch: CouchClient,
  sharedTripId: string,
): Promise<{ billingOwner: string; members: string[]; name: string }> => {
  const path = `/${sharedTripDbName(sharedTripId)}/${encodeURIComponent('sharedtrip:meta')}`
  const res = await couch.request(path)
  if (!res.ok) {
    throw new Error(`sharedtrip:meta GET ${sharedTripId} ${res.status}`)
  }
  return res.json() as Promise<{
    billingOwner: string
    members: string[]
    name: string
  }>
}

/**
 * Mints an invite JWT the same way `/sharedtrips/:id/invite` would, so the
 * spec can drive Bob's rejoin without intercepting the mock-Resend email.
 *
 * Mirrors `signJwt` in `server/jwt.js`: HS256 over
 * base64url(header).base64url(payload).
 */
export const mintInviteJwt = (
  sharedTripId: string,
  inviteeEmail: string,
  inviter: string,
): string => {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'HS256', typ: 'JWT' }
  const payload = {
    exp: now + 7 * 24 * 60 * 60,
    flockId: sharedTripId,
    iat: now,
    inviteeEmail: inviteeEmail.toLowerCase(),
    inviter: inviter.toLowerCase(),
  }
  const b64url = (s: string): string =>
    Buffer.from(s).toString('base64url')
  const signingInput =
    b64url(JSON.stringify(header)) + '.' + b64url(JSON.stringify(payload))
  const sig = createHmac('sha256', SERVER_SECRET).update(signingInput).digest()
  return signingInput + '.' + sig.toString('base64url')
}

/**
 * Convenience: returns the wrangler auth-server URL, derived from harness
 * state. Specs that need to call `/sharedtrips/*` HTTP endpoints route through
 * here rather than the real api.ternpike.com hostname.
 */
export const authServerBaseUrl = (): string => {
  const state = readHarnessState()
  return `http://127.0.0.1:${state.serverPort}`
}
