// POST /billing/checkout — start a Stripe Checkout session for an Osprey
// subscription or a one-time Trailblazer purchase.
// POST /billing/portal   — open the Stripe Customer Portal so the user can
//                          update card / cancel from Stripe-hosted UI.
// GET  /billing/trailblazer-status — public, cached, used by the marketing
//                          site + the upgrade UI to show "X of 500 left".
//
// We talk to Stripe over raw `fetch` (NOT the Stripe Node SDK) because the
// SDK reads `baseUrl` from `process.env` at module load time and `workerd`
// doesn't populate `process.env` — the same trap that bit the Resend SDK,
// documented in CLAUDE.md "Resend + workerd". Bodies are
// `application/x-www-form-urlencoded` per Stripe's REST API conventions.
//
// Identity convention: Stripe `client_reference_id` is the lowercased
// email. The webhook in #18 reads it back to drive `upsertUser`.
//
// Trailblazer slot atomicity: we /reserve in the Durable Object (#16)
// before creating the Checkout session, then bake the slot number +
// reservation token into Checkout `metadata`. The webhook claims the slot
// permanently via /confirm on `checkout.session.completed`. The Checkout
// session `expires_at` is held under the DO's 30-minute reservation TTL
// so an abandoned checkout naturally frees the slot.

import { authenticateCaller } from './auth.js'
import { freshUser, getUser, upsertUser } from './users.js'

const STRIPE_DEFAULT_BASE_URL = 'https://api.stripe.com'

const VALID_PLANS = new Set(['osprey_monthly', 'osprey_yearly', 'trailblazer'])

const ALLOWED_ORIGINS = new Set([
  'http://localhost:3000',
  'https://app.ternpike.com',
])

const TRAILBLAZER_CHECKOUT_EXPIRES_SECONDS = 29 * 60

// Whitelist Origin so a crafted request can't redirect users to an
// attacker-controlled `success_url` / `cancel_url`. Defaults to the
// production app origin when the header is absent (some user-agents
// don't send Origin on same-site POSTs).
function resolveAppOrigin(c) {
  const origin = c.req.header('origin') || c.req.header('Origin')
  if (!origin) return { ok: true, origin: 'https://app.ternpike.com' }
  if (!ALLOWED_ORIGINS.has(origin)) return { ok: false }
  return { ok: true, origin }
}

function stripeContext(env) {
  return {
    auth: 'Bearer ' + env.STRIPE_SECRET_KEY,
    base: env.STRIPE_BASE_URL || STRIPE_DEFAULT_BASE_URL,
  }
}

