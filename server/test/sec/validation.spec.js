// [Flock-Sec] validate_doc_update write policy — exercises the per-write
// validation function installed on each flock DB. These tests hit a real
// CouchDB authenticated as a seeded user (NOT as admin — admin writes bypass
// validate_doc_update), so we can be sure the validator is actually firing.
//
// Issue: https://github.com/m0n01d/ternpike/issues/66
// Validator source: server/couch/sharedTripValidator.js

import { after, before, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { derivePassword } from '../fixtures/auth.js'
import { couchAdminFetch, couchUserFetch, startCouch } from '../fixtures/couch.js'
import { buildEnv } from '../fixtures/env.js'
import { provisionFlock, readSecurity } from '../fixtures/flocks.js'
import { ALICE, BOB, seedUser } from '../fixtures/users.js'

let couch
let env
let aliceCreds
let bobCreds

before(async () => {
  couch = await startCouch()
  env = buildEnv(couch)
  await seedUser(env, couch, ALICE, 'osprey')
  await seedUser(env, couch, BOB, 'osprey')
  aliceCreds = {
    email: ALICE,
    password: await derivePassword(ALICE, env.SERVER_SECRET),
  }
  bobCreds = {
    email: BOB,
    password: await derivePassword(BOB, env.SERVER_SECRET),
  }
})

after(async () => {
  if (couch) await couch.stop()
})

// Helpers ────────────────────────────────────────────────────────────────────

const putAs = (creds, dbName, docId, doc) =>
  couchUserFetch(
    couch,
    creds.email,
    creds.password,
    `/${dbName}/${encodeURIComponent(docId)}`,
    { method: 'PUT', body: JSON.stringify(doc) },
  )

const putAsAdmin = (dbName, docId, doc) =>
  couchAdminFetch(couch, `/${dbName}/${encodeURIComponent(docId)}`, {
    method: 'PUT',
    body: JSON.stringify(doc),
  })

// Update the `_security` doc so the validator (which reads `secObj.flock`)
// sees the new billing status.
async function setBillingStatus(dbName, status) {
  const sec = await readSecurity(couch, dbName)
  sec.flock = { ...(sec.flock || {}), billingStatus: status }
  const r = await couchAdminFetch(couch, `/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(sec),
  })
  if (!r.ok) throw new Error(`_security PUT ${r.status}`)
}

// Deterministic ID factories — the trip/expense ID format in the app is
// `<type>::<iso>::<rand>` but for these tests we just need distinct strings.
let idCounter = 0
const nextId = (prefix) =>
  `${prefix}::2026-05-21T00:00:00.000Z::${(++idCounter).toString(16).padStart(6, '0')}`

const expense = (createdBy, overrides = {}) => {
  const id = overrides._id ?? nextId('expense')
  return {
    _id: id,
    type: 'expense',
    createdBy,
    amount: 1000,
    date: '2026-05-21',
    category: 'fuel',
    note: '',
    merchant: '',
    createdAt: new Date().toISOString(),
    ...overrides,
  }
}

const trip = (createdBy, overrides = {}) => {
  const id = overrides._id ?? nextId('trip')
  return {
    _id: id,
    type: 'trip',
    createdBy,
    name: 'Test Trip',
    startDate: '2026-05-21',
    createdAt: new Date().toISOString(),
    ...overrides,
  }
}

const amendment = (targetExpenseId, createdBy, overrides = {}) => {
  const id = `amend::${targetExpenseId}::${(++idCounter).toString(16)}`
  return {
    _id: id,
    type: 'amend',
    createdBy,
    target: targetExpenseId,
    amount: 2000,
    createdAt: new Date().toISOString(),
    ...overrides,
  }
}

const voidDoc = (targetId, createdBy, overrides = {}) => ({
  _id: `void::${targetId}::del`,
  type: 'void',
  createdBy,
  target: targetId,
  createdAt: new Date().toISOString(),
  ...overrides,
})

// Test suites ────────────────────────────────────────────────────────────────

describe('billing status enforcement', () => {
  let dbName

  before(async () => {
    const f = await provisionFlock(couch, {
      name: 'billing-test',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    dbName = f.dbName
  })

  test('member write rejected when billingStatus = "grace"', async () => {
    await setBillingStatus(dbName, 'grace')
    const res = await putAs(bobCreds, dbName, expense(BOB)._id, expense(BOB))
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /billing/i)
  })

  test('member write rejected when billingStatus = "frozen"', async () => {
    await setBillingStatus(dbName, 'frozen')
    const res = await putAs(bobCreds, dbName, expense(BOB)._id, expense(BOB))
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /billing/i)
  })

  test('positive control — member write accepted when billingStatus = "active"', async () => {
    await setBillingStatus(dbName, 'active')
    const doc = expense(BOB)
    const res = await putAs(bobCreds, dbName, doc._id, doc)
    assert.equal(res.status, 201)
  })
})

describe('author integrity (createdBy)', () => {
  let dbName

  before(async () => {
    const f = await provisionFlock(couch, {
      name: 'author-test',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    dbName = f.dbName
  })

  test("member writing someone else's createdBy is rejected", async () => {
    const doc = expense(ALICE) // BOB tries to claim ALICE wrote it
    const res = await putAs(bobCreds, dbName, doc._id, doc)
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /createdBy/i)
  })

  test("member writing a void with someone else's createdBy is rejected", async () => {
    const aliceExpense = expense(ALICE)
    const seed = await putAsAdmin(dbName, aliceExpense._id, aliceExpense)
    assert.ok(seed.ok, `seed expense PUT ${seed.status}`)

    const v = voidDoc(aliceExpense._id, ALICE) // BOB forges ALICE as createdBy
    const res = await putAs(bobCreds, dbName, v._id, v)
    assert.equal(res.status, 403)
  })

  test("positive control — member can amend another member's expense with own createdBy", async () => {
    const aliceExpense = expense(ALICE)
    const seed = await putAsAdmin(dbName, aliceExpense._id, aliceExpense)
    assert.ok(seed.ok, `seed expense PUT ${seed.status}`)

    const amend = amendment(aliceExpense._id, BOB)
    const res = await putAs(bobCreds, dbName, amend._id, amend)
    assert.equal(res.status, 201)
  })
})

describe('owner-only doc types', () => {
  let dbName

  before(async () => {
    const f = await provisionFlock(couch, {
      name: 'owner-test',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    dbName = f.dbName
  })

  test('non-owner writing type:"trip" is rejected', async () => {
    const doc = trip(BOB)
    const res = await putAs(bobCreds, dbName, doc._id, doc)
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /owner/i)
  })

  test('non-owner writing void::trip::... is rejected', async () => {
    const aliceTrip = trip(ALICE)
    const seed = await putAsAdmin(dbName, aliceTrip._id, aliceTrip)
    assert.ok(seed.ok, `seed trip PUT ${seed.status}`)

    const v = voidDoc(aliceTrip._id, BOB) // BOB tries to void ALICE's trip
    const res = await putAs(bobCreds, dbName, v._id, v)
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /owner/i)
  })

  test('positive control — owner can write type:"trip"', async () => {
    const doc = trip(ALICE)
    const res = await putAs(aliceCreds, dbName, doc._id, doc)
    assert.equal(res.status, 201)
  })

  test('positive control — owner can write void::trip::...', async () => {
    const aliceTrip = trip(ALICE)
    const seed = await putAs(aliceCreds, dbName, aliceTrip._id, aliceTrip)
    assert.equal(seed.status, 201)

    const v = voidDoc(aliceTrip._id, ALICE)
    const res = await putAs(aliceCreds, dbName, v._id, v)
    assert.equal(res.status, 201)
  })
})

describe('sharedtrip:meta admin-only', () => {
  let dbName

  before(async () => {
    const f = await provisionFlock(couch, {
      name: 'meta-test',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    dbName = f.dbName
  })

  test('non-owner member writing sharedtrip:meta is rejected', async () => {
    const cur = await couchAdminFetch(couch, `/${dbName}/sharedtrip%3Ameta`)
    const meta = await cur.json()
    meta.billingStatus = 'active' // attempt to mutate
    const res = await putAs(bobCreds, dbName, 'sharedtrip:meta', meta)
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /admin/i)
  })

  test('owner (non-admin) writing sharedtrip:meta is rejected', async () => {
    const cur = await couchAdminFetch(couch, `/${dbName}/sharedtrip%3Ameta`)
    const meta = await cur.json()
    meta.name = 'renamed-by-owner'
    const res = await putAs(aliceCreds, dbName, 'sharedtrip:meta', meta)
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /admin/i)
  })

  test('positive control — couchdb admin can write sharedtrip:meta', async () => {
    const cur = await couchAdminFetch(couch, `/${dbName}/sharedtrip%3Ameta`)
    const meta = await cur.json()
    meta.name = 'renamed-by-admin'
    const res = await putAsAdmin(dbName, 'sharedtrip:meta', meta)
    assert.ok(res.ok, `admin meta PUT ${res.status}`)
  })
})

describe('doc shape sanity', () => {
  let dbName

  before(async () => {
    const f = await provisionFlock(couch, {
      name: 'shape-test',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    dbName = f.dbName
  })

  test('malformed _id with path-traversal segments is rejected', async () => {
    const doc = expense(BOB, { _id: 'expense::../../escape' })
    const res = await putAs(bobCreds, dbName, doc._id, doc)
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /malformed _id/i)
  })

  test('unknown type value is rejected', async () => {
    const doc = expense(BOB, { type: 'weird-unknown' })
    const res = await putAs(bobCreds, dbName, doc._id, doc)
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /unknown type|type/i)
  })

  test('missing type field is rejected', async () => {
    const doc = expense(BOB)
    delete doc.type
    const res = await putAs(bobCreds, dbName, doc._id, doc)
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /type/i)
  })

  test('missing createdBy field is rejected', async () => {
    const doc = expense(BOB)
    delete doc.createdBy
    const res = await putAs(bobCreds, dbName, doc._id, doc)
    assert.equal(res.status, 403)
    const body = await res.json()
    assert.match(body.reason, /createdBy/i)
  })

  test('positive control — well-formed expense from author is accepted', async () => {
    const doc = expense(BOB)
    const res = await putAs(bobCreds, dbName, doc._id, doc)
    assert.equal(res.status, 201)
  })
})
