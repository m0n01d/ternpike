// Per-device push notification subscription + preference management.
//
// Four endpoints, all paid-only (Osprey + Trailblazer). Tern callers get
// 402 `upgrade-required` so the client can render the upsell. All four
// re-check tier on every request — never trust the client to gate this.
//
// KV schema (in `PUSH_KV`):
//   push:sub:<email>:<sha256hex(endpoint)>  → JSON subscription record
//   push:pref:<email>:<sha256hex(endpoint)> → JSON preference record
//
// Hashing the endpoint keeps keys bounded in length (browser push
// endpoints can be 200+ chars) and avoids storing them verbatim as keys
// while still letting us reconstruct the lookup deterministically from
// the client-supplied endpoint string.
//
// The Friday-17:00-UTC cron dispatcher that iterates these keys lands
// in a follow-up issue (#180); this file owns the read/write surface
// only.

import { buildPushPayload } from '@block65/webcrypto-web-push'

import { authenticateCaller, getTier, isPaidTier } from './auth.js'

const PUSH_PREFIX = 'push:sub:'
const PREF_PREFIX = 'push:pref:'

const DEFAULT_PREFS = { weeklyScanReminder: true }

// SHA-256 of `s`, hex-encoded. Used to bound KV key length when the
// caller-supplied push endpoint is long (Mozilla autopush endpoints
// can be 200+ characters).
export async function sha256Hex(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))
  const bytes = new Uint8Array(buf)
  let hex = ''
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0')
  }
  return hex
}

function keysFor(email, endpointHash) {
  return {
    pref: `${PREF_PREFIX}${email}:${endpointHash}`,
    sub: `${PUSH_PREFIX}${email}:${endpointHash}`,
  }
}

// Authenticate + tier-gate. Returns either `{ caller, tier }` on success
// or `{ error: Response }` where the Response is the appropriate 401/402
// to short-circuit the handler. Re-runs on every request so a tier
// change in TIERS_KV takes effect immediately.
async function requirePaidCaller(c) {
  const caller = await authenticateCaller(c)
  if (!caller) return { error: c.json({ ok: false }, 401) }
  const tier = await getTier(c.env, caller.email)
  if (!isPaidTier(tier)) {
    return { error: c.json({ error: 'upgrade-required', ok: false }, 402) }
  }
  return { caller, tier }
}

async function readJsonBody(c) {
  try {
    return await c.req.json()
  } catch {
    return {}
  }
}

