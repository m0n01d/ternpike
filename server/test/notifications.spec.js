// Coverage for the four `/notifications/*` routes (#179).
//
// No CouchDB dependency — these endpoints only touch `PUSH_KV` and
// `TIERS_KV`, both of which we stub with the in-memory KV from
// fixtures/env.js. The test mirrors the geocode.spec.js pattern.

import { beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { request } from './fixtures/app.js'
import { basicAuthHeader, tamperedAuthHeader } from './fixtures/auth.js'
import { memoryKv } from './fixtures/env.js'

const ALICE = 'alice@test.ternpike.com'
const EVE = 'eve@test.ternpike.com'
const TRAIL = 'trail@test.ternpike.com'
const SERVER_SECRET = 'test-server-secret-do-not-use-in-production'

const ENDPOINT = 'https://push.example.com/abc123'
const ENDPOINT_OTHER = 'https://push.example.com/xyz789'
const KEYS = { auth: 'auth-secret', p256dh: 'p256dh-pub' }

let env

async function authed(email) {
  return { Authorization: await basicAuthHeader(email, SERVER_SECRET) }
}

beforeEach(async () => {
  env = {
    PUSH_KV: memoryKv(),
    SERVER_SECRET,
    TIERS_KV: memoryKv(),
  }
  await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey')
  await env.TIERS_KV.put(EVE.toLowerCase(), 'tern')
  await env.TIERS_KV.put(TRAIL.toLowerCase(), 'trailblazer')
})

describe('POST /notifications/subscribe', () => {
  test('missing auth returns 401', async () => {
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: KEYS },
    })
    assert.equal(res.status, 401)
    assert.equal(res.body.ok, false)
  })

  test('tampered basic-auth returns 401', async () => {
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: KEYS },
      headers: { Authorization: tamperedAuthHeader(ALICE) },
    })
    assert.equal(res.status, 401)
  })

  test('tern caller gets 402 upgrade-required', async () => {
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: KEYS },
      headers: await authed(EVE),
    })
    assert.equal(res.status, 402)
    assert.equal(res.body.error, 'upgrade-required')
    assert.equal(res.body.ok, false)
  })

  test('osprey caller succeeds with 200', async () => {
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: KEYS },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
  })

  test('trailblazer caller succeeds with 200', async () => {
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: KEYS },
      headers: await authed(TRAIL),
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
  })

  test('missing endpoint returns 400 malformed', async () => {
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body: { keys: KEYS },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'malformed')
  })

  test('missing keys.auth returns 400 malformed', async () => {
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: { p256dh: 'p' } },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'malformed')
  })

  test('missing keys.p256dh returns 400 malformed', async () => {
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: { auth: 'a' } },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'malformed')
  })

  test('empty body returns 400 malformed', async () => {
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body: {},
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'malformed')
  })

  test('subscription record persists with expected fields', async () => {
    await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: KEYS },
      headers: await authed(ALICE),
    })
    const dump = env.PUSH_KV._dump()
    const subEntry = dump.find(([k]) => k.startsWith('push:sub:'))
    assert.ok(subEntry, 'expected a push:sub:* key')
    const [key, { value }] = subEntry
    assert.match(key, /^push:sub:alice@test\.ternpike\.com:[a-f0-9]{64}$/)
    const record = JSON.parse(value)
    assert.equal(record.auth, KEYS.auth)
    assert.equal(record.p256dh, KEYS.p256dh)
    assert.equal(record.endpoint, ENDPOINT)
    assert.equal(record.tierAtSubscribe, 'osprey')
    assert.equal(typeof record.createdAt, 'string')
    assert.match(record.createdAt, /^\d{4}-\d{2}-\d{2}T/)
  })

  test('default prefs are seeded when subscriptions field omitted', async () => {
    await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: KEYS },
      headers: await authed(ALICE),
    })
    const dump = env.PUSH_KV._dump()
    const prefEntry = dump.find(([k]) => k.startsWith('push:pref:'))
    assert.ok(prefEntry, 'expected a push:pref:* key')
    assert.deepEqual(JSON.parse(prefEntry[1].value), {
      weeklyScanReminder: true,
    })
  })

  test('custom prefs are stored when subscriptions field provided', async () => {
    await request(env, 'POST', '/notifications/subscribe', {
      body: {
        endpoint: ENDPOINT,
        keys: KEYS,
        subscriptions: { weeklyScanReminder: false },
      },
      headers: await authed(ALICE),
    })
    const dump = env.PUSH_KV._dump()
    const prefEntry = dump.find(([k]) => k.startsWith('push:pref:'))
    assert.deepEqual(JSON.parse(prefEntry[1].value), {
      weeklyScanReminder: false,
    })
  })
})

