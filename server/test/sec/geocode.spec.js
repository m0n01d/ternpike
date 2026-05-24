// Negative + happy-path coverage for `POST /geocode` (#152 + #169).
//
// No CouchDB dependency — the geocode endpoint only touches the KV
// bindings and the Google Geocoding API, both of which we stub in-
// process. Each test gets a fresh env so the per-user rate-limit KV
// starts empty.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { request } from '../fixtures/app.js'
import { basicAuthHeader, tamperedAuthHeader } from '../fixtures/auth.js'
import { memoryKv } from '../fixtures/env.js'

const ALICE = 'alice@test.ternpike.com'
const EVE = 'eve@test.ternpike.com'
const SERVER_SECRET = 'test-server-secret-do-not-use-in-production'

const GOOGLE_BASE = 'https://google.test.local'

let env
let upstreamCalls
let upstreamHandler
let realFetch

function installGoogleMock() {
  upstreamCalls = []
  realFetch = globalThis.fetch
  globalThis.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input.url
    if (url.startsWith(GOOGLE_BASE)) {
      upstreamCalls.push({ url, init })
      return upstreamHandler(url, init)
    }
    return realFetch(input, init)
  }
}

function uninstallGoogleMock() {
  globalThis.fetch = realFetch
}

function jsonResponse(body, init = {}) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    ...init,
  })
}

function googleHit(lat, lng) {
  return jsonResponse({
    status: 'OK',
    results: [{ geometry: { location: { lat, lng } } }],
  })
}

beforeEach(async () => {
  env = {
    SERVER_SECRET,
    GOOGLE_GEOCODING_BASE_URL: GOOGLE_BASE,
    GOOGLE_GEOCODING_API_KEY: 'test-google-key',
    TIERS_KV: memoryKv(),
    GEOCODE_RL_KV: memoryKv(),
    GEOCODE_CACHE_KV: memoryKv(),
  }
  await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey')
  await env.TIERS_KV.put(EVE.toLowerCase(), 'tern')
  upstreamHandler = (_url) => googleHit(38.8977, -77.0366)
  installGoogleMock()
})

afterEach(() => {
  uninstallGoogleMock()
})

const authed = async (email) => ({
  Authorization: await basicAuthHeader(email, SERVER_SECRET),
})

describe('POST /geocode', () => {
  test('tern caller is rejected with 403 paid_tier_required', async () => {
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(EVE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 403)
    assert.equal(res.body.error, 'paid_tier_required')
  })

  test('missing authorization header returns 401', async () => {
    const res = await request(env, 'POST', '/geocode', {
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 401)
  })

  test('tampered basic-auth password returns 401', async () => {
    const res = await request(env, 'POST', '/geocode', {
      headers: { Authorization: tamperedAuthHeader(ALICE) },
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 401)
  })

  test('empty body returns 400 bad_request', async () => {
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: {},
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'bad_request')
  })

  test('oversized address (>256 chars) returns 400 bad_request', async () => {
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: 'x'.repeat(300) },
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'bad_request')
  })

  test('whitespace-only address is rejected as 400', async () => {
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '   ' },
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'bad_request')
  })

  test('paid caller gets a successful geocode (200) with numeric lat/lon and source: google', async () => {
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
    assert.equal(typeof res.body.lat, 'number')
    assert.equal(typeof res.body.lon, 'number')
    assert.equal(res.body.lat, 38.8977)
    assert.equal(res.body.lon, -77.0366)
    assert.equal(res.body.source, 'google')
  })

  test('upstream URL includes the API key', async () => {
    await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(upstreamCalls.length, 1)
    assert.match(upstreamCalls[0].url, /key=test-google-key/)
  })

  test('Google ZERO_RESULTS returns 200 with null lat/lon', async () => {
    upstreamHandler = () => jsonResponse({ status: 'ZERO_RESULTS', results: [] })
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: 'nonexistent place 9999' },
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
    assert.equal(res.body.lat, null)
    assert.equal(res.body.lon, null)
  })

  test('Google OVER_QUERY_LIMIT returns 502 upstream', async () => {
    upstreamHandler = () =>
      jsonResponse({ status: 'OVER_QUERY_LIMIT', results: [] })
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 502)
    assert.equal(res.body.error, 'upstream')
  })

  test('Google REQUEST_DENIED returns 502 upstream', async () => {
    upstreamHandler = () =>
      jsonResponse({ status: 'REQUEST_DENIED', results: [] })
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 502)
    assert.equal(res.body.error, 'upstream')
  })

  test('Google 5xx returns 502 upstream', async () => {
    upstreamHandler = () => new Response('upstream broke', { status: 503 })
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 502)
    assert.equal(res.body.error, 'upstream')
  })

  test('per-user token bucket admits a batch of 100 within the same window', async () => {
    // A real batch-scanned road-trip week is 30-50 receipts. 100 in
    // succession is the cap; the next one is 429'd.
    for (let i = 0; i < 100; i++) {
      const res = await request(env, 'POST', '/geocode', {
        headers: await authed(ALICE),
        body: { address: `${i} stop st` },
      })
      assert.equal(res.status, 200, `call #${i + 1} should pass`)
    }
    const overflow = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: 'one too many' },
    })
    assert.equal(overflow.status, 429)
    assert.equal(overflow.body.error, 'rate_limited')
  })

  test('cache hit: same address resolved twice only calls Google once', async () => {
    await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    const second = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(second.status, 200)
    assert.equal(second.body.cached, true)
    assert.equal(upstreamCalls.length, 1)
  })

  test('cache key normalizes case + whitespace so equivalent addresses share an entry', async () => {
    await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    const second = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '  1600   pennsylvania   ave   nw  ' },
    })
    assert.equal(second.status, 200)
    assert.equal(second.body.cached, true)
    assert.equal(upstreamCalls.length, 1)
  })

  test('missing GOOGLE_GEOCODING_API_KEY returns 502 upstream', async () => {
    env.GOOGLE_GEOCODING_API_KEY = undefined
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 502)
    assert.equal(res.body.error, 'upstream')
  })
})
