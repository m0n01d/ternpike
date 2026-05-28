// POST /stripe/webhook — Stripe webhook receiver. This is the **source of
// truth** for "did the payment land": Checkout returning a success URL is
// UX-only; we don't flip `tier` until Stripe signs us a webhook event.
//
// Three jobs, in order:
//
//   1. Verify the Stripe-Signature header (HMAC-SHA256 of `${t}.${rawBody}`
//      against `STRIPE_WEBHOOK_SECRET`, constant-time compared to `v1`).
//      Reject replays > 5 minutes old. Per
//      https://docs.stripe.com/webhooks/signatures.
//
//   2. Idempotently store the `event.id` in `CODES_KV` for 7 days so retries
//      of the same event (Stripe retries any non-2xx forever) don't re-apply
//      the same mutation. We piggy-back on `CODES_KV` rather than provision a
//      `STRIPE_KV` — it has the right TTL semantics and is already in the
//      secrets list.
//
//   3. Route the event to the right `upsertUser` mutation. Subscription
//      events flip `tier` between `osprey` and `tern` based on
//      `subscriptionStatus`; the one-time Trailblazer event confirms a slot
//      in the `TRAILBLAZER_SLOTS` Durable Object before writing the user
//      record. Trailblazer wins — every handler short-circuits if the on-disk
//      user is already a Trailblazer; defense-in-depth on top of
//      `upsertUser`'s downgrade refusal.
//
// Identity convention: `event.data.object.client_reference_id` (set by
// `billing.js` when creating the Checkout session) is the lowercased email.
// Customer-ID → email lookup for subsequent subscription events comes from
// a `stripe:customer:<id>` index also stored in `CODES_KV`, written here on
// `checkout.session.completed`.
//
// Return semantics:
//   - 400 only for signature / parse failures (Stripe will retry, but that
//     means our secret is wrong or the payload is corrupted — failing loud is
//     the right move).
//   - 200 for everything else, including handler errors and unknown event
//     types. Stripe retries on non-2xx, and there's nothing a retry will fix
//     for an event we don't subscribe to.

import { constantTimeEqual } from './auth.js'
import { getUser, upsertUser } from './users.js'

const STRIPE_TIMESTAMP_TOLERANCE_SECONDS = 5 * 60
const EVENT_TTL_SECONDS = 7 * 24 * 3600
const CUSTOMER_INDEX_TTL_SECONDS = 365 * 24 * 3600

const SUBSCRIPTION_PAID_STATUSES = new Set(['active', 'trialing'])

const encoder = new TextEncoder()

const importHmacKey = (secret) =>
  crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )

const bytesToHex = (bytes) => {
  let s = ''
  for (let i = 0; i < bytes.length; i++) {
    s += bytes[i].toString(16).padStart(2, '0')
  }
  return s
}

// Parse the `Stripe-Signature` header into `{ t, v1Sigs }`. Multiple `v1`
// values can appear (during secret rotation) — we collect them all and accept
// the request if any one matches.
function parseStripeSignatureHeader(header) {
  if (typeof header !== 'string' || header.length === 0) return null
  const parts = header.split(',')
  let t = null
  const v1Sigs = []
  for (const part of parts) {
    const eq = part.indexOf('=')
    if (eq === -1) continue
    const key = part.slice(0, eq).trim()
    const value = part.slice(eq + 1).trim()
    if (!key || !value) continue
    if (key === 't') t = value
    else if (key === 'v1') v1Sigs.push(value)
  }
  if (!t || v1Sigs.length === 0) return null
  if (!/^\d+$/.test(t)) return null
  return { t, v1Sigs }
}

async function computeSignature(secret, signedPayload) {
  const key = await importHmacKey(secret)
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode(signedPayload),
  )
  return bytesToHex(new Uint8Array(sig))
}

