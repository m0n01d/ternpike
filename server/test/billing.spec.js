// Coverage for the billing routes (server/billing.js).
//
// Stripe is stubbed by spinning up an in-process Node `http.createServer`
// on a random port and pointing `STRIPE_BASE_URL` at it. The TrailblazerSlots
// Durable Object is stubbed at the env-binding level — we only need
// `idFromName(...).fetch(...)` to return a canned Response. No CouchDB.

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'

import { request } from './fixtures/app.js'
import { basicAuthHeader } from './fixtures/auth.js'
import { memoryKv } from './fixtures/env.js'
import { freshUser, getUser, upsertUser } from '../users.js'

const ALICE = 'alice@test.ternpike.com'
const SERVER_SECRET = 'test-server-secret-do-not-use-in-production'

const APP_ORIGIN = 'https://app.ternpike.com'
const LOCAL_DEV_ORIGIN = 'http://localhost:3000'
const EVIL_ORIGIN = 'https://evil.example.com'

let env
let stripe
let trailblazerStub

// In-process mock Stripe server. Each call captures the body + path so
// tests can assert on what we sent, and the test sets up `respond` to
// control the canned response per endpoint.
async function startMockStripe() {
  const calls = []
  let responder = null
  const server = http.createServer((req, res) => {
    let raw = ''
    req.on('data', (chunk) => {
      raw += chunk.toString()
    })
    req.on('end', () => {
      const params = new URLSearchParams(raw)
      const body = {}
      for (const [k, v] of params.entries()) body[k] = v
      calls.push({ body, path: req.url, raw })
      const handler = responder || ((path) => {
        if (path.startsWith('/v1/customers')) {
          return { status: 200, body: { id: 'cus_test_1', object: 'customer' } }
        }
        if (path.startsWith('/v1/checkout/sessions')) {
          return {
            status: 200,
            body: {
              id: 'cs_test_1',
              object: 'checkout.session',
              url: 'https://stripe.test/checkout/cs_test_1',
            },
          }
        }
        if (path.startsWith('/v1/billing_portal/sessions')) {
          return {
            status: 200,
            body: {
              id: 'bps_test_1',
              object: 'billing_portal.session',
              url: 'https://stripe.test/portal/bps_test_1',
            },
          }
        }
        return { status: 404, body: { error: { message: 'not stubbed' } } }
      })
      const out = handler(req.url, body)
      res.statusCode = out.status
      res.setHeader('Content-Type', 'application/json')
      res.end(JSON.stringify(out.body))
    })
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  const { port } = server.address()
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    calls,
    close: () =>
      new Promise((resolve) => server.close(() => resolve())),
    setResponder: (fn) => {
      responder = fn
    },
  }
}

// Stub `env.TRAILBLAZER_SLOTS` — production callers do
// `env.NAMESPACE.get(env.NAMESPACE.idFromName('global')).fetch(...)`,
// so the mock exposes both `idFromName` (returning an opaque id) and
// `get(id)` (returning a fetchable stub). Earlier versions of this mock
// fused them into one object and let `idFromName().fetch()` work
// directly — that hid a real bug in server/billing.js that 502'd at
// runtime because DurableObjectId has no `.fetch`. See PR fixing this.
function makeTrailblazerStub() {
  const calls = []
  let responder = (path) => {
    if (path === '/status') {
      return { status: 200, body: { available: 500, total: 500 } }
    }
    if (path === '/reserve') {
      return {
        status: 200,
        body: { number: 42, ok: true, reservationToken: 'tok_test' },
      }
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

beforeEach(async () => {
  stripe = await startMockStripe()
  trailblazerStub = makeTrailblazerStub()
  env = {
    CODES_KV: memoryKv(),
    SERVER_SECRET,
    STRIPE_BASE_URL: stripe.baseUrl,
    STRIPE_PRICE_OSPREY_MONTHLY: 'price_osprey_monthly_test',
    STRIPE_PRICE_OSPREY_YEARLY: 'price_osprey_yearly_test',
    STRIPE_PRICE_TRAILBLAZER: 'price_trailblazer_test',
    STRIPE_SECRET_KEY: 'sk_test_mock',
    TIERS_KV: memoryKv(),
    TRAILBLAZER_SLOTS: trailblazerStub.stub,
  }
})

afterEach(async () => {
  await stripe.close()
})

const authed = async (email, origin = APP_ORIGIN) => ({
  Authorization: await basicAuthHeader(email, SERVER_SECRET),
  Origin: origin,
})

describe('POST /billing/checkout — auth', () => {
  test('missing authorization → 401', async () => {
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'osprey_monthly' },
      headers: { Origin: APP_ORIGIN },
    })
    assert.equal(res.status, 401)
    assert.equal(res.body.error, 'unauthorized')
  })

  test('invalid plan → 400', async () => {
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'mega_premium' },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'invalid_plan')
  })

  test('crafted Origin → 400 bad_origin', async () => {
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'osprey_monthly' },
      headers: await authed(ALICE, EVIL_ORIGIN),
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'bad_origin')
  })

  test('localhost:3000 Origin is accepted', async () => {
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'osprey_monthly' },
      headers: await authed(ALICE, LOCAL_DEV_ORIGIN),
    })
    assert.equal(res.status, 200)
    assert.ok(res.body.url)
  })
})

