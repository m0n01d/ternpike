// Coverage for the Stripe webhook receiver (server/billingWebhook.js).
//
// The webhook is the source of truth for "did payment land" — we exercise
// signature verification, idempotency, and every event-type branch including
// the Trailblazer permanence rules.
//
// Stripe is never contacted (the webhook is the receiving side). The
// TrailblazerSlots Durable Object is stubbed at the env-binding level the
// same way billing.spec.js does. Signatures are minted in-test against a
// known `STRIPE_WEBHOOK_SECRET`.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'
import crypto from 'node:crypto'

import { request } from './fixtures/app.js'
import { memoryKv } from './fixtures/env.js'
import { freshUser, getUser, upsertUser } from '../users.js'

const ALICE = 'alice@test.ternpike.com'
const BOB = 'bob@test.ternpike.com'
const STRIPE_WEBHOOK_SECRET = 'whsec_test_do_not_use_in_production'
const SERVER_SECRET = 'test-server-secret-do-not-use-in-production'

let env
let trailblazerStub

function makeTrailblazerStub() {
  const calls = []
  let responder = (path) => {
    if (path === '/confirm') {
      return { status: 200, body: { ok: true, number: 42 } }
    }
    return { status: 404, body: { error: 'not_stubbed' } }
  }
  const objectStub = {
    fetch: async (input, init = {}) => {
      const url = typeof input === 'string' ? input : input.url
      const path = new URL(url).pathname
      let body = null
      if (init.body) {
        try {
          body = JSON.parse(init.body)
        } catch {
          body = init.body
        }
      }
      calls.push({ body, method: init.method || 'GET', path })
      const out = responder(path, body)
      return new Response(JSON.stringify(out.body), {
        headers: { 'Content-Type': 'application/json' },
        status: out.status,
      })
    },
  }
  const stub = {
    idFromName: (name) => ({ name }),
    get: () => objectStub,
  }
  return {
    calls,
    setResponder: (fn) => {
      responder = fn
    },
    stub,
  }
}

// Sign a payload the way Stripe does: HMAC-SHA256(secret, `${t}.${body}`),
// emit a `t=...,v1=...` header.
function stripeSignatureHeader(rawBody, secret, timestampSeconds) {
  const t = String(timestampSeconds)
  const signedPayload = `${t}.${rawBody}`
  const sig = crypto
    .createHmac('sha256', secret)
    .update(signedPayload)
    .digest('hex')
  return `t=${t},v1=${sig}`
}

function makeEvent(id, type, dataObject) {
  return {
    id,
    object: 'event',
    type,
    data: { object: dataObject },
    created: Math.floor(Date.now() / 1000),
  }
}

const OMIT_HEADER = Symbol('omit-header')

async function postWebhook(eventOrRaw, opts = {}) {
  const { secret = STRIPE_WEBHOOK_SECRET, timestamp, header } = opts
  const rawBody =
    typeof eventOrRaw === 'string' ? eventOrRaw : JSON.stringify(eventOrRaw)
  const t = timestamp ?? Math.floor(Date.now() / 1000)
  const headers = { 'Content-Type': 'application/json' }
  let sigHeader
  if (header === OMIT_HEADER) {
    sigHeader = undefined
  } else if (header !== undefined) {
    sigHeader = header
  } else {
    sigHeader = stripeSignatureHeader(rawBody, secret, t)
  }
  if (sigHeader !== undefined) headers['stripe-signature'] = sigHeader
  return request(env, 'POST', '/stripe/webhook', { body: rawBody, headers })
}

beforeEach(() => {
  trailblazerStub = makeTrailblazerStub()
  env = {
    CODES_KV: memoryKv(),
    SERVER_SECRET,
    STRIPE_WEBHOOK_SECRET,
    TIERS_KV: memoryKv(),
    TRAILBLAZER_SLOTS: trailblazerStub.stub,
  }
})

afterEach(() => {
  trailblazerStub = null
  env = null
})

