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
  FUNNEL_STAGE_ALLOWLIST,
  GUEST_PREVIEW_GATE,
  SHARE_TOKEN_EXPIRY_SECONDS,
  assertPreviewable,
  assertSharePayload,
  buildAlreadyMemberBody,
  buildTeaser,
  classifyJoinToken,
  deriveInviterName,
  isAllowedFunnelStage,
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

  test('GUEST_PREVIEW_GATE is the documented default', () => {
    assert.equal(GUEST_PREVIEW_GATE, 'view_scan_preview')
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

describe('[Invite] deriveInviterName redaction (#331)', () => {
  test('uses the email local-part first token, title-cased — never the email', () => {
    assert.equal(
      deriveInviterName({ createdBy: 'alice.smith@example.com' }, null),
      'Alice',
    )
    assert.equal(
      deriveInviterName({ createdBy: 'bob+trips@example.com' }, null),
      'Bob',
    )
    assert.equal(
      deriveInviterName({ createdBy: 'carol_jones@x.io' }, null),
      'Carol',
    )
  })

  test('falls back createdBy → billingOwner → token inviter', () => {
    assert.equal(
      deriveInviterName({ billingOwner: 'dave@x.io' }, null),
      'Dave',
    )
    assert.equal(deriveInviterName({}, 'erin@x.io'), 'Erin')
  })

  test('an explicit non-email createdByName wins', () => {
    assert.equal(
      deriveInviterName(
        { createdByName: 'Captain Ahab', createdBy: 'ahab@x.io' },
        null,
      ),
      'Captain Ahab',
    )
  })

  test('never returns an email and never empty', () => {
    const name = deriveInviterName({ createdBy: 'nobody@x.io' }, null)
    assert.ok(!name.includes('@'))
    assert.ok(name.length > 0)
    assert.equal(deriveInviterName(null, null), 'A crewmate')
    assert.equal(deriveInviterName({}, null), 'A crewmate')
  })
})

describe('[Invite] buildTeaser aggregation + redaction (#331)', () => {
  const META = {
    billingOwner: 'alice@example.com',
    createdBy: 'alice@example.com',
    inviteEpoch: 0,
    members: ['alice@example.com', 'bob@example.com'],
    name: 'Honeymoon',
  }

  const expense = (id, amount, date, extra = {}) => ({
    _id: id,
    type: 'expense',
    amount,
    date,
    merchant: 'Secret Merchant ' + id,
    note: 'private note',
    longNote: 'private long note',
    lat: 12.34,
    lon: 56.78,
    createdAt: '2026-05-21T00:00:00Z',
    createdBy: 'alice@example.com',
    tripId: 'trip::x',
    ...extra,
  })

  test('happy path: totals, counts, distinct days, meta-driven name + members', () => {
    const docs = [
      { _id: 'trip::x', type: 'trip', name: 'Honeymoon', startDate: '', endDate: '' },
      expense('e1', 10.5, '2026-05-21'),
      expense('e2', 20.25, '2026-05-21'),
      expense('e3', 5, '2026-05-22'),
    ]
    const t = buildTeaser(docs, META)
    assert.equal(t.ok, undefined) // ok is added by the route, not buildTeaser
    assert.equal(t.tripName, 'Honeymoon')
    assert.equal(t.inviterName, 'Alice')
    assert.equal(t.totalSpent, 35.75)
    assert.equal(t.entryCount, 3)
    assert.equal(t.dayCount, 2)
    assert.equal(t.memberCount, 2)
    assert.equal(t.gate, 'view_scan_preview')
  })

  test('amendments apply newest-wins to amount + date (effective totals)', () => {
    const docs = [
      expense('e1', 10, '2026-05-21'),
      // two amendments; the later createdAt wins the amount.
      { _id: 'a1', type: 'amend', targetId: 'e1', amount: 99, createdAt: '2026-05-22T00:00:00Z' },
      { _id: 'a2', type: 'amend', targetId: 'e1', amount: 42, date: '2026-05-25', createdAt: '2026-05-23T00:00:00Z' },
    ]
    const t = buildTeaser(docs, META)
    assert.equal(t.totalSpent, 42) // newest amendment's amount, not 10 or 99
    assert.equal(t.entryCount, 1)
    assert.equal(t.dayCount, 1)
    // date amendment moved the only entry to 2026-05-25.
    assert.equal(t.startDate, '2026-05-25')
    assert.equal(t.endDate, '2026-05-25')
  })

  test('voided expenses are excluded from every aggregate', () => {
    const docs = [
      expense('e1', 100, '2026-05-21'),
      expense('e2', 50, '2026-05-22'),
      { _id: 'v1', type: 'void', targetId: 'e2', createdAt: '2026-05-23T00:00:00Z' },
    ]
    const t = buildTeaser(docs, META)
    assert.equal(t.totalSpent, 100)
    assert.equal(t.entryCount, 1)
    assert.equal(t.dayCount, 1)
  })

  test('dayCount counts DISTINCT effective dates only', () => {
    const docs = [
      expense('e1', 1, '2026-05-21'),
      expense('e2', 1, '2026-05-21'),
      expense('e3', 1, '2026-05-21'),
      expense('e4', 1, '2026-05-22'),
    ]
    const t = buildTeaser(docs, META)
    assert.equal(t.entryCount, 4)
    assert.equal(t.dayCount, 2)
  })

  test('trip startDate/endDate win when set; else min/max effective entry date', () => {
    const withTripDates = buildTeaser(
      [
        { _id: 'trip::x', type: 'trip', name: 'T', startDate: '2026-01-01', endDate: '2026-12-31' },
        expense('e1', 1, '2026-05-21'),
      ],
      META,
    )
    assert.equal(withTripDates.startDate, '2026-01-01')
    assert.equal(withTripDates.endDate, '2026-12-31')

    const fromEntries = buildTeaser(
      [
        { _id: 'trip::x', type: 'trip', name: 'T', startDate: '', endDate: '' },
        expense('e1', 1, '2026-05-25'),
        expense('e2', 1, '2026-05-21'),
        expense('e3', 1, '2026-05-23'),
      ],
      META,
    )
    assert.equal(fromEntries.startDate, '2026-05-21')
    assert.equal(fromEntries.endDate, '2026-05-25')
  })

  test('empty trip: zero counts, empty date range, name from meta', () => {
    const t = buildTeaser([], META)
    assert.equal(t.totalSpent, 0)
    assert.equal(t.entryCount, 0)
    assert.equal(t.dayCount, 0)
    assert.equal(t.startDate, '')
    assert.equal(t.endDate, '')
    assert.equal(t.tripName, 'Honeymoon') // meta.name fallback
    assert.equal(t.memberCount, 2)
  })

  test('REDACTION: output has no email, merchant, note, longNote, lat, lon, or per-entry rows', () => {
    const docs = [
      { _id: 'trip::x', type: 'trip', name: 'Honeymoon', startDate: '', endDate: '' },
      expense('e1', 10, '2026-05-21'),
      expense('e2', 20, '2026-05-22'),
    ]
    const t = buildTeaser(docs, META)
    const json = JSON.stringify(t)

    // No leaked sensitive substrings anywhere in the serialized teaser.
    assert.ok(!json.includes('@'), 'no email')
    assert.ok(!json.toLowerCase().includes('merchant'), 'no merchant')
    assert.ok(!json.includes('private note'), 'no note')
    assert.ok(!json.includes('private long note'), 'no longNote')
    assert.ok(!json.includes('12.34'), 'no lat')
    assert.ok(!json.includes('56.78'), 'no lon')

    // The key set is EXACTLY the documented teaser keys — nothing extra.
    assert.deepEqual(
      Object.keys(t).sort(),
      [
        'dayCount',
        'endDate',
        'entryCount',
        'gate',
        'inviterName',
        'memberCount',
        'startDate',
        'totalSpent',
        'tripName',
      ],
    )
  })

  test('floating-point folds round to cents', () => {
    const docs = [expense('e1', 0.1, '2026-05-21'), expense('e2', 0.2, '2026-05-21')]
    const t = buildTeaser(docs, META)
    assert.equal(t.totalSpent, 0.3)
  })
})

describe('[Invite] classifyJoinToken — /sharedtrips/join branch selection (#334)', () => {
  test('typ:"share" → share path (no email match required)', () => {
    const out = classifyJoinToken({
      typ: 'share',
      flockId: 'abc',
      epoch: 2,
      jti: 'deadbeefcafe',
    })
    assert.deepEqual(out, { flockId: 'abc', kind: 'share' })
    // A share token carries no inviteeEmail — the classifier must not surface
    // one, so the route can never accidentally email-match a share token.
    assert.equal(out.inviteeEmail, undefined)
  })

  test('typ:"invite" → legacy email-match path, surfaces inviteeEmail', () => {
    const out = classifyJoinToken({
      typ: 'invite',
      flockId: 'abc',
      inviteeEmail: 'bob@example.com',
    })
    assert.deepEqual(out, {
      flockId: 'abc',
      inviteeEmail: 'bob@example.com',
      kind: 'invite',
    })
  })

  test('absent typ (legacy 7-day token in the wild) → email-match path', () => {
    // The 7-day tokens already issued carry no payload typ — back-compat treats
    // absent as "invite" (docs/nest-invite-funnel.md §A).
    const out = classifyJoinToken({
      flockId: 'abc',
      inviteeEmail: 'bob@example.com',
    })
    assert.equal(out.kind, 'invite')
    assert.equal(out.inviteeEmail, 'bob@example.com')

    // Explicit null typ is also treated as legacy.
    const nullTyp = classifyJoinToken({
      typ: null,
      flockId: 'abc',
      inviteeEmail: 'bob@example.com',
    })
    assert.equal(nullTyp.kind, 'invite')
  })

  test('unknown typ (e.g. "magic") → 401 invalid_token_type', () => {
    const out = classifyJoinToken({ typ: 'magic', flockId: 'abc' })
    assert.deepEqual(out, {
      kind: 'error',
      status: 401,
      error: 'invalid_token_type',
    })
  })

  test('missing/blank flockId → 401 invalid_token (any typ)', () => {
    assert.equal(classifyJoinToken({ typ: 'share' }).status, 401)
    assert.equal(
      classifyJoinToken({ typ: 'share' }).error,
      'invalid_token',
    )
    assert.equal(classifyJoinToken({ typ: 'share', flockId: '' }).status, 401)
    assert.equal(
      classifyJoinToken({ typ: 'invite', inviteeEmail: 'b@x.io' }).error,
      'invalid_token',
    )
  })

  test('legacy/invite token missing inviteeEmail → 401 invalid_token', () => {
    const out = classifyJoinToken({ typ: 'invite', flockId: 'abc' })
    assert.deepEqual(out, {
      kind: 'error',
      status: 401,
      error: 'invalid_token',
    })
    // Absent-typ with no inviteeEmail is the same failure.
    assert.equal(
      classifyJoinToken({ flockId: 'abc' }).error,
      'invalid_token',
    )
  })

  test('null / non-object payload → 401 invalid_token', () => {
    assert.equal(classifyJoinToken(null).status, 401)
    assert.equal(classifyJoinToken(undefined).status, 401)
    assert.equal(classifyJoinToken('nope').error, 'invalid_token')
  })
})

describe('[Invite] buildAlreadyMemberBody — 409 deep-link body (#334)', () => {
  test('includes flockId, dbName, and the trip name', () => {
    const body = buildAlreadyMemberBody('abc', 'sharedtrip-abc', {
      name: 'Honeymoon',
      members: ['a@x.io'],
    })
    assert.deepEqual(body, {
      dbName: 'sharedtrip-abc',
      error: 'already_member',
      flockId: 'abc',
      name: 'Honeymoon',
      ok: false,
    })
  })

  test('name falls back to null on a legacy meta with no name', () => {
    const body = buildAlreadyMemberBody('abc', 'sharedtrip-abc', {
      members: ['a@x.io'],
    })
    assert.equal(body.name, null)
    // null survives JSON.stringify (undefined would be dropped).
    assert.ok(JSON.stringify(body).includes('"name":null'))
  })

  test('null meta → name null, still carries flockId + dbName', () => {
    const body = buildAlreadyMemberBody('abc', 'sharedtrip-abc', null)
    assert.equal(body.flockId, 'abc')
    assert.equal(body.dbName, 'sharedtrip-abc')
    assert.equal(body.name, null)
  })
})

describe('[Invite] /sharedtrips/join frozen rejection (#334)', () => {
  // The share path rejects frozen via assertPreviewable (covered above); this
  // pins that a frozen trip throws trip_frozen on a clean (non-revoked) share
  // token — i.e. the join handler's share branch will surface 403 trip_frozen.
  test('share path: frozen trip → 403 trip_frozen via assertPreviewable', async () => {
    const env = {
      INVITE_KV: {
        async get() {
          return null
        },
      },
    }
    await assert.rejects(
      () =>
        assertPreviewable(
          { inviteEpoch: 0, billingStatus: 'frozen' },
          0,
          'aaaaaaaaaaaa',
          env,
        ),
      (e) => e.status === 403 && e.error === 'trip_frozen',
    )
  })
})

describe('[Analytics] isAllowedFunnelStage allowlist (#340)', () => {
  test('all four canonical stages are allowed', () => {
    for (const stage of FUNNEL_STAGE_ALLOWLIST) {
      assert.equal(isAllowedFunnelStage(stage), true, `stage "${stage}" should be allowed`)
    }
  })

  test('exact allowlist contains the four expected stages', () => {
    assert.deepEqual(
      [...FUNNEL_STAGE_ALLOWLIST].sort(),
      ['convert_requested', 'join_succeeded', 'nest_preview_viewed', 'scan_try_succeeded'],
    )
  })

  test('unknown stages are rejected', () => {
    const unknown = ['', 'foo', 'NEST_PREVIEW_VIEWED', 'nest-preview-viewed', 'admin', '../etc']
    for (const stage of unknown) {
      assert.equal(isAllowedFunnelStage(stage), false, `stage "${stage}" should be rejected`)
    }
  })

  test('non-string inputs are rejected', () => {
    for (const val of [null, undefined, 42, {}, [], true]) {
      assert.equal(isAllowedFunnelStage(val), false, `${JSON.stringify(val)} should be rejected`)
    }
  })
})

describe('[Invite] reset-links epoch bump (#339)', () => {
  // Tests the pure invariant: a token minted with epoch N is rejected by
  // assertPreviewable once the live meta epoch has been bumped to N+1.
  // The actual HTTP endpoint (POST /sharedtrips/:id/reset-links) does the
  // write-meta step; here we confirm the guard that makes the revocation
  // work — no Docker required.

  const noKv = { INVITE_KV: { async get() { return null } } }

  test('token epoch === live epoch → allowed', async () => {
    // Epoch 3 in both token and meta — should not throw.
    await assert.doesNotReject(() =>
      assertPreviewable({ inviteEpoch: 3 }, 3, 'jti_abc', noKv),
    )
  })

  test('token epoch < live epoch (epoch bumped) → 403 revoked', async () => {
    // Meta was at epoch 3 when token was minted; owner bumped to 4.
    await assert.rejects(
      () => assertPreviewable({ inviteEpoch: 4 }, 3, 'jti_abc', noKv),
      (e) => e.status === 403 && e.error === 'revoked',
    )
  })

  test('token epoch > live epoch → 403 revoked (tampered)', async () => {
    // A tampered token claiming a future epoch is also rejected.
    await assert.rejects(
      () => assertPreviewable({ inviteEpoch: 2 }, 5, 'jti_abc', noKv),
      (e) => e.status === 403 && e.error === 'revoked',
    )
  })

  test('epoch bump invalidates previously minted token (integration of mint + guard)', async () => {
    const env = { SERVER_SECRET: SECRET, ...noKv }
    const { payload } = await mintShareToken({
      env,
      flockId: 'testflk',
      inviter: 'owner@example.com',
      epoch: 7,
    })
    // Meta at epoch 7 — token is valid.
    await assert.doesNotReject(() =>
      assertPreviewable({ inviteEpoch: 7 }, payload.epoch, payload.jti, noKv),
    )
    // Owner bumps epoch to 8 — same token is now revoked.
    await assert.rejects(
      () => assertPreviewable({ inviteEpoch: 8 }, payload.epoch, payload.jti, noKv),
      (e) => e.status === 403 && e.error === 'revoked',
    )
  })
})
