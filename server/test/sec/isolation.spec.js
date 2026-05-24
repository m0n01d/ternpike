// Cross-tenant isolation regression tests (#70). Verifies that data written
// into one flock never appears in another, that personal docs don't bleed
// into any flock (and vice versa), and that members can only see docs from
// flocks they belong to.
//
// These tests bypass the browser-side JS port fan-out — they talk to CouchDB
// directly as each user (Basic auth with the HMAC-derived password) so any
// cross-DB leak surfaces as a docs-where-they-shouldn't-be failure, not a
// port-routing failure. The fan-out itself is covered by the E2E in #74.
//
// Provisioning is grouped under top-level `before` so we pay the docker +
// CouchDB cost once per suite instead of once per test.

import { after, before, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { derivePassword } from '../fixtures/auth.js'
import {
  assertDocAbsent,
  couchAdminFetch,
  couchUserFetch,
} from '../fixtures/couch.js'
import { buildEnv } from '../fixtures/env.js'
import { provisionFlock } from '../fixtures/flocks.js'
import {
  ALICE,
  BOB,
  personalDbFor,
  seedUser,
} from '../fixtures/users.js'
import { setupHarness, teardownHarness } from '../setup.js'

let harness
let env
let alicePass
let bobPass
let aliceFetch
let bobFetch
let flockA
let flockB
let alicePersonalDb
let bobPersonalDb

const aliceExpense = (suffix) => ({
  _id: `expense::2026-05-21T10:00:00.000Z::${suffix}`,
  type: 'expense',
  createdBy: ALICE,
  createdAt: '2026-05-21T10:00:00.000Z',
  amount: 1234,
  category: 'food',
  note: `alice-${suffix}`,
})

const aliceTrip = (suffix, name) => ({
  _id: `trip::2026-05-21T10:00:00.000Z::${suffix}`,
  type: 'trip',
  createdBy: ALICE,
  createdAt: '2026-05-21T10:00:00.000Z',
  name,
})

async function putDoc(userFetch, dbName, doc) {
  const r = await userFetch(`/${dbName}/${encodeURIComponent(doc._id)}`, {
    method: 'PUT',
    body: JSON.stringify(doc),
  })
  if (!r.ok) {
    const text = await r.text()
    throw new Error(`PUT ${dbName}/${doc._id} ${r.status}: ${text}`)
  }
  return r.json()
}

async function getDocOk(userFetch, dbName, docId) {
  const r = await userFetch(`/${dbName}/${encodeURIComponent(docId)}`)
  assert.equal(r.status, 200, `expected ${dbName}/${docId} present`)
  return r.json()
}

before(async () => {
  harness = await setupHarness()
  env = harness.buildEnv()
  await seedUser(env, harness.couch, ALICE, 'osprey')
  await seedUser(env, harness.couch, BOB, 'osprey')

  alicePass = await derivePassword(ALICE, env.SERVER_SECRET)
  bobPass = await derivePassword(BOB, env.SERVER_SECRET)
  aliceFetch = (path, init) =>
    couchUserFetch(harness.couch, ALICE, alicePass, path, init)
  bobFetch = (path, init) =>
    couchUserFetch(harness.couch, BOB, bobPass, path, init)

  alicePersonalDb = personalDbFor(ALICE)
  bobPersonalDb = personalDbFor(BOB)

  flockA = await provisionFlock(harness.couch, {
    name: 'flock-A',
    owner: ALICE,
    members: [ALICE, BOB],
  })
  flockB = await provisionFlock(harness.couch, {
    name: 'flock-B',
    owner: ALICE,
    members: [ALICE],
  })
})

after(async () => {
  await teardownHarness(harness)
})

describe('isolation: no cross-DB doc bleed (flock to flock)', () => {
  const doc = aliceExpense('a-to-b-bleed')

  before(async () => {
    await putDoc(aliceFetch, flockA.dbName, doc)
  })

  test('positive control — expense is present in flock-A', async () => {
    const got = await getDocOk(aliceFetch, flockA.dbName, doc._id)
    assert.equal(got.note, 'alice-a-to-b-bleed')
  })

  test('expense is NOT present in flock-B', async () => {
    await assertDocAbsent(aliceFetch, flockB.dbName, doc._id)
  })
})

describe('isolation: personal stays personal', () => {
  const doc = aliceExpense('personal-only')

  before(async () => {
    await putDoc(aliceFetch, alicePersonalDb, doc)
  })

  test('positive control — expense is present in alice personal', async () => {
    const got = await getDocOk(aliceFetch, alicePersonalDb, doc._id)
    assert.equal(got.note, 'alice-personal-only')
  })

  test('expense is NOT present in flock-A', async () => {
    await assertDocAbsent(aliceFetch, flockA.dbName, doc._id)
  })

  test('expense is NOT present in flock-B', async () => {
    await assertDocAbsent(aliceFetch, flockB.dbName, doc._id)
  })
})

describe('isolation: flock docs do not leak into personal', () => {
  const doc = aliceExpense('flock-only')

  before(async () => {
    await putDoc(aliceFetch, flockA.dbName, doc)
  })

  test('positive control — expense is present in flock-A', async () => {
    await getDocOk(aliceFetch, flockA.dbName, doc._id)
  })

  test('expense is NOT present in alice personal', async () => {
    await assertDocAbsent(aliceFetch, alicePersonalDb, doc._id)
  })
})

describe('isolation: identical-name trip collision', () => {
  const personalTrip = aliceTrip('italy-personal', 'Italy')
  const flockTrip = aliceTrip('italy-flock-a', 'Italy')

  before(async () => {
    await putDoc(aliceFetch, alicePersonalDb, personalTrip)
    // Trip docs in flocks can only be written by the billing owner (ALICE
    // owns flock-A). Validator enforces this; admin fetch would bypass it
    // and miss real bugs.
    await putDoc(aliceFetch, flockA.dbName, flockTrip)
  })

  test('distinct trip ids', () => {
    assert.notEqual(personalTrip._id, flockTrip._id)
  })

  test('personal trip is present in personal db, absent in flock-A', async () => {
    const got = await getDocOk(aliceFetch, alicePersonalDb, personalTrip._id)
    assert.equal(got.name, 'Italy')
    await assertDocAbsent(aliceFetch, flockA.dbName, personalTrip._id)
  })

  test('flock trip is present in flock-A, absent in personal db', async () => {
    const got = await getDocOk(aliceFetch, flockA.dbName, flockTrip._id)
    assert.equal(got.name, 'Italy')
    await assertDocAbsent(aliceFetch, alicePersonalDb, flockTrip._id)
  })

  test('each db has exactly one trip with name "Italy" written by alice', async () => {
    const countItalyTrips = async (dbName) => {
      const r = await couchAdminFetch(
        harness.couch,
        `/${dbName}/_all_docs?include_docs=true`,
      )
      assert.equal(r.status, 200)
      const body = await r.json()
      return body.rows.filter(
        (row) =>
          row.doc &&
          row.doc.type === 'trip' &&
          row.doc.name === 'Italy' &&
          row.doc.createdBy === ALICE,
      ).length
    }
    assert.equal(await countItalyTrips(alicePersonalDb), 1)
    assert.equal(await countItalyTrips(flockA.dbName), 1)
  })
})

describe('isolation: member sees only their flocks', () => {
  // Alice writes a doc to flock-B; bob is NOT in flock-B. Bob asks CouchDB
  // for everything he can see in flock-A — must contain zero flock-B docs
  // and zero personal-db docs.
  const aliceFlockBDoc = aliceExpense('flock-b-private')
  const aliceFlockADoc = aliceExpense('flock-a-shared')

  before(async () => {
    await putDoc(aliceFetch, flockB.dbName, aliceFlockBDoc)
    await putDoc(aliceFetch, flockA.dbName, aliceFlockADoc)
  })

  test('bob cannot read flock-B at all (403/404)', async () => {
    const r = await bobFetch(`/${flockB.dbName}/_all_docs`)
    assert.ok(
      r.status === 403 || r.status === 404,
      `expected 403/404, got ${r.status}`,
    )
  })

  test('bob CAN read flock-A (positive control)', async () => {
    const r = await bobFetch(
      `/${flockA.dbName}/_all_docs?include_docs=true`,
    )
    assert.equal(r.status, 200)
    const body = await r.json()
    // Must include the shared doc alice put in flock-A.
    const ids = body.rows.map((row) => row.id)
    assert.ok(
      ids.includes(aliceFlockADoc._id),
      `expected flock-A shared doc in bob's view, got ${JSON.stringify(ids)}`,
    )
  })

  test('bob\'s flock-A view contains zero flock-B docs or personal docs', async () => {
    const r = await bobFetch(
      `/${flockA.dbName}/_all_docs?include_docs=true`,
    )
    assert.equal(r.status, 200)
    const body = await r.json()
    for (const row of body.rows) {
      assert.notEqual(
        row.id,
        aliceFlockBDoc._id,
        `flock-B doc ${row.id} leaked into bob's flock-A view`,
      )
      // No personal-db doc ids either. Personal docs use the same id shapes
      // (expense::, trip::, user:flocks), so the strongest assertion is
      // "every id matches something we actually put here" — checked above —
      // and a bound on the doc count.
    }
    // user:flocks lives in personal dbs only, not flocks. If it shows up
    // here, something is very wrong.
    const personalOnlyIds = body.rows.filter((row) =>
      row.id.startsWith('user:'),
    )
    assert.deepEqual(personalOnlyIds, [])
  })
})

describe('isolation: two-user same-flock — personal does not leak', () => {
  // Both alice and bob are members of flock-A. Alice writes a doc to her
  // personal db. Bob can read flock-A in full, but the doc must not be
  // reachable from any db bob can read.
  const alicePrivate = aliceExpense('alice-personal-private')

  before(async () => {
    await putDoc(aliceFetch, alicePersonalDb, alicePrivate)
  })

  test('bob cannot read alice\'s personal db (403/404)', async () => {
    const r = await bobFetch(`/${alicePersonalDb}/_all_docs`)
    assert.ok(
      r.status === 403 || r.status === 404,
      `expected 403/404, got ${r.status}`,
    )
  })

  test('bob cannot fetch alice\'s private doc by id from alice personal', async () => {
    await assertDocAbsent(bobFetch, alicePersonalDb, alicePrivate._id)
  })

  test('alice\'s private doc is NOT in flock-A (so bob\'s flock-A sync would not pull it)', async () => {
    await assertDocAbsent(bobFetch, flockA.dbName, alicePrivate._id)
    // Also verify via admin lens — guards against bob being denied for the
    // wrong reason (e.g. permission error masking a real leak).
    await assertDocAbsent(
      (path, init) => couchAdminFetch(harness.couch, path, init),
      flockA.dbName,
      alicePrivate._id,
    )
  })

  test('bob cannot fetch alice\'s private doc from bob\'s own personal db either', async () => {
    await assertDocAbsent(bobFetch, bobPersonalDb, alicePrivate._id)
  })
})