describe('POST /stripe/webhook — signature verification', () => {
  test('missing Stripe-Signature header → 400', async () => {
    const event = makeEvent('evt_test_missing', 'checkout.session.completed', {})
    const res = await postWebhook(event, { header: OMIT_HEADER })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'invalid_signature')
  })

  test('malformed header → 400', async () => {
    const event = makeEvent('evt_test_malformed', 'checkout.session.completed', {})
    const res = await postWebhook(event, { header: 'not-a-real-header' })
    assert.equal(res.status, 400)
  })

  test('header with t but no v1 → 400', async () => {
    const event = makeEvent('evt_test_no_v1', 'checkout.session.completed', {})
    const t = Math.floor(Date.now() / 1000)
    const res = await postWebhook(event, { header: `t=${t}` })
    assert.equal(res.status, 400)
  })

  test('valid signature with wrong secret → 400', async () => {
    const event = makeEvent('evt_test_wrong_secret', 'checkout.session.completed', {})
    const res = await postWebhook(event, { secret: 'whsec_different' })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'invalid_signature')
  })

  test('replay attack (timestamp > 5min old) → 400', async () => {
    const event = makeEvent('evt_test_old', 'checkout.session.completed', {})
    const stale = Math.floor(Date.now() / 1000) - 6 * 60
    const res = await postWebhook(event, { timestamp: stale })
    assert.equal(res.status, 400)
  })

  test('valid signature with unknown event type → 200 (ack)', async () => {
    const event = makeEvent('evt_test_unknown', 'some.event.we.do.not.handle', {
      customer: 'cus_x',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    assert.equal(res.body.ok, true)
  })

  test('no STRIPE_WEBHOOK_SECRET configured → 400', async () => {
    env.STRIPE_WEBHOOK_SECRET = undefined
    const event = makeEvent('evt_test_no_secret', 'checkout.session.completed', {})
    const res = await postWebhook(event, { secret: 'anything' })
    assert.equal(res.status, 400)
  })
})

describe('POST /stripe/webhook — idempotency', () => {
  test('first delivery applies; second delivery with same event.id is a no-op replay', async () => {
    await upsertUser(env, freshUser(ALICE))
    const event = makeEvent('evt_idem_1', 'checkout.session.completed', {
      client_reference_id: ALICE,
      customer: 'cus_idem_1',
      mode: 'subscription',
      subscription: 'sub_idem_1',
    })

    const first = await postWebhook(event)
    assert.equal(first.status, 200)
    assert.equal(first.body.replay, undefined)

    const userAfterFirst = await getUser(env, ALICE)
    assert.equal(userAfterFirst.tier, 'osprey')
    assert.equal(userAfterFirst.stripeCustomerId, 'cus_idem_1')
    assert.equal(userAfterFirst.subscriptionId, 'sub_idem_1')
    const updatedAtAfterFirst = userAfterFirst.updatedAt

    // Wait a tick so any second write would have a later updatedAt
    await new Promise((r) => setTimeout(r, 10))

    const second = await postWebhook(event)
    assert.equal(second.status, 200)
    assert.equal(second.body.replay, true)

    const userAfterSecond = await getUser(env, ALICE)
    // Same record — replay didn't re-upsert
    assert.equal(userAfterSecond.updatedAt, updatedAtAfterFirst)
  })
})

describe('POST /stripe/webhook — checkout.session.completed (subscription)', () => {
  test('writes stripeCustomerId, subscriptionId, tier=osprey, status=active + customer index', async () => {
    await upsertUser(env, freshUser(ALICE))
    const event = makeEvent('evt_osprey_1', 'checkout.session.completed', {
      client_reference_id: ALICE,
      customer: 'cus_osprey_1',
      mode: 'subscription',
      subscription: 'sub_osprey_1',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)

    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'osprey')
    assert.equal(user.subscriptionStatus, 'active')
    assert.equal(user.stripeCustomerId, 'cus_osprey_1')
    assert.equal(user.subscriptionId, 'sub_osprey_1')

    // customer-id → email index written
    const indexed = await env.CODES_KV.get('stripe:customer:cus_osprey_1')
    assert.equal(indexed, ALICE.toLowerCase())
  })

  test('upserts user even when no UserRecord exists yet (defensive)', async () => {
    // no upsertUser before — webhook arrives first somehow
    const event = makeEvent('evt_osprey_new', 'checkout.session.completed', {
      client_reference_id: BOB,
      customer: 'cus_bob_1',
      mode: 'subscription',
      subscription: 'sub_bob_1',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, BOB)
    assert.equal(user.tier, 'osprey')
    assert.equal(user.email, BOB.toLowerCase())
  })

  test('subscription checkout ignored when user is already trailblazer', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_tb_alice',
      tier: 'trailblazer',
      trailblazerNumber: 12,
      trailblazerPurchasedAt: new Date().toISOString(),
    })
    const event = makeEvent('evt_osprey_for_tb', 'checkout.session.completed', {
      client_reference_id: ALICE,
      customer: 'cus_tb_alice',
      mode: 'subscription',
      subscription: 'sub_should_be_ignored',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)

    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'trailblazer') // unchanged
    assert.equal(user.trailblazerNumber, 12)
    assert.equal(user.subscriptionId, null)
  })

  test('missing client_reference_id → ack 200, no user write', async () => {
    const event = makeEvent('evt_no_email', 'checkout.session.completed', {
      customer: 'cus_orphan',
      mode: 'subscription',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    // no customer index either
    const indexed = await env.CODES_KV.get('stripe:customer:cus_orphan')
    assert.equal(indexed, null)
  })
})

