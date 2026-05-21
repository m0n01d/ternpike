// Post-leave / post-kick access revocation. Exercises the CouchDB-side
// promise of "membership change is immediate": once a user is removed from
// `_security.members`, their pre-revocation Basic-auth credentials stop
// authorizing requests on the very next call — no caching mismatch, no
// stale-session window. Re-add restores access.
//
// CouchDB response-code convention. Issue #69 talks loosely about "401" for
// a revoked client, but that's the *client-side experience* (PouchDB raises
// `unauthorized` for any non-2xx auth error). The actual CouchDB response
// for a user whose credentials still verify but who is no longer in
// `_security.members` is **403 Forbidden** — 401 is reserved for bad/no
// credentials. We pin 403 here so a regression in either direction (CouchDB
// upgrade changing the code, or a misconfigured `_users` entry getting
// silently nuked) is visible.
//
// Out of scope here:
//
//   The JS port-layer sync-stop behavior (closing the PouchDB handle in
//   `pouch.js` and surfacing `SyncError` to Elm on a 401/403 from the
//   replicator) is exercised by the Playwright E2E suite in #76, not by
//   this server-side spec. The harness has no browser and the multi-DB
//   sync path under test in #59 lives in `src/pouch.js`. We assert here
//   only what CouchDB itself enforces: that a removed member's
//   credentials get rejected on every endpoint of the database. Whatever
//   the client does with that rejection is verified end-to-end elsewhere.
//
// Test cases (#69):
//   1. Read revocation         — GET _changes → 403 immediately after remove
//   2. Write revocation        — POST a doc   → 403 immediately after remove
//   3. Replication revocation  — pre-revoke handshake worked; post-revoke fails
//   4. Rejoin path             — admin re-adds; reads + writes recover
//   5. Re-invite after leave   — self-leave + new invite + redeem round-trips,
//                                and `user:flocks` reflects the rejoin

import { after, before, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { request } from '../fixtures/app.js'
import { basicAuthHeader, derivePassword } from '../fixtures/auth.js'
import { couchAdminFetch, startCouch } from '../fixtures/couch.js'
import { buildEnv, installResendCapture } from '../fixtures/env.js'
import {
  provisionFlock,
  readMeta,
  readSecurity,
} from '../fixtures/flocks.js'
import {
  ALICE,
  BOB,
  CAROL,
  EVE,
  personalDbFor,
  seedUser,
} from '../fixtures/users.js'

let couch
let env
let resend

before(async () => {
  couch = await startCouch()
  resend = installResendCapture()
})

after(async () => {
  if (resend) resend.uninstall()
  if (couch) await couch.stop()
})

beforeEach(async () => {
  env = buildEnv(couch)
  resend.reset()
  await seedUser(env, couch, ALICE, 'fly')
  await seedUser(env, couch, BOB, 'fly')
  await seedUser(env, couch, CAROL, 'fly')
  await seedUser(env, couch, EVE, 'fledgling')
})

const authed = async (email) => ({
  Authorization: await basicAuthHeader(email, env.SERVER_SECRET),
})

// Build a direct-to-CouchDB Basic-auth header for a user. Pre-revocation
// credentials live here: the password is the same HMAC-derived secret the
// `_users` doc was seeded with, so Bob's PouchDB client would send exactly
// this header.
const couchAuthFor = async (email) => {
  const password = await derivePassword(email, env.SERVER_SECRET)
  const token = Buffer.from(`${email.toLowerCase()}:${password}`).toString(
    'base64',
  )
  return `Basic ${token}`
}

const couchUserFetch = async (email, path, init = {}) => {
  const auth = await couchAuthFor(email)
  return fetch(`${couch.baseUrl}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: auth,
      ...(init.headers || {}),
    },
  })
}

// Admin-side simulation of an owner kick or self-leave: drop a member from
// both `_security.members.names` and `flock:meta.members`, exactly how the
// server's leave/kick path writes them.
const adminRemoveMember = async (dbName, email) => {
  const secRes = await couchAdminFetch(couch, `/${dbName}/_security`)
  if (!secRes.ok) throw new Error(`_security GET ${secRes.status}`)
  const sec = await secRes.json()
  sec.members.names = sec.members.names.filter((n) => n !== email)
  const secPut = await couchAdminFetch(couch, `/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(sec),
  })
  if (!secPut.ok) throw new Error(`_security PUT ${secPut.status}`)

  const metaRes = await couchAdminFetch(couch, `/${dbName}/flock%3Ameta`)
  if (!metaRes.ok) throw new Error(`flock:meta GET ${metaRes.status}`)
  const meta = await metaRes.json()
  meta.members = meta.members.filter((m) => m !== email)
  const metaPut = await couchAdminFetch(couch, `/${dbName}/flock%3Ameta`, {
    method: 'PUT',
    body: JSON.stringify(meta),
  })
  if (!metaPut.ok) throw new Error(`flock:meta PUT ${metaPut.status}`)
}

