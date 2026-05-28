// Seed a personal trip (the trip doc + its expenses, amendments, and voids)
// into a user's personal CouchDB, the way the PouchDB client would after the
// user added entries on their own device. Used by the adopt-trip tests to set
// up the "I have a personal trip I want to share" starting state.
//
// `personalDbName` is imported from the production module (not re-implemented)
// so the email-sanitization rule can never drift between test and prod.

import { personalDbName } from '../../sharedTrips.js'
import { couchAdminFetch } from './couch.js'

let nonce = 0
const uniq = () => `${Date.now().toString(36)}${(nonce++).toString(36)}`

export const mkTrip = (fields = {}) => ({
  _id: `trip::2024-05-21T14:30:45Z::${uniq()}`,
  type: 'trip',
  name: 'Italy',
  ...fields,
})

export const mkExpense = (tripId, fields = {}) => ({
  _id: `expense::2024-05-21T14:31:00Z::${uniq()}`,
  type: 'expense',
  tripId,
  amount: 10,
  merchant: 'Cafe',
  ...fields,
})

export const mkAmend = (targetId, fields = {}) => ({
  _id: `amend::${targetId}::${uniq()}`,
  type: 'amend',
  targetId,
  ...fields,
})

export const mkVoid = (targetId) => ({
  _id: `void::${targetId}::del`,
  type: 'void',
  targetId,
})

// Bulk-write a trip and its children into `email`'s personal DB. The DB is
// assumed to exist already (seedUser provisions it); we PUT it defensively in
// case a test seeds a trip for a user it didn't seedUser first.
export async function seedPersonalTrip(
  couch,
  email,
  { trip, expenses = [], amendments = [], voids = [] },
) {
  const dbName = personalDbName(email)
  const create = await couchAdminFetch(couch, `/${dbName}`, { method: 'PUT' })
  if (!create.ok && create.status !== 412) {
    throw new Error(`personal db PUT ${create.status}`)
  }
  const docs = [trip, ...expenses, ...amendments, ...voids].filter(Boolean)
  const res = await couchAdminFetch(couch, `/${dbName}/_bulk_docs`, {
    method: 'POST',
    body: JSON.stringify({ docs }),
  })
  if (!res.ok) throw new Error(`seed _bulk_docs ${res.status}`)
  const rows = await res.json()
  const failed = rows.filter((r) => !r.ok)
  if (failed.length) {
    throw new Error(`seed bulk failures: ${JSON.stringify(failed)}`)
  }
  return { dbName, docs }
}

// True iff `docId` is a live (non-deleted) doc in `dbName` per admin.
export async function docExists(couch, dbName, docId) {
  const r = await couchAdminFetch(couch, `/${dbName}/${encodeURIComponent(docId)}`)
  return r.status === 200
}

// All live, non-design doc ids in `dbName` per admin — for whole-DB assertions.
export async function liveDocIds(couch, dbName) {
  const r = await couchAdminFetch(couch, `/${dbName}/_all_docs`)
  if (!r.ok) throw new Error(`_all_docs ${r.status}`)
  const body = await r.json()
  return body.rows
    .map((row) => row.id)
    .filter((id) => !id.startsWith('_design/'))
}