describe('POST /stripe/webhook — checkout.session.completed (trailblazer payment)', () => {
  test('confirms slot, writes tier=trailblazer + number + purchasedAt', async () => {
    trailblazerStub.setResponder((path) => {
      if (path === '/confirm') {
        return { status: 200, body: { ok: true, number: 17 } }
      }
      return { status: 404, body: {} }
    })
    await upsertUser(env, freshUser(ALICE))
    const event = makeEvent('evt_tb_1', 'checkout.session.completed', {
      client_reference_id: ALICE,
      customer: 'cus_tb_1',
      metadata: {
        email: ALICE.toLowerCase(),
        reservationToken: 'tok_tb_1',
        trailblazerNumber: '17',
      },
      mode: 'payment',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)

    assert.equal(trailblazerStub.calls.length, 1)
    assert.equal(trailblazerStub.calls[0].path, '/confirm')
    assert.equal(trailblazerStub.calls[0].body.email, ALICE.toLowerCase())
    assert.equal(trailblazerStub.calls[0].body.reservationToken, 'tok_tb_1')

    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'trailblazer')
    assert.equal(user.trailblazerNumber, 17)
    assert.ok(user.trailblazerPurchasedAt)
    assert.equal(user.stripeCustomerId, 'cus_tb_1')
    assert.equal(user.subscriptionId, null)
    assert.equal(user.subscriptionStatus, null)
  })

  test('DO /confirm returns 410 expired → 200 with no user write', async () => {
    trailblazerStub.setResponder((path) => {
      if (path === '/confirm') {
        return { status: 410, body: { ok: false, error: 'reservation_expired' } }
      }
      return { status: 404, body: {} }
    })
    await upsertUser(env, freshUser(ALICE))
    const event = makeEvent('evt_tb_expired', 'checkout.session.completed', {
      client_reference_id: ALICE,
      customer: 'cus_tb_expired',
      metadata: {
        reservationToken: 'tok_expired',
        trailblazerNumber: '5',
      },
      mode: 'payment',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)

    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'tern') // unchanged
    assert.equal(user.trailblazerNumber, null)
  })

  test('trailblazer event for already-trailblazer user → 200, no DO call, no rewrite', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_tb_already',
      tier: 'trailblazer',
      trailblazerNumber: 3,
      trailblazerPurchasedAt: new Date().toISOString(),
    })
    const event = makeEvent('evt_tb_already', 'checkout.session.completed', {
      client_reference_id: ALICE,
      customer: 'cus_tb_already',
      metadata: {
        reservationToken: 'tok_already',
        trailblazerNumber: '99',
      },
      mode: 'payment',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    assert.equal(trailblazerStub.calls.length, 0) // short-circuited

    const user = await getUser(env, ALICE)
    assert.equal(user.trailblazerNumber, 3) // unchanged
  })

  test('payment mode without trailblazerNumber metadata → 200, no-op', async () => {
    await upsertUser(env, freshUser(ALICE))
    const event = makeEvent('evt_payment_no_meta', 'checkout.session.completed', {
      client_reference_id: ALICE,
      customer: 'cus_x',
      metadata: {},
      mode: 'payment',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    assert.equal(trailblazerStub.calls.length, 0)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'tern')
  })
})

