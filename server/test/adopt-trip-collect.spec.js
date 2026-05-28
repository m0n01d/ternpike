// Pure coverage for `collectTripDocs` (server/sharedTrips.js) — the gather
// step of the adopt-trip endpoint. No CouchDB: it operates on a plain array of
// docs (the shape `_all_docs?include_docs=true` returns via `row.doc`).

import { describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { collectTripDocs } from '../sharedTrips.js'

const TRIP = 'trip::2024-05-21T14:30:45Z::aaaa'
const OTHER_TRIP = 'trip::2024-06-01T09:00:00Z::zzzz'
const EXP_1 = 'expense::2024-05-21T14:31:00Z::e001'
const EXP_2 = 'expense::2024-05-21T14:32:00Z::e002'
const EXP_VOIDED = 'expense::2024-05-21T14:33:00Z::e003'
const OTHER_EXP = 'expense::2024-06-01T09:05:00Z::e999'

// A realistic personal-DB dump: the trip, three of its expenses (one amended,
// one voided), the amend/void docs, plus noise that MUST be excluded — another
// trip's expense + amendment, the user:sharedtrips index, and a design doc.
const docs = () => [
  { _id: TRIP, _rev: '1-a', type: 'trip', name: 'Italy' },
  { _id: EXP_1, _rev: '1-b', type: 'expense', tripId: TRIP, amount: 12.5 },
  { _id: EXP_2, _rev: '1-c', type: 'expense', tripId: TRIP, amount: 4 },
  { _id: EXP_VOIDED, _rev: '1-d', type: 'expense', tripId: TRIP, amount: 9 },
  {
    _id: `amend::${EXP_1}::t1`,
    _rev: '1-e',
    type: 'amend',
    targetId: EXP_1,
    amount: 13,
  },
  {
    _id: `amend::${EXP_VOIDED}::t2`,
    _rev: '1-f',
    type: 'amend',
    targetId: EXP_VOIDED,
    note: 'edited before it was voided',
  },
  { _id: `void::${EXP_VOIDED}::del`, _rev: '1-g', type: 'void', targetId: EXP_VOIDED },
  // noise — must NOT be collected:
  { _id: OTHER_TRIP, _rev: '1-h', type: 'trip', name: 'Spain' },
  { _id: OTHER_EXP, _rev: '1-i', type: 'expense', tripId: OTHER_TRIP, amount: 1 },
  { _id: `amend::${OTHER_EXP}::t3`, _rev: '1-j', type: 'amend', targetId: OTHER_EXP },
  { _id: 'user:sharedtrips', _rev: '1-k', type: 'userFlocks', flocks: [] },
  { _id: '_design/foo', _rev: '1-l', views: {} },
]

describe('collectTripDocs', () => {
  test('collects the trip, its expenses, amendments, and voids', () => {
    const { trip, expenses, amendments, voids } = collectTripDocs(docs(), TRIP)
    assert.equal(trip._id, TRIP)
    assert.deepEqual(
      expenses.map((e) => e._id).sort(),
      [EXP_1, EXP_2, EXP_VOIDED].sort(),
    )
    assert.deepEqual(
      amendments.map((a) => a._id).sort(),
      [`amend::${EXP_1}::t1`, `amend::${EXP_VOIDED}::t2`].sort(),
    )
    assert.deepEqual(voids.map((v) => v._id), [`void::${EXP_VOIDED}::del`])
  })

  test('preserves history: amendment for an already-voided expense is kept', () => {
    const { amendments } = collectTripDocs(docs(), TRIP)
    assert.ok(amendments.some((a) => a.targetId === EXP_VOIDED))
  })

  test('excludes other trips, user:sharedtrips, and design docs (positive allowlist)', () => {
    const { trip, expenses, amendments, voids } = collectTripDocs(docs(), TRIP)
    const allIds = [trip, ...expenses, ...amendments, ...voids].map((d) => d._id)
    assert.ok(!allIds.includes(OTHER_TRIP))
    assert.ok(!allIds.includes(OTHER_EXP))
    assert.ok(!allIds.includes(`amend::${OTHER_EXP}::t3`))
    assert.ok(!allIds.includes('user:sharedtrips'))
    assert.ok(!allIds.includes('_design/foo'))
  })

  test('includes a trip-level void tombstone for symmetry', () => {
    const withTripVoid = [
      ...docs(),
      { _id: `void::${TRIP}::del`, _rev: '1-m', type: 'void', targetId: TRIP },
    ]
    const { voids } = collectTripDocs(withTripVoid, TRIP)
    assert.ok(voids.some((v) => v.targetId === TRIP))
  })

  test('empty trip (no expenses) still returns the trip doc and no children', () => {
    const minimal = [{ _id: TRIP, _rev: '1-a', type: 'trip', name: 'Italy' }]
    const { trip, expenses, amendments, voids } = collectTripDocs(minimal, TRIP)
    assert.equal(trip._id, TRIP)
    assert.deepEqual(expenses, [])
    assert.deepEqual(amendments, [])
    assert.deepEqual(voids, [])
  })

  test('missing trip → trip is null', () => {
    const { trip } = collectTripDocs(docs(), 'trip::nope::xxxx')
    assert.equal(trip, null)
  })
})
