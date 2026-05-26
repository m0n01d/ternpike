// Coverage for `sendSharedTripAccessChangePush` (#226).
//
// No CouchDB dependency — authentication uses in-memory KV fixtures.
// Push fan-out stubs `buildPushPayload` via `env.__buildPushPayload` and
// captures `fetch` calls via `installFetchSpy`.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { sendSharedTripAccessChangePush, sha256Hex } from '../notifications.js'
import { memoryKv } from './fixtures/env.js'

const ALICE = 'alice@test.ternpike.com'
const BOB = 'bob@test.ternpike.com'

const BOB_ENDPOINT = 'https://push.example.com/bob'
const ALICE_ENDPOINT = 'https://push.example.com/alice'
const KEYS = { auth: 'auth-secret', p256dh: 'p256dh-pub' }

const TRIP_NAME = 'Italy 2026'

let env
let realFetch

// Plant a push subscription directly in PUSH_KV (bypasses tier gate).
async function seedSub(email, endpoint, prefs) {
  const hash = await sha256Hex(endpoint)
  await env.PUSH_KV.put(
    `push:sub:${email.toLowerCase()}:${hash}`,
    JSON.stringify({
      auth: KEYS.auth,
      createdAt: '2026-05-01T00:00:00.000Z',
      endpoint,
      p256dh: KEYS.p256dh,
      tierAtSubscribe: 'osprey',
    }),
  )
  await env.PUSH_KV.put(
    `push:pref:${email.toLowerCase()}:${hash}`,
    JSON.stringify(
      prefs ?? {
        sharedTripAccessChange: true,
        sharedTripActivity: true,
        syncStalled: true,
        weeklyScanReminder: true,
      },
    ),
  )
}

function stubBuildPushPayload() {
  return async (_msg, _sub, _vapid) => ({
    body: 'test-encrypted-payload',
    headers: { 'content-type': 'application/octet-stream' },
    method: 'POST',
  })
}

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

function envWithStub() {
  return {
    ...env,
    VAPID_PRIVATE_KEY: 'test-vapid-private',
    VAPID_PUBLIC_KEY: 'test-vapid-public',
    VAPID_SUBJECT: 'mailto:test@ternpike.com',
    __buildPushPayload: stubBuildPushPayload(),
  }
}

beforeEach(async () => {
  env = {
    PUSH_KV: memoryKv(),
  }
})

afterEach(() => {
  if (realFetch) {
    globalThis.fetch = realFetch
    realFetch = undefined
  }
})

// ---------------------------------------------------------------------------
// Removal tests
// ---------------------------------------------------------------------------

describe('sendSharedTripAccessChangePush — removal', () => {
  test('positive: Bob receives push with read-only subtitle when removed', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    const calls = installFetchSpy(() => new Response('', { status: 201 }))
    const capturedMsgs = []
    const captureEnv = {
      ...envWithStub(),
      __buildPushPayload: async (msg, _sub, _vapid) => {
        capturedMsgs.push(msg)
        return { body: 'payload', headers: { 'content-type': 'application/octet-stream' }, method: 'POST' }
      },
    }

    await sendSharedTripAccessChangePush(captureEnv, {
      kind: 'removed',
      recipientEmail: BOB,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 1, 'exactly one push delivered to Bob')
    assert.equal(calls[0].url, BOB_ENDPOINT)
    assert.equal(capturedMsgs.length, 1)
    const payload = JSON.parse(capturedMsgs[0].data)
    assert.ok(
      payload.title.includes(TRIP_NAME),
      `title should include trip name, got: ${payload.title}`,
    )
    assert.ok(
      payload.title.includes('You were removed from'),
      `title should say "You were removed from", got: ${payload.title}`,
    )
    assert.ok(
      payload.body.includes('read-only'),
      `body should include read-only subtitle, got: ${payload.body}`,
    )
    assert.equal(payload.data.url, '/settings', 'tap action should be /settings')
  })

  test('pref-off: Bob with sharedTripAccessChange:false receives no push', async () => {
    await seedSub(BOB, BOB_ENDPOINT, {
      sharedTripAccessChange: false,
      sharedTripActivity: true,
      syncStalled: true,
      weeklyScanReminder: true,
    })
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    await sendSharedTripAccessChangePush(envWithStub(), {
      kind: 'removed',
      recipientEmail: BOB,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 0, 'opted-out Bob receives no push')
  })

  test('410 → both push:sub: and push:pref: deleted on removal', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    assert.equal(env.PUSH_KV._dump().filter(([k]) => k.startsWith('push:')).length, 2)

    installFetchSpy(() => new Response('', { status: 410 }))

    await sendSharedTripAccessChangePush(envWithStub(), {
      kind: 'removed',
      recipientEmail: BOB,
      tripName: TRIP_NAME,
    })

    const remaining = env.PUSH_KV._dump().filter(
      ([k]) => k.startsWith('push:sub:') || k.startsWith('push:pref:'),
    )
    assert.equal(remaining.length, 0, 'both sub + pref deleted on 410')
  })

  test('404 → both push:sub: and push:pref: deleted on removal', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    installFetchSpy(() => new Response('', { status: 404 }))

    await sendSharedTripAccessChangePush(envWithStub(), {
      kind: 'removed',
      recipientEmail: BOB,
      tripName: TRIP_NAME,
    })

    const remaining = env.PUSH_KV._dump().filter(
      ([k]) => k.startsWith('push:sub:') || k.startsWith('push:pref:'),
    )
    assert.equal(remaining.length, 0, 'both sub + pref deleted on 404')
  })
})

