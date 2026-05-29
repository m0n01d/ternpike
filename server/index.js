import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { Resend } from 'resend'

import { registerAdminRoutes } from './admin.js'
import { authenticateCaller, getTier } from './auth.js'
import { registerBillingRoutes } from './billing.js'
import { registerBillingWebhookRoute } from './billingWebhook.js'
import { registerGeocodeRoutes } from './geocode.js'
import {
  checkMagicRedemption,
  magicLinkUrl,
  mintMagicToken,
  registerInviteFunnelRoutes,
} from './inviteFunnel.js'
import { verifyJwt } from './jwt.js'
import { freshUser, getEmailBySlug, getUser, migrateLegacy, upsertUser } from './users.js'
import {
  registerNotificationRoutes,
  sendSyncStalledReminders,
  sendWeeklyScanReminders,
} from './notifications.js'
import { registerQrRoutes } from './qr.js'
import { registerScanRoutes } from './scan.js'
import { registerScanDemoRoutes } from './scanDemo.js'
import { registerSharedTripRoutes, runGraceFreezeSweep } from './sharedTrips.js'

// Re-export the Durable Object class so wrangler can find it via the
// `TRAILBLAZER_SLOTS` binding (see wrangler.toml `[[migrations]]`).
export { TrailblazerSlots } from './trailblazerSlots.js'

const CODE_TTL_SECONDS = 600
const CODE_LENGTH = 6

const encoder = new TextEncoder()

const importHmacKey = (secret) =>
  crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )

const bytesToBase64 = (bytes) => {
  let s = ''
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i])
  return btoa(s)
}

const bytesToHex = (bytes) => {
  let s = ''
  for (let i = 0; i < bytes.length; i++) {
    s += bytes[i].toString(16).padStart(2, '0')
  }
  return s
}

const hashCode = async (code, secret) => {
  const key = await importHmacKey(secret)
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(code))
  return bytesToBase64(new Uint8Array(sig))
}

const derivePassword = async (email, secret) => {
  const key = await importHmacKey(secret)
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode('couch:' + email.toLowerCase()),
  )
  return bytesToHex(new Uint8Array(sig)).slice(0, 32)
}

// Referral attribution: parse a `ref` value of the form
// `qr-user-XXXX` (set by ShareModal / marketing cookie capture) and
// resolve it to the referrer's lowercased email via the slug→email
// index in TIERS_KV. Returns null on any failure (missing, malformed,
// slug unknown, self-referral). Never throws — bad refs must not block
// signup.
const REF_PATTERN = /^qr-(user-[a-z0-9]{1,32})$/
async function resolveReferrer(env, signupEmail, ref) {
  if (typeof ref !== 'string') return null
  const m = REF_PATTERN.exec(ref.trim())
  if (!m) return null
  const slug = m[1]
  try {
    const referrer = await getEmailBySlug(env, slug)
    if (!referrer) return null
    if (referrer === signupEmail) return null
    return referrer
  } catch (err) {
    console.error('resolveReferrer:', err)
    return null
  }
}

const constantTimeEqual = (a, b) => {
  let acc = 0
  const len = Math.min(a.length, b.length)
  for (let i = 0; i < len; i++) {
    acc |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return acc === 0 && a.length === b.length
}

const generateCode = () => {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000
  return String(n).padStart(CODE_LENGTH, '0')
}

const sanitizeDb = (email) =>
  'ternpike-' + email.toLowerCase().replace(/[^a-z0-9_$()+/-]/g, '-')

const couchAdmin = (env, path, init = {}) => {
  const adminAuth =
    'Basic ' + btoa(`${env.COUCH_ADMIN_USER}:${env.COUCH_ADMIN_PASS}`)
  return fetch(`${env.COUCH_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: adminAuth,
      ...(init.headers || {}),
    },
  })
}

async function ensureUser(env, email, password) {
  const id = `org.couchdb.user:${email}`
  const url = `/_users/${encodeURIComponent(id)}`
  const cur = await couchAdmin(env, url)
  const rev = cur.ok ? (await cur.json())._rev : null
  const body = {
    _id: id,
    name: email,
    password,
    roles: [],
    type: 'user',
    ...(rev && { _rev: rev }),
  }
  const put = await couchAdmin(env, url, {
    method: 'PUT',
    body: JSON.stringify(body),
  })
  if (!put.ok) throw new Error(`_users PUT ${put.status}`)
}

async function ensureDb(env, dbName, email) {
  const create = await couchAdmin(env, `/${dbName}`, { method: 'PUT' })
  if (!create.ok && create.status !== 412)
    throw new Error(`db PUT ${create.status}`)
  const security = {
    admins: { names: [], roles: [] },
    members: { names: [email], roles: [] },
  }
  const sec = await couchAdmin(env, `/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(security),
  })
  if (!sec.ok) throw new Error(`_security PUT ${sec.status}`)
}

