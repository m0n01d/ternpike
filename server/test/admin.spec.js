// Coverage for the `/admin/users*` mutation routes after the tier-shadow
// fix (admin writes now go through `upsertUser`, the canonical `user:<email>`
// record, instead of the legacy bare-key `setTier` that `getTier` shadowed).
//
// No CouchDB container needed: these routes only touch `TIERS_KV` for the
// assertions that matter, and the couch calls (provision, the onTierChanged
// cascade, delete) are satisfied by a tiny in-test `fetch` stub — 404 on GET
// (so cascades find no owned trips and dropUser early-returns) and 200 on
// PUT/DELETE (so provisioning succeeds). Mirrors the notifications.spec.js
// in-memory-KV pattern.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { request } from './fixtures/app.js'
import { memoryKv } from './fixtures/env.js'
import { freshUser, slugFor } from '../users.js'

const ADMIN_SECRET = 'test-admin-secret'
const ADMIN = { 'x-admin-secret': ADMIN_SECRET }
const COUCH = 'https://couch.test'

const ALICE = 'alice@test.ternpike.com'
const BOB = 'bob@test.ternpike.com'

const userKey = (email) => 'user:' + email.toLowerCase()

let env
let realFetch

async function seedRecord(email, overrides = {}) {
  const rec = { ...freshUser(email), ...overrides, email: email.toLowerCase() }
  await env.TIERS_KV.put(userKey(email), JSON.stringify(rec))
  return rec
}

async function readRecord(email) {
  const raw = await env.TIERS_KV.get(userKey(email))
  return raw ? JSON.parse(raw) : null
}

beforeEach(() => {
  env = {
    ADMIN_SECRET,
    COUCH_URL: COUCH,
    COUCH_ADMIN_USER: 'admin',
    COUCH_ADMIN_PASS: 'pass',
    SERVER_SECRET: 'test-server-secret-do-not-use-in-production',
    TIERS_KV: memoryKv(),
  }
  realFetch = globalThis.fetch
  globalThis.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input.url
    if (url.startsWith(COUCH)) {
      const method = (init?.method || 'GET').toUpperCase()
      // GET → 404 so cascades find nothing and dropUser early-returns;
      // PUT/DELETE → 200 so provisioning/_security/db-drop succeed.
      return method === 'GET'
        ? new Response('', { status: 404 })
        : new Response('{}', { status: 200 })
    }
    return realFetch(input, init)
  }
})

afterEach(() => {
  globalThis.fetch = realFetch
})

describe('admin guard', () => {
  test('missing x-admin-secret → 401', async () => {
    const res = await request(env, 'GET', '/admin/users')
    assert.equal(res.status, 401)
    assert.equal(res.body.ok, false)
  })

  test('wrong x-admin-secret → 401', async () => {
    const res = await request(env, 'GET', '/admin/users', {
      headers: { 'x-admin-secret': 'nope' },
    })
    assert.equal(res.status, 401)
  })
})