const adminAddMember = async (dbName, email) => {
  const secRes = await couchAdminFetch(couch, `/${dbName}/_security`)
  if (!secRes.ok) throw new Error(`_security GET ${secRes.status}`)
  const sec = await secRes.json()
  if (!sec.members.names.includes(email)) sec.members.names.push(email)
  const secPut = await couchAdminFetch(couch, `/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(sec),
  })
  if (!secPut.ok) throw new Error(`_security PUT ${secPut.status}`)

  const metaRes = await couchAdminFetch(couch, `/${dbName}/flock%3Ameta`)
  if (!metaRes.ok) throw new Error(`flock:meta GET ${metaRes.status}`)
  const meta = await metaRes.json()
  if (!meta.members.includes(email)) meta.members.push(email)
  const metaPut = await couchAdminFetch(couch, `/${dbName}/flock%3Ameta`, {
    method: 'PUT',
    body: JSON.stringify(meta),
  })
  if (!metaPut.ok) throw new Error(`flock:meta PUT ${metaPut.status}`)
}

const readUserFlocks = async (email) => {
  const personalDb = personalDbFor(email)
  const r = await couchAdminFetch(
    couch,
    `/${personalDb}/user%3Aflocks`,
  )
  if (!r.ok) throw new Error(`user:flocks GET ${r.status}`)
  return r.json()
}

describe('Read revocation', () => {
  let flockId
  let dbName

  beforeEach(async () => {
    const f = await provisionFlock(couch, {
      name: 'read-revoke',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    flockId = f.flockId
    dbName = f.dbName
  })

  test('positive control — current member can read _changes', async () => {
    const r = await couchUserFetch(BOB, `/${dbName}/_changes?limit=1`)
    assert.equal(r.status, 200)
  })

  test('removed member is rejected on _changes immediately on the next request', async () => {
    // Sanity-check the positive control first within this test to rule out
    // an ordering bug where CouchDB sees the membership change late.
    const before = await couchUserFetch(BOB, `/${dbName}/_changes?limit=1`)
    assert.equal(before.status, 200)

    await adminRemoveMember(dbName, BOB)

    const after = await couchUserFetch(BOB, `/${dbName}/_changes?limit=1`)
    // 403, not 401: Bob's `_users` entry is unchanged so the credentials
    // still verify — he just isn't in `_security.members` anymore.
    assert.equal(after.status, 403)
  })

  test('other members are unaffected by Bob being removed', async () => {
    await adminRemoveMember(dbName, BOB)
    const r = await couchUserFetch(ALICE, `/${dbName}/_changes?limit=1`)
    assert.equal(r.status, 200)
  })

  test('flockId is the routable identifier', () => {
    assert.ok(flockId)
    assert.equal(dbName, `flock-${flockId}`)
  })
})

describe('Write revocation', () => {
  let dbName

  beforeEach(async () => {
    const f = await provisionFlock(couch, {
      name: 'write-revoke',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    dbName = f.dbName
  })

  // Build a doc that satisfies the flock `validate_doc_update` design doc:
  // it requires `type`, `_id`, and `createdBy` matching the caller.
  const expenseDocFor = (email, marker) => ({
    _id: `expense::${new Date().toISOString()}::${marker}`,
    type: 'expense',
    createdBy: email,
    amount: 100,
    category: 'fuel',
  })

  test('positive control — current member can POST a doc', async () => {
    const r = await couchUserFetch(BOB, `/${dbName}`, {
      method: 'POST',
      body: JSON.stringify(expenseDocFor(BOB, 'pre-revoke')),
    })
    assert.equal(r.status, 201)
  })

  test('removed member is rejected when POSTing a new doc', async () => {
    await adminRemoveMember(dbName, BOB)
    const r = await couchUserFetch(BOB, `/${dbName}`, {
      method: 'POST',
      body: JSON.stringify(expenseDocFor(BOB, 'post-revoke')),
    })
    assert.equal(r.status, 403)
  })

  test('removed member is also rejected on PUT to a specific doc id', async () => {
    await adminRemoveMember(dbName, BOB)
    const r = await couchUserFetch(
      BOB,
      `/${dbName}/${encodeURIComponent('expense::2026-05-21T00:00:00.000Z::ghost')}`,
      {
        method: 'PUT',
        body: JSON.stringify({
          type: 'expense',
          createdBy: BOB,
          amount: 1,
          category: 'fuel',
        }),
      },
    )
    assert.equal(r.status, 403)
  })
})

describe('Replication revocation', () => {
  // The replication handshake PouchDB performs is, in practice, a series of
  // GETs against the source db: `/dbName`, `/dbName/_local/<id>`, and
  // `/dbName/_changes?...`. If any of those returns a non-2xx auth error,
  // the replicator halts. We exercise those calls directly instead of
  // pulling in a real PouchDB client — the contract under test is
  // CouchDB's, not Pouch's.
  let dbName

  beforeEach(async () => {
    const f = await provisionFlock(couch, {
      name: 'repl-revoke',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    dbName = f.dbName
  })

  test('positive control — pre-revocation handshake succeeds', async () => {
    const info = await couchUserFetch(BOB, `/${dbName}`)
    assert.equal(info.status, 200)
    const changes = await couchUserFetch(
      BOB,
      `/${dbName}/_changes?style=all_docs&limit=1`,
    )
    assert.equal(changes.status, 200)
  })

  test('post-revocation, every handshake step is rejected with 403', async () => {
    await adminRemoveMember(dbName, BOB)

    const info = await couchUserFetch(BOB, `/${dbName}`)
    assert.equal(info.status, 403)

    const changes = await couchUserFetch(
      BOB,
      `/${dbName}/_changes?style=all_docs&limit=1`,
    )
    assert.equal(changes.status, 403)

    const localCheckpoint = await couchUserFetch(
      BOB,
      `/${dbName}/_local/replication-checkpoint`,
    )
    assert.equal(localCheckpoint.status, 403)
  })
})

describe('Rejoin path (admin re-adds)', () => {
  let dbName

  beforeEach(async () => {
    const f = await provisionFlock(couch, {
      name: 'rejoin',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    dbName = f.dbName
  })

  test('after re-add, reads and writes succeed again', async () => {
    // Revoke.
    await adminRemoveMember(dbName, BOB)
    const denied = await couchUserFetch(BOB, `/${dbName}/_changes?limit=1`)
    assert.equal(denied.status, 403)

    // Re-add.
    await adminAddMember(dbName, BOB)

    // Read recovers.
    const read = await couchUserFetch(BOB, `/${dbName}/_changes?limit=1`)
    assert.equal(read.status, 200)

    // Write recovers.
    const write = await couchUserFetch(BOB, `/${dbName}`, {
      method: 'POST',
      body: JSON.stringify({
        _id: `expense::${new Date().toISOString()}::after-rejoin`,
        type: 'expense',
        createdBy: BOB,
        amount: 500,
        category: 'fuel',
      }),
    })
    assert.equal(write.status, 201)
  })

  test('rejoin gate: non-member is denied until explicitly added', async () => {
    // Carol was never a member. adminAddMember inside the test should be
    // the only way she gets in — confirm she stays out by default.
    const before = await couchUserFetch(CAROL, `/${dbName}/_changes?limit=1`)
    assert.equal(before.status, 403)
    await adminAddMember(dbName, CAROL)
    const after = await couchUserFetch(CAROL, `/${dbName}/_changes?limit=1`)
    assert.equal(after.status, 200)
  })
})

describe('Re-invite after self-leave', () => {
  test('Bob leaves, Alice re-invites, Bob redeems; user:flocks reflects rejoin', async () => {
    const f = await provisionFlock(couch, {
      name: 'reinvite',
      owner: ALICE,
      members: [ALICE, BOB],
    })

    // Sanity: Bob's user:flocks lists this flock pre-leave.
    const beforeFlocks = await readUserFlocks(BOB)
    assert.ok(
      (beforeFlocks.flocks || []).some((x) => x.id === f.flockId),
      'expected Bob.user:flocks to include the flock before leave',
    )

    // Bob self-leaves via the endpoint (exercises the real removal path).
    const leave = await request(env, 'POST', `/flocks/${f.flockId}/leave`, {
      headers: await authed(BOB),
    })
    assert.equal(leave.status, 200)

    // After leave: Bob's user:flocks no longer lists it, and CouchDB
    // rejects his reads.
    const midFlocks = await readUserFlocks(BOB)
    assert.equal(
      (midFlocks.flocks || []).filter((x) => x.id === f.flockId).length,
      0,
    )
    const mid = await couchUserFetch(BOB, `/${f.dbName}/_changes?limit=1`)
    assert.equal(mid.status, 403)

    // Alice re-invites Bob. We extract the join token from the captured
    // email body (same pattern as the existing /flocks/join round-trip
    // test in endpoints.spec.js).
    resend.reset()
    const invite = await request(env, 'POST', `/flocks/${f.flockId}/invite`, {
      headers: await authed(ALICE),
      body: { inviteeEmail: BOB },
    })
    assert.equal(invite.status, 200)
    const sentText = resend.sent[resend.sent.length - 1].body.text
    const match = sentText.match(/token=([^\s]+)/)
    assert.ok(match, 'expected join link in re-invite email body')
    const token = decodeURIComponent(match[1])

    const join = await request(env, 'POST', '/flocks/join', {
      headers: await authed(BOB),
      body: { token },
    })
    assert.equal(join.status, 200)

    // Bob is back in `_security` and `flock:meta.members`.
    const sec = await readSecurity(couch, f.dbName)
    assert.ok(sec.members.names.includes(BOB))
    const meta = await readMeta(couch, f.dbName)
    assert.ok(meta.members.includes(BOB))

    // Bob's user:flocks reflects the rejoin (one entry, not duplicated).
    const afterFlocks = await readUserFlocks(BOB)
    const matching = (afterFlocks.flocks || []).filter(
      (x) => x.id === f.flockId,
    )
    assert.equal(matching.length, 1, 'flock should appear exactly once')

    // And Bob's direct CouchDB reads work again.
    const read = await couchUserFetch(BOB, `/${f.dbName}/_changes?limit=1`)
    assert.equal(read.status, 200)
  })

  test('fledgling caller cannot leverage re-invite to bypass paid gate on creating flocks', async () => {
    // Positive control bracketing the re-invite path: re-invite is owner-
    // bounded. EVE (fledgling) cannot mint an invite into a flock she
    // doesn't own — exercises that the kick/leave revocation cannot be
    // chained into an unauthorized re-invite.
    const f = await provisionFlock(couch, {
      name: 'reinvite-guard',
      owner: ALICE,
      members: [ALICE],
    })
    const res = await request(env, 'POST', `/flocks/${f.flockId}/invite`, {
      headers: await authed(EVE),
      body: { inviteeEmail: BOB },
    })
    // Non-member: 404 (don't confirm existence). See #68.
    assert.equal(res.status, 404)
  })
})