// Verify the Stripe-Signature header against the raw body. Returns `true`
// on success, `false` on any failure (missing/malformed header, no secret,
// signature mismatch, replay window exceeded).
async function verifyStripeSignature(env, header, rawBody, nowSeconds) {
  if (!env.STRIPE_WEBHOOK_SECRET) return false
  const parsed = parseStripeSignatureHeader(header)
  if (!parsed) return false
  const ts = Number(parsed.t)
  if (!Number.isFinite(ts)) return false
  if (Math.abs(nowSeconds - ts) > STRIPE_TIMESTAMP_TOLERANCE_SECONDS) {
    return false
  }
  const signedPayload = `${parsed.t}.${rawBody}`
  const expected = await computeSignature(
    env.STRIPE_WEBHOOK_SECRET,
    signedPayload,
  )
  // Iterate every v1 the header carried so we don't short-circuit on the
  // first mismatch. Each compare itself is constant-time.
  let matched = false
  for (const candidate of parsed.v1Sigs) {
    if (constantTimeEqual(candidate, expected)) matched = true
  }
  return matched
}

const eventKvKey = (eventId) => 'stripe:event:' + eventId
const customerKvKey = (customerId) => 'stripe:customer:' + customerId

async function alreadyProcessed(env, eventId) {
  if (!env.CODES_KV) return false
  const existing = await env.CODES_KV.get(eventKvKey(eventId))
  return existing !== null
}

async function markProcessed(env, eventId) {
  if (!env.CODES_KV) return
  await env.CODES_KV.put(eventKvKey(eventId), '1', {
    expirationTtl: EVENT_TTL_SECONDS,
  })
}

async function rememberCustomer(env, customerId, email) {
  if (!env.CODES_KV || !customerId || !email) return
  await env.CODES_KV.put(customerKvKey(customerId), email.toLowerCase(), {
    expirationTtl: CUSTOMER_INDEX_TTL_SECONDS,
  })
}

async function getEmailForCustomer(env, customerId) {
  if (!env.CODES_KV || !customerId) return null
  return env.CODES_KV.get(customerKvKey(customerId))
}

// Map a Stripe subscription `status` to the user-facing tier. Anything other
// than `active`/`trialing` collapses to `tern` — `canceled`, `past_due`,
// `incomplete`, `unpaid`, `incomplete_expired`, `paused`.
function tierForSubscriptionStatus(status) {
  return SUBSCRIPTION_PAID_STATUSES.has(status) ? 'osprey' : 'tern'
}

// Subset of Stripe subscription statuses that `upsertUser` accepts. Stripe
// emits more (`incomplete`, `unpaid`, `incomplete_expired`, `paused`), but
// `users.js` only validates the four we care to round-trip; map the rest to
// `canceled` for storage purposes since the corresponding `tier` is `tern`
// either way.
const SUBSCRIPTION_STATUS_PERSIST = new Set([
  'active',
  'canceled',
  'past_due',
  'trialing',
])

function persistableSubscriptionStatus(status) {
  if (typeof status !== 'string') return 'canceled'
  if (SUBSCRIPTION_STATUS_PERSIST.has(status)) return status
  return 'canceled'
}

// Confirm a Trailblazer reservation against the DO. Returns one of:
//   { ok: true, number }   slot permanently claimed
//   { ok: false, expired } reservation was expired (DO returned 410)
//   { ok: false }          other failure (network, malformed response, etc.)
async function confirmTrailblazerSlot(env, email, reservationToken) {
  if (!env.TRAILBLAZER_SLOTS) return { ok: false }
  const stub = env.TRAILBLAZER_SLOTS.idFromName('global')
  const res = await stub.fetch('https://do.local/confirm', {
    body: JSON.stringify({ email, reservationToken }),
    headers: { 'Content-Type': 'application/json' },
    method: 'POST',
  })
  if (res.status === 410) return { expired: true, ok: false }
  if (!res.ok) return { ok: false }
  let body = null
  try {
    const text = await res.text()
    body = text.length ? JSON.parse(text) : null
  } catch {
    body = null
  }
  if (!body || body.ok !== true || typeof body.number !== 'number') {
    return { ok: false }
  }
  return { number: body.number, ok: true }
}

