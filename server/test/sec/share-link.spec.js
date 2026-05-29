// [Invite] #328 — share-link mint + revocation scaffolding.
//
// Adversarial coverage for the new owner-only share-link surface
// (`POST /sharedtrips/:id/share-link`) and the revocation primitives that the
// downstream funnel endpoints (`/invite/resolve`, `/scan-guest`) gate on via
// `assertPreviewable` (server/inviteFunnel.js).
//
// The mint endpoint is exercised end-to-end through the worker; the
// revocation predicate is exercised directly against `assertPreviewable`
// (the funnel endpoints that consume it land in later issues, so there is no
// HTTP surface for them yet — testing the predicate is the in-scope unit).
//
// Requires a disposable CouchDB (docker). If docker is unavailable the whole
// sec suite is skipped by the harness; see the run notes in the #328 report.

import { after, before, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import {
  assertPreviewable,
  mintShareToken,
} from '../../inviteFunnel.js'
import { request } from '../fixtures/app.js'
import { basicAuthHeader } from '../fixtures/auth.js'
import { startCouch, couchAdminFetch } from '../fixtures/couch.js'
import { buildEnv, installResendCapture } from '../fixtures/env.js'
import { provisionFlock, readMeta } from '../fixtures/flocks.js'
import { ALICE, BOB, seedUser } from '../fixtures/users.js'

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
  await seedUser(env, couch, ALICE, 'osprey')
  await seedUser(env, couch, BOB, 'osprey')
})

const authed = async (email) => ({
  Authorization: await basicAuthHeader(email, env.SERVER_SECRET),
})

// Decode a JWT payload segment without verifying (tests only).
const decodePayload = (token) => {
  const part = token.split('.')[1]
  const padded = part.replace(/-/g, '+').replace(/_/g, '/')
  const pad = padded.length % 4 === 0 ? '' : '='.repeat(4 - (padded.length % 4))
  return JSON.parse(Buffer.from(padded + pad, 'base64').toString('utf8'))
}

// Read sharedtrip:meta, apply `patch`, and write it back (admin lens).
const patchMeta = async (dbName, patch) => {
  const cur = await readMeta(couch, dbName)
  const next = { ...cur, ...patch }
  const res = await couchAdminFetch(couch, `/${dbName}/sharedtrip%3Ameta`, {
    method: 'PUT',
    body: JSON.stringify(next),
  })
  if (!res.ok) throw new Error(`meta PUT ${res.status}`)
}

describe('[Invite] share-link mint + revocation (#328)', () => {
  let flockId
  let dbName

  beforeEach(async () => {
    const f = await provisionFlock(couch, {
      name: 'share-link',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    flockId = f.flockId
    dbName = f.dbName
  })

  test('owner mint: 200, returns nest URL with a typ:share token', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/share-link`, {
      headers: await authed(ALICE),
      body: {},
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
    assert.match(res.body.url, /^https:\/\/app\.ternpike\.com\/nest\?token=/)

    const token = decodeURIComponent(res.body.url.split('token=')[1])
    const payload = decodePayload(token)
    assert.equal(payload.typ, 'share')
    assert.equal(payload.flockId, flockId)
    assert.equal(payload.inviter, ALICE)
    assert.equal(payload.epoch, 0)
    assert.equal(typeof payload.jti, 'string')
    assert.equal(payload.jti.length, 12)
    // 30-day exp.
    assert.equal(payload.exp - payload.iat, 30 * 24 * 60 * 60)
    // Recipient-agnostic — no email bound into the token.
    assert.equal(payload.inviteeEmail, undefined)
  })

  test('non-owner member mint: bob (member, not owner) → 403 not_owner', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/share-link`, {
      headers: await authed(BOB),
      body: {},
    })
    assert.equal(res.status, 403)
    assert.equal(res.body.error, 'not_owner')
  })

  test('unauthenticated mint → 401', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/share-link`, {
      body: {},
    })
    assert.equal(res.status, 401)
  })

  test('mint for a nonexistent trip → 404 not_found (authenticated path)', async () => {
    const res = await request(env, 'POST', '/sharedtrips/deadbeef00ff/share-link', {
      headers: await authed(ALICE),
      body: {},
    })
    assert.equal(res.status, 404)
    assert.equal(res.body.error, 'not_found')
  })

  test('epoch bump revokes: token minted at epoch 0 fails after bump to 1', async () => {
    const { payload } = await mintShareToken({
      env,
      flockId,
      inviter: ALICE,
      epoch: 0,
    })
    // Token is good against the live meta initially.
    let meta = await readMeta(couch, dbName)
    await assertPreviewable(meta, payload.epoch, payload.jti, env)

    // Owner resets links → epoch bumps.
    await patchMeta(dbName, { inviteEpoch: 1 })
    meta = await readMeta(couch, dbName)
    await assert.rejects(
      () => assertPreviewable(meta, payload.epoch, payload.jti, env),
      (err) => err.status === 403 && err.error === 'revoked',
    )
  })

  test('jti deny-list revokes: revoked:<jti> in INVITE_KV → 403 revoked', async () => {
    const { payload } = await mintShareToken({
      env,
      flockId,
      inviter: ALICE,
      epoch: 0,
    })
    const meta = await readMeta(couch, dbName)
    // Good before the kill.
    await assertPreviewable(meta, payload.epoch, payload.jti, env)

    await env.INVITE_KV.put(`revoked:${payload.jti}`, '1')
    await assert.rejects(
      () => assertPreviewable(meta, payload.epoch, payload.jti, env),
      (err) => err.status === 403 && err.error === 'revoked',
    )
  })

  test('frozen trip → 403 trip_frozen', async () => {
    const { payload } = await mintShareToken({
      env,
      flockId,
      inviter: ALICE,
      epoch: 0,
    })
    await patchMeta(dbName, { billingStatus: 'frozen' })
    const meta = await readMeta(couch, dbName)
    await assert.rejects(
      () => assertPreviewable(meta, payload.epoch, payload.jti, env),
      (err) => err.status === 403 && err.error === 'trip_frozen',
    )
  })

  test('missing trip surfaces as 403 (not 404) via readMetaForPreview', async () => {
    const { readMetaForPreview } = await import('../../inviteFunnel.js')
    await assert.rejects(
      () => readMetaForPreview(env, 'deadbeef00ff'),
      (err) => err.status === 403 && err.error === 'revoked',
    )
  })

  test('positive control: minted link previews clean against live meta', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/share-link`, {
      headers: await authed(ALICE),
      body: {},
    })
    assert.equal(res.status, 200)
    const token = decodeURIComponent(res.body.url.split('token=')[1])
    const payload = decodePayload(token)
    const meta = await readMeta(couch, dbName)
    // No throw == previewable.
    await assertPreviewable(meta, payload.epoch, payload.jti, env)
  })
})
