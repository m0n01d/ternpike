// Seed deterministic test users into CouchDB (mirrors the server's
// `ensureUser`) and into the in-memory tier KV. Each user gets a personal db
// matching `personalDbName(email)` since several endpoints write to
// `user:flocks` there.

import { derivePassword } from './auth.js'
import { couchAdminFetch } from './couch.js'

export const ALICE = 'alice@test.ternpike.com'
export const BOB = 'bob@test.ternpike.com'
export const CAROL = 'carol@test.ternpike.com'
export const EVE = 'eve@test.ternpike.com'

const personalDbName = (email) =>
  'ternpike-' + email.toLowerCase().replace(/[^a-z0-9_$()+/-]/g, '-')

async function ensureCouchUser(couch, email, password) {
  const id = `org.couchdb.user:${email}`
  const path = `/_users/${encodeURIComponent(id)}`
  const cur = await couchAdminFetch(couch, path)
  const rev = cur.ok ? (await cur.json())._rev : null
  const body = {
    _id: id,
    name: email,
    password,
    roles: [],
    type: 'user',
    ...(rev && { _rev: rev }),
  }
  const put = await couchAdminFetch(couch, path, {
    method: 'PUT',
    body: JSON.stringify(body),
  })
  if (!put.ok) throw new Error(`_users PUT ${put.status}`)
}

async function ensurePersonalDb(couch, email) {
  const dbName = personalDbName(email)
  const create = await couchAdminFetch(couch, `/${dbName}`, { method: 'PUT' })
  if (!create.ok && create.status !== 412) {
    throw new Error(`personal db PUT ${create.status}`)
  }
  const sec = {
    admins: { names: [], roles: [] },
    members: { names: [email], roles: [] },
  }
  const r = await couchAdminFetch(couch, `/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(sec),
  })
  if (!r.ok) throw new Error(`personal _security PUT ${r.status}`)
}

export async function seedUser(env, couch, email, tier) {
  const password = await derivePassword(email, env.SERVER_SECRET)
  await ensureCouchUser(couch, email, password)
  await ensurePersonalDb(couch, email)
  await env.TIERS_KV.put(email.toLowerCase(), tier)
}

export async function setTier(env, email, tier) {
  await env.TIERS_KV.put(email.toLowerCase(), tier)
}

export function personalDbFor(email) {
  return personalDbName(email)
}