async function handleCheckoutSessionCompleted(env, event) {
  const obj = event?.data?.object || {}
  const rawEmail = obj.client_reference_id
  if (typeof rawEmail !== 'string' || !rawEmail.includes('@')) {
    console.error('webhook checkout.session.completed: missing email')
    return
  }
  const email = rawEmail.toLowerCase()
  const customerId =
    typeof obj.customer === 'string' && obj.customer.length > 0
      ? obj.customer
      : null

  if (obj.mode === 'subscription') {
    const user = await getUser(env, email)
    if (user?.tier === 'trailblazer') {
      console.log('webhook: ignoring subscription checkout for trailblazer', email)
      if (customerId) await rememberCustomer(env, customerId, email)
      return
    }
    const subscriptionId =
      typeof obj.subscription === 'string' ? obj.subscription : null
    await upsertUser(env, {
      ...(user || { email }),
      email,
      stripeCustomerId: customerId,
      subscriptionId,
      subscriptionStatus: 'active',
      tier: 'osprey',
    })
    if (customerId) await rememberCustomer(env, customerId, email)
    return
  }

  if (obj.mode === 'payment') {
    const metadata = obj.metadata || {}
    const trailblazerNumberStr =
      typeof metadata.trailblazerNumber === 'string'
        ? metadata.trailblazerNumber
        : null
    if (!trailblazerNumberStr) {
      console.error('webhook payment mode without trailblazerNumber metadata')
      return
    }
    const reservationToken =
      typeof metadata.reservationToken === 'string'
        ? metadata.reservationToken
        : null
    if (!reservationToken) {
      console.error('webhook trailblazer payment without reservationToken')
      return
    }
    const user = await getUser(env, email)
    if (user?.tier === 'trailblazer') {
      console.log('webhook: trailblazer event for already-trailblazer', email)
      if (customerId) await rememberCustomer(env, customerId, email)
      return
    }
    const confirm = await confirmTrailblazerSlot(env, email, reservationToken)
    if (!confirm.ok) {
      if (confirm.expired) {
        console.error('webhook trailblazer reservation expired', email)
      } else {
        console.error('webhook trailblazer confirm failed', email)
      }
      return
    }
    const number = Number.parseInt(trailblazerNumberStr, 10)
    await upsertUser(env, {
      ...(user || { email }),
      email,
      stripeCustomerId: customerId,
      subscriptionId: null,
      subscriptionStatus: null,
      tier: 'trailblazer',
      trailblazerNumber: Number.isFinite(number) ? number : confirm.number,
      trailblazerPurchasedAt: new Date().toISOString(),
    })
    if (customerId) await rememberCustomer(env, customerId, email)
    return
  }
}

async function handleSubscriptionUpdated(env, event) {
  const obj = event?.data?.object || {}
  const customerId = typeof obj.customer === 'string' ? obj.customer : null
  if (!customerId) {
    console.error('webhook subscription.updated: missing customer')
    return
  }
  const email = await getEmailForCustomer(env, customerId)
  if (!email) {
    console.error('webhook subscription.updated: unknown customer', customerId)
    return
  }
  const user = await getUser(env, email)
  if (user?.tier === 'trailblazer') {
    console.log('webhook: ignoring subscription.updated for trailblazer', email)
    return
  }
  const status = typeof obj.status === 'string' ? obj.status : 'canceled'
  const subscriptionId =
    typeof obj.id === 'string' ? obj.id : user?.subscriptionId || null
  await upsertUser(env, {
    ...(user || { email }),
    email,
    stripeCustomerId: customerId,
    subscriptionId,
    subscriptionStatus: persistableSubscriptionStatus(status),
    tier: tierForSubscriptionStatus(status),
  })
}

