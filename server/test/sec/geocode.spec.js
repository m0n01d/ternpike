// Negative + happy-path coverage for `POST /geocode` (#152).
//
// No CouchDB dependency — the geocode endpoint only touches the KV
// bindings and Nominatim, both of which we stub in-process. Each test
// gets a fresh env so the per-user rate-limit KV starts empty.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { request } from '../fixtures/app.js'
import { basicAuthHeader, tamperedAuthHeader } from '../fixtures/auth.js'
import { memoryKv } from '../fixtures/env.js'

const ALICE = 'alice@test.ternpike.com'
const EVE = 'eve@test.ternpike.com'
const SERVER_SECRET = 'test-server-secret-do-not-use-in-production'

const NOMINATIM_BASE = 'https://nominatim.test.local'

let env
let upstreamCalls
let upstreamHandler
let realFetch

function installNominatimMock() {
  upstreamCalls = []
  realFetch = globalThis.fetch
  globalThis.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input.url
    if (url.startsWith(NOMINATIM_BASE)) {
      upstreamCalls.push({ url, init })
      return upstreamHandler(url, init)
    }
    return realFetch(input, init)
  }
}

function uninstallNominatimMock() {
  globalThis.fetch = realFetch
}

function jsonResponse(body, init = {}) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    ...init,
  })
}

beforeEach(async () => {
  env = {
    SERVER_SECRET,
    NOMINATIM_BASE_URL: NOMINATIM_BASE,
    APP_VERSION: 'test',
    TIERS_KV: memoryKv(),
    GEOCODE_RL_KV: memoryKv(),
    GEOCODE_CACHE_KV: memoryKv(),
  }
  await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey')
  await env.TIERS_KV.put(EVE.toLowerCase(), 'tern')
  upstreamHandler = (_url) =>
    jsonResponse([
      {
        lat: '38.8977',
        lon: '-77.0366',
        display_name: '1600 Pennsylvania Ave NW, Washington DC',
      },
    ])
  installNominatimMock()
})

afterEach(() => {
  uninstallNominatimMock()
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

  test('paid caller gets a successful geocode (200) and the lat/lon parses to numbers', async () => {
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
    assert.equal(typeof res.body.lat, 'number')
    assert.equal(typeof res.body.lon, 'number')
    assert.equal(res.body.source, 'nominatim')
  })

  test('upstream User-Agent header includes Ternpike + contact email', async () => {
    await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(upstreamCalls.length, 1)
    const ua = upstreamCalls[0].init.headers['User-Agent']
    assert.match(ua, /Ternpike\/test/)
    assert.match(ua, /contact@ternpike\.com/)
  })

  test('Nominatim no-match returns 200 with null lat/lon', async () => {
    upstreamHandler = () => jsonResponse([])
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: 'nonexistent place 9999' },
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
    assert.equal(res.body.lat, null)
    assert.equal(res.body.lon, null)
  })

  test('Nominatim 5xx returns 502 upstream', async () => {
    upstreamHandler = () =>
      new Response('upstream broke', { status: 503 })
    const res = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(res.status, 502)
    assert.equal(res.body.error, 'upstream')
  })

  test('second request within rate-limit window returns 429', async () => {
    const first = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    assert.equal(first.status, 200)
    const second = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: 'another address' },
    })
    assert.equal(second.status, 429)
    assert.equal(second.body.error, 'rate_limited')
  })

  test('cache hit: same address resolved twice only calls Nominatim once', async () => {
    // First call populates the cache.
    await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '1600 Pennsylvania Ave NW' },
    })
    // Reset the rate limit so the second call isn't 429'd.
    await env.GEOCODE_RL_KV.delete(`rl:${ALICE.toLowerCase()}`)
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
    await env.GEOCODE_RL_KV.delete(`rl:${ALICE.toLowerCase()}`)
    const second = await request(env, 'POST', '/geocode', {
      headers: await authed(ALICE),
      body: { address: '  1600   pennsylvania   ave   nw  ' },
    })
    assert.equal(second.status, 200)
    assert.equal(second.body.cached, true)
    assert.equal(upstreamCalls.length, 1)
  })
})
