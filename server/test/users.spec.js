// Coverage for the server-authoritative user record (server/users.js)
// and the `getTier` JSON-first / legacy-fallback behavior in
// server/auth.js. No CouchDB dependency — these helpers only touch
// `TIERS_KV`, stubbed with `memoryKv()` from fixtures/env.js.

import { beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { getTier } from '../auth.js'
import {
  freshUser,
  getEmailBySlug,
  getUser,
  migrateLegacy,
  shortHash,
  slugFor,
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

describe('shortHash + slugFor', () => {
  test('produces 4-char lowercase hex matching the Elm side', () => {
    // These pin values are also asserted in tests/UserIdTests.elm. Both
    // sides MUST stay aligned because the slug→email index is written
    // server-side but the slug is generated client-side by Elm. Drift
    // breaks referral attribution silently.
    assert.equal(shortHash('alice@test.ternpike.com'), 'de3b')
    assert.equal(shortHash('bob@test.ternpike.com'), '5513')
    assert.equal(shortHash('carol@test.ternpike.com'), 'de47')
    assert.equal(shortHash('dwight.j.doane@gmail.com'), 'ec1d')
    assert.equal(shortHash('alice@example.com'), 'c281')
  })

  test('slugFor returns the user-<hash> form ShareModal uses', () => {
    assert.equal(slugFor('alice@test.ternpike.com'), 'user-de3b')
    assert.equal(slugFor('ALICE@test.ternpike.com'), 'user-de3b')
  })
})

describe('referral attribution', () => {
  test('freshUser preserves referredBy when passed', () => {
    const u = freshUser(BOB, { referredBy: ALICE })
    assert.equal(u.referredBy, ALICE.toLowerCase())
  })

  test('freshUser defaults referredBy to null', () => {
    const u = freshUser(BOB)
    assert.equal(u.referredBy, null)
  })

  test('freshUser rejects garbage referredBy values', () => {
    assert.equal(freshUser(BOB, { referredBy: '' }).referredBy, null)
    assert.equal(freshUser(BOB, { referredBy: 'no-at-sign' }).referredBy, null)
    assert.equal(freshUser(BOB, { referredBy: 42 }).referredBy, null)
  })

  test('upsertUser writes a slug→email index', async () => {
    await upsertUser(env, freshUser(ALICE))
    const indexed = await env.TIERS_KV.get('slug:' + slugFor(ALICE))
    assert.equal(indexed, ALICE.toLowerCase())
  })

  test('getEmailBySlug round-trips through upsertUser', async () => {
    await upsertUser(env, freshUser(ALICE))
    const slug = slugFor(ALICE)
    assert.equal(await getEmailBySlug(env, slug), ALICE.toLowerCase())
  })

  test('getEmailBySlug returns null for an unknown slug', async () => {
    assert.equal(await getEmailBySlug(env, 'user-0000'), null)
  })

  test('getEmailBySlug returns null when TIERS_KV is unbound', async () => {
    assert.equal(await getEmailBySlug({}, 'user-de3b'), null)
  })

  test('upsertUser persists referredBy on first insert', async () => {
    await upsertUser(env, freshUser(BOB, { referredBy: ALICE }))
    const read = await getUser(env, BOB)
    assert.equal(read.referredBy, ALICE.toLowerCase())
  })

  test('referredBy is write-once — never overwritten on subsequent upserts', async () => {
    await upsertUser(env, freshUser(BOB, { referredBy: ALICE }))
    // A later upsert (e.g., billing webhook) tries to clear or change it.
    await upsertUser(env, { ...freshUser(BOB), referredBy: null, tier: 'osprey' })
    const read = await getUser(env, BOB)
    assert.equal(read.referredBy, ALICE.toLowerCase())
    assert.equal(read.tier, 'osprey')
  })

  test('referredBy stays null when no referrer is provided on first insert', async () => {
    await upsertUser(env, freshUser(BOB))
    const read = await getUser(env, BOB)
    assert.equal(read.referredBy, null)
  })

  test('slug index backfills on upsert for existing users predating this feature', async () => {
    // Simulate a user record that exists without a slug index entry.
    await env.TIERS_KV.put(
      'user:' + ALICE.toLowerCase(),
      JSON.stringify({
        createdAt: '2025-01-01T00:00:00.000Z',
        email: ALICE.toLowerCase(),
        stripeCustomerId: null,
        subscriptionId: null,
        subscriptionStatus: null,
        tier: 'tern',
        trailblazerNumber: null,
        trailblazerPurchasedAt: null,
        updatedAt: '2025-01-01T00:00:00.000Z',
      }),
    )
    // Confirm no slug index yet.
    assert.equal(await env.TIERS_KV.get('slug:' + slugFor(ALICE)), null)
    // Any subsequent upsert (e.g., /me refresh) writes the index.
    const existing = await getUser(env, ALICE)
    await upsertUser(env, existing)
    assert.equal(
      await env.TIERS_KV.get('slug:' + slugFor(ALICE)),
      ALICE.toLowerCase(),
    )
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
