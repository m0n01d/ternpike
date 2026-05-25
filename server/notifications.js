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