// Shared provisioning path for both `/auth/verify-code` and
// `/auth/verify-magic-link` (#333). Derives the CouchDB password, ensures the
// per-user `_users` doc + DB exist, runs the first-login user-record hook
// (referral attribution included), and returns the EXACT response body shape
// the Elm `Creds` decoder consumes — so both auth paths reuse the same client
// code with zero changes. Returns a plain object; the caller wraps it in
// `c.json(..., 200)`. Throws on a CouchDB failure (caller maps to 500).
async function provisionUser(env, email, ref) {
  const password = await derivePassword(email, env.SERVER_SECRET)
  const dbName = sanitizeDb(email)
  await ensureUser(env, email, password)
  await ensureDb(env, dbName, email)
  // First-login hook: materialize the server-authoritative user record so
  // downstream billing endpoints have something to point at. See the
  // `/auth/verify-code` comment for the full rationale (referral attribution
  // is data-only here — no bonus is granted).
  if (env.TIERS_KV) {
    try {
      const existing = await getUser(env, email)
      if (!existing) {
        const migrated = await migrateLegacy(env, email)
        if (!migrated) {
          const referredBy = await resolveReferrer(env, email.toLowerCase(), ref)
          await upsertUser(env, freshUser(email, { referredBy }))
        }
      }
    } catch (err) {
      console.error('provisionUser upsert:', err)
    }
  }
  const record = await getUser(env, email)
  const tier = record?.tier || (await getTier(env, email))
  const subscriptionStatus = record?.subscriptionStatus ?? null
  const trailblazerNumber = record?.trailblazerNumber ?? null
  return {
    dbName,
    email,
    ok: true,
    password,
    subscriptionStatus,
    tier,
    trailblazerNumber,
  }
}

const app = new Hono()

const STATIC_ORIGINS = new Set([
  'https://app.ternpike.com',
  'https://ternpike.com',
  'http://localhost:5173',
])

const PREVIEW_ORIGIN =
  /^https:\/\/[a-z0-9-]+-ternpike\.dwightdoane\.workers\.dev$/

const LOCAL_DEV_ORIGIN = /^http:\/\/(?:127\.0\.0\.1|localhost):\d+$/

const corsConfig = cors({
  origin: (origin) => {
    if (!origin) return null
    if (STATIC_ORIGINS.has(origin)) return origin
    if (PREVIEW_ORIGIN.test(origin)) return origin
    if (LOCAL_DEV_ORIGIN.test(origin)) return origin
    return null
  },
  allowMethods: ['DELETE', 'GET', 'OPTIONS', 'POST', 'PUT'],
  allowHeaders: ['Authorization', 'Content-Type', 'X-Webhook-Secret'],
  maxAge: 86400,
})

app.use('/auth/*', corsConfig)
app.use('/billing/*', corsConfig)
app.use('/geocode', corsConfig)
// Nest invite funnel (#328). `/auth/*` already covers the magic-link
// endpoints; these two cover the unauthenticated preview + guest-scan surface.
app.use('/invite/*', corsConfig)
app.use('/marketing/*', corsConfig)
app.use('/me', corsConfig)
app.use('/notifications/*', corsConfig)
app.use('/scan', corsConfig)
app.use('/scan-demo', corsConfig)
app.use('/scan-guest', corsConfig)
app.use('/sharedtrips/*', corsConfig)
app.use('/sharedtrips', corsConfig)

// --- billing routes (#17) ---
registerBillingRoutes(app)

// --- billing webhook (#18) ---
// No corsConfig — Stripe is server-to-server; we also need c.req.raw.text()
// to be the exact bytes Stripe signed, so we don't mount any middleware that
// might parse the body first.
registerBillingWebhookRoute(app)

app.post('/auth/request-code', async (c) => {
  const env = c.env
  let body
  try {
    body = await c.req.json()
  } catch {
    body = {}
  }
  const { email } = body || {}
  if (typeof email !== 'string' || !email.includes('@')) {
    return c.json({ ok: false }, 400)
  }
  const code = generateCode()
  const hashB64 = await hashCode(code, env.SERVER_SECRET)
  await env.CODES_KV.put(email.toLowerCase(), hashB64, {
    expirationTtl: CODE_TTL_SECONDS,
  })
  try {
    const resend = new Resend(env.RESEND_API_KEY)
    await resend.emails.send({
      from: 'Ternpike <noreply@ternpike.com>',
      to: email,
      subject: `Your Ternpike code: ${code}`,
      text: `Your code is ${code}. It expires in 10 minutes.\n`,
    })
    return c.json({ ok: true })
  } catch (err) {
    console.error('sendMail:', err)
    return c.json({ ok: false }, 500)
  }
})

