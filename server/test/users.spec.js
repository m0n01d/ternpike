// Coverage for the server-authoritative user record (server/users.js)
// and the `getTier` JSON-first / legacy-fallback behavior in
// server/auth.js. No CouchDB dependency — these helpers only touch
// `TIERS_KV`, stubbed with `memoryKv()` from fixtures/env.js.

import { beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { getTier } from '../auth.js'
import {
  freshUser,
  getUser,
  migrateLegacy,
  upsertUser,
} from '../users.js'
import { memoryKv } from './fixtures/env.js'

const ALICE = 'alice@test.ternpike.com'
const BOB = 'bob@test.ternpike.com'
const CAROL = 'carol@test.ternpike.com'

let env

beforeEach(() => {
  env = { TIERS_KV: memoryKv() }
})

describe('getUser', () => {
  test('returns null for unknown email', async () => {
    assert.equal(await getUser(env, ALICE), null)
  })

  test('returns null when TIERS_KV is unbound', async () => {
    assert.equal(await getUser({}, ALICE), null)
  })

  test('returns null on corrupted JSON without throwing', async () => {
    await env.TIERS_KV.put('user:' + ALICE.toLowerCase(), '{not valid json')
    assert.equal(await getUser(env, ALICE), null)
  })
})

describe('upsertUser', () => {
  test('round-trips a fresh record', async () => {
    const written = await upsertUser(env, freshUser(ALICE))
    const read = await getUser(env, ALICE)
    assert.deepEqual(read, written)
    assert.equal(read.email, ALICE.toLowerCase())
    assert.equal(read.tier, 'tern')
    assert.equal(read.stripeCustomerId, null)
    assert.equal(read.subscriptionId, null)
    assert.equal(read.subscriptionStatus, null)
    assert.equal(read.trailblazerNumber, null)
    assert.equal(read.trailblazerPurchasedAt, null)
    assert.ok(read.createdAt)
    assert.ok(read.updatedAt)
  })

  test('preserves createdAt across updates and bumps updatedAt', async () => {
    const first = await upsertUser(env, freshUser(ALICE))
    // Force a measurable delta between updates.
    await new Promise((resolve) => setTimeout(resolve, 5))
    const second = await upsertUser(env, { ...first, tier: 'osprey' })
    assert.equal(second.createdAt, first.createdAt)
    assert.notEqual(second.updatedAt, first.updatedAt)
    assert.equal(second.tier, 'osprey')
  })

  test('serialized record has alphabetized keys', async () => {
    await upsertUser(env, freshUser(ALICE))
    const raw = await env.TIERS_KV.get('user:' + ALICE.toLowerCase())
    const parsed = JSON.parse(raw)
    const keys = Object.keys(parsed)
    const sorted = [...keys].sort()
    assert.deepEqual(keys, sorted, `keys not alphabetized: ${keys.join(',')}`)
  })

  test('rejects invalid tier', async () => {
    await assert.rejects(
      () => upsertUser(env, { ...freshUser(ALICE), tier: 'gold' }),
      /invalid tier/,
    )
  })

  test('rejects invalid subscriptionStatus', async () => {
    await assert.rejects(
      () =>
        upsertUser(env, {
          ...freshUser(ALICE),
          subscriptionStatus: 'frozen',
        }),
      /invalid subscriptionStatus/,
    )
  })

  test('refuses to downgrade a trailblazer', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      tier: 'trailblazer',
      trailblazerNumber: 7,
      trailblazerPurchasedAt: new Date().toISOString(),
    })
    await assert.rejects(
      () => upsertUser(env, { ...freshUser(ALICE), tier: 'tern' }),
      /downgrade trailblazer/,
    )
    await assert.rejects(
      () => upsertUser(env, { ...freshUser(ALICE), tier: 'osprey' }),
      /downgrade trailblazer/,
    )
    // The on-disk record is unchanged.
    const after = await getUser(env, ALICE)
    assert.equal(after.tier, 'trailblazer')
    assert.equal(after.trailblazerNumber, 7)
  })

  test('throws when TIERS_KV is unbound', async () => {
    await assert.rejects(
      () => upsertUser({}, freshUser(ALICE)),
      /TIERS_KV not bound/,
    )
  })

  test('rejects malformed email', async () => {
    await assert.rejects(
      () => upsertUser(env, { ...freshUser(ALICE), email: 'no-at-sign' }),
      /invalid email/,
    )
  })
})

describe('migrateLegacy', () => {
  test('materializes a fresh UserRecord from a legacy osprey string', async () => {
    await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey')
    const migrated = await migrateLegacy(env, ALICE)
    assert.ok(migrated)
    assert.equal(migrated.tier, 'osprey')
    assert.equal(migrated.email, ALICE.toLowerCase())
    // The materialized record is now readable via getUser.
    const read = await getUser(env, ALICE)
    assert.deepEqual(read, migrated)
  })

  test('materializes from a legacy trailblazer string', async () => {
    await env.TIERS_KV.put(BOB.toLowerCase(), 'trailblazer')
    const migrated = await migrateLegacy(env, BOB)
    assert.equal(migrated.tier, 'trailblazer')
  })

  test('no-op when JSON record already exists', async () => {
    const existing = await upsertUser(env, {
      ...freshUser(ALICE),
      tier: 'osprey',
    })
    // Park a stale legacy string alongside; migrateLegacy should ignore it.
    await env.TIERS_KV.put(ALICE.toLowerCase(), 'tern')
    const result = await migrateLegacy(env, ALICE)
    assert.deepEqual(result, existing)
  })

  test('returns null when there is nothing to migrate', async () => {
    assert.equal(await migrateLegacy(env, CAROL), null)
  })

  test('falls back to tern when legacy value is unrecognized', async () => {
    await env.TIERS_KV.put(ALICE.toLowerCase(), 'banana')
    const migrated = await migrateLegacy(env, ALICE)
    assert.equal(migrated.tier, 'tern')
  })

  test('leaves the legacy raw-string key in place', async () => {
    await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey')
    await migrateLegacy(env, ALICE)
    const legacy = await env.TIERS_KV.get(ALICE.toLowerCase())
    assert.equal(legacy, 'osprey')
  })
})

describe('getTier (JSON-first, legacy fallback)', () => {
  test('reads from the new JSON record first', async () => {
    await upsertUser(env, { ...freshUser(ALICE), tier: 'trailblazer' })
    // Stale legacy value — must be ignored.
    await env.TIERS_KV.put(ALICE.toLowerCase(), 'tern')
    assert.equal(await getTier(env, ALICE), 'trailblazer')
  })

  test('falls back to the legacy raw-string key', async () => {
    await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey')
    assert.equal(await getTier(env, ALICE), 'osprey')
  })

  test('returns tern when nothing is stored', async () => {
    assert.equal(await getTier(env, ALICE), 'tern')
  })

  test('returns tern when TIERS_KV is unbound', async () => {
    assert.equal(await getTier({}, ALICE), 'tern')
  })

  test('reads tern from a JSON record (explicit, not just default)', async () => {
    await upsertUser(env, freshUser(ALICE))
    // No legacy fallback in play here — make sure the JSON path
    // recognizes `'tern'` as a legitimate tier rather than treating it
    // as "missing" and double-reading the bare key.
    assert.equal(await getTier(env, ALICE), 'tern')
  })
})
