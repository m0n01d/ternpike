// Coverage for `sendSharedTripActivityPush` (#220) and the
// `POST /sharedtrips/:id/notify-activity` endpoint.
//
// No CouchDB dependency — authentication uses the in-memory KV fixtures.
// Push fan-out stubs `buildPushPayload` via `env.__buildPushPayload` and
// captures `fetch` calls.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { sendSharedTripActivityPush, sha256Hex } from '../notifications.js'
import { request } from './fixtures/app.js'
import { basicAuthHeader } from './fixtures/auth.js'
import { memoryKv } from './fixtures/env.js'

const ALICE = 'alice@test.ternpike.com'
const BOB = 'bob@test.ternpike.com'
const CAROL = 'carol@test.ternpike.com'
const SERVER_SECRET = 'test-server-secret-do-not-use-in-production'

const ALICE_ENDPOINT = 'https://push.example.com/alice'
const BOB_ENDPOINT = 'https://push.example.com/bob'
const CAROL_ENDPOINT = 'https://push.example.com/carol'
const KEYS = { auth: 'auth-secret', p256dh: 'p256dh-pub' }

const TRIP_ID = 'abc123'
const TRIP_NAME = 'Italy 2026'

let env
let realFetch

async function authed(email) {
  return { Authorization: await basicAuthHeader(email, SERVER_SECRET) }
}

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
    JSON.stringify(prefs ?? { sharedTripActivity: true, syncStalled: true, weeklyScanReminder: true }),
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
    SERVER_SECRET,
    TIERS_KV: memoryKv(),
  }
  await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey')
  await env.TIERS_KV.put(BOB.toLowerCase(), 'osprey')
  await env.TIERS_KV.put(CAROL.toLowerCase(), 'osprey')
})

afterEach(() => {
  if (realFetch) {
    globalThis.fetch = realFetch
    realFetch = undefined
  }
})

// ---------------------------------------------------------------------------
// Unit tests for sendSharedTripActivityPush
// ---------------------------------------------------------------------------