export function registerNotificationRoutes(app) {
  // POST /notifications/subscribe
  //
  // Register (or re-register) a device's push subscription. Body:
  //   { endpoint: string, keys: { auth: string, p256dh: string },
  //     subscriptions?: { weeklyScanReminder: boolean } }
  // The optional `subscriptions` field seeds the per-device prefs
  // record; if omitted, we install the defaults.
  app.post('/notifications/subscribe', async (c) => {
    const guard = await requirePaidCaller(c)
    if (guard.error) return guard.error
    const body = await readJsonBody(c)
    const endpoint = body.endpoint
    const keys = body.keys
    if (
      typeof endpoint !== 'string' ||
      !endpoint ||
      !keys ||
      typeof keys.auth !== 'string' ||
      !keys.auth ||
      typeof keys.p256dh !== 'string' ||
      !keys.p256dh
    ) {
      return c.json({ error: 'malformed', ok: false }, 400)
    }
    const hash = await sha256Hex(endpoint)
    const k = keysFor(guard.caller.email, hash)
    await c.env.PUSH_KV.put(
      k.sub,
      JSON.stringify({
        auth: keys.auth,
        createdAt: new Date().toISOString(),
        endpoint,
        p256dh: keys.p256dh,
        tierAtSubscribe: guard.tier,
      }),
    )
    await c.env.PUSH_KV.put(
      k.pref,
      JSON.stringify(body.subscriptions || DEFAULT_PREFS),
    )
    return c.json({ ok: true })
  })

  // DELETE /notifications/subscribe
  //
  // Drop a device's subscription + prefs. Idempotent — succeeds even
  // when the key isn't present, so the client can clean up after a
  // 410-from-push-service without first checking existence.
  app.delete('/notifications/subscribe', async (c) => {
    const guard = await requirePaidCaller(c)
    if (guard.error) return guard.error
    const body = await readJsonBody(c)
    const endpoint = body.endpoint
    if (typeof endpoint !== 'string' || !endpoint) {
      return c.json({ error: 'malformed', ok: false }, 400)
    }
    const hash = await sha256Hex(endpoint)
    const k = keysFor(guard.caller.email, hash)
    await c.env.PUSH_KV.delete(k.sub)
    await c.env.PUSH_KV.delete(k.pref)
    return c.json({ ok: true })
  })

  // GET /notifications/preferences?endpoint=<url>
  //
  // Read prefs for a single device. Returns the defaults
  // (`{ weeklyScanReminder: true }`) when no prefs record exists so
  // the client doesn't have to special-case "never set".
  app.get('/notifications/preferences', async (c) => {
    const guard = await requirePaidCaller(c)
    if (guard.error) return guard.error
    const endpoint = c.req.query('endpoint')
    if (typeof endpoint !== 'string' || !endpoint) {
      return c.json({ error: 'malformed', ok: false }, 400)
    }
    const hash = await sha256Hex(endpoint)
    const raw = await c.env.PUSH_KV.get(keysFor(guard.caller.email, hash).pref)
    return c.json({
      ok: true,
      prefs: raw ? JSON.parse(raw) : DEFAULT_PREFS,
    })
  })

  // PUT /notifications/preferences
  //
  // Replace prefs for a single device. Body:
  //   { endpoint: string, prefs: { weeklyScanReminder: boolean } }
  // No partial-merge — the client sends the full prefs object.
  app.put('/notifications/preferences', async (c) => {
    const guard = await requirePaidCaller(c)
    if (guard.error) return guard.error
    const body = await readJsonBody(c)
    const endpoint = body.endpoint
    const prefs = body.prefs
    if (
      typeof endpoint !== 'string' ||
      !endpoint ||
      !prefs ||
      typeof prefs !== 'object'
    ) {
      return c.json({ error: 'malformed', ok: false }, 400)
    }
    const hash = await sha256Hex(endpoint)
    await c.env.PUSH_KV.put(
      keysFor(guard.caller.email, hash).pref,
      JSON.stringify(prefs),
    )
    return c.json({ ok: true })
  })
}

// One-off test push for admin verification. Dispatched from
// `POST /admin/test-push` in `server/admin.js`. Sends a push to every
// subscription registered for the given email, ignoring the
// `weeklyScanReminder` pref (this is a test, not a scheduled delivery).
// Still re-checks tier so a Tern caller can't use the admin endpoint as
// a free pass — returns `{ ok: false, reason: 'not-paid', sent: 0 }` for
// non-paid users.
//
// On 404/410 the subscription is stale — delete both KV keys. On other
// non-OK statuses, log and continue (transient push-service failure).
//
// `env.__buildPushPayload` is the same test hook as `sendWeeklyScanReminders`.
export async function sendTestPush(env, email) {
  const tier = await getTier(env, email)
  if (!isPaidTier(tier)) return { ok: false, reason: 'not-paid', sent: 0 }
  const build = env.__buildPushPayload || buildPushPayload
  const vapid = {
    privateKey: env.VAPID_PRIVATE_KEY,
    publicKey: env.VAPID_PUBLIC_KEY,
    subject: env.VAPID_SUBJECT,
  }
  const payload = JSON.stringify({
    body: 'If you see this, push delivery is working.',
    tag: 'admin-test-push',
    title: 'Ternpike test push',
    url: '/settings',
  })
  let cursor
  let sent = 0
  do {
    const page = await env.PUSH_KV.list({ cursor, prefix: `${PUSH_PREFIX}${email}:` })
    for (const k of page.keys) {
      const subRaw = await env.PUSH_KV.get(k.name)
      if (!subRaw) continue
      const stored = JSON.parse(subRaw)
      const subscription = {
        endpoint: stored.endpoint,
        expirationTime: null,
        keys: { auth: stored.auth, p256dh: stored.p256dh },
      }
      const prefKey = k.name.replace(PUSH_PREFIX, PREF_PREFIX)
      try {
        const req = await build(
          { data: payload, options: { ttl: 3600 } },
          subscription,
          vapid,
        )
        const res = await fetch(stored.endpoint, req)
        if (res.ok || res.status === 201) {
          sent++
        } else if (res.status === 404 || res.status === 410) {
          await env.PUSH_KV.delete(k.name)
          await env.PUSH_KV.delete(prefKey)
        } else {
          console.error('test push send failed', { email, status: res.status })
        }
      } catch (err) {
        console.error('test push send threw', { email, err: String(err) })
      }
    }
    cursor = page.list_complete ? undefined : page.cursor
  } while (cursor)
  return { ok: true, sent }
}