// ---------------------------------------------------------------------------
// Transfer-ownership tests
// ---------------------------------------------------------------------------

describe('sendSharedTripAccessChangePush — transfer', () => {
  test('positive: Bob receives push with @alice handle and trip name on transfer', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    const calls = installFetchSpy(() => new Response('', { status: 201 }))
    const capturedMsgs = []
    const captureEnv = {
      ...envWithStub(),
      __buildPushPayload: async (msg, _sub, _vapid) => {
        capturedMsgs.push(msg)
        return { body: 'payload', headers: { 'content-type': 'application/octet-stream' }, method: 'POST' }
      },
    }

    await sendSharedTripAccessChangePush(captureEnv, {
      kind: 'transfer',
      prevOwnerEmail: ALICE,
      recipientEmail: BOB,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 1, 'exactly one push delivered to Bob')
    assert.equal(calls[0].url, BOB_ENDPOINT)
    assert.equal(capturedMsgs.length, 1)
    const payload = JSON.parse(capturedMsgs[0].data)
    assert.ok(
      payload.body.includes('@alice'),
      `body should include @alice handle, got: ${payload.body}`,
    )
    assert.ok(
      payload.body.includes(TRIP_NAME),
      `body should include trip name, got: ${payload.body}`,
    )
    assert.ok(
      payload.body.includes('billing owner'),
      `body should mention billing owner, got: ${payload.body}`,
    )
    assert.equal(payload.data.url, '/settings', 'tap action should be /settings')
  })

  test('previous-owner-does-not-push: Alice does not receive a push on transfer', async () => {
    await seedSub(ALICE, ALICE_ENDPOINT)
    await seedSub(BOB, BOB_ENDPOINT)
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    await sendSharedTripAccessChangePush(envWithStub(), {
      kind: 'transfer',
      prevOwnerEmail: ALICE,
      recipientEmail: BOB,
      tripName: TRIP_NAME,
    })

    // Only Bob should receive a push; Alice is the previous owner (initiator)
    assert.equal(calls.length, 1, 'only one push sent')
    assert.equal(calls[0].url, BOB_ENDPOINT, 'push goes to Bob (new owner), not Alice')
  })

  test('pref-off: Bob with sharedTripAccessChange:false receives no push on transfer', async () => {
    await seedSub(BOB, BOB_ENDPOINT, {
      sharedTripAccessChange: false,
      sharedTripActivity: true,
      syncStalled: true,
      weeklyScanReminder: true,
    })
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    await sendSharedTripAccessChangePush(envWithStub(), {
      kind: 'transfer',
      prevOwnerEmail: ALICE,
      recipientEmail: BOB,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 0, 'opted-out Bob receives no push on transfer')
  })

  test('410 → both push:sub: and push:pref: deleted on transfer', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    assert.equal(env.PUSH_KV._dump().filter(([k]) => k.startsWith('push:')).length, 2)

    installFetchSpy(() => new Response('', { status: 410 }))

    await sendSharedTripAccessChangePush(envWithStub(), {
      kind: 'transfer',
      prevOwnerEmail: ALICE,
      recipientEmail: BOB,
      tripName: TRIP_NAME,
    })

    const remaining = env.PUSH_KV._dump().filter(
      ([k]) => k.startsWith('push:sub:') || k.startsWith('push:pref:'),
    )
    assert.equal(remaining.length, 0, 'both sub + pref deleted on 410')
  })
})