describe('POST /billing/checkout — osprey subscription', () => {
  test('osprey_monthly happy path creates customer + checkout session', async () => {
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'osprey_monthly' },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 200)
    assert.ok(res.body.url, 'response includes a checkout url')
    assert.match(res.body.url, /stripe\.test\/checkout/)

    // stripe was called for /v1/customers then /v1/checkout/sessions
    const paths = stripe.calls.map((c) => c.path)
    assert.deepEqual(paths, ['/v1/customers', '/v1/checkout/sessions'])

    const checkoutCall = stripe.calls[1]
    assert.equal(checkoutCall.body.mode, 'subscription')
    assert.equal(checkoutCall.body.customer, 'cus_test_1')
    assert.equal(checkoutCall.body.client_reference_id, ALICE.toLowerCase())
    assert.equal(
      checkoutCall.body['line_items[0][price]'],
      'price_osprey_monthly_test',
    )
    assert.equal(checkoutCall.body['line_items[0][quantity]'], '1')
    assert.equal(
      checkoutCall.body.success_url,
      APP_ORIGIN + '/settings?checkout=success',
    )
    assert.equal(
      checkoutCall.body.cancel_url,
      APP_ORIGIN + '/settings?checkout=canceled',
    )

    // stripeCustomerId persisted to the user record
    const user = await getUser(env, ALICE)
    assert.equal(user.stripeCustomerId, 'cus_test_1')
    assert.equal(user.tier, 'tern') // unchanged — webhook flips this later
  })

  test('osprey_yearly happy path uses the yearly price id', async () => {
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'osprey_yearly' },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 200)
    const checkoutCall = stripe.calls.find((c) =>
      c.path.startsWith('/v1/checkout/sessions'),
    )
    assert.equal(
      checkoutCall.body['line_items[0][price]'],
      'price_osprey_yearly_test',
    )
  })

  test('reuses existing stripeCustomerId — no extra customer create', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_existing_42',
    })
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'osprey_monthly' },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 200)
    const paths = stripe.calls.map((c) => c.path)
    assert.deepEqual(paths, ['/v1/checkout/sessions'])
    assert.equal(stripe.calls[0].body.customer, 'cus_existing_42')
  })
})

describe('POST /billing/checkout — tier-gated paths', () => {
  test('already-osprey re-requesting osprey → portal url (200)', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_osprey_alice',
      subscriptionStatus: 'active',
      tier: 'osprey',
    })
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'osprey_monthly' },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 200)
    assert.ok(res.body.url)
    assert.match(res.body.url, /stripe\.test\/portal/)

    const paths = stripe.calls.map((c) => c.path)
    assert.deepEqual(paths, ['/v1/billing_portal/sessions'])
    assert.equal(stripe.calls[0].body.customer, 'cus_osprey_alice')
  })

  test('already-trailblazer → 403 already_trailblazer', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_tb_alice',
      tier: 'trailblazer',
      trailblazerNumber: 7,
      trailblazerPurchasedAt: new Date().toISOString(),
    })
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'osprey_monthly' },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 403)
    assert.equal(res.body.reason, 'already_trailblazer')

    // Trailblazer is permanent — no checkout/portal created
    const paths = stripe.calls.map((c) => c.path)
    assert.deepEqual(
      paths.filter((p) => !p.startsWith('/v1/customers')),
      [],
    )
  })

  test('already-trailblazer requesting trailblazer → 403', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_tb_alice',
      tier: 'trailblazer',
      trailblazerNumber: 7,
      trailblazerPurchasedAt: new Date().toISOString(),
    })
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'trailblazer' },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 403)
    assert.equal(res.body.reason, 'already_trailblazer')
  })
})

