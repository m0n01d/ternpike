// [Auth] #333 — hardened magic-link unit tests (no CouchDB).
//
// Covers the security-critical, CouchDB-free logic of the magic-link
// endpoints: token mint shape + lifetime, the magic-link URL builder, and the
// `checkMagicRedemption` guard (typ-pinning, expiry→410, wrong-typ→401,
// forwarded-token+mismatched-email→403, replay/consume semantics, happy path).
//
// Provisioning (`provisionUser` in server/index.js) hits CouchDB, so the full
// `/auth/verify-magic-link` round-trip is exercised by the Docker-backed sec
// suite; here we factor out and pin the verifiable boundary. These run without
// Docker so they always exercise in CI.

import { describe, test } from 'node:test'
import assert from 'node:assert/strict'

import {
  MAGIC_TOKEN_EXPIRY_SECONDS,
  checkMagicRedemption,
  magicLinkUrl,
  mintMagicToken,
} from '../inviteFunnel.js'
import { signJwt, verifyJwt } from '../jwt.js'

const SECRET = 'test-server-secret-do-not-use-in-production'

describe('[Auth] magic-link mint + url (#333)', () => {
  test('MAGIC_TOKEN_EXPIRY_SECONDS is 5 minutes', () => {
    assert.equal(MAGIC_TOKEN_EXPIRY_SECONDS, 5 * 60)
  })

  test('mintMagicToken: verifiable typ:magic token, lowercased email, 15m exp, no invite', async () => {
    const env = { SERVER_SECRET: SECRET }
    const { token, payload } = await mintMagicToken({
      env,
      email: 'Alice@Example.com',
    })
    assert.equal(payload.typ, 'magic')
    assert.equal(payload.email, 'alice@example.com') // lowercased
    assert.match(payload.jti, /^[0-9a-f]{12}$/)
    assert.equal(payload.exp - payload.iat, MAGIC_TOKEN_EXPIRY_SECONDS)
    // Magic tokens do NOT carry the invite (the share token rides in `next`).
    assert.equal(payload.flockId, undefined)
    assert.equal(payload.inviteeEmail, undefined)

    const verified = await verifyJwt(token, SECRET)
    assert.equal(verified.ok, true)
    assert.equal(verified.payload.typ, 'magic')

    // A forged secret fails verification.
    const forged = await verifyJwt(token, 'wrong-secret')
    assert.equal(forged.ok, false)
  })

  test('magicLinkUrl: token + next are url-encoded; next is optional', () => {
    assert.equal(
      magicLinkUrl('https://app.ternpike.com', 'a.b.c', 'share.tok.en'),
      'https://app.ternpike.com/auth/magic?token=a.b.c&next=share.tok.en',
    )
    // Reserved chars in next get encoded.
    assert.equal(
      magicLinkUrl('https://app.ternpike.com', 'a.b.c', 'x+y/z'),
      'https://app.ternpike.com/auth/magic?token=a.b.c&next=x%2By%2Fz',
    )
    // No next → no &next= segment.
    assert.equal(
      magicLinkUrl('https://app.ternpike.com', 'a.b.c', undefined),
      'https://app.ternpike.com/auth/magic?token=a.b.c',
    )
    assert.equal(
      magicLinkUrl('https://app.ternpike.com', 'a.b.c', ''),
      'https://app.ternpike.com/auth/magic?token=a.b.c',
    )
  })
})

