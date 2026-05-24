import { after, before, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { request } from '../fixtures/app.js'
import { basicAuthHeader, tamperedAuthHeader } from '../fixtures/auth.js'
import { startCouch } from '../fixtures/couch.js'
import { buildEnv, installResendCapture } from '../fixtures/env.js'
import {
  flockDbName,
  provisionFlock,
  readMeta,
  readSecurity,
} from '../fixtures/flocks.js'
import {
  ALICE,
  BOB,
  CAROL,
  EVE,
  seedUser,
  setTier,
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
  await seedUser(env, couch, ALICE, 'osprey')
  await seedUser(env, couch, BOB, 'osprey')
  await seedUser(env, couch, CAROL, 'osprey')
  await seedUser(env, couch, EVE, 'tern')
})

const authed = async (email) => ({
  Authorization: await basicAuthHeader(email, env.SERVER_SECRET),
})

describe('POST /sharedtrips', () => {
  test('fledgling caller is rejected with 403', async () => {
    const res = await request(env, 'POST', '/sharedtrips', {
      headers: await authed(EVE),
      body: { name: 'eve-flock' },
    })
    assert.equal(res.status, 403)
    assert.equal(res.body.error, 'paid_tier_required')
  })

  test('fly caller can create a flock (201)', async () => {
    const res = await request(env, 'POST', '/sharedtrips', {
      headers: await authed(ALICE),
      body: { name: 'alaska' },
    })
    assert.equal(res.status, 201)
    assert.ok(res.body.flockId)
    assert.equal(res.body.dbName, `sharedtrip-${res.body.flockId}`)
  })

  test('trailblazer caller can create a flock (201)', async () => {
    await setTier(env, ALICE, 'trailblazer')
    const res = await request(env, 'POST', '/sharedtrips', {
      headers: await authed(ALICE),
      body: { name: 'tb-flock' },
    })
    assert.equal(res.status, 201)
    assert.ok(res.body.flockId)
  })

  test('missing authorization header returns 401', async () => {
    const res = await request(env, 'POST', '/sharedtrips', {
      body: { name: 'no-auth' },
    })
    assert.equal(res.status, 401)
  })

  test('tampered basic-auth password returns 401', async () => {
    const res = await request(env, 'POST', '/sharedtrips', {
      headers: { Authorization: tamperedAuthHeader(ALICE) },
      body: { name: 'tampered' },
    })
    assert.equal(res.status, 401)
  })

  test('server ignores tier asserted in the request body', async () => {
    const res = await request(env, 'POST', '/sharedtrips', {
      headers: await authed(EVE),
      body: { name: 'sneaky', tier: 'osprey' },
    })
    assert.equal(res.status, 403)
    assert.equal(res.body.error, 'paid_tier_required')
  })
})

describe('POST /sharedtrips/:id/invite', () => {
  let flockId
  let dbName

  beforeEach(async () => {
    const f = await provisionFlock(couch, {
      name: 'invite-test',
      owner: ALICE,
      members: [ALICE],
    })
    flockId = f.flockId
    dbName = f.dbName
  })

  test('non-member caller is rejected (404, not 403)', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/invite`, {
      headers: await authed(BOB),
      body: { inviteeEmail: 'newbie@test.ternpike.com' },
    })
    // 404 — don't confirm existence of the flock to outsiders.
    assert.equal(res.status, 404)
  })

  test('member-but-not-owner caller is rejected with 403', async () => {
    // Promote a separate flock where BOB is a member but not the owner.
    const f2 = await provisionFlock(couch, {
      name: 'invite-test-2',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    const res = await request(env, 'POST', `/sharedtrips/${f2.flockId}/invite`, {
      headers: await authed(BOB),
      body: { inviteeEmail: 'newbie@test.ternpike.com' },
    })
    assert.equal(res.status, 403)
    assert.equal(res.body.error, 'not_owner')
  })

  test('owner caller can invite and the email is delivered', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/invite`, {
      headers: await authed(ALICE),
      body: { inviteeEmail: 'newbie@test.ternpike.com' },
    })
    assert.equal(res.status, 200)
    assert.equal(resend.sent.length, 1)
    assert.equal(resend.sent[0].body.to, 'newbie@test.ternpike.com')
  })

  test('invalid email format returns 400', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/invite`, {
      headers: await authed(ALICE),
      body: { inviteeEmail: 'not-an-email' },
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'invalid_email')
  })

  test('missing authorization header returns 401', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/invite`, {
      body: { inviteeEmail: 'newbie@test.ternpike.com' },
    })
    assert.equal(res.status, 401)
  })

  test('unknown flock id returns 404', async () => {
    const res = await request(env, 'POST', '/sharedtrips/nope-not-a-sharedtrip/invite', {
      headers: await authed(ALICE),
      body: { inviteeEmail: 'newbie@test.ternpike.com' },
    })
    assert.equal(res.status, 404)
  })

  test('positive control — dbName matches the provisioned flock', () => {
    assert.equal(dbName, flockDbName(flockId))
  })
})

