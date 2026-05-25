// Coverage for the four `/notifications/*` routes (#179).
//
// No CouchDB dependency — these endpoints only touch `PUSH_KV` and
// `TIERS_KV`, both of which we stub with the in-memory KV from
// fixtures/env.js. The test mirrors the geocode.spec.js pattern.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { sendTestPush, sendWeeklyScanReminders, sha256Hex } from '../notifications.js'
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

describe('sendWeeklyScanReminders', () => {
  // Seed a real subscribe call so the PUSH_KV has the canonical record
  // shape (auth/p256dh/endpoint/createdAt/tierAtSubscribe) the sweep
  // expects. Caller controls who the seed runs as + which endpoint +
  // optional prefs override.
  async function seedSubscription(email, endpoint, subscriptions) {
    const body = { endpoint, keys: KEYS }
    if (subscriptions) body.subscriptions = subscriptions
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body,
      headers: await authed(email),
    })
    assert.equal(res.status, 200, `seedSubscription ${email} ${endpoint}`)
  }

  // Hook the no-crypto path: tests assert KV iteration + filter +
  // fetch-call shape, not VAPID signing. Returns a Request-shaped
  // object that `fetch` will accept as the second arg's init.
  function stubBuildPushPayload() {
    return async (_msg, _sub, _vapid) => ({
      body: 'test-encrypted-payload',
      headers: { 'content-type': 'application/octet-stream' },
      method: 'POST',
    })
  }

  // Capture every `fetch` call the sweep makes. Resolves each one to
  // whatever `responder(url, init, callIndex)` returns. Restored in
  // afterEach via the captured `realFetch` reference.
  let realFetch
  function installFetchSpy(responder) {
    const calls = []
    realFetch = globalThis.fetch
    globalThis.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input.url
      const idx = calls.length
      calls.push({ init, url })
      return responder(url, init, idx)
    }
    return calls
  }

  afterEach(() => {
    if (realFetch) {
      globalThis.fetch = realFetch
      realFetch = undefined
    }
  })

  function envWithStub() {
    return {
      ...env,
      VAPID_PRIVATE_KEY: 'test-vapid-private',
      VAPID_PUBLIC_KEY: 'test-vapid-public',
      VAPID_SUBJECT: 'mailto:test@ternpike.com',
      __buildPushPayload: stubBuildPushPayload(),
    }
  }

  test('skips downgraded users — only paid endpoints receive a push', async () => {
    await seedSubscription(ALICE, ENDPOINT) // paid (osprey)
    // Seed Eve via a direct PUSH_KV put so we don't have to flip her
    // tier mid-test: the subscribe endpoint 402s for Tern.
    await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey')
    // Manually plant a subscription for a tern user — the real route
    // would reject it, but this models "user downgraded after a prior
    // paid subscribe", which is exactly what the sweep must guard.
    const eveEndpoint = 'https://push.example.com/eve-device'
    const eveHash = await sha256Hex(eveEndpoint)
    await env.PUSH_KV.put(
      `push:sub:${EVE.toLowerCase()}:${eveHash}`,
      JSON.stringify({
        auth: KEYS.auth,
        createdAt: '2026-05-01T00:00:00.000Z',
        endpoint: eveEndpoint,
        p256dh: KEYS.p256dh,
        tierAtSubscribe: 'osprey',
      }),
    )
    await env.PUSH_KV.put(
      `push:pref:${EVE.toLowerCase()}:${eveHash}`,
      JSON.stringify({ weeklyScanReminder: true }),
    )

    const calls = installFetchSpy(() => new Response('', { status: 201 }))
    await sendWeeklyScanReminders(envWithStub())

    assert.equal(calls.length, 1, 'fetch called exactly once')
    assert.equal(calls[0].url, ENDPOINT, 'paid user endpoint reached')
  })

  test('skips opted-out devices — only the opted-in device receives a push', async () => {
    await seedSubscription(ALICE, ENDPOINT, { weeklyScanReminder: true })
    await seedSubscription(ALICE, ENDPOINT_OTHER, {
      weeklyScanReminder: false,
    })

    const calls = installFetchSpy(() => new Response('', { status: 201 }))
    await sendWeeklyScanReminders(envWithStub())

    assert.equal(calls.length, 1, 'fetch called exactly once')
    assert.equal(calls[0].url, ENDPOINT, 'opted-in endpoint reached')
  })

  test('deletes both push:sub: and push:pref: keys on 410 Gone', async () => {
    await seedSubscription(ALICE, ENDPOINT)
    assert.equal(env.PUSH_KV._dump().length, 2)

    installFetchSpy(() => new Response('', { status: 410 }))
    await sendWeeklyScanReminders(envWithStub())

    const remaining = env.PUSH_KV._dump()
    assert.equal(remaining.length, 0, 'both sub + pref deleted')
  })

  test('deletes both keys on 404 Not Found', async () => {
    await seedSubscription(ALICE, ENDPOINT)
    assert.equal(env.PUSH_KV._dump().length, 2)

    installFetchSpy(() => new Response('', { status: 404 }))
    await sendWeeklyScanReminders(envWithStub())

    assert.equal(env.PUSH_KV._dump().length, 0)
  })

  test('logs non-fatal errors and continues — neither sub deleted on 500', async () => {
    await seedSubscription(ALICE, ENDPOINT)
    await seedSubscription(ALICE, ENDPOINT_OTHER)
    assert.equal(env.PUSH_KV._dump().length, 4)

    // First call fails 500, second succeeds 201. Capture console.error
    // so the test output stays clean while still asserting the call.
    const errors = []
    const realError = console.error
    console.error = (...args) => {
      errors.push(args)
    }
    try {
      const calls = installFetchSpy((_url, _init, idx) =>
        idx === 0
          ? new Response('', { status: 500 })
          : new Response('', { status: 201 }),
      )
      await sendWeeklyScanReminders(envWithStub())
      assert.equal(calls.length, 2, 'both endpoints attempted')
    } finally {
      console.error = realError
    }

    assert.equal(env.PUSH_KV._dump().length, 4, 'no keys deleted')
    assert.ok(
      errors.some(([msg]) => msg === 'push send failed'),
      'logged the 500 failure',
    )
  })
})