app.post('/auth/verify-code', async (c) => {
  const env = c.env
  let body
  try {
    body = await c.req.json()
  } catch {
    body = {}
  }
  const { email, code, ref } = body || {}
  if (typeof email !== 'string' || typeof code !== 'string') {
    return c.json({ ok: false }, 400)
  }
  const key = email.toLowerCase()
  const stored = await env.CODES_KV.get(key)
  if (!stored) return c.json({ ok: false }, 401)
  const incoming = await hashCode(code, env.SERVER_SECRET)
  if (!constantTimeEqual(incoming, stored)) {
    return c.json({ ok: false }, 401)
  }
  await env.CODES_KV.delete(key)

  try {
    // First-login hook + per-user DB provisioning live in `provisionUser`,
    // shared with `/auth/verify-magic-link` so both auth paths return the
    // identical `Creds` response body. Referral attribution (`ref`) is
    // data-only — no bonus is granted here.
    const creds = await provisionUser(env, email, ref)
    return c.json(creds)
  } catch (err) {
    console.error('provision:', err)
    return c.json({ ok: false }, 500)
  }
})

// --- Hardened magic-link endpoints (#333) ---
//
// Passwordless signup for the Nest invite funnel. The magic token is short-
// lived (15m), single-use (jti deny-list in INVITE_KV), and email-confirmed at
// redemption (the forwarding login-CSRF mitigation). See
// docs/nest-invite-funnel.md §A "Magic token" and §C.

// POST /auth/request-magic-link — `{ email, next? }`. ALWAYS returns
// `{ ok: true }` (200) regardless of whether the email exists, so the endpoint
// can't be used to enumerate accounts. Only a malformed/missing email is a 400.
// `next` (typically the opaque share token) rides through to the magic-link
// URL so the share survives the round-trip (docs §D).
app.post('/auth/request-magic-link', async (c) => {
  const env = c.env
  let body
  try {
    body = await c.req.json()
  } catch {
    body = {}
  }
  const { email, next } = body || {}
  if (typeof email !== 'string' || !email.includes('@')) {
    return c.json({ ok: false }, 400)
  }

  const { token } = await mintMagicToken({ env, email })
  const appBaseUrl = env.APP_BASE_URL || 'https://app.ternpike.com'
  const url = magicLinkUrl(appBaseUrl, token, next)

  try {
    // Raw fetch (not the Resend SDK) so the `RESEND_BASE_URL` env binding
    // reaches the call site under workerd (CLAUDE.md "Resend + workerd").
    const resendBase = env.RESEND_BASE_URL || 'https://api.resend.com'
    const res = await fetch(`${resendBase}/emails`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'Ternpike <noreply@ternpike.com>',
        to: email,
        subject: 'Your Ternpike sign-in link',
        text: `Tap to sign in to Ternpike:\n\n${url}\n\nThis link expires in 15 minutes and can be used once.\n`,
      }),
    })
    if (!res.ok) {
      console.error('request-magic-link sendMail:', res.status)
    }
  } catch (err) {
    // Never leak send failures to the caller — enumeration-resistant by design.
    console.error('request-magic-link sendMail:', err)
  }
  // Always 200, regardless of whether the email exists or mail send succeeded.
  return c.json({ ok: true })
})

