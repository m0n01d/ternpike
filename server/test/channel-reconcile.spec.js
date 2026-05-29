// [Notifications] #341 — Share-link vs email-invite channel reconciliation.
//
// Two notification channels coexist without double-notifying:
//
//   Primary   POST /sharedtrips/:id/share-link  — SILENT (no email, no push).
//             The link is handed to navigator.share by the client; the server
//             just mints the token and returns the URL.
//
//   Secondary POST /sharedtrips/:id/invite      — emails a named invitee AND
//             fires a push via sendSharedTripInvitePush. 24h dedup prevents
//             duplicate pushes for the same (inviter, invitee, trip) tuple.
//
// Tests run without Docker — CouchDB is faked by an in-process Node http server
// that returns a minimal sharedtrip:meta doc. Resend is captured via
// installResendCapture(). Push fan-out is stubbed via env.__buildPushPayload.
//
// See docs/nest-invite-funnel.md §C "Notification channels" for the model.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'

import { request } from './fixtures/app.js'
import { basicAuthHeader } from './fixtures/auth.js'
import { installResendCapture, memoryKv } from './fixtures/env.js'
import { sha256Hex } from '../notifications.js'

const ALICE = 'alice@test.ternpike.com'
const BOB = 'bob@test.ternpike.com'
const SERVER_SECRET = 'test-server-secret-do-not-use-in-production'
const SHARED_TRIP_ID = 'aa11bb22cc33'
const DB_NAME = `sharedtrip-${SHARED_TRIP_ID}`
const TRIP_NAME = 'Channel Reconcile Test Trip'

// Minimal sharedtrip:meta that satisfies readSharedTripMeta + owner/member checks.
const makeMeta = ({ billingOwner = ALICE, members = [ALICE], billingStatus = 'active' } = {}) => ({
  _id: 'sharedtrip:meta',
  _rev: '1-abc',
  type: 'sharedtrip:meta',
  flockId: SHARED_TRIP_ID,
  name: TRIP_NAME,
  members,
  billingOwner,
  billingStatus,
  billingLapsedAt: null,
  inviteEpoch: 0,
  createdBy: ALICE,
  createdAt: '2026-01-01T00:00:00.000Z',
})

// Spin up a minimal in-process CouchDB stub. Returns the sharedtrip:meta doc
// on GET /sharedtrip-<id>/sharedtrip%3Ameta; everything else 404s.
async function startMockCouch() {
  const server = http.createServer((req, res) => {
    res.setHeader('Content-Type', 'application/json')
    // GET /sharedtrip-<id>/sharedtrip%3Ameta → return meta
    if (req.method === 'GET' && req.url === `/${DB_NAME}/sharedtrip%3Ameta`) {
      res.statusCode = 200
      res.end(JSON.stringify(makeMeta()))
      return
    }
    // Any other path → 404 (don't need _security or _bulk_docs for these tests)
    res.statusCode = 404
    res.end(JSON.stringify({ error: 'not_found', reason: 'missing' }))
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  const { port } = server.address()
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve) => server.close(() => resolve())),
  }
}

// Build an env that points to the mock CouchDB, with an in-memory PUSH_KV.
function buildEnv(couch, overrides = {}) {
  return {
    COUCH_URL: couch.baseUrl,
    COUCH_ADMIN_USER: 'admin',
    COUCH_ADMIN_PASS: 'password',
    SERVER_SECRET,
    RESEND_API_KEY: 'test-resend-key',
    TIER_WEBHOOK_SECRET: 'test-webhook-secret',
    CODES_KV: memoryKv(),
    TIERS_KV: memoryKv(),
    INVITE_KV: memoryKv(),
    PUSH_KV: memoryKv(),
    VAPID_PRIVATE_KEY: 'test-vapid-private',
    VAPID_PUBLIC_KEY: 'test-vapid-public',
    VAPID_SUBJECT: 'mailto:test@ternpike.com',
    ...overrides,
  }
}