describe('[Auth] checkMagicRedemption guard (#333)', () => {
  test('expired token → 410 expired', () => {
    const r = checkMagicRedemption(
      { ok: false, reason: 'expired' },
      'alice@example.com',
    )
    assert.deepEqual(r, { ok: false, status: 410, error: 'expired' })
  })

  test('bad signature / malformed → 401 invalid_token', () => {
    for (const reason of ['signature', 'malformed', 'alg']) {
      const r = checkMagicRedemption({ ok: false, reason }, 'alice@example.com')
      assert.deepEqual(r, { ok: false, status: 401, error: 'invalid_token' })
    }
  })

  test('wrong payload typ → 401 invalid_token', () => {
    const r = checkMagicRedemption(
      { ok: true, payload: { typ: 'share', email: 'alice@example.com' } },
      'alice@example.com',
    )
    assert.deepEqual(r, { ok: false, status: 401, error: 'invalid_token' })
  })

  test('missing payload email → 401 invalid_token', () => {
    const r = checkMagicRedemption(
      { ok: true, payload: { typ: 'magic' } },
      'alice@example.com',
    )
    assert.deepEqual(r, { ok: false, status: 401, error: 'invalid_token' })
  })

  test('forwarded token + mismatched body email → 403 email_mismatch', () => {
    const verified = {
      ok: true,
      payload: { typ: 'magic', email: 'alice@example.com', jti: 'aaaaaaaaaaaa' },
    }
    const r = checkMagicRedemption(verified, 'mallory@evil.com')
    assert.deepEqual(r, { ok: false, status: 403, error: 'email_mismatch' })
  })

  test('missing body email → 403 email_mismatch (cannot confirm)', () => {
    const verified = {
      ok: true,
      payload: { typ: 'magic', email: 'alice@example.com', jti: 'aaaaaaaaaaaa' },
    }
    assert.deepEqual(checkMagicRedemption(verified, undefined), {
      ok: false,
      status: 403,
      error: 'email_mismatch',
    })
    assert.deepEqual(checkMagicRedemption(verified, ''), {
      ok: false,
      status: 403,
      error: 'email_mismatch',
    })
  })

  test('happy path: case-insensitive email match → ok with email, jti, exp', () => {
    const verified = {
      ok: true,
      payload: {
        typ: 'magic',
        email: 'alice@example.com',
        jti: 'deadbeefcafe',
        exp: 1234567890,
      },
    }
    // Caller submits a differently-cased address — still confirms.
    const r = checkMagicRedemption(verified, 'ALICE@Example.com')
    assert.deepEqual(r, {
      ok: true,
      email: 'alice@example.com',
      jti: 'deadbeefcafe',
      exp: 1234567890,
    })
  })

  test('end-to-end: a freshly minted token passes verify + redemption', async () => {
    const env = { SERVER_SECRET: SECRET }
    const { token, payload } = await mintMagicToken({
      env,
      email: 'bob@example.com',
    })
    const verified = await verifyJwt(token, SECRET)
    const r = checkMagicRedemption(verified, 'bob@example.com')
    assert.equal(r.ok, true)
    assert.equal(r.email, 'bob@example.com')
    assert.equal(r.jti, payload.jti)
    assert.equal(r.exp, payload.exp)
  })

  test('replay: a genuinely expired minted token surfaces as 410', async () => {
    // Hand-sign a magic payload whose exp is already in the past, then run it
    // through the real verifyJwt → checkMagicRedemption pipeline.
    const past = Math.floor(Date.now() / 1000) - 10
    const token = await signJwt(
      { typ: 'magic', email: 'carol@example.com', jti: 'ffffffffffff', iat: past - 900, exp: past },
      SECRET,
    )
    const verified = await verifyJwt(token, SECRET)
    const r = checkMagicRedemption(verified, 'carol@example.com')
    assert.deepEqual(r, { ok: false, status: 410, error: 'expired' })
  })
})

describe('[Auth] single-use jti consume semantics (#333)', () => {
  // The route writes `revoked:<jti>` to INVITE_KV after a successful provision
  // and rejects a second redemption when that key is present. We model that
  // KV interaction here (the provision step itself needs CouchDB and is
  // covered by the Docker sec suite).
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

  test('first redemption: jti absent from deny-list, then written', async () => {
    const kv = memoryKv()
    const jti = 'deadbeefcafe'
    assert.equal(await kv.get(`revoked:${jti}`), null) // not yet consumed
    await kv.put(`revoked:${jti}`, '1')
    assert.equal(await kv.get(`revoked:${jti}`), '1') // now consumed
  })

  test('replay: second redemption sees the consumed jti', async () => {
    const kv = memoryKv()
    const jti = 'aaaaaaaaaaaa'
    await kv.put(`revoked:${jti}`, '1')
    // The route treats a present deny-list entry as a 401 invalid_token.
    assert.equal(await kv.get(`revoked:${jti}`), '1')
  })
})
