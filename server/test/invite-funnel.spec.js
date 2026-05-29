// [Invite] #328 — invite-funnel scaffolding unit tests (no CouchDB).
//
// Pure / KV-only coverage for server/inviteFunnel.js: the share-token mint
// shape, the `typ` payload guard, the revocation predicate (epoch + jti
// deny-list + frozen), and the anti-enumeration mapping in
// `readMetaForPreview`. These run without Docker so they exercise in CI even
// when the disposable-CouchDB sec suite is skipped (see share-link.spec.js).

import { describe, test } from 'node:test'
import assert from 'node:assert/strict'

import {
  SHARE_TOKEN_EXPIRY_SECONDS,
  assertPreviewable,
  assertSharePayload,
  mintShareToken,
  randomJti,
  readMetaForPreview,
  shareLinkUrl,
} from '../inviteFunnel.js'
import { verifyJwt } from '../jwt.js'

const SECRET = 'test-server-secret-do-not-use-in-production'

// In-memory KV with the subset of methods assertPreviewable touches.
const memoryKv = () => {
  const store = new Map()
  return {
    async get(key) {
      return store.has(key) ? store.get(key) : null
    },
    async put(key, value) {
      store.set(key, value)
    },
  }
}

describe('[Invite] inviteFunnel mint + guards (#328)', () => {
  test('randomJti is 12 lowercase hex chars', () => {
    for (let i = 0; i < 50; i++) {
      assert.match(randomJti(), /^[0-9a-f]{12}$/)
    }
  })

  test('mintShareToken produces a verifiable typ:share token with 30d exp', async () => {
    const env = { SERVER_SECRET: SECRET }
    const { token, payload } = await mintShareToken({
      env,
      flockId: 'abc123',
      inviter: 'owner@example.com',
      epoch: 4,
    })
    assert.equal(payload.typ, 'share')
    assert.equal(payload.flockId, 'abc123')
    assert.equal(payload.inviter, 'owner@example.com')
    assert.equal(payload.epoch, 4)
    assert.match(payload.jti, /^[0-9a-f]{12}$/)
    assert.equal(payload.exp - payload.iat, SHARE_TOKEN_EXPIRY_SECONDS)
    assert.equal(payload.inviteeEmail, undefined)

    // Signature + header pin verify against the same secret.
    const verified = await verifyJwt(token, SECRET)
    assert.equal(verified.ok, true)
    assert.equal(verified.payload.typ, 'share')

    // A forged secret fails verification.
    const forged = await verifyJwt(token, 'wrong-secret')
    assert.equal(forged.ok, false)
  })

  test('mintShareToken defaults a non-numeric epoch to 0', async () => {
    const env = { SERVER_SECRET: SECRET }
    const { payload } = await mintShareToken({
      env,
      flockId: 'x',
      inviter: 'a@b.com',
      epoch: undefined,
    })
    assert.equal(payload.epoch, 0)
  })

  test('shareLinkUrl builds the /nest funnel URL with an encoded token', () => {
    assert.equal(
      shareLinkUrl('a.b.c'),
      'https://app.ternpike.com/nest?token=a.b.c',
    )
    // Tokens never contain reserved chars, but the helper still encodes.
    assert.equal(
      shareLinkUrl('a+b/c'),
      'https://app.ternpike.com/nest?token=a%2Bb%2Fc',
    )
  })

  test('assertSharePayload pins typ:share and a string flockId', () => {
    assert.throws(() => assertSharePayload(null), (e) => e.status === 403)
    assert.throws(
      () => assertSharePayload({ typ: 'invite', flockId: 'x' }),
      (e) => e.status === 403 && e.error === 'invalid_token',
    )
    assert.throws(
      () => assertSharePayload({ typ: 'share' }),
      (e) => e.status === 403 && e.error === 'invalid_token',
    )
    const ok = assertSharePayload({ typ: 'share', flockId: 'abc' })
    assert.equal(ok.flockId, 'abc')
  })

  test('assertPreviewable: clean token previews (no throw)', async () => {
    const env = { INVITE_KV: memoryKv() }
    await assertPreviewable(
      { inviteEpoch: 2, billingStatus: 'active' },
      2,
      'aaaaaaaaaaaa',
      env,
    )
  })

  test('assertPreviewable: epoch mismatch → 403 revoked', async () => {
    const env = { INVITE_KV: memoryKv() }
    await assert.rejects(
      () => assertPreviewable({ inviteEpoch: 3 }, 2, 'j', env),
      (e) => e.status === 403 && e.error === 'revoked',
    )
  })

  test('assertPreviewable: missing inviteEpoch defaults to 0 on both sides', async () => {
    const env = { INVITE_KV: memoryKv() }
    // meta with no inviteEpoch (legacy) + token epoch 0 → match, no throw.
    await assertPreviewable({ billingStatus: 'active' }, 0, 'x', env)
    // token epoch 1 against legacy-0 meta → mismatch.
    await assert.rejects(
      () => assertPreviewable({ billingStatus: 'active' }, 1, 'x', env),
      (e) => e.status === 403 && e.error === 'revoked',
    )
  })

  test('assertPreviewable: jti on deny-list → 403 revoked', async () => {
    const env = { INVITE_KV: memoryKv() }
    await env.INVITE_KV.put('revoked:deadbeefcafe', '1')
    await assert.rejects(
      () =>
        assertPreviewable({ inviteEpoch: 0 }, 0, 'deadbeefcafe', env),
      (e) => e.status === 403 && e.error === 'revoked',
    )
    // A different jti is still fine.
    await assertPreviewable({ inviteEpoch: 0 }, 0, 'aaaaaaaaaaaa', env)
  })

  test('assertPreviewable: frozen trip → 403 trip_frozen', async () => {
    const env = { INVITE_KV: memoryKv() }
    await assert.rejects(
      () =>
        assertPreviewable(
          { inviteEpoch: 0, billingStatus: 'frozen' },
          0,
          'x',
          env,
        ),
      (e) => e.status === 403 && e.error === 'trip_frozen',
    )
  })

  test('assertPreviewable: null meta → 403 revoked (defense in depth)', async () => {
    const env = { INVITE_KV: memoryKv() }
    await assert.rejects(
      () => assertPreviewable(null, 0, 'x', env),
      (e) => e.status === 403 && e.error === 'revoked',
    )
  })

  test('readMetaForPreview: a 404 from couch surfaces as 403 revoked', async () => {
    // env with COUCH_URL pointing nowhere — the underlying fetch fails, which
    // readMetaForPreview collapses to a 403 (anti-enumeration). We assert the
    // contract (never 404, never throw a bare error) rather than the network.
    const env = {
      COUCH_URL: 'http://127.0.0.1:1',
      COUCH_ADMIN_USER: 'admin',
      COUCH_ADMIN_PASS: 'pass',
    }
    await assert.rejects(
      () => readMetaForPreview(env, 'nonexistent'),
      (e) => e.status === 403 && e.error === 'revoked',
    )
  })
})
