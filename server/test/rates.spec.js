// Coverage for GET /rates (#448) — the free FX proxy for the spend estimate.
//
// No CouchDB: /rates only authenticates and (optionally) touches a cache KV.
// The upstream open.er-api call is stubbed by patching globalThis.fetch.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { request } from './fixtures/app.js'
import { basicAuthHeader, tamperedAuthHeader } from './fixtures/auth.js'
import { memoryKv } from './fixtures/env.js'

const ALICE = 'alice@test.ternpike.com'
const SERVER_SECRET = 'test-server-secret-do-not-use-in-production'

async function authed(email) {
  return { Authorization: await basicAuthHeader(email, SERVER_SECRET) }
}

// open.er-api shape: rates are FOREIGN-per-USD. /rates inverts to
// HOME(USD)-per-foreign and lowercases the codes.
function stubUpstream({ ok = true, body } = {}) {
  const realFetch = globalThis.fetch
  let calls = 0
  globalThis.fetch = async (input) => {
    const url = typeof input === 'string' ? input : input.url
    if (url.includes('/latest/USD')) {
      calls += 1
      return new Response(JSON.stringify(body), {
        status: ok ? 200 : 502,
        headers: { 'Content-Type': 'application/json' },
      })
    }
    return realFetch(input)
  }
  return {
    callCount: () => calls,
    restore: () => {
      globalThis.fetch = realFetch
    },
  }
}

const OPEN_ER_API_BODY = {
  result: 'success',
  base_code: 'USD',
  time_last_update_utc: 'Sat, 01 Jun 2026 00:00:01 +0000',
  rates: { CAD: 1.37, MXN: 17.24, GTQ: 7.69, USD: 1, EUR: 0.93 },
}

let env
let fx

beforeEach(() => {
  env = { SERVER_SECRET, GEOCODE_CACHE_KV: memoryKv() }
})

afterEach(() => {
  if (fx) {
    fx.restore()
    fx = null
  }
})

describe('GET /rates', () => {
  test('no Authorization header returns 401', async () => {
    const res = await request(env, 'GET', '/rates')
    assert.equal(res.status, 401)
    assert.equal(res.body.ok, false)
  })

  test('tampered credentials return 401', async () => {
    const res = await request(env, 'GET', '/rates', {
      headers: { Authorization: tamperedAuthHeader(ALICE) },
    })
    assert.equal(res.status, 401)
  })

  test('authed returns USD-per-foreign rates, inverted and lowercased', async () => {
    fx = stubUpstream({ body: OPEN_ER_API_BODY })
    const res = await request(env, 'GET', '/rates', { headers: await authed(ALICE) })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
    assert.equal(res.body.base, 'usd')
    assert.equal(res.body.cached, false)
    // 1 / 1.37 ≈ 0.729927
    assert.ok(Math.abs(res.body.rates.cad - 1 / 1.37) < 1e-5)
    assert.ok(Math.abs(res.body.rates.mxn - 1 / 17.24) < 1e-5)
    // EUR is returned by upstream but not in the SUPPORTED set → omitted.
    assert.equal(res.body.rates.eur, undefined)
    // USD itself is never a foreign rate.
    assert.equal(res.body.rates.usd, undefined)
    assert.equal(res.body.date, '2026-06-01')
  })

  test('second call is served from cache (upstream hit once)', async () => {
    fx = stubUpstream({ body: OPEN_ER_API_BODY })
    const first = await request(env, 'GET', '/rates', { headers: await authed(ALICE) })
    assert.equal(first.body.cached, false)
    const second = await request(env, 'GET', '/rates', { headers: await authed(ALICE) })
    assert.equal(second.body.cached, true)
    assert.deepEqual(second.body.rates, first.body.rates)
    assert.equal(fx.callCount(), 1)
  })

  test('works without a cache binding (degrades to fetch-every-time)', async () => {
    fx = stubUpstream({ body: OPEN_ER_API_BODY })
    const noCacheEnv = { SERVER_SECRET }
    const a = await request(noCacheEnv, 'GET', '/rates', { headers: await authed(ALICE) })
    const b = await request(noCacheEnv, 'GET', '/rates', { headers: await authed(ALICE) })
    assert.equal(a.status, 200)
    assert.equal(b.status, 200)
    assert.equal(fx.callCount(), 2)
  })

  test('upstream failure returns 502', async () => {
    fx = stubUpstream({ ok: false, body: { result: 'error' } })
    const res = await request(env, 'GET', '/rates', { headers: await authed(ALICE) })
    assert.equal(res.status, 502)
    assert.equal(res.body.ok, false)
  })

  test('upstream result:error (200 body) returns 502', async () => {
    fx = stubUpstream({ body: { result: 'error', 'error-type': 'unsupported-code' } })
    const res = await request(env, 'GET', '/rates', { headers: await authed(ALICE) })
    assert.equal(res.status, 502)
  })
})