describe('sendTestPush', () => {
  // Seed a real subscribe call so PUSH_KV has the canonical record shape.
  async function seedSubscription(email, endpoint, subscriptions) {
    const body = { endpoint, keys: KEYS }
    if (subscriptions) body.subscriptions = subscriptions
    const res = await request(env, 'POST', '/notifications/subscribe', {
      body,
      headers: await authed(email),
    })
    assert.equal(res.status, 200, `seedSubscription ${email} ${endpoint}`)
  }

  function stubBuildPushPayload() {
    return async (_msg, _sub, _vapid) => ({
      body: 'test-encrypted-payload',
      headers: { 'content-type': 'application/octet-stream' },
      method: 'POST',
    })
  }

  let realFetch
  function installFetchSpy(responder) {
    const calls = []
    realFetch = globalThis.fetch
    globalThis.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input.url
      const idx = calls.length
      calls.push({ init, url })
      return responder(url, init, idx)
    }
    return calls
  }

  afterEach(() => {
    if (realFetch) {
      globalThis.fetch = realFetch
      realFetch = undefined
    }
  })

  function envWithStub() {
    return {
      ...env,
      VAPID_PRIVATE_KEY: 'test-vapid-private',
      VAPID_PUBLIC_KEY: 'test-vapid-public',
      VAPID_SUBJECT: 'mailto:test@ternpike.com',
      __buildPushPayload: stubBuildPushPayload(),
    }
  }

  test('tern user gets { ok: false, reason: not-paid, sent: 0 } — fetch not called', async () => {
    // EVE is tern tier; put a subscription in KV manually since the
    // subscribe route 402s for tern callers — simulates a user who
    // downgraded after subscribing.
    const eveEndpoint = 'https://push.example.com/eve-test-device'
    const eveHash = await sha256Hex(eveEndpoint)
    await env.PUSH_KV.put(
      `push:sub:${EVE.toLowerCase()}:${eveHash}`,
      JSON.stringify({
        auth: KEYS.auth,
        createdAt: '2026-05-01T00:00:00.000Z',
        endpoint: eveEndpoint,
        p256dh: KEYS.p256dh,
        tierAtSubscribe: 'osprey',
      }),
    )
    const calls = installFetchSpy(() => new Response('', { status: 201 }))
    const result = await sendTestPush(envWithStub(), EVE)
    assert.deepEqual(result, { ok: false, reason: 'not-paid', sent: 0 })
    assert.equal(calls.length, 0, 'fetch must not be called for tern user')
  })

  test('sends to all subscriptions for a paid user — fetch called twice, sent: 2', async () => {
    await seedSubscription(ALICE, ENDPOINT)
    await seedSubscription(ALICE, ENDPOINT_OTHER)

    const calls = installFetchSpy(() => new Response('', { status: 201 }))
    const result = await sendTestPush(envWithStub(), ALICE)

    assert.equal(result.ok, true)
    assert.equal(result.sent, 2, 'both subscriptions dispatched')
    assert.equal(calls.length, 2, 'fetch called exactly twice')
  })

  test('ignores weeklyScanReminder: false — fetch called even when opted out', async () => {
    await seedSubscription(ALICE, ENDPOINT, { weeklyScanReminder: false })

    const calls = installFetchSpy(() => new Response('', { status: 201 }))
    const result = await sendTestPush(envWithStub(), ALICE)

    assert.equal(result.ok, true)
    assert.equal(result.sent, 1, 'opted-out subscription still receives test push')
    assert.equal(calls.length, 1, 'fetch called once')
  })

  test('410 response deletes both push:sub: and push:pref: keys', async () => {
    await seedSubscription(ALICE, ENDPOINT)
    assert.equal(env.PUSH_KV._dump().length, 2)

    installFetchSpy(() => new Response('', { status: 410 }))
    const result = await sendTestPush(envWithStub(), ALICE)

    assert.equal(result.ok, true)
    assert.equal(result.sent, 0, 'gone subscription not counted as sent')
    const remaining = env.PUSH_KV._dump()
    assert.equal(remaining.length, 0, 'both sub + pref keys deleted on 410')
  })
})