async function stripePost(env, path, params) {
  const { auth, base } = stripeContext(env)
  const res = await fetch(base + path, {
    body: params,
    headers: {
      Authorization: auth,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    method: 'POST',
  })
  const text = await res.text()
  let parsed = null
  try {
    parsed = text.length ? JSON.parse(text) : null
  } catch {
    parsed = null
  }
  return { body: parsed, ok: res.ok, status: res.status }
}

// Lazily create a Stripe Customer for the user and persist its id on the
// `UserRecord`. Idempotent — returns the existing id when one is already
// stored. A missing user record is materialized as a fresh `tern` record
// (defensive — `/auth/verify-code` should have created it).
async function ensureStripeCustomer(env, email) {
  let user = await getUser(env, email)
  if (!user) {
    user = await upsertUser(env, freshUser(email))
  }
  if (user.stripeCustomerId) return { stripeCustomerId: user.stripeCustomerId, user }
  const params = new URLSearchParams()
  params.set('email', email)
  const created = await stripePost(env, '/v1/customers', params)
  if (!created.ok || !created.body?.id) {
    throw new Error(
      `stripe customer create ${created.status}: ${JSON.stringify(created.body)}`,
    )
  }
  const next = await upsertUser(env, {
    ...user,
    stripeCustomerId: created.body.id,
  })
  return { stripeCustomerId: created.body.id, user: next }
}

async function createPortalSession(env, customerId, returnUrl) {
  const params = new URLSearchParams()
  params.set('customer', customerId)
  params.set('return_url', returnUrl)
  const res = await stripePost(env, '/v1/billing_portal/sessions', params)
  if (!res.ok || !res.body?.url) {
    throw new Error(
      `stripe portal ${res.status}: ${JSON.stringify(res.body)}`,
    )
  }
  return res.body.url
}

function ospreyPriceId(env, plan) {
  if (plan === 'osprey_monthly') return env.STRIPE_PRICE_OSPREY_MONTHLY
  if (plan === 'osprey_yearly') return env.STRIPE_PRICE_OSPREY_YEARLY
  return null
}

async function createOspreyCheckout(env, { customerId, email, originUrl, priceId }) {
  const params = new URLSearchParams()
  params.append('line_items[0][price]', priceId)
  params.append('line_items[0][quantity]', '1')
  params.set('cancel_url', originUrl + '/settings?checkout=canceled')
  params.set('client_reference_id', email)
  params.set('customer', customerId)
  params.set('mode', 'subscription')
  params.set('success_url', originUrl + '/settings?checkout=success')
  const res = await stripePost(env, '/v1/checkout/sessions', params)
  if (!res.ok || !res.body?.url) {
    throw new Error(
      `stripe checkout ${res.status}: ${JSON.stringify(res.body)}`,
    )
  }
  return res.body.url
}

async function reserveTrailblazerSlot(env, email) {
  const id = env.TRAILBLAZER_SLOTS.idFromName('global')
  const stub = env.TRAILBLAZER_SLOTS.get(id)
  const res = await stub.fetch('https://do.local/reserve', {
    body: JSON.stringify({ email }),
    headers: { 'Content-Type': 'application/json' },
    method: 'POST',
  })
  const text = await res.text()
  return text.length ? JSON.parse(text) : null
}

async function createTrailblazerCheckout(
  env,
  { customerId, email, number, originUrl, reservationToken },
) {
  const expiresAt =
    Math.floor(Date.now() / 1000) + TRAILBLAZER_CHECKOUT_EXPIRES_SECONDS
  const params = new URLSearchParams()
  params.append('line_items[0][price]', env.STRIPE_PRICE_TRAILBLAZER)
  params.append('line_items[0][quantity]', '1')
  params.set('cancel_url', originUrl + '/settings?checkout=canceled')
  params.set('client_reference_id', email)
  params.set('customer', customerId)
  params.set('expires_at', String(expiresAt))
  params.set('metadata[email]', email)
  params.set('metadata[reservationToken]', reservationToken)
  params.set('metadata[trailblazerNumber]', String(number))
  params.set('mode', 'payment')
  params.set('success_url', originUrl + '/settings?checkout=success')
  const res = await stripePost(env, '/v1/checkout/sessions', params)
  if (!res.ok || !res.body?.url) {
    throw new Error(
      `stripe checkout ${res.status}: ${JSON.stringify(res.body)}`,
    )
  }
  return res.body.url
}

export function registerBillingRoutes(app) {
  app.post('/billing/checkout', async (c) => {
    const env = c.env
    const caller = await authenticateCaller(c)
    if (!caller) return c.json({ ok: false, error: 'unauthorized' }, 401)

    const origin = resolveAppOrigin(c)
    if (!origin.ok) return c.json({ ok: false, error: 'bad_origin' }, 400)

    let body
    try {
      body = await c.req.json()
    } catch {
      body = {}
    }
    const plan = typeof body?.plan === 'string' ? body.plan : ''
    if (!VALID_PLANS.has(plan)) {
      return c.json({ ok: false, error: 'invalid_plan' }, 400)
    }

    let ensured
    try {
      ensured = await ensureStripeCustomer(env, caller.email)
    } catch (err) {
      console.error('billing customer:', err)
      return c.json({ ok: false, error: 'stripe' }, 502)
    }
    const { stripeCustomerId, user } = ensured

    // Trailblazer is permanent — no upgrade target, no re-buy.
    if (user.tier === 'trailblazer') {
      return c.json({ ok: false, reason: 'already_trailblazer' }, 403)
    }

    // Existing Osprey re-requesting Osprey → bounce them to the Portal so
    // Stripe handles plan-swap / card-update via its own UI rather than
    // creating a second subscription.
    if (user.tier === 'osprey' && plan.startsWith('osprey_')) {
      try {
        const url = await createPortalSession(
          env,
          stripeCustomerId,
          origin.origin + '/settings',
        )
        return c.json({ url })
      } catch (err) {
        console.error('billing portal (osprey->osprey):', err)
        return c.json({ ok: false, error: 'stripe' }, 502)
      }
    }

    if (plan === 'trailblazer') {
      let reservation
      try {
        reservation = await reserveTrailblazerSlot(env, caller.email)
      } catch (err) {
        console.error('billing reserve:', err)
        return c.json({ ok: false, error: 'reserve_failed' }, 502)
      }
      if (!reservation || reservation.ok === false) {
        if (reservation?.reason === 'sold_out') {
          return c.json({ ok: false, remaining: 0 }, 409)
        }
        return c.json({ ok: false, error: 'reserve_failed' }, 502)
      }
      try {
        const url = await createTrailblazerCheckout(env, {
          customerId: stripeCustomerId,
          email: caller.email,
          number: reservation.number,
          originUrl: origin.origin,
          reservationToken: reservation.reservationToken,
        })
        return c.json({ number: reservation.number, url })
      } catch (err) {
        console.error('billing trailblazer checkout:', err)
        return c.json({ ok: false, error: 'stripe' }, 502)
      }
    }

    // Osprey subscription path.
    const priceId = ospreyPriceId(env, plan)
    if (!priceId) {
      return c.json({ ok: false, error: 'price_not_configured' }, 500)
    }
    try {
      const url = await createOspreyCheckout(env, {
        customerId: stripeCustomerId,
        email: caller.email,
        originUrl: origin.origin,
        priceId,
      })
      return c.json({ url })
    } catch (err) {
      console.error('billing osprey checkout:', err)
      return c.json({ ok: false, error: 'stripe' }, 502)
    }
  })

  app.post('/billing/portal', async (c) => {
    const env = c.env
    const caller = await authenticateCaller(c)
    if (!caller) return c.json({ ok: false, error: 'unauthorized' }, 401)

    const origin = resolveAppOrigin(c)
    if (!origin.ok) return c.json({ ok: false, error: 'bad_origin' }, 400)

    const user = await getUser(env, caller.email)
    if (!user || !user.stripeCustomerId) {
      return c.json({ ok: false, error: 'no_customer' }, 404)
    }
    try {
      const url = await createPortalSession(
        env,
        user.stripeCustomerId,
        origin.origin + '/settings',
      )
      return c.json({ url })
    } catch (err) {
      console.error('billing portal:', err)
      return c.json({ ok: false, error: 'stripe' }, 502)
    }
  })

  app.get('/billing/trailblazer-status', async (c) => {
    const env = c.env
    if (!env.TRAILBLAZER_SLOTS) {
      return c.json({ ok: false, error: 'not_configured' }, 500)
    }
    try {
      const id = env.TRAILBLAZER_SLOTS.idFromName('global')
      const stub = env.TRAILBLAZER_SLOTS.get(id)
      const res = await stub.fetch('https://do.local/status', {
        method: 'GET',
      })
      const text = await res.text()
      const parsed = text.length ? JSON.parse(text) : {}
      c.header('Cache-Control', 'public, max-age=30')
      return c.json({ available: parsed.available, total: parsed.total })
    } catch (err) {
      console.error('trailblazer-status:', err)
      return c.json({ ok: false, error: 'status_failed' }, 502)
    }
  })
}