describe('DELETE /notifications/subscribe', () => {
  test('missing auth returns 401', async () => {
    const res = await request(env, 'DELETE', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT },
    })
    assert.equal(res.status, 401)
  })

  test('tern caller gets 402 upgrade-required', async () => {
    const res = await request(env, 'DELETE', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT },
      headers: await authed(EVE),
    })
    assert.equal(res.status, 402)
    assert.equal(res.body.error, 'upgrade-required')
  })

  test('missing endpoint returns 400 malformed', async () => {
    const res = await request(env, 'DELETE', '/notifications/subscribe', {
      body: {},
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 400)
  })

  test('is idempotent — returns 200 even when key is absent', async () => {
    const res = await request(env, 'DELETE', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
  })

  test('removes both sub + pref keys after a prior subscribe', async () => {
    await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: KEYS },
      headers: await authed(ALICE),
    })
    assert.equal(env.PUSH_KV._dump().length, 2)
    const res = await request(env, 'DELETE', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 200)
    assert.equal(env.PUSH_KV._dump().length, 0)
  })

  test('deleting one device leaves a sibling device intact', async () => {
    await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT, keys: KEYS },
      headers: await authed(ALICE),
    })
    await request(env, 'POST', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT_OTHER, keys: KEYS },
      headers: await authed(ALICE),
    })
    assert.equal(env.PUSH_KV._dump().length, 4)
    await request(env, 'DELETE', '/notifications/subscribe', {
      body: { endpoint: ENDPOINT },
      headers: await authed(ALICE),
    })
    assert.equal(env.PUSH_KV._dump().length, 2)
  })
})

describe('GET /notifications/preferences', () => {
  test('missing auth returns 401', async () => {
    const res = await request(
      env,
      'GET',
      `/notifications/preferences?endpoint=${encodeURIComponent(ENDPOINT)}`,
    )
    assert.equal(res.status, 401)
  })

  test('tern caller gets 402 upgrade-required', async () => {
    const res = await request(
      env,
      'GET',
      `/notifications/preferences?endpoint=${encodeURIComponent(ENDPOINT)}`,
      { headers: await authed(EVE) },
    )
    assert.equal(res.status, 402)
  })

  test('missing endpoint query returns 400 malformed', async () => {
    const res = await request(env, 'GET', '/notifications/preferences', {
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'malformed')
  })

  test('returns default prefs when no record exists', async () => {
    const res = await request(
      env,
      'GET',
      `/notifications/preferences?endpoint=${encodeURIComponent(ENDPOINT)}`,
      { headers: await authed(ALICE) },
    )
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
    assert.deepEqual(res.body.prefs, { weeklyScanReminder: true })
  })

  test('returns stored prefs after a subscribe', async () => {
    await request(env, 'POST', '/notifications/subscribe', {
      body: {
        endpoint: ENDPOINT,
        keys: KEYS,
        subscriptions: { weeklyScanReminder: false },
      },
      headers: await authed(ALICE),
    })
    const res = await request(
      env,
      'GET',
      `/notifications/preferences?endpoint=${encodeURIComponent(ENDPOINT)}`,
      { headers: await authed(ALICE) },
    )
    assert.equal(res.status, 200)
    assert.deepEqual(res.body.prefs, { weeklyScanReminder: false })
  })
})

describe('PUT /notifications/preferences', () => {
  test('missing auth returns 401', async () => {
    const res = await request(env, 'PUT', '/notifications/preferences', {
      body: { endpoint: ENDPOINT, prefs: { weeklyScanReminder: false } },
    })
    assert.equal(res.status, 401)
  })

  test('tern caller gets 402 upgrade-required', async () => {
    const res = await request(env, 'PUT', '/notifications/preferences', {
      body: { endpoint: ENDPOINT, prefs: { weeklyScanReminder: false } },
      headers: await authed(EVE),
    })
    assert.equal(res.status, 402)
  })

  test('missing endpoint returns 400 malformed', async () => {
    const res = await request(env, 'PUT', '/notifications/preferences', {
      body: { prefs: { weeklyScanReminder: false } },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 400)
  })

  test('missing prefs returns 400 malformed', async () => {
    const res = await request(env, 'PUT', '/notifications/preferences', {
      body: { endpoint: ENDPOINT },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 400)
  })

  test('written prefs are readable via GET', async () => {
    const put = await request(env, 'PUT', '/notifications/preferences', {
      body: { endpoint: ENDPOINT, prefs: { weeklyScanReminder: false } },
      headers: await authed(ALICE),
    })
    assert.equal(put.status, 200)
    assert.equal(put.body.ok, true)
    const get = await request(
      env,
      'GET',
      `/notifications/preferences?endpoint=${encodeURIComponent(ENDPOINT)}`,
      { headers: await authed(ALICE) },
    )
    assert.equal(get.status, 200)
    assert.deepEqual(get.body.prefs, { weeklyScanReminder: false })
  })

  test('overwrites any prior prefs (no partial-merge)', async () => {
    await request(env, 'PUT', '/notifications/preferences', {
      body: {
        endpoint: ENDPOINT,
        prefs: { extraFlag: 'kept', weeklyScanReminder: true },
      },
      headers: await authed(ALICE),
    })
    await request(env, 'PUT', '/notifications/preferences', {
      body: { endpoint: ENDPOINT, prefs: { weeklyScanReminder: false } },
      headers: await authed(ALICE),
    })
    const res = await request(
      env,
      'GET',
      `/notifications/preferences?endpoint=${encodeURIComponent(ENDPOINT)}`,
      { headers: await authed(ALICE) },
    )
    assert.deepEqual(res.body.prefs, { weeklyScanReminder: false })
  })
})
