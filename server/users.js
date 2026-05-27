// Server-authoritative user records backing identity, tier, and billing
// state. Keyed by lowercased email in `TIERS_KV` under the `user:` prefix.
//
// Schema (alphabetized fields, JSDoc since this repo has no TypeScript):
//
//   type UserRecord = {
//     createdAt: string,            // ISO
//     email: string,                // PK, lowercased
//     stripeCustomerId: string | null,
//     subscriptionId: string | null,
//     subscriptionStatus:
//       | 'active'
//       | 'canceled'
//       | 'past_due'
//       | 'trialing'
//       | null,
//     tier: 'tern' | 'osprey' | 'trailblazer',
//     trailblazerNumber: number | null,        // 1..500
//     trailblazerPurchasedAt: string | null,   // ISO
//     updatedAt: string,            // ISO
//   }
//
// `getTier` (server/auth.js) reads `user:<email>` first, then falls back to
// the legacy raw-string `<email>` key written by `setTier` (server/sharedTrips.js)
// and by direct admin pokes. New writes go through `upsertUser`, which always
// sets both `createdAt` (preserved on existing records) and `updatedAt`.
//
// Trailblazer is permanent. Webhook code must never write a record that
// downgrades a Trailblazer to anything else. The Trailblazer slot counter
// lives in a Durable Object (`server/trailblazerSlots.js`); the per-user
// `trailblazerNumber` here is the authoritative record of which slot a
// given email holds, set when /confirm succeeds in the DO.

const VALID_TIERS = new Set(['tern', 'osprey', 'trailblazer'])

const VALID_SUBSCRIPTION_STATUSES = new Set([
  'active',
  'canceled',
  'past_due',
  'trialing',
])

const userKey = (email) => 'user:' + email.toLowerCase()

/**
 * Build a fresh `UserRecord` for a newly-seen email. `tier` defaults to
 * `'tern'` (free) unless the caller passes a legacy override (used by
 * `migrateLegacy`).
 *
 * @param {string} email
 * @param {{ tier?: string }} [opts]
 * @returns {object}
 */
export function freshUser(email, opts = {}) {
  const now = new Date().toISOString()
  const tier = VALID_TIERS.has(opts.tier) ? opts.tier : 'tern'
  return {
    createdAt: now,
    email: email.toLowerCase(),
    stripeCustomerId: null,
    subscriptionId: null,
    subscriptionStatus: null,
    tier,
    trailblazerNumber: null,
    trailblazerPurchasedAt: null,
    updatedAt: now,
  }
}

/**
 * Read the `UserRecord` for `email`, or `null` if no record exists.
 *
 * Does NOT auto-migrate from the legacy raw-string `<email>` key — see
 * `migrateLegacy` for that. `getTier` (server/auth.js) handles the
 * read-side fallback so callers that only need the tier don't have to
 * orchestrate two reads.
 *
 * @param {object} env
 * @param {string} email
 * @returns {Promise<object|null>}
 */
export async function getUser(env, email) {
  if (!env.TIERS_KV) return null
  const raw = await env.TIERS_KV.get(userKey(email))
  if (!raw) return null
  try {
    return JSON.parse(raw)
  } catch (err) {
    console.error('getUser parse:', err)
    return null
  }
}

/**
 * Write a `UserRecord` to KV. The caller is responsible for the field
 * values — `upsertUser` only stamps `updatedAt` and normalizes `email` to
 * lowercase. Validates `tier` and `subscriptionStatus`; throws on invalid
 * values rather than silently writing garbage.
 *
 * Trailblazer is permanent: if the existing record on disk has
 * `tier === 'trailblazer'` and the incoming `record.tier !== 'trailblazer'`,
 * this throws. Webhook code that hits this is a bug — fix the webhook.
 *
 * @param {object} env
 * @param {object} record
 * @returns {Promise<object>}
 */
export async function upsertUser(env, record) {
  if (!env.TIERS_KV) throw new Error('TIERS_KV not bound')
  if (typeof record?.email !== 'string' || !record.email.includes('@')) {
    throw new Error('upsertUser: invalid email')
  }
  if (!VALID_TIERS.has(record.tier)) {
    throw new Error(`upsertUser: invalid tier ${record.tier}`)
  }
  if (
    record.subscriptionStatus !== null &&
    !VALID_SUBSCRIPTION_STATUSES.has(record.subscriptionStatus)
  ) {
    throw new Error(
      `upsertUser: invalid subscriptionStatus ${record.subscriptionStatus}`,
    )
  }
  const email = record.email.toLowerCase()
  const existing = await getUser(env, email)
  if (existing?.tier === 'trailblazer' && record.tier !== 'trailblazer') {
    throw new Error('upsertUser: refusing to downgrade trailblazer')
  }
  const next = {
    createdAt: existing?.createdAt || record.createdAt || new Date().toISOString(),
    email,
    stripeCustomerId: record.stripeCustomerId ?? null,
    subscriptionId: record.subscriptionId ?? null,
    subscriptionStatus: record.subscriptionStatus ?? null,
    tier: record.tier,
    trailblazerNumber: record.trailblazerNumber ?? null,
    trailblazerPurchasedAt: record.trailblazerPurchasedAt ?? null,
    updatedAt: new Date().toISOString(),
  }
  await env.TIERS_KV.put(userKey(email), JSON.stringify(next))
  return next
}

/**
 * If no `user:<email>` record exists but a legacy raw-string tier does,
 * materialize a fresh `UserRecord` from it. No-op if a JSON record
 * already exists or no legacy data is present. Returns the resulting
 * record (or `null` if nothing to migrate).
 *
 * The legacy raw-string key is left in place — `getTier`'s fallback path
 * continues to read it for callers that haven't been migrated yet. We
 * never delete it from here; a later sweep can prune once every user has
 * been read at least once through `getUser`.
 *
 * @param {object} env
 * @param {string} email
 * @returns {Promise<object|null>}
 */
export async function migrateLegacy(env, email) {
  if (!env.TIERS_KV) return null
  const existing = await getUser(env, email)
  if (existing) return existing
  const legacy = await env.TIERS_KV.get(email.toLowerCase())
  if (!legacy) return null
  const tier = VALID_TIERS.has(legacy) ? legacy : 'tern'
  return upsertUser(env, freshUser(email, { tier }))
}