describe('POST /stripe/webhook — customer.subscription.updated', () => {
  async function seedOsprey(email, customerId) {
    await upsertUser(env, {
      ...freshUser(email),
      stripeCustomerId: customerId,
      subscriptionId: 'sub_x',
      subscriptionStatus: 'active',
      tier: 'osprey',
    })
    await env.CODES_KV.put(
      'stripe:customer:' + customerId,
      email.toLowerCase(),
    )
  }

  test('status=active → tier=osprey, status=active', async () => {
    await seedOsprey(ALICE, 'cus_active_1')
    const event = makeEvent('evt_sub_active', 'customer.subscription.updated', {
      customer: 'cus_active_1',
      id: 'sub_active_1',
      status: 'active',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'osprey')
    assert.equal(user.subscriptionStatus, 'active')
    assert.equal(user.subscriptionId, 'sub_active_1')
  })

  test('status=canceled → tier=tern, status=canceled', async () => {
    await seedOsprey(ALICE, 'cus_cancel_1')
    const event = makeEvent('evt_sub_cancel', 'customer.subscription.updated', {
      customer: 'cus_cancel_1',
      id: 'sub_cancel_1',
      status: 'canceled',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'tern')
    assert.equal(user.subscriptionStatus, 'canceled')
  })

  test('status=trialing → tier=osprey, status=trialing', async () => {
    await seedOsprey(ALICE, 'cus_trial_1')
    const event = makeEvent('evt_sub_trial', 'customer.subscription.updated', {
      customer: 'cus_trial_1',
      id: 'sub_trial_1',
      status: 'trialing',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'osprey')
    assert.equal(user.subscriptionStatus, 'trialing')
  })

  test('status=past_due → tier=tern (not in paid-status set)', async () => {
    await seedOsprey(ALICE, 'cus_past_1')
    const event = makeEvent('evt_sub_past', 'customer.subscription.updated', {
      customer: 'cus_past_1',
      id: 'sub_past_1',
      status: 'past_due',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'tern')
    assert.equal(user.subscriptionStatus, 'past_due')
  })

  test('status=incomplete (non-spec) collapses to canceled storage, tier=tern', async () => {
    await seedOsprey(ALICE, 'cus_incomplete_1')
    const event = makeEvent('evt_sub_incomplete', 'customer.subscription.updated', {
      customer: 'cus_incomplete_1',
      id: 'sub_incomplete_1',
      status: 'incomplete',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'tern')
    // storage normalizes non-canonical statuses to 'canceled'
    assert.equal(user.subscriptionStatus, 'canceled')
  })

  test('trailblazer user ignored (no downgrade)', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_tb_sub',
      tier: 'trailblazer',
      trailblazerNumber: 1,
      trailblazerPurchasedAt: new Date().toISOString(),
    })
    await env.CODES_KV.put('stripe:customer:cus_tb_sub', ALICE.toLowerCase())
    const event = makeEvent('evt_sub_tb', 'customer.subscription.updated', {
      customer: 'cus_tb_sub',
      id: 'sub_zombie',
      status: 'canceled',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'trailblazer')
  })

  test('unknown customer (event arrives before checkout) → 200, no-op', async () => {
    const event = makeEvent('evt_sub_unknown', 'customer.subscription.updated', {
      customer: 'cus_never_seen',
      id: 'sub_x',
      status: 'active',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
  })
})

describe('POST /stripe/webhook — customer.subscription.deleted', () => {
  test('clears subscription, tier=tern, status=canceled', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_del_1',
      subscriptionId: 'sub_to_delete',
      subscriptionStatus: 'active',
      tier: 'osprey',
    })
    await env.CODES_KV.put('stripe:customer:cus_del_1', ALICE.toLowerCase())
    const event = makeEvent('evt_sub_deleted', 'customer.subscription.deleted', {
      customer: 'cus_del_1',
      id: 'sub_to_delete',
      status: 'canceled',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'tern')
    assert.equal(user.subscriptionStatus, 'canceled')
    assert.equal(user.subscriptionId, null)
  })

  test('trailblazer user ignored', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_tb_del',
      tier: 'trailblazer',
      trailblazerNumber: 2,
      trailblazerPurchasedAt: new Date().toISOString(),
    })
    await env.CODES_KV.put('stripe:customer:cus_tb_del', ALICE.toLowerCase())
    const event = makeEvent('evt_sub_del_tb', 'customer.subscription.deleted', {
      customer: 'cus_tb_del',
      id: 'sub_x',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'trailblazer')
  })
})

describe('POST /stripe/webhook — invoice.payment_failed', () => {
  test('osprey user → tier stays osprey (grace), status=past_due', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_pf_1',
      subscriptionId: 'sub_pf_1',
      subscriptionStatus: 'active',
      tier: 'osprey',
    })
    await env.CODES_KV.put('stripe:customer:cus_pf_1', ALICE.toLowerCase())
    const event = makeEvent('evt_pf_1', 'invoice.payment_failed', {
      customer: 'cus_pf_1',
      id: 'in_pf_1',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'osprey')
    assert.equal(user.subscriptionStatus, 'past_due')
    assert.equal(user.subscriptionId, 'sub_pf_1')
  })

  test('trailblazer user ignored', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_pf_tb',
      tier: 'trailblazer',
      trailblazerNumber: 4,
      trailblazerPurchasedAt: new Date().toISOString(),
    })
    await env.CODES_KV.put('stripe:customer:cus_pf_tb', ALICE.toLowerCase())
    const event = makeEvent('evt_pf_tb', 'invoice.payment_failed', {
      customer: 'cus_pf_tb',
      id: 'in_pf_tb',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'trailblazer')
  })

  test('unknown customer → 200, no-op', async () => {
    const event = makeEvent('evt_pf_unknown', 'invoice.payment_failed', {
      customer: 'cus_unknown_pf',
      id: 'in_x',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
  })
})

describe('POST /stripe/webhook — unknown event types', () => {
  test('returns 200 without touching user records', async () => {
    await upsertUser(env, freshUser(ALICE))
    const event = makeEvent('evt_unknown_1', 'product.created', {
      id: 'prod_x',
    })
    const res = await postWebhook(event)
    assert.equal(res.status, 200)
    const user = await getUser(env, ALICE)
    assert.equal(user.tier, 'tern')
  })
})
