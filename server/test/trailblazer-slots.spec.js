// Coverage for the Trailblazer slot Durable Object
// (server/trailblazerSlots.js). DOs are single-threaded by design, so the
// 500-cap atomicity guarantee is free — these tests exercise the state
// machine, not concurrency.
//
// We don't spin up a real DO runtime; we instantiate the class with a
// Map-backed storage stub. The DO API surface used by the implementation
// is exactly `state.storage.get(key)` + `state.storage.put(key, value)`,
// both of which the stub satisfies.

import { beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { TrailblazerSlots } from '../trailblazerSlots.js'

const ALICE = 'alice@test.ternpike.com'
const BOB = 'bob@test.ternpike.com'
const CAROL = 'carol@test.ternpike.com'

function memoryStorage() {
  const map = new Map()
  return {
    async get(key) {
      return map.has(key) ? structuredClone(map.get(key)) : undefined
    },
    async put(key, value) {
      map.set(key, structuredClone(value))
    },
    async delete(key) {
      map.delete(key)
    },
    _peek: () => map,
  }
}

function makeDo() {
  const storage = memoryStorage()
  const state = { storage }
  return { do: new TrailblazerSlots(state, {}), storage }
}

async function jsonRequest(method, path, body) {
  const init = { method }
  if (body !== undefined) {
    init.body = JSON.stringify(body)
    init.headers = { 'Content-Type': 'application/json' }
  }
  return new Request('https://do.local' + path, init)
}

async function call(doInstance, method, path, body) {
  const req = await jsonRequest(method, path, body)
  const res = await doInstance.fetch(req)
  const text = await res.text()
  const parsed = text.length ? JSON.parse(text) : null
  return { status: res.status, body: parsed }
}

describe('TrailblazerSlots /reserve', () => {
  let h

  beforeEach(() => {
    h = makeDo()
  })

  test('first reservation gets number 1', async () => {
    const res = await call(h.do, 'POST', '/reserve', { email: ALICE })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
    assert.equal(res.body.number, 1)
    assert.ok(typeof res.body.reservationToken === 'string')
    assert.ok(res.body.reservationToken.length > 0)
  })

  test('two different users get distinct numbers', async () => {
    const a = await call(h.do, 'POST', '/reserve', { email: ALICE })
    const b = await call(h.do, 'POST', '/reserve', { email: BOB })
    assert.equal(a.body.number, 1)
    assert.equal(b.body.number, 2)
    assert.notEqual(a.body.reservationToken, b.body.reservationToken)
  })

  test('repeat reserve from same email returns existing reservation', async () => {
    const first = await call(h.do, 'POST', '/reserve', { email: ALICE })
    const second = await call(h.do, 'POST', '/reserve', { email: ALICE })
    assert.equal(second.body.number, first.body.number)
    assert.equal(second.body.reservationToken, first.body.reservationToken)
  })

  test('rejects invalid email', async () => {
    const res = await call(h.do, 'POST', '/reserve', { email: 'not-an-email' })
    assert.equal(res.status, 400)
    assert.equal(res.body.ok, false)
  })

  test('rejects invalid JSON body', async () => {
    const req = new Request('https://do.local/reserve', {
      method: 'POST',
      body: '{not json',
      headers: { 'Content-Type': 'application/json' },
    })
    const res = await h.do.fetch(req)
    assert.equal(res.status, 400)
  })
})

describe('TrailblazerSlots /confirm', () => {
  let h

  beforeEach(() => {
    h = makeDo()
  })

  test('happy path: reserve then confirm', async () => {
    const reserve = await call(h.do, 'POST', '/reserve', { email: ALICE })
    const confirm = await call(h.do, 'POST', '/confirm', {
      email: ALICE,
      reservationToken: reserve.body.reservationToken,
    })
    assert.equal(confirm.status, 200)
    assert.equal(confirm.body.ok, true)
    assert.equal(confirm.body.number, reserve.body.number)
  })

  test('confirmed slot does not reappear in subsequent reserves', async () => {
    const a = await call(h.do, 'POST', '/reserve', { email: ALICE })
    await call(h.do, 'POST', '/confirm', {
      email: ALICE,
      reservationToken: a.body.reservationToken,
    })
    const b = await call(h.do, 'POST', '/reserve', { email: BOB })
    assert.notEqual(b.body.number, a.body.number)
  })

  test('rejects unknown reservationToken with 410', async () => {
    const res = await call(h.do, 'POST', '/confirm', {
      email: ALICE,
      reservationToken: 'made-up-token',
    })
    assert.equal(res.status, 410)
    assert.equal(res.body.error, 'reservation_expired')
  })

  test('rejects mismatched email with 403', async () => {
    const reserve = await call(h.do, 'POST', '/reserve', { email: ALICE })
    const res = await call(h.do, 'POST', '/confirm', {
      email: BOB,
      reservationToken: reserve.body.reservationToken,
    })
    assert.equal(res.status, 403)
    assert.equal(res.body.error, 'email_mismatch')
  })

  test('rejects missing fields with 400', async () => {
    const r1 = await call(h.do, 'POST', '/confirm', { email: ALICE })
    assert.equal(r1.status, 400)
    const r2 = await call(h.do, 'POST', '/confirm', {
      reservationToken: 'x',
    })
    assert.equal(r2.status, 400)
  })
})

describe('TrailblazerSlots sold-out at 500', () => {
  test('rejects reservations beyond the 500 cap', async () => {
    // Pre-seed 500 confirmed slots to avoid 500 real round-trips.
    const h = makeDo()
    const confirmedNumbers = Array.from({ length: 500 }, (_, i) => i + 1)
    await h.storage.put('state', {
      confirmed: 500,
      confirmedNumbers,
      reservations: {},
    })

    const status = await call(h.do, 'GET', '/status')
    assert.equal(status.body.available, 0)
    assert.equal(status.body.total, 500)

    const reserve = await call(h.do, 'POST', '/reserve', { email: ALICE })
    assert.equal(reserve.body.ok, false)
    assert.equal(reserve.body.reason, 'sold_out')
    assert.equal(reserve.body.remaining, 0)
  })

  test('reservations + confirmations together fill the cap', async () => {
    // 499 confirmed + 1 active reservation = full.
    const h = makeDo()
    const confirmedNumbers = Array.from({ length: 499 }, (_, i) => i + 1)
    await h.storage.put('state', {
      confirmed: 499,
      confirmedNumbers,
      reservations: {
        'token-active': {
          email: BOB,
          expiresAt: Date.now() + 60_000,
          number: 500,
        },
      },
    })
    const res = await call(h.do, 'POST', '/reserve', { email: CAROL })
    assert.equal(res.body.ok, false)
    assert.equal(res.body.reason, 'sold_out')
  })
})

describe('TrailblazerSlots reservation expiry', () => {
  test('expired reservations free up their slot', async () => {
    const h = makeDo()
    // Park one expired reservation in storage directly.
    await h.storage.put('state', {
      confirmed: 0,
      confirmedNumbers: [],
      reservations: {
        'old-token': {
          email: ALICE,
          expiresAt: Date.now() - 1000,
          number: 1,
        },
      },
    })
    // Bob asks to reserve — sweep should drop Alice's stale reservation
    // and hand slot 1 to Bob.
    const res = await call(h.do, 'POST', '/reserve', { email: BOB })
    assert.equal(res.body.ok, true)
    assert.equal(res.body.number, 1)
    assert.notEqual(res.body.reservationToken, 'old-token')
  })

  test('expired reservation cannot be confirmed', async () => {
    const h = makeDo()
    await h.storage.put('state', {
      confirmed: 0,
      confirmedNumbers: [],
      reservations: {
        'stale-token': {
          email: ALICE,
          expiresAt: Date.now() - 1000,
          number: 1,
        },
      },
    })
    const res = await call(h.do, 'POST', '/confirm', {
      email: ALICE,
      reservationToken: 'stale-token',
    })
    assert.equal(res.status, 410)
  })
})

describe('TrailblazerSlots /status', () => {
  let h

  beforeEach(() => {
    h = makeDo()
  })

  test('empty state shows 500 available', async () => {
    const res = await call(h.do, 'GET', '/status')
    assert.equal(res.status, 200)
    assert.equal(res.body.available, 500)
    assert.equal(res.body.total, 500)
  })

  test('counts reflect confirmed + active reservations', async () => {
    await call(h.do, 'POST', '/reserve', { email: ALICE })
    const reserveB = await call(h.do, 'POST', '/reserve', { email: BOB })
    await call(h.do, 'POST', '/confirm', {
      email: BOB,
      reservationToken: reserveB.body.reservationToken,
    })
    const status = await call(h.do, 'GET', '/status')
    assert.equal(status.body.available, 498) // 1 reservation + 1 confirmed
    assert.equal(status.body.total, 500)
  })

  test('sweeps expired reservations from status', async () => {
    await h.storage.put('state', {
      confirmed: 0,
      confirmedNumbers: [],
      reservations: {
        'stale-token': {
          email: ALICE,
          expiresAt: Date.now() - 1000,
          number: 42,
        },
      },
    })
    const res = await call(h.do, 'GET', '/status')
    assert.equal(res.body.available, 500)
  })
})

describe('TrailblazerSlots unknown routes', () => {
  test('unknown path returns 404', async () => {
    const h = makeDo()
    const res = await call(h.do, 'GET', '/nope')
    assert.equal(res.status, 404)
  })
})