describe('PUT /admin/users/:email/tier (anti-shadow)', () => {
  test('writes the canonical record so getTier sees the new tier', async () => {
    // Simulate the bug's precondition: a `user:` record pinned to tern,
    // which used to shadow any bare-key admin write.
    const before = await seedRecord(ALICE, { tier: 'tern' })
    const res = await request(env, 'PUT', `/admin/users/${ALICE}/tier`, {
      headers: ADMIN,
      body: { tier: 'osprey' },
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
    assert.equal(res.body.tier, 'osprey')
    // The record getTier reads first is now osprey — the shadow is gone.
    const after = await readRecord(ALICE)
    assert.equal(after.tier, 'osprey')
    assert.equal(after.createdAt, before.createdAt) // preserved
  })

  test('creates a record for an email with none', async () => {
    const res = await request(env, 'PUT', `/admin/users/${BOB}/tier`, {
      headers: ADMIN,
      body: { tier: 'osprey' },
    })
    assert.equal(res.status, 200)
    assert.equal((await readRecord(BOB)).tier, 'osprey')
  })

  test('refuses to downgrade a Trailblazer → 409', async () => {
    await seedRecord(ALICE, { tier: 'trailblazer', trailblazerNumber: 7 })
    const res = await request(env, 'PUT', `/admin/users/${ALICE}/tier`, {
      headers: ADMIN,
      body: { tier: 'tern' },
    })
    assert.equal(res.status, 409)
    assert.equal(res.body.error, 'trailblazer_permanent')
    assert.equal((await readRecord(ALICE)).tier, 'trailblazer') // unchanged
  })

  test('invalid tier → 400', async () => {
    const res = await request(env, 'PUT', `/admin/users/${ALICE}/tier`, {
      headers: ADMIN,
      body: { tier: 'gold' },
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'invalid_tier')
  })
})

describe('PUT /admin/users/:email (generic record update)', () => {
  test('updates billing fields without touching tier', async () => {
    await seedRecord(ALICE, { tier: 'osprey' })
    const res = await request(env, 'PUT', `/admin/users/${ALICE}`, {
      headers: ADMIN,
      body: { subscriptionStatus: 'active', stripeCustomerId: 'cus_123' },
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.record.subscriptionStatus, 'active')
    assert.equal(res.body.record.stripeCustomerId, 'cus_123')
    assert.equal(res.body.record.tier, 'osprey') // untouched
  })

  test('materializes a record for a brand-new email', async () => {
    const res = await request(env, 'PUT', `/admin/users/${BOB}`, {
      headers: ADMIN,
      body: { tier: 'osprey' },
    })
    assert.equal(res.status, 200)
    assert.equal((await readRecord(BOB)).tier, 'osprey')
  })

  test('invalid subscriptionStatus → 400', async () => {
    await seedRecord(ALICE)
    const res = await request(env, 'PUT', `/admin/users/${ALICE}`, {
      headers: ADMIN,
      body: { subscriptionStatus: 'bogus' },
    })
    assert.equal(res.status, 400)
  })

  test('refuses to downgrade a Trailblazer → 409', async () => {
    await seedRecord(ALICE, { tier: 'trailblazer' })
    const res = await request(env, 'PUT', `/admin/users/${ALICE}`, {
      headers: ADMIN,
      body: { tier: 'tern' },
    })
    assert.equal(res.status, 409)
    assert.equal(res.body.error, 'trailblazer_permanent')
  })
})

describe('GET /admin/users (de-pollution)', () => {
  test('one row per user; never user:/slug: keys', async () => {
    await seedRecord(ALICE, { tier: 'osprey', subscriptionStatus: 'active' })
    // slugFor index that upsert writes — must NOT appear as a user row.
    await env.TIERS_KV.put('slug:' + slugFor(ALICE), ALICE.toLowerCase())
    // Legacy bare-key user with no canonical record yet.
    await env.TIERS_KV.put(BOB.toLowerCase(), 'osprey')

    const res = await request(env, 'GET', '/admin/users', { headers: ADMIN })
    assert.equal(res.status, 200)
    const emails = res.body.users.map((u) => u.email).sort()
    assert.deepEqual(emails, [ALICE.toLowerCase(), BOB.toLowerCase()])
    const alice = res.body.users.find((u) => u.email === ALICE.toLowerCase())
    assert.equal(alice.tier, 'osprey')
    assert.equal(alice.subscriptionStatus, 'active')
    assert.ok('trailblazerNumber' in alice)
  })
})

describe('GET /admin/users/:email', () => {
  test('includes the full canonical record', async () => {
    await seedRecord(ALICE, { tier: 'osprey', stripeCustomerId: 'cus_9' })
    const res = await request(env, 'GET', `/admin/users/${ALICE}`, {
      headers: ADMIN,
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.tier, 'osprey')
    assert.equal(res.body.record.stripeCustomerId, 'cus_9')
    assert.equal(res.body.record.tier, 'osprey')
  })
})

describe('DELETE /admin/users/:email (full cleanup)', () => {
  test('removes record, legacy bare key, and slug index', async () => {
    await seedRecord(ALICE, { tier: 'osprey' })
    await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey') // legacy bare
    await env.TIERS_KV.put('slug:' + slugFor(ALICE), ALICE.toLowerCase())

    const res = await request(env, 'DELETE', `/admin/users/${ALICE}`, {
      headers: ADMIN,
    })
    assert.equal(res.status, 200)
    assert.equal(await env.TIERS_KV.get(userKey(ALICE)), null)
    assert.equal(await env.TIERS_KV.get(ALICE.toLowerCase()), null)
    assert.equal(await env.TIERS_KV.get('slug:' + slugFor(ALICE)), null)
  })
})

describe('POST /admin/users (provision)', () => {
  test('writes the canonical record at the requested tier', async () => {
    const res = await request(env, 'POST', '/admin/users', {
      headers: ADMIN,
      body: { email: BOB, tier: 'osprey' },
    })
    assert.equal(res.status, 201)
    assert.equal(res.body.tier, 'osprey')
    assert.equal((await readRecord(BOB)).tier, 'osprey')
  })

  test('refuses to recreate-downgrade a Trailblazer → 409', async () => {
    await seedRecord(BOB, { tier: 'trailblazer' })
    const res = await request(env, 'POST', '/admin/users', {
      headers: ADMIN,
      body: { email: BOB, tier: 'tern' },
    })
    assert.equal(res.status, 409)
    assert.equal(res.body.error, 'trailblazer_permanent')
  })
})
