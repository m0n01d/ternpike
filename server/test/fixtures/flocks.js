// Provision a flock the same way `POST /flocks` would — CouchDB db, the
// `_security` object with the `flock` mirror, the `validate_doc_update`
// design doc, and `flock:meta`. Used by tests that need a pre-existing flock
// rather than calling the endpoint.

import {
  FLOCK_DESIGN_DOC_ID,
  buildFlockDesignDoc,
} from '../../couch/flockValidator.js'
import { couchAdminFetch } from './couch.js'

const randomId = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(6))
  let s = ''
  for (let i = 0; i < bytes.length; i++) s += bytes[i].toString(16).padStart(2, '0')
  return s
}

export const flockDbName = (flockId) => `flock-${flockId}`

export async function provisionFlock(couch, { name, owner, members }) {
  const flockId = randomId()
  const dbName = flockDbName(flockId)

  const create = await couchAdminFetch(couch, `/${dbName}`, { method: 'PUT' })
  if (!create.ok && create.status !== 412) {
    throw new Error(`db PUT ${create.status}`)
  }

  const meta = {
    _id: 'flock:meta',
    type: 'flock',
    name,
    members,
    billingOwner: owner,
    billingStatus: 'active',
    billingLapsedAt: null,
    createdBy: owner,
    createdAt: new Date().toISOString(),
  }

  const security = {
    admins: { names: [], roles: [] },
    members: { names: members, roles: [] },
    flock: {
      billingOwner: meta.billingOwner,
      billingStatus: meta.billingStatus,
    },
  }
  const sec = await couchAdminFetch(couch, `/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(security),
  })
  if (!sec.ok) throw new Error(`_security PUT ${sec.status}`)

  const design = buildFlockDesignDoc(null)
  const designRes = await couchAdminFetch(
    couch,
    `/${dbName}/${encodeURIComponent(FLOCK_DESIGN_DOC_ID)}`,
    { method: 'PUT', body: JSON.stringify(design) },
  )
  if (!designRes.ok) throw new Error(`design PUT ${designRes.status}`)

  const metaRes = await couchAdminFetch(
    couch,
    `/${dbName}/flock%3Ameta`,
    { method: 'PUT', body: JSON.stringify(meta) },
  )
  if (!metaRes.ok) throw new Error(`flock:meta PUT ${metaRes.status}`)

  // Mirror `user:flocks` for each member so endpoints that touch it work.
  for (const m of members) {
    await appendUserFlocks(couch, m, { id: flockId, name, dbName })
  }

  return { flockId, dbName, meta }
}

async function appendUserFlocks(couch, email, entry) {
  const personalDb =
    'ternpike-' + email.toLowerCase().replace(/[^a-z0-9_$()+/-]/g, '-')
  const url = `/${personalDb}/user%3Aflocks`
  const cur = await couchAdminFetch(couch, url)
  let doc
  if (cur.ok) {
    doc = await cur.json()
    const without = (doc.flocks || []).filter((f) => f.id !== entry.id)
    doc.flocks = [...without, entry]
  } else if (cur.status === 404) {
    doc = { _id: 'user:flocks', type: 'userFlocks', flocks: [entry] }
  } else {
    throw new Error(`user:flocks GET ${cur.status}`)
  }
  const put = await couchAdminFetch(couch, url, {
    method: 'PUT',
    body: JSON.stringify(doc),
  })
  if (!put.ok) throw new Error(`user:flocks PUT ${put.status}`)
}

export async function readMeta(couch, dbName) {
  const r = await couchAdminFetch(couch, `/${dbName}/flock%3Ameta`)
  if (!r.ok) throw new Error(`meta GET ${r.status}`)
  return r.json()
}

export async function readSecurity(couch, dbName) {
  const r = await couchAdminFetch(couch, `/${dbName}/_security`)
  if (!r.ok) throw new Error(`security GET ${r.status}`)
  return r.json()
}