describe('POST /sharedtrips/:id/leave', () => {
  let flockId
  let dbName

  beforeEach(async () => {
    const f = await provisionFlock(couch, {
      name: 'leave-test',
      owner: ALICE,
      members: [ALICE, BOB],
    })
    flockId = f.flockId
    dbName = f.dbName
  })

  test('non-member caller is rejected', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/leave`, {
      headers: await authed(CAROL),
    })
    // Spec: should be 404 not 403 — don't confirm existence to outsiders.
    // Current implementation returns 403; this test pins the gap so it
    // surfaces in CI rather than silently shipping.
    assert.equal(res.status, 404)
  })

  test('member-not-owner can leave; security members shrinks', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/leave`, {
      headers: await authed(BOB),
    })
    assert.equal(res.status, 200)
    const sec = await readSecurity(couch, dbName)
    assert.deepEqual(sec.members.names, [ALICE])
    const meta = await readMeta(couch, dbName)
    assert.deepEqual(meta.members, [ALICE])
  })

  test('owner self-leave while others remain returns 409', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/leave`, {
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 409)
    assert.equal(res.body.error, 'transfer_ownership_first')
  })

  test('sole-member owner self-leave is not exposed in v1', async () => {
    const solo = await provisionFlock(couch, {
      name: 'solo',
      owner: CAROL,
      members: [CAROL],
    })
    const res = await request(env, 'POST', `/sharedtrips/${solo.flockId}/leave`, {
      headers: await authed(CAROL),
    })
    // Documented gap: delete-flock is out of scope for v1. The endpoint
    // should reject the request rather than orphan the db; 409 is fine.
    assert.equal(res.status, 409)
  })

  test('missing authorization header returns 401', async () => {
    const res = await request(env, 'POST', `/sharedtrips/${flockId}/leave`)
    assert.equal(res.status, 401)
  })
})

describe('POST /sharedtrips/:id/transfer-ownership', () => {
  let flockId
  let dbName

  beforeEach(async () => {
    const f = await provisionFlock(couch, {
      name: 'transfer-test',
      owner: ALICE,
      members: [ALICE, BOB, EVE],
    })
    flockId = f.flockId
    dbName = f.dbName
  })

  test('non-owner caller is rejected with 403', async () => {
    const res = await request(
      env,
      'POST',
      `/sharedtrips/${flockId}/transfer-ownership`,
      {
        headers: await authed(BOB),
        body: { newOwnerEmail: BOB },
      },
    )
    assert.equal(res.status, 403)
    assert.equal(res.body.error, 'not_owner')
  })

  test('transfer to a non-member is rejected', async () => {
    const res = await request(
      env,
      'POST',
      `/sharedtrips/${flockId}/transfer-ownership`,
      {
        headers: await authed(ALICE),
        body: { newOwnerEmail: CAROL },
      },
    )
    assert.equal(res.body.error, 'new_owner_not_a_member')
    assert.ok(res.status === 400 || res.status === 409)
  })

  test('transfer to a fledgling member is rejected', async () => {
    const res = await request(
      env,
      'POST',
      `/sharedtrips/${flockId}/transfer-ownership`,
      {
        headers: await authed(ALICE),
        body: { newOwnerEmail: EVE },
      },
    )
    assert.equal(res.body.error, 'new_owner_not_paid')
    assert.ok(res.status === 400 || res.status === 409)
  })

  test('transfer to a fly member succeeds and updates billingOwner', async () => {
    const res = await request(
      env,
      'POST',
      `/sharedtrips/${flockId}/transfer-ownership`,
      {
        headers: await authed(ALICE),
        body: { newOwnerEmail: BOB },
      },
    )
    assert.equal(res.status, 200)
    assert.equal(res.body.billingOwner, BOB)
    const meta = await readMeta(couch, dbName)
    assert.equal(meta.billingOwner, BOB)
    const sec = await readSecurity(couch, dbName)
    assert.equal(sec.flock.billingOwner, BOB)
  })

  test('owner transferring to themselves is rejected', async () => {
    const res = await request(
      env,
      'POST',
      `/sharedtrips/${flockId}/transfer-ownership`,
      {
        headers: await authed(ALICE),
        body: { newOwnerEmail: ALICE },
      },
    )
    assert.ok(res.status >= 400 && res.status < 500)
    assert.notEqual(res.status, 200)
  })

  test('invalid email format returns 400', async () => {
    const res = await request(
      env,
      'POST',
      `/sharedtrips/${flockId}/transfer-ownership`,
      {
        headers: await authed(ALICE),
        body: { newOwnerEmail: 'not-an-email' },
      },
    )
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'invalid_email')
  })

  test('missing authorization header returns 401', async () => {
    const res = await request(
      env,
      'POST',
      `/sharedtrips/${flockId}/transfer-ownership`,
      { body: { newOwnerEmail: BOB } },
    )
    assert.equal(res.status, 401)
  })
})

describe('POST /sharedtrips/join (positive control via real invite)', () => {
  test('inviting and joining round-trips end-to-end', async () => {
    const f = await provisionFlock(couch, {
      name: 'join-rt',
      owner: ALICE,
      members: [ALICE],
    })
    const invite = await request(env, 'POST', `/sharedtrips/${f.flockId}/invite`, {
      headers: await authed(ALICE),
      body: { inviteeEmail: BOB },
    })
    assert.equal(invite.status, 200)
    // Extract the join token from the captured email body.
    const sentText = resend.sent[resend.sent.length - 1].body.text
    const match = sentText.match(/token=([^\s]+)/)
    assert.ok(match, 'expected join link in email body')
    const token = decodeURIComponent(match[1])
    const join = await request(env, 'POST', '/sharedtrips/join', {
      headers: await authed(BOB),
      body: { token },
    })
    assert.equal(join.status, 200)
    const meta = await readMeta(couch, f.dbName)
    assert.ok(meta.members.includes(BOB))
  })
})