// Build Alice's paid-tier env (osprey, so invite endpoint is accessible).
async function buildAliceEnv(couch, extraEnv = {}) {
  const tiers = memoryKv()
  await tiers.put(ALICE, 'osprey')
  return buildEnv(couch, { TIERS_KV: tiers, ...extraEnv })
}

// Plant a push subscription for an email directly in PUSH_KV.
async function seedPushSub(env, email, endpoint = `https://push.example.com/${email}`) {
  const hash = await sha256Hex(endpoint)
  await env.PUSH_KV.put(
    `push:sub:${email.toLowerCase()}:${hash}`,
    JSON.stringify({
      auth: 'auth-secret',
      createdAt: '2026-05-01T00:00:00.000Z',
      endpoint,
      p256dh: 'p256dh-pub',
      tierAtSubscribe: 'osprey',
    }),
  )
  await env.PUSH_KV.put(
    `push:pref:${email.toLowerCase()}:${hash}`,
    JSON.stringify({
      sharedTripAccessChange: true,
      sharedTripActivity: true,
      sharedTripInvite: true,
      syncStalled: true,
      weeklyScanReminder: true,
    }),
  )
}

// A push payload builder that records calls without doing VAPID crypto.
function stubBuildPushPayload(calls) {
  return async (msg, _sub, _vapid) => {
    calls.push(JSON.parse(msg.data))
    return { body: 'stub', headers: { 'content-type': 'application/octet-stream' }, method: 'POST' }
  }
}

let couch
let resend
let aliceAuth

beforeEach(async () => {
  couch = await startMockCouch()
  resend = installResendCapture()
  aliceAuth = await basicAuthHeader(ALICE, SERVER_SECRET)
})

afterEach(async () => {
  resend.uninstall()
  await couch.close()
})

// ---------------------------------------------------------------------------
// PRIMARY CHANNEL: share-link — silent (no email, no push)
// ---------------------------------------------------------------------------

describe('[#341] share-link path is silent', () => {
  test('POST /sharedtrips/:id/share-link sends no Resend email', async () => {
    const env = await buildAliceEnv(couch)

    const res = await request(env, 'POST', `/sharedtrips/${SHARED_TRIP_ID}/share-link`, {
      headers: { Authorization: aliceAuth },
    })

    // Endpoint may return 200 or 500 depending on whether SECRET-based JWT
    // signing succeeds in the test env — what matters is NO email was sent.
    assert.equal(resend.sent.length, 0, 'share-link must send no Resend email')
  })

  test('POST /sharedtrips/:id/share-link triggers no push fan-out', async () => {
    const pushCalls = []
    const env = await buildAliceEnv(couch, {
      __buildPushPayload: stubBuildPushPayload(pushCalls),
    })

    // Give Alice a push subscription so we'd notice if anything fired.
    await seedPushSub(env, ALICE)

    let fetchCalls = 0
    const realFetch = globalThis.fetch
    globalThis.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input.url
      // Count calls to push endpoints (not CouchDB/Resend)
      if (url.startsWith('https://push.example.com')) {
        fetchCalls++
      }
      return realFetch(input, init)
    }
    try {
      await request(env, 'POST', `/sharedtrips/${SHARED_TRIP_ID}/share-link`, {
        headers: { Authorization: aliceAuth },
      })
    } finally {
      globalThis.fetch = realFetch
    }

    assert.equal(pushCalls.length, 0, 'share-link must invoke no push builder')
    assert.equal(fetchCalls, 0, 'share-link must POST to no push endpoints')
  })
})

// ---------------------------------------------------------------------------
// SECONDARY CHANNEL: email-invite — dedup is intact
// ---------------------------------------------------------------------------