describe('sendSharedTripActivityPush', () => {
  test('positive: Bob receives push when Alice adds an expense', async () => {
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

    await sendSharedTripActivityPush(captureEnv, {
      action: 'add',
      allMembers: [ALICE, BOB],
      amount: 12.5,
      authorEmail: ALICE,
      note: 'Pasta dinner',
      tripId: TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 1, 'exactly one push delivered to Bob')
    assert.equal(calls[0].url, BOB_ENDPOINT)
    assert.equal(capturedMsgs.length, 1)
    const payload = JSON.parse(capturedMsgs[0].data)
    assert.ok(payload.body.includes('@alice'), `body should include @alice handle, got: ${payload.body}`)
    assert.ok(payload.body.includes('12.50'), `body should include amount, got: ${payload.body}`)
    assert.ok(payload.body.includes('Pasta dinner'), `body should include note clip, got: ${payload.body}`)
    assert.equal(payload.data.url, `/trip/ledger?tripId=${encodeURIComponent('trip::' + TRIP_ID)}`)
    assert.equal(payload.title, TRIP_NAME)
  })

  test('author-no-self-push: Alice does not receive her own push', async () => {
    await seedSub(ALICE, ALICE_ENDPOINT)
    await seedSub(BOB, BOB_ENDPOINT)
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    await sendSharedTripActivityPush(envWithStub(), {
      action: 'add',
      allMembers: [ALICE, BOB],
      amount: 5.0,
      authorEmail: ALICE,
      note: null,
      tripId: TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 1, 'only Bob receives push, not Alice')
    assert.equal(calls[0].url, BOB_ENDPOINT, 'the one push goes to Bob')
  })

  test('pref-off: Bob with sharedTripActivity:false receives no push', async () => {
    await seedSub(BOB, BOB_ENDPOINT, { sharedTripActivity: false, syncStalled: true, weeklyScanReminder: true })
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    await sendSharedTripActivityPush(envWithStub(), {
      action: 'edit',
      allMembers: [ALICE, BOB],
      amount: 20.0,
      authorEmail: ALICE,
      note: null,
      tripId: TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 0, 'opted-out Bob receives no push')
  })

  test('void body template includes amount', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    const capturedMsgs = []
    installFetchSpy(() => new Response('', { status: 201 }))
    const captureEnv = {
      ...envWithStub(),
      __buildPushPayload: async (msg, _sub, _vapid) => {
        capturedMsgs.push(msg)
        return { body: 'payload', headers: { 'content-type': 'application/octet-stream' }, method: 'POST' }
      },
    }

    await sendSharedTripActivityPush(captureEnv, {
      action: 'void',
      allMembers: [ALICE, BOB],
      amount: 99.99,
      authorEmail: ALICE,
      note: null,
      tripId: TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(capturedMsgs.length, 1)
    const payload = JSON.parse(capturedMsgs[0].data)
    assert.ok(payload.body.includes('voided'), `body should say voided, got: ${payload.body}`)
    assert.ok(payload.body.includes('99.99'), `body should include amount, got: ${payload.body}`)
  })

  test('edit body template does not include amount', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    const capturedMsgs = []
    installFetchSpy(() => new Response('', { status: 201 }))
    const captureEnv = {
      ...envWithStub(),
      __buildPushPayload: async (msg, _sub, _vapid) => {
        capturedMsgs.push(msg)
        return { body: 'payload', headers: { 'content-type': 'application/octet-stream' }, method: 'POST' }
      },
    }

    await sendSharedTripActivityPush(captureEnv, {
      action: 'edit',
      allMembers: [ALICE, BOB],
      amount: 50.0,
      authorEmail: ALICE,
      note: null,
      tripId: TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(capturedMsgs.length, 1)
    const payload = JSON.parse(capturedMsgs[0].data)
    assert.ok(payload.body.includes('edited'), `body should say edited, got: ${payload.body}`)
    assert.ok(!payload.body.includes('50.00'), `edit body should not include amount, got: ${payload.body}`)
  })

  test('coalescing: 5 rapid events → 1 coalesced push on the 3rd+', async () => {
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

    const args = {
      action: 'add',
      allMembers: [ALICE, BOB],
      amount: 10.0,
      authorEmail: ALICE,
      note: null,
      tripId: TRIP_ID,
      tripName: TRIP_NAME,
    }

    for (let i = 0; i < 5; i++) {
      await sendSharedTripActivityPush(captureEnv, args)
    }

    // All 5 calls reach the send path (one push per call to Bob).
    assert.equal(calls.length, 5, '5 pushes sent (one per event, including coalesced ones)')

    // From the 3rd event onwards, the body should be the coalesced form.
    const firstPayload = JSON.parse(capturedMsgs[0].data)
    const thirdPayload = JSON.parse(capturedMsgs[2].data)
    const fifthPayload = JSON.parse(capturedMsgs[4].data)

    assert.ok(firstPayload.body.includes('added'), `first should be individual, got: ${firstPayload.body}`)
    assert.ok(thirdPayload.body.includes('3 expenses'), `3rd should be coalesced with count 3, got: ${thirdPayload.body}`)
    assert.ok(fifthPayload.body.includes('5 expenses'), `5th should be coalesced with count 5, got: ${fifthPayload.body}`)
  })

  test('coalescing keys are per (author, trip, recipient) — separate trips do not share state', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    const capturedMsgs = []
    installFetchSpy(() => new Response('', { status: 201 }))
    const captureEnv = {
      ...envWithStub(),
      __buildPushPayload: async (msg, _sub, _vapid) => {
        capturedMsgs.push(msg)
        return { body: 'payload', headers: { 'content-type': 'application/octet-stream' }, method: 'POST' }
      },
    }

    const otherTripId = 'def456'
    const args1 = { action: 'add', allMembers: [ALICE, BOB], amount: 5, authorEmail: ALICE, note: null, tripId: TRIP_ID, tripName: 'Italy' }
    const args2 = { action: 'add', allMembers: [ALICE, BOB], amount: 5, authorEmail: ALICE, note: null, tripId: otherTripId, tripName: 'Japan' }

    // 3 events on trip 1 → coalesced
    await sendSharedTripActivityPush(captureEnv, args1)
    await sendSharedTripActivityPush(captureEnv, args1)
    await sendSharedTripActivityPush(captureEnv, args1)

    // First event on different trip → should be individual (count = 1)
    await sendSharedTripActivityPush(captureEnv, args2)

    const fourthPayload = JSON.parse(capturedMsgs[3].data)
    assert.ok(!fourthPayload.body.includes('expenses'), `different trip's 1st event should not be coalesced, got: ${fourthPayload.body}`)
    assert.ok(fourthPayload.body.includes('added'), `different trip's 1st event should be individual, got: ${fourthPayload.body}`)
  })

  test('410 → both push:sub: and push:pref: deleted', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    assert.equal(env.PUSH_KV._dump().filter(([k]) => k.startsWith('push:')).length, 2)

    installFetchSpy(() => new Response('', { status: 410 }))

    await sendSharedTripActivityPush(envWithStub(), {
      action: 'add',
      allMembers: [ALICE, BOB],
      amount: 5.0,
      authorEmail: ALICE,
      note: null,
      tripId: TRIP_ID,
      tripName: TRIP_NAME,
    })

    const remaining = env.PUSH_KV._dump().filter(([k]) => k.startsWith('push:sub:') || k.startsWith('push:pref:'))
    assert.equal(remaining.length, 0, 'both sub + pref deleted on 410')
  })

  test('404 → both push:sub: and push:pref: deleted', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    installFetchSpy(() => new Response('', { status: 404 }))

    await sendSharedTripActivityPush(envWithStub(), {
      action: 'add',
      allMembers: [ALICE, BOB],
      amount: 5.0,
      authorEmail: ALICE,
      note: null,
      tripId: TRIP_ID,
      tripName: TRIP_NAME,
    })

    const remaining = env.PUSH_KV._dump().filter(([k]) => k.startsWith('push:sub:') || k.startsWith('push:pref:'))
    assert.equal(remaining.length, 0, 'both sub + pref deleted on 404')
  })

  test('fan-out to multiple recipients: Carol and Bob both receive push', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    await seedSub(CAROL, CAROL_ENDPOINT)
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    await sendSharedTripActivityPush(envWithStub(), {
      action: 'add',
      allMembers: [ALICE, BOB, CAROL],
      amount: 30.0,
      authorEmail: ALICE,
      note: null,
      tripId: TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 2, 'both Bob and Carol receive a push')
    const urls = calls.map((c) => c.url).sort()
    assert.deepEqual(urls, [BOB_ENDPOINT, CAROL_ENDPOINT].sort())
  })

  test('no PUSH_KV binding → no error thrown', async () => {
    // Simulates a misconfigured Worker env — should fail gracefully.
    const noKvEnv = { ...envWithStub(), PUSH_KV: undefined }

    await assert.doesNotReject(
      sendSharedTripActivityPush(noKvEnv, {
        action: 'add',
        allMembers: [ALICE, BOB],
        amount: 5.0,
        authorEmail: ALICE,
        note: null,
        tripId: TRIP_ID,
        tripName: TRIP_NAME,
      }),
    )
  })
})

// ---------------------------------------------------------------------------
// HTTP endpoint: POST /sharedtrips/:id/notify-activity
// ---------------------------------------------------------------------------

describe('POST /sharedtrips/:id/notify-activity', () => {
  // The notify-activity endpoint reads sharedtrip:meta from CouchDB. We
  // can't easily stub CouchDB in these unit tests (that's for e2e/sec),
  // so the tests below focus on the auth layer (no CouchDB needed).

  test('missing auth returns 401', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${TRIP_ID}/notify-activity`, {
      body: { action: 'add', amount: 10 },
    })
    assert.equal(res.status, 401)
    assert.equal(res.body.ok, false)
  })

  test('invalid action returns 400 or 404/500 (no CouchDB)', async () => {
    // Without a real CouchDB the meta read will fail (500 or 404),
    // but for unauthenticated calls it must be 401 first.
    const res = await request(env, 'POST', `/sharedtrips/${TRIP_ID}/notify-activity`, {
      body: { action: 'invalid', amount: 10 },
    })
    // The endpoint is 401 without auth — action validation happens after auth.
    assert.equal(res.status, 401)
  })
})
