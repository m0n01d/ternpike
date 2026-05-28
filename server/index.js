import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { Resend } from 'resend'

import { registerAdminRoutes } from './admin.js'
import { authenticateCaller, getTier } from './auth.js'
import { registerBillingRoutes } from './billing.js'
import { registerBillingWebhookRoute } from './billingWebhook.js'
import { registerGeocodeRoutes } from './geocode.js'
import { freshUser, getUser, migrateLegacy, upsertUser } from './users.js'
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
app.use('/marketing/*', corsConfig)
app.use('/me', corsConfig)
app.use('/notifications/*', corsConfig)
app.use('/scan', corsConfig)
app.use('/scan-demo', corsConfig)
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
  const { email, code } = body || {}
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

  const password = await derivePassword(email, env.SERVER_SECRET)
  const dbName = sanitizeDb(email)
  try {
    await ensureUser(env, email, password)
    await ensureDb(env, dbName, email)
    // First-login hook: materialize the server-authoritative user record
    // so downstream billing endpoints (#17/#18) have something to point at.
    // If a legacy raw-string tier exists, migrate it; otherwise create a
    // fresh `tern` record. The legacy-fallback inside `getTier` keeps
    // existing callers green during the migration window.
    if (env.TIERS_KV) {
      try {
        const existing = await getUser(env, email)
        if (!existing) {
          const migrated = await migrateLegacy(env, email)
          if (!migrated) {
            await upsertUser(env, freshUser(email))
          }
        }
      } catch (err) {
        console.error('verify-code user upsert:', err)
      }
    }
    // Load the full record so the client can render subscription status on
    // the post-login UI without an extra /me round-trip.
    const record = await getUser(env, email)
    const tier = record?.tier || await getTier(env, email)
    const subscriptionStatus = record?.subscriptionStatus ?? null
    const trailblazerNumber = record?.trailblazerNumber ?? null
    return c.json({
      dbName,
      email,
      ok: true,
      password,
      subscriptionStatus,
      tier,
      trailblazerNumber,
    })
  } catch (err) {
    console.error('provision:', err)
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