// POST /auth/verify-magic-link — `{ token, email }`. Verifies the magic token,
// pins `typ:"magic"`, enforces the email-confirm, consumes the single-use jti,
// then provisions IDENTICALLY to `/auth/verify-code` (same response body, so
// the client `Creds` path is reused unchanged). `next` is opaque to the server.
//
// Status contract:
//   400              — missing/empty `token`
//   401 invalid_token — bad signature / malformed / wrong payload typ / consumed
//   403 email_mismatch — `body.email` absent or != `payload.email`
//   410 expired       — token past its `exp`
//   200 { dbName, email, ok, password, subscriptionStatus, tier, trailblazerNumber }
app.post('/auth/verify-magic-link', async (c) => {
  const env = c.env
  let body
  try {
    body = await c.req.json()
  } catch {
    body = {}
  }
  const token = body && typeof body.token === 'string' ? body.token : ''
  if (!token) {
    return c.json({ ok: false, error: 'token_required' }, 400)
  }

  const verified = await verifyJwt(token, env.SERVER_SECRET)
  // checkMagicRedemption maps verify failure → 410/401, pins typ:"magic", and
  // enforces the email-confirm (forwarding login-CSRF mitigation).
  const redemption = checkMagicRedemption(verified, body && body.email)
  if (!redemption.ok) {
    return c.json({ ok: false, error: redemption.error }, redemption.status)
  }

  // Single-use: a consumed jti is a flat 401 (the link was already redeemed).
  const denyKey = redemption.jti ? `revoked:${redemption.jti}` : null
  if (denyKey && env.INVITE_KV) {
    const consumed = await env.INVITE_KV.get(denyKey)
    if (consumed) {
      return c.json({ ok: false, error: 'invalid_token' }, 401)
    }
  }

  try {
    const creds = await provisionUser(env, redemption.email, body && body.ref)
    // Burn the jti AFTER a successful provision so a transient CouchDB error
    // doesn't permanently consume the user's only valid link. TTL = remaining
    // token life, so the deny-list entry expires exactly when the token would.
    if (denyKey && env.INVITE_KV) {
      const nowSec = Math.floor(Date.now() / 1000)
      const ttl = redemption.exp ? redemption.exp - nowSec : null
      const opts = ttl && ttl > 0 ? { expirationTtl: ttl } : undefined
      try {
        await env.INVITE_KV.put(denyKey, '1', opts)
      } catch (err) {
        console.error('verify-magic-link jti consume:', err)
      }
    }
    return c.json(creds)
  } catch (err) {
    console.error('verify-magic-link provision:', err)
    return c.json({ ok: false }, 500)
  }
})

// --- /me (#19) ---
app.get('/me', async (c) => {
  const env = c.env
  const caller = await authenticateCaller(c)
  if (!caller) return c.json({ ok: false }, 401)
  // Materialize on demand for users predating #16 who haven't logged in
  // since. getUser returns null in that case; migrateLegacy folds in the
  // legacy raw-string tier if present, else upsertUser writes a fresh
  // tern record. Either way the next read sees a UserRecord.
  let record = await getUser(env, caller.email)
  if (!record) {
    record = await migrateLegacy(env, caller.email)
  }
  if (!record) {
    record = await upsertUser(env, freshUser(caller.email))
  }
  return c.json({
    email: record.email,
    stripeCustomerId: record.stripeCustomerId,
    subscriptionId: record.subscriptionId,
    subscriptionStatus: record.subscriptionStatus,
    tier: record.tier,
    trailblazerNumber: record.trailblazerNumber,
  })
})

app.post('/marketing/waitlist', async (c) => {
  const env = c.env
  let body
  try {
    body = await c.req.json()
  } catch {
    body = {}
  }
  const { email } = body || {}
  if (typeof email !== 'string' || !email.includes('@')) {
    return c.json({ ok: false }, 400)
  }
  const normalized = email.toLowerCase()
  const resend = new Resend(env.RESEND_WAITLIST_API_KEY)
  const contact = await resend.contacts.create({
    audienceId: env.RESEND_AUDIENCE_ID,
    email: normalized,
    unsubscribed: false,
  })
  if (contact.error) {
    console.error('waitlist contact:', contact.error)
    return c.json({ ok: false, error: contact.error.message }, 500)
  }
  const sent = await resend.emails.send({
    from: 'Ternpike <noreply@ternpike.com>',
    to: normalized,
    subject: "You're on the Ternpike list",
    text:
      "Thanks for signing up. We'll let you know when the managed version is ready to scan and go.\n\n— Ternpike\n",
  })
  if (sent.error) {
    console.error('waitlist confirm:', sent.error)
  }
  return c.json({ ok: true })
})

registerGeocodeRoutes(app)
registerInviteFunnelRoutes(app)
registerNotificationRoutes(app)
registerQrRoutes(app)
registerScanRoutes(app)
registerScanDemoRoutes(app)
registerSharedTripRoutes(app)
registerAdminRoutes(app)

export default {
  fetch: app.fetch,
  // Multiple cron triggers are configured in `wrangler.toml`; Cloudflare
  // multiplexes them into a single `scheduled()` handler. Branch on
  // `event.cron` to dispatch each pattern to its own sweep.
  //   '0 17 * * 5' → Friday 17:00 UTC, push notifications
  //   default     → hourly billing/grace freeze sweep
  async scheduled(event, env, ctx) {
    if (event.cron === '0 17 * * 5') {
      ctx.waitUntil(sendWeeklyScanReminders(env))
    } else {
      ctx.waitUntil(runGraceFreezeSweep(env))
    }
    ctx.waitUntil(sendSyncStalledReminders(env))
  },
}