async function handleSubscriptionDeleted(env, event) {
  const obj = event?.data?.object || {}
  const customerId = typeof obj.customer === 'string' ? obj.customer : null
  if (!customerId) {
    console.error('webhook subscription.deleted: missing customer')
    return
  }
  const email = await getEmailForCustomer(env, customerId)
  if (!email) {
    console.error('webhook subscription.deleted: unknown customer', customerId)
    return
  }
  const user = await getUser(env, email)
  if (user?.tier === 'trailblazer') {
    console.log('webhook: ignoring subscription.deleted for trailblazer', email)
    return
  }
  await upsertUser(env, {
    ...(user || { email }),
    email,
    stripeCustomerId: customerId,
    subscriptionId: null,
    subscriptionStatus: 'canceled',
    tier: 'tern',
  })
}

async function handleInvoicePaymentFailed(env, event) {
  const obj = event?.data?.object || {}
  const customerId = typeof obj.customer === 'string' ? obj.customer : null
  if (!customerId) {
    console.error('webhook invoice.payment_failed: missing customer')
    return
  }
  const email = await getEmailForCustomer(env, customerId)
  if (!email) {
    console.error('webhook invoice.payment_failed: unknown customer', customerId)
    return
  }
  const user = await getUser(env, email)
  if (user?.tier === 'trailblazer') {
    console.log('webhook: ignoring invoice.payment_failed for trailblazer', email)
    return
  }
  await upsertUser(env, {
    ...(user || { email }),
    email,
    stripeCustomerId: customerId,
    // Hold tier='osprey' through the Stripe-driven grace period. The next
    // customer.subscription.updated (status=canceled) will downgrade us
    // when Stripe stops retrying.
    subscriptionId: user?.subscriptionId || null,
    subscriptionStatus: 'past_due',
    // Hold osprey through the grace period — the next subscription.updated
    // (status=canceled) downgrades us once Stripe gives up retrying.
    tier: 'osprey',
  })
}

async function routeEvent(env, event) {
  switch (event?.type) {
    case 'checkout.session.completed':
      await handleCheckoutSessionCompleted(env, event)
      return
    case 'customer.subscription.updated':
      await handleSubscriptionUpdated(env, event)
      return
    case 'customer.subscription.deleted':
      await handleSubscriptionDeleted(env, event)
      return
    case 'invoice.payment_failed':
      await handleInvoicePaymentFailed(env, event)
      return
    default:
      // Unsubscribed event — Stripe will keep retrying on non-2xx, so we
      // ack with 200 and move on.
      return
  }
}

export function registerBillingWebhookRoute(app) {
  app.post('/stripe/webhook', async (c) => {
    const env = c.env
    const rawBody = await c.req.raw.text()
    const sigHeader =
      c.req.header('stripe-signature') || c.req.header('Stripe-Signature')
    const verified = await verifyStripeSignature(
      env,
      sigHeader,
      rawBody,
      Math.floor(Date.now() / 1000),
    )
    if (!verified) {
      return c.json({ ok: false, error: 'invalid_signature' }, 400)
    }

    let event
    try {
      event = JSON.parse(rawBody)
    } catch {
      return c.json({ ok: false, error: 'invalid_json' }, 400)
    }
    if (typeof event?.id !== 'string' || event.id.length === 0) {
      return c.json({ ok: false, error: 'invalid_event' }, 400)
    }

    if (await alreadyProcessed(env, event.id)) {
      return c.json({ ok: true, replay: true })
    }

    try {
      await routeEvent(env, event)
    } catch (err) {
      console.error('webhook handler:', err)
      // Don't 5xx — Stripe would retry forever for what's almost always a
      // bug on our side. We still mark the event processed so the retry
      // doesn't redo the half-applied work; debug logs above tell us what
      // happened.
    }

    await markProcessed(env, event.id)
    return c.json({ ok: true })
  })
}