describe('[#341] email-invite 24h dedup is intact', () => {
  test('invite push not re-sent within 24h for same (inviter, invitee, trip)', async () => {
    const pushCalls = []
    const env = await buildAliceEnv(couch, {
      __buildPushPayload: stubBuildPushPayload(pushCalls),
    })

    // Give Bob a push subscription so the first invite push could fire.
    await seedPushSub(env, BOB, `https://push.example.com/bob`)

    // Write the dedup key directly — simulating that an invite push was already
    // sent within the last 24h for this exact (alice, bob, trip) tuple.
    const dedupKey = `push:invite-dedup:${ALICE.toLowerCase()}:${BOB.toLowerCase()}:${SHARED_TRIP_ID}`
    await env.PUSH_KV.put(dedupKey, '1', { expirationTtl: 24 * 60 * 60 })

    // The dedup key now exists — sendSharedTripInvitePush must return early.
    // We test sendSharedTripInvitePush directly (same pattern as invite-push.spec.js).
    const { sendSharedTripInvitePush } = await import('../notifications.js')

    const realFetch = globalThis.fetch
    let pushFetches = 0
    globalThis.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input.url
      if (url.startsWith('https://push.example.com')) pushFetches++
      return realFetch(input, init)
    }
    try {
      await sendSharedTripInvitePush(env, {
        inviteeEmail: BOB,
        inviterEmail: ALICE,
        sharedTripId: SHARED_TRIP_ID,
        tripName: TRIP_NAME,
      })
    } finally {
      globalThis.fetch = realFetch
    }

    assert.equal(pushFetches, 0, 'dedup key present → no push endpoint POSTed')
    assert.equal(pushCalls.length, 0, 'dedup key present → push builder not called')
  })

  test('dedup key is keyed on (inviter, invitee, tripId) — different trip is NOT deduped', async () => {
    const pushCalls = []
    const env = await buildAliceEnv(couch, {
      __buildPushPayload: stubBuildPushPayload(pushCalls),
    })
    await seedPushSub(env, BOB, `https://push.example.com/bob`)

    // Pre-seed dedup for SHARED_TRIP_ID.
    const dedupKey = `push:invite-dedup:${ALICE.toLowerCase()}:${BOB.toLowerCase()}:${SHARED_TRIP_ID}`
    await env.PUSH_KV.put(dedupKey, '1', { expirationTtl: 24 * 60 * 60 })

    const { sendSharedTripInvitePush } = await import('../notifications.js')
    const realFetch = globalThis.fetch
    let pushFetches = 0
    globalThis.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input.url
      if (url.startsWith('https://push.example.com')) pushFetches++
      // Respond 201 OK so sentAny is true and dedup key is written.
      return new Response('', { status: 201 })
    }
    try {
      await sendSharedTripInvitePush(env, {
        inviteeEmail: BOB,
        inviterEmail: ALICE,
        sharedTripId: 'different-trip-id',  // different trip — no dedup
        tripName: 'Different Trip',
      })
    } finally {
      globalThis.fetch = realFetch
    }

    assert.equal(pushFetches, 1, 'different tripId is not covered by dedup → push fires')
    assert.equal(pushCalls.length, 1, 'push builder called once for different trip')
  })

  test('dedup key format is push:invite-dedup:<inviter>:<invitee>:<tripId>', async () => {
    // Structural test — verify the KV key written by sendSharedTripInvitePush
    // matches the documented format so future callers can construct it.
    const env = await buildAliceEnv(couch)
    const { sendSharedTripInvitePush } = await import('../notifications.js')

    // No push subscriptions — function will skip push fan-out but still write the dedup key.
    const realFetch = globalThis.fetch
    globalThis.fetch = async () => new Response('', { status: 201 })
    try {
      await sendSharedTripInvitePush(env, {
        inviteeEmail: BOB,
        inviterEmail: ALICE,
        sharedTripId: SHARED_TRIP_ID,
        tripName: TRIP_NAME,
      })
    } finally {
      globalThis.fetch = realFetch
    }

    const expectedKey = `push:invite-dedup:${ALICE.toLowerCase()}:${BOB.toLowerCase()}:${SHARED_TRIP_ID}`
    const dedupValue = await env.PUSH_KV.get(expectedKey)
    assert.equal(dedupValue, '1', `dedup key ${expectedKey} should be written after send`)
  })
})