// Friday 17:00 UTC cron sweep. Dispatched from `scheduled()` in
// `server/index.js` when `event.cron === '0 17 * * 5'`. Iterates every
// stored subscription, re-checks tier per user (downgrades since
// subscribe are skipped — never trust `tierAtSubscribe`), filters by
// the per-device `weeklyScanReminder` pref, signs a VAPID push with
// `@block65/webcrypto-web-push`, and POSTs to each push-service
// endpoint. The Node `web-push` library uses Node-only crypto APIs
// that don't run in workerd; this library is pure WebCrypto.
//
// On 404/410 the subscription is gone for good (browser uninstalled,
// permission revoked) — delete BOTH `push:sub:` and `push:pref:` for
// that endpoint. On other non-OK statuses, log and continue: the push
// service is transiently unhappy and we'll retry next Friday.
//
// `env.__buildPushPayload` is an opt-in test hook so unit tests can
// short-circuit the crypto path without spinning up VAPID keys. In
// production it's undefined and the real `buildPushPayload` runs.
export async function sendWeeklyScanReminders(env) {
  const vapid = {
    privateKey: env.VAPID_PRIVATE_KEY,
    publicKey: env.VAPID_PUBLIC_KEY,
    subject: env.VAPID_SUBJECT,
  }
  const build = env.__buildPushPayload || buildPushPayload
  const payload = JSON.stringify({
    body: "Capture this week's receipts in Ternpike.",
    tag: 'weekly-scan-reminder',
    title: 'Time to scan receipts',
    url: '/trips',
  })
  let cursor
  do {
    const page = await env.PUSH_KV.list({ cursor, prefix: PUSH_PREFIX })
    for (const k of page.keys) {
      // Slice off the prefix, then read up to the first `:` — emails
      // cannot contain `:` per RFC 5321, so this is unambiguous.
      const email = k.name.slice(PUSH_PREFIX.length).split(':')[0]
      const tier = await getTier(env, email)
      if (!isPaidTier(tier)) continue
      const prefKey = k.name.replace(PUSH_PREFIX, PREF_PREFIX)
      const prefRaw = await env.PUSH_KV.get(prefKey)
      const prefs = prefRaw ? JSON.parse(prefRaw) : DEFAULT_PREFS
      if (!prefs.weeklyScanReminder) continue
      const subRaw = await env.PUSH_KV.get(k.name)
      if (!subRaw) continue
      const stored = JSON.parse(subRaw)
      const subscription = {
        endpoint: stored.endpoint,
        expirationTime: null,
        keys: { auth: stored.auth, p256dh: stored.p256dh },
      }
      try {
        const req = await build(
          { data: payload, options: { ttl: 3600 } },
          subscription,
          vapid,
        )
        const res = await fetch(stored.endpoint, req)
        if (res.status === 404 || res.status === 410) {
          await env.PUSH_KV.delete(k.name)
          await env.PUSH_KV.delete(prefKey)
        } else if (!res.ok) {
          console.error('push send failed', { email, status: res.status })
        }
      } catch (err) {
        console.error('push send threw', { email, err: String(err) })
      }
    }
    cursor = page.list_complete ? undefined : page.cursor
  } while (cursor)
}