describe('POST /billing/checkout — trailblazer one-time', () => {
  test('happy path: reserves slot + checkout w/ metadata + returns number', async () => {
    trailblazerStub.setResponder((path) => {
      if (path === '/reserve') {
        return {
          status: 200,
          body: { number: 17, ok: true, reservationToken: 'tok_abc123' },
        }
      }
      return { status: 404, body: {} }
    })
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'trailblazer' },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.number, 17)
    assert.ok(res.body.url)

    // DO /reserve was called with the lowercased email
    assert.equal(trailblazerStub.calls.length, 1)
    assert.equal(trailblazerStub.calls[0].path, '/reserve')
    assert.equal(trailblazerStub.calls[0].body.email, ALICE.toLowerCase())

    const checkoutCall = stripe.calls.find((c) =>
      c.path.startsWith('/v1/checkout/sessions'),
    )
    assert.ok(checkoutCall, 'checkout session was created')
    assert.equal(checkoutCall.body.mode, 'payment')
    assert.equal(
      checkoutCall.body['line_items[0][price]'],
      'price_trailblazer_test',
    )
    assert.equal(checkoutCall.body['metadata[trailblazerNumber]'], '17')
    assert.equal(checkoutCall.body['metadata[reservationToken]'], 'tok_abc123')
    assert.equal(checkoutCall.body['metadata[email]'], ALICE.toLowerCase())
    assert.ok(checkoutCall.body.expires_at)
    // 29 minutes ahead of now, give or take a few seconds
    const expiresAt = Number(checkoutCall.body.expires_at)
    const nowSec = Math.floor(Date.now() / 1000)
    const delta = expiresAt - nowSec
    assert.ok(delta > 28 * 60 && delta <= 30 * 60, `expires_at delta ${delta}`)
  })

  test('sold-out → 409 with remaining=0', async () => {
    trailblazerStub.setResponder((path) => {
      if (path === '/reserve') {
        return {
          status: 200,
          body: { ok: false, reason: 'sold_out', remaining: 0 },
        }
      }
      return { status: 404, body: {} }
    })
    const res = await request(env, 'POST', '/billing/checkout', {
      body: { plan: 'trailblazer' },
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 409)
    assert.equal(res.body.remaining, 0)

    // No checkout session created when slot reservation fails
    const checkoutCall = stripe.calls.find((c) =>
      c.path.startsWith('/v1/checkout/sessions'),
    )
    assert.equal(checkoutCall, undefined)
  })
})

describe('POST /billing/portal', () => {
  test('missing auth → 401', async () => {
    const res = await request(env, 'POST', '/billing/portal', {
      headers: { Origin: APP_ORIGIN },
    })
    assert.equal(res.status, 401)
  })

  test('user without stripeCustomerId → 404 no_customer', async () => {
    await upsertUser(env, freshUser(ALICE))
    const res = await request(env, 'POST', '/billing/portal', {
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 404)
    assert.equal(res.body.error, 'no_customer')
  })

  test('happy path returns portal url', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_portal_alice',
      tier: 'osprey',
    })
    const res = await request(env, 'POST', '/billing/portal', {
      headers: await authed(ALICE),
    })
    assert.equal(res.status, 200)
    assert.ok(res.body.url)
    assert.match(res.body.url, /stripe\.test\/portal/)
    assert.equal(stripe.calls[0].body.customer, 'cus_portal_alice')
    assert.equal(stripe.calls[0].body.return_url, APP_ORIGIN + '/settings')
  })

  test('crafted Origin → 400 bad_origin', async () => {
    await upsertUser(env, {
      ...freshUser(ALICE),
      stripeCustomerId: 'cus_portal_alice',
    })
    const res = await request(env, 'POST', '/billing/portal', {
      headers: await authed(ALICE, EVIL_ORIGIN),
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'bad_origin')
  })
})

describe('GET /billing/trailblazer-status', () => {
  test('public — no auth required, returns {available, total} + cache header', async () => {
    trailblazerStub.setResponder((path) => {
      if (path === '/status') {
        return { status: 200, body: { available: 483, total: 500 } }
      }
      return { status: 404, body: {} }
    })
    const res = await request(env, 'GET', '/billing/trailblazer-status')
    assert.equal(res.status, 200)
    assert.equal(res.body.available, 483)
    assert.equal(res.body.total, 500)
    assert.equal(
      res.headers.get('cache-control'),
      'public, max-age=30',
    )
  })

  test('passes through DO status when zero available', async () => {
    trailblazerStub.setResponder((path) => {
      if (path === '/status') {
        return { status: 200, body: { available: 0, total: 500 } }
      }
      return { status: 404, body: {} }
    })
    const res = await request(env, 'GET', '/billing/trailblazer-status')
    assert.equal(res.status, 200)
    assert.equal(res.body.available, 0)
  })
})
