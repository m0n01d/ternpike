// Behavior + negative coverage for POST /sharedtrips/:id/adopt-trip — the
// endpoint that promotes a personal trip into a shared trip by moving its docs
// across CouchDB databases (and hard-deleting the originals). Runs against a
// disposable couchdb:3 container.

import { after, before, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { request } from '../fixtures/app.js'
import { basicAuthHeader } from '../fixtures/auth.js'
import { startCouch } from '../fixtures/couch.js'
import { buildEnv } from '../fixtures/env.js'
import { provisionFlock } from '../fixtures/flocks.js'
import {
  docExists,
  mkAmend,
  mkExpense,
  mkTrip,
  mkVoid,
  seedPersonalTrip,
} from '../fixtures/trips.js'
import {
  ALICE,
  BOB,
  CAROL,
  EVE,
  personalDbFor,
  seedUser,
} from '../fixtures/users.js'

let couch
let env

before(async () => {
  couch = await startCouch()
})

after(async () => {
  if (couch) await couch.stop()
})

beforeEach(async () => {
  env = buildEnv(couch)
  await seedUser(env, couch, ALICE, 'osprey')
  await seedUser(env, couch, BOB, 'osprey')
  await seedUser(env, couch, CAROL, 'osprey')
  await seedUser(env, couch, EVE, 'tern')
})

const authed = async (email) => ({
  Authorization: await basicAuthHeader(email, env.SERVER_SECRET),
})

const adopt = async (email, flockId, tripId) =>
  request(env, 'POST', `/sharedtrips/${flockId}/adopt-trip`, {
    headers: email ? await authed(email) : {},
    body: { tripId },
  })

// Build a personal trip with one amended expense and one voided expense.
const seedRichTrip = async (email) => {
  const trip = mkTrip({ name: 'Italy' })
  const exp1 = mkExpense(trip._id, { merchant: 'Trattoria' })
  const expVoided = mkExpense(trip._id, { merchant: 'Gone' })
  const amend = mkAmend(exp1._id, { amount: 99 })
  const tombstone = mkVoid(expVoided._id)
  await seedPersonalTrip(couch, email, {
    trip,
    expenses: [exp1, expVoided],
    amendments: [amend],
    voids: [tombstone],
  })
  return { trip, exp1, expVoided, amend, tombstone }
}

describe('POST /sharedtrips/:id/adopt-trip — guards', () => {
  test('missing authorization → 401', async () => {
    const { flockId } = await provisionFlock(couch, {
      name: 'a',
      owner: ALICE,
      members: [ALICE],
    })
    const res = await adopt(null, flockId, 'trip::x::y')
    assert.equal(res.status, 401)
  })

  test('non-member caller → 404 (existence not confirmed)', async () => {
    const { flockId } = await provisionFlock(couch, {
      name: 'a',
      owner: ALICE,
      members: [ALICE],
    })
    const res = await adopt(CAROL, flockId, 'trip::x::y')
    assert.equal(res.status, 404)
  })

  test('member but not owner → 403 not_owner', async () => {
    const { flockId } = await provisionFlock(couch, {
      name: 'a',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    const res = await adopt(BOB, flockId, 'trip::x::y')
    assert.equal(res.status, 403)
    assert.equal(res.body.error, 'not_owner')
  })

  test('owner on free tier → 403 paid_tier_required', async () => {
    const { flockId } = await provisionFlock(couch, {
      name: 'a',
      owner: EVE,
      members: [EVE],
    })
    const res = await adopt(EVE, flockId, 'trip::x::y')
    assert.equal(res.status, 403)
    assert.equal(res.body.error, 'paid_tier_required')
  })

  test('bad tripId → 400 invalid_trip_id', async () => {
    const { flockId } = await provisionFlock(couch, {
      name: 'a',
      owner: ALICE,
      members: [ALICE],
    })
    const res = await adopt(ALICE, flockId, 'not-a-trip')
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'invalid_trip_id')
  })

  test('owner+paid but trip absent from personal DB → 404 trip_not_found', async () => {
    const { flockId } = await provisionFlock(couch, {
      name: 'a',
      owner: ALICE,
      members: [ALICE],
    })
    const res = await adopt(ALICE, flockId, 'trip::2024-01-01T00:00:00Z::ghost')
    assert.equal(res.status, 404)
    assert.equal(res.body.error, 'trip_not_found')
  })
})

describe('POST /sharedtrips/:id/adopt-trip — the move', () => {
  test('moves trip + expenses + amendments + voids; deletes originals', async () => {
    const { flockId, dbName } = await provisionFlock(couch, {
      name: 'shared',
      owner: ALICE,
      members: [ALICE],
    })
    const { trip, exp1, expVoided, amend, tombstone } = await seedRichTrip(ALICE)

    const res = await adopt(ALICE, flockId, trip._id)
    assert.equal(res.status, 200)
    assert.deepEqual(res.body.moved, {
      trips: 1,
      expenses: 2,
      amendments: 1,
      voids: 1,
    })

    const personal = personalDbFor(ALICE)
    for (const doc of [trip, exp1, expVoided, amend, tombstone]) {
      assert.ok(
        await docExists(couch, dbName, doc._id),
        `${doc._id} should be in shared DB`,
      )
      assert.ok(
        !(await docExists(couch, personal, doc._id)),
        `${doc._id} should be gone from personal DB`,
      )
    }
  })

  test('preserves history: the amendment id survives the move', async () => {
    const { flockId, dbName } = await provisionFlock(couch, {
      name: 'shared',
      owner: ALICE,
      members: [ALICE],
    })
    const { trip, amend } = await seedRichTrip(ALICE)
    await adopt(ALICE, flockId, trip._id)
    assert.ok(await docExists(couch, dbName, amend._id))
  })

  test('empty trip (no expenses) moves just the trip doc', async () => {
    const { flockId, dbName } = await provisionFlock(couch, {
      name: 'shared',
      owner: ALICE,
      members: [ALICE],
    })
    const trip = mkTrip({ name: 'Solo' })
    await seedPersonalTrip(couch, ALICE, { trip })

    const res = await adopt(ALICE, flockId, trip._id)
    assert.equal(res.status, 200)
    assert.deepEqual(res.body.moved, {
      trips: 1,
      expenses: 0,
      amendments: 0,
      voids: 0,
    })
    assert.ok(await docExists(couch, dbName, trip._id))
    assert.ok(!(await docExists(couch, personalDbFor(ALICE), trip._id)))
  })
})

describe('POST /sharedtrips/:id/adopt-trip — idempotency', () => {
  test('clean re-run after success → 200 alreadyAdopted, no-op', async () => {
    const { flockId } = await provisionFlock(couch, {
      name: 'shared',
      owner: ALICE,
      members: [ALICE],
    })
    const { trip } = await seedRichTrip(ALICE)
    const first = await adopt(ALICE, flockId, trip._id)
    assert.equal(first.status, 200)

    const second = await adopt(ALICE, flockId, trip._id)
    assert.equal(second.status, 200)
    assert.equal(second.body.alreadyAdopted, true)
    assert.deepEqual(second.body.moved, {
      trips: 0,
      expenses: 0,
      amendments: 0,
      voids: 0,
    })
  })

  test('resume: docs already partly in shared still complete the move', async () => {
    const { flockId, dbName } = await provisionFlock(couch, {
      name: 'shared',
      owner: ALICE,
      members: [ALICE],
    })
    const { trip, exp1 } = await seedRichTrip(ALICE)

    // Simulate a prior run that copied the trip doc but never deleted: pre-place
    // the trip doc in the shared DB. The re-run must skip it (no conflict),
    // copy the rest, and delete all originals.
    const { _rev, ...tripCopy } = trip
    const pre = await fetch(`${couch.baseUrl}/${dbName}/_bulk_docs`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization:
          'Basic ' +
          Buffer.from(`${couch.adminUser}:${couch.adminPass}`).toString('base64'),
      },
      body: JSON.stringify({ docs: [tripCopy] }),
    })
    assert.ok(pre.ok)

    const res = await adopt(ALICE, flockId, trip._id)
    assert.equal(res.status, 200)
    assert.deepEqual(res.body.moved, {
      trips: 1,
      expenses: 2,
      amendments: 1,
      voids: 1,
    })
    assert.ok(await docExists(couch, dbName, exp1._id))
    assert.ok(!(await docExists(couch, personalDbFor(ALICE), trip._id)))
    assert.ok(!(await docExists(couch, personalDbFor(ALICE), exp1._id)))
  })
})
