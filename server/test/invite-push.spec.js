// Coverage for `sendSharedTripInvitePush` (#221).
//
// No CouchDB dependency — authentication uses in-memory KV fixtures.
// Push fan-out stubs `buildPushPayload` via `env.__buildPushPayload` and
// captures `fetch` calls via `installFetchSpy`.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { sendSharedTripInvitePush, sha256Hex } from '../notifications.js'
import { memoryKv } from './fixtures/env.js'

const ALICE = 'alice@test.ternpike.com'
const BOB = 'bob@test.ternpike.com'
const CAROL = 'carol@test.ternpike.com'

const BOB_ENDPOINT = 'https://push.example.com/bob'
const ALICE_ENDPOINT = 'https://push.example.com/alice'
const CAROL_ENDPOINT = 'https://push.example.com/carol'
const KEYS = { auth: 'auth-secret', p256dh: 'p256dh-pub' }

const TRIP_NAME = 'Italy 2026'
const SHARED_TRIP_ID = 'abc123sharedtrip'

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
        sharedTripInvite: true,
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
// Positive test
// ---------------------------------------------------------------------------

describe('sendSharedTripInvitePush — positive', () => {
  test('Bob receives push with @alice handle, trip name, and /settings tap URL', async () => {
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

    await sendSharedTripInvitePush(captureEnv, {
      inviteeEmail: BOB,
      inviterEmail: ALICE,
      sharedTripId: SHARED_TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 1, 'exactly one push delivered to Bob')
    assert.equal(calls[0].url, BOB_ENDPOINT)
    assert.equal(capturedMsgs.length, 1)
    const payload = JSON.parse(capturedMsgs[0].data)
    assert.ok(
      payload.title.includes('@alice'),
      `title should include @alice handle, got: ${payload.title}`,
    )
    assert.ok(
      payload.title.includes(TRIP_NAME),
      `title should include trip name, got: ${payload.title}`,
    )
    assert.ok(
      payload.title.includes('invited you to'),
      `title should say "invited you to", got: ${payload.title}`,
    )
    assert.ok(
      payload.body.includes('accept or decline'),
      `body should mention accept or decline, got: ${payload.body}`,
    )
    assert.equal(payload.data.url, '/settings', 'tap action should be /settings')
  })
})

// ---------------------------------------------------------------------------
// Pref-off test
// ---------------------------------------------------------------------------

describe('sendSharedTripInvitePush — pref-off', () => {
  test('Bob with sharedTripInvite:false receives no push', async () => {
    await seedSub(BOB, BOB_ENDPOINT, {
      sharedTripAccessChange: true,
      sharedTripActivity: true,
      sharedTripInvite: false,
      syncStalled: true,
      weeklyScanReminder: true,
    })
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    await sendSharedTripInvitePush(envWithStub(), {
      inviteeEmail: BOB,
      inviterEmail: ALICE,
      sharedTripId: SHARED_TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 0, 'opted-out Bob receives no push')
  })
})

// ---------------------------------------------------------------------------
// 24h dedup tests
// ---------------------------------------------------------------------------

describe('sendSharedTripInvitePush — 24h dedup', () => {
  test('same invite twice fires push only once', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    // First invite — should push.
    await sendSharedTripInvitePush(envWithStub(), {
      inviteeEmail: BOB,
      inviterEmail: ALICE,
      sharedTripId: SHARED_TRIP_ID,
      tripName: TRIP_NAME,
    })

    // Second invite (same tuple) — should be suppressed by dedup.
    await sendSharedTripInvitePush(envWithStub(), {
      inviteeEmail: BOB,
      inviterEmail: ALICE,
      sharedTripId: SHARED_TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 1, 'only one push sent despite two calls (dedup)')
  })

  test('different inviter is not deduped', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    // Alice invites Bob.
    await sendSharedTripInvitePush(envWithStub(), {
      inviteeEmail: BOB,
      inviterEmail: ALICE,
      sharedTripId: SHARED_TRIP_ID,
      tripName: TRIP_NAME,
    })

    // Carol also invites Bob (different inviter — different dedup key).
    await sendSharedTripInvitePush(envWithStub(), {
      inviteeEmail: BOB,
      inviterEmail: CAROL,
      sharedTripId: SHARED_TRIP_ID,
      tripName: TRIP_NAME,
    })

    assert.equal(calls.length, 2, 'different inviter produces a second push')
  })

  test('different trip is not deduped', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    // Alice invites Bob to trip A.
    await sendSharedTripInvitePush(envWithStub(), {
      inviteeEmail: BOB,
      inviterEmail: ALICE,
      sharedTripId: 'trip-A',
      tripName: 'Trip A',
    })

    // Alice also invites Bob to trip B (different trip — different dedup key).
    await sendSharedTripInvitePush(envWithStub(), {
      inviteeEmail: BOB,
      inviterEmail: ALICE,
      sharedTripId: 'trip-B',
      tripName: 'Trip B',
    })

    assert.equal(calls.length, 2, 'different trip produces a second push')
  })
})

// ---------------------------------------------------------------------------
// 404/410 cleanup
// ---------------------------------------------------------------------------

describe('sendSharedTripInvitePush — stale subscription cleanup', () => {
  test('410 → both push:sub: and push:pref: deleted', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    assert.equal(env.PUSH_KV._dump().filter(([k]) => k.startsWith('push:')).length, 2)

    installFetchSpy(() => new Response('', { status: 410 }))

    await sendSharedTripInvitePush(envWithStub(), {
      inviteeEmail: BOB,
      inviterEmail: ALICE,
      sharedTripId: SHARED_TRIP_ID,
      tripName: TRIP_NAME,
    })

    const remaining = env.PUSH_KV._dump().filter(
      ([k]) => k.startsWith('push:sub:') || k.startsWith('push:pref:'),
    )
    assert.equal(remaining.length, 0, 'both sub + pref deleted on 410')
  })

  test('404 → both push:sub: and push:pref: deleted', async () => {
    await seedSub(BOB, BOB_ENDPOINT)
    installFetchSpy(() => new Response('', { status: 404 }))

    await sendSharedTripInvitePush(envWithStub(), {
      inviteeEmail: BOB,
      inviterEmail: ALICE,
      sharedTripId: SHARED_TRIP_ID,
      tripName: TRIP_NAME,
    })

    const remaining = env.PUSH_KV._dump().filter(
      ([k]) => k.startsWith('push:sub:') || k.startsWith('push:pref:'),
    )
    assert.equal(remaining.length, 0, 'both sub + pref deleted on 404')
  })
})

// ---------------------------------------------------------------------------
// No-subscriptions silent skip
// ---------------------------------------------------------------------------

describe('sendSharedTripInvitePush — no subscriptions', () => {
  test('invitee has no push subscriptions — no error, no fetch call', async () => {
    // Bob has no subscriptions in PUSH_KV.
    const calls = installFetchSpy(() => new Response('', { status: 201 }))

    // Should return silently — no throw, no fetch.
    await assert.doesNotReject(
      () =>
        sendSharedTripInvitePush(envWithStub(), {
          inviteeEmail: BOB,
          inviterEmail: ALICE,
          sharedTripId: SHARED_TRIP_ID,
          tripName: TRIP_NAME,
        }),
      'should not reject when invitee has no subscriptions',
    )

    assert.equal(calls.length, 0, 'no fetch calls when no subscriptions exist')
  })
})
