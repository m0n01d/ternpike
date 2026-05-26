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

const DEFAULT_PREFS = {
  sharedTripAccessChange: true,
  sharedTripActivity: true,
  syncStalled: true,
  weeklyScanReminder: true,
}

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

// Dedup prefix constants for stall/auth-expired notifications.
const STALL_DEDUP_PREFIX = 'push:stall-dedup:'
const AUTH_EXPIRED_DEDUP_PREFIX = 'push:authexpired-dedup:'

// Seven days in seconds — TTL for per-user dedup keys so each category fires
// at most once per week.
const DEDUP_TTL_SECONDS = 7 * 24 * 60 * 60

// Three days in milliseconds — a sync gap older than this triggers the stall push.
const STALL_THRESHOLD_MS = 3 * 24 * 60 * 60 * 1000

// Twenty-four hours in milliseconds — auth-failed state older than this triggers
// the auth-expired push.
const AUTH_EXPIRED_THRESHOLD_MS = 24 * 60 * 60 * 1000

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
//
// Also dispatches stall and auth-expired checks via
// `sendSyncStalledReminders` — see that function for details.
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

// Helper shared by sendSyncStalledReminders. Sends `payload` to every
// subscription belonging to `email` that has `prefKey` set to true, skipping
// if the user is not paid or if `dedupKvKey` already exists in `env.PUSH_KV`
// (meaning we fired this category within the last 7 days).
//
// On a successful send, writes `dedupKvKey` with a 7-day TTL so the next
// sweep run skips this user for this category.
//
// Returns `true` if at least one push was sent, `false` otherwise.
async function sendCategoryPush(env, email, { dedupKvKey, payload, prefKey }) {
  const tier = await getTier(env, email)
  if (!isPaidTier(tier)) return false

  const alreadySent = await env.PUSH_KV.get(dedupKvKey)
  if (alreadySent) return false

  const build = env.__buildPushPayload || buildPushPayload
  const vapid = {
    privateKey: env.VAPID_PRIVATE_KEY,
    publicKey: env.VAPID_PUBLIC_KEY,
    subject: env.VAPID_SUBJECT,
  }

  let sentAny = false
  let cursor
  do {
    const page = await env.PUSH_KV.list({
      cursor,
      prefix: `${PUSH_PREFIX}${email}:`,
    })
    for (const k of page.keys) {
      const subRaw = await env.PUSH_KV.get(k.name)
      if (!subRaw) continue
      const stored = JSON.parse(subRaw)
      const pref = k.name.replace(PUSH_PREFIX, PREF_PREFIX)
      const prefRaw = await env.PUSH_KV.get(pref)
      const prefs = prefRaw ? JSON.parse(prefRaw) : DEFAULT_PREFS
      if (!prefs[prefKey]) continue
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
        if (res.ok || res.status === 201) {
          sentAny = true
        } else if (res.status === 404 || res.status === 410) {
          await env.PUSH_KV.delete(k.name)
          await env.PUSH_KV.delete(pref)
        } else {
          console.error('category push send failed', {
            category: prefKey,
            email,
            status: res.status,
          })
        }
      } catch (err) {
        console.error('category push send threw', {
          category: prefKey,
          email,
          err: String(err),
        })
      }
    }
    cursor = page.list_complete ? undefined : page.cursor
  } while (cursor)

  if (sentAny) {
    await env.PUSH_KV.put(dedupKvKey, '1', {
      expirationTtl: DEDUP_TTL_SECONDS,
    })
  }
  return sentAny
}

// Hourly (or Friday) cron sweep for sync-stall and auth-expired conditions.
//
// Per-user checks:
//   - Stall: if `sync:lastsync:<email>` in PUSH_KV is older than 3 days,
//     and `syncStalled` pref is enabled, and no dedup key exists, fire a
//     stall push. Tap → /settings.
//   - Auth-expired: if `auth:failed:<email>` in PUSH_KV was written more
//     than 24h ago, fire an auth-expired push. Tap → /login.
//
// Both checks skip non-paid users and use 7-day KV dedup keys
// (`push:stall-dedup:<email>` and `push:authexpired-dedup:<email>`) so each
// category fires at most once per week per user.
//
// Reset: call `resetSyncStalledDedup(env, email)` when a successful sync or
// sign-in occurs, so the next stall fires fresh after a real new gap.
export async function sendSyncStalledReminders(env, nowMs = Date.now()) {
  const seenEmails = new Set()
  let cursor
  do {
    const page = await env.PUSH_KV.list({ cursor, prefix: PUSH_PREFIX })
    for (const k of page.keys) {
      const email = k.name.slice(PUSH_PREFIX.length).split(':')[0]
      if (seenEmails.has(email)) continue
      seenEmails.add(email)

      // Stall check.
      const lastSyncRaw = await env.PUSH_KV.get(`sync:lastsync:${email}`)
      if (lastSyncRaw) {
        const lastSyncMs = Number(lastSyncRaw)
        const gapMs = nowMs - lastSyncMs
        if (gapMs > STALL_THRESHOLD_MS) {
          const days = Math.floor(gapMs / (24 * 60 * 60 * 1000))
          const stallPayload = JSON.stringify({
            body: 'Open Ternpike on a connected device.',
            tag: 'sync-stall',
            title: `Your Ternpike data hasn't backed up in ${days} day${days === 1 ? '' : 's'}`,
            url: '/settings',
          })
          await sendCategoryPush(env, email, {
            dedupKvKey: `${STALL_DEDUP_PREFIX}${email}`,
            payload: stallPayload,
            prefKey: 'syncStalled',
          })
        }
      }

      // Auth-expired check.
      const authFailedRaw = await env.PUSH_KV.get(`auth:failed:${email}`)
      if (authFailedRaw) {
        const authFailedMs = Number(authFailedRaw)
        if (nowMs - authFailedMs > AUTH_EXPIRED_THRESHOLD_MS) {
          const authExpiredPayload = JSON.stringify({
            body: 'Sign in to keep your data backed up.',
            tag: 'auth-expired',
            title: 'Your Ternpike session expired',
            url: '/login',
          })
          await sendCategoryPush(env, email, {
            dedupKvKey: `${AUTH_EXPIRED_DEDUP_PREFIX}${email}`,
            payload: authExpiredPayload,
            prefKey: 'syncStalled',
          })
        }
      }
    }
    cursor = page.list_complete ? undefined : page.cursor
  } while (cursor)
}

// KV prefix for shared-trip-activity coalescing windows.
const ACTIVITY_COALESCE_PREFIX = 'push:activity:'

// Rolling-window TTL in seconds — 60 s from the last write.
const ACTIVITY_COALESCE_TTL_SECONDS = 60

// Mirror of `Data.UserId.handle` — returns the `@`-prefixed local-part
// of the email string. Used for notification copy rendered server-side.
function emailHandle(email) {
  const at = email.indexOf('@')
  if (at <= 0) return '@unknown'
  return '@' + email.slice(0, at)
}

// Send a push notification to all co-travelers of a shared trip when an
// expense is added, edited, or voided. Called from the server-side
// expense-notification endpoint in `sharedTrips.js`.
//
// Fan-out:
//   1. For each member of `allMembers`, skip `authorEmail`.
//   2. Look up every `push:sub:<email>:*` for that member.
//   3. Check `push:pref:*` for `sharedTripActivity === true`.
//   4. Coalesce rapid bursts: if the same (authorEmail, tripId,
//      recipientEmail) tuple has had >2 events within the rolling
//      60-second window, send a coalesced "N expenses" message instead.
//   5. 404/410 → delete both KV keys (stale subscription).
//
// `env.__buildPushPayload` is the test hook short-circuiting VAPID crypto.
export async function sendSharedTripActivityPush(
  env,
  {
    action,        // 'add' | 'edit' | 'void'
    allMembers,    // string[] — full member list from sharedtrip:meta
    amount,        // number — raw amount in dollars, for body copy
    authorEmail,   // string — who performed the action (excluded from fan-out)
    note,          // string | null — note field for 'add' body
    tripId,        // string — sharedTripId (for the deep-link and coalescing key)
    tripName,      // string — for notification title
  },
) {
  if (!env.PUSH_KV) return
  const build = env.__buildPushPayload || buildPushPayload
  const vapid = {
    privateKey: env.VAPID_PRIVATE_KEY,
    publicKey: env.VAPID_PUBLIC_KEY,
    subject: env.VAPID_SUBJECT,
  }
  const authorHandle = emailHandle(authorEmail)
  const tapUrl = `/trip/ledger?tripId=${encodeURIComponent('trip::' + tripId)}`

  for (const member of allMembers) {
    if (member.toLowerCase() === authorEmail.toLowerCase()) continue

    // Coalescing: read the rolling window for this (author, trip, recipient) tuple.
    const coalesceKey = `${ACTIVITY_COALESCE_PREFIX}${authorEmail}:${tripId}:${member}`
    const coalesceRaw = await env.PUSH_KV.get(coalesceKey)
    let count = coalesceRaw ? Number(coalesceRaw) : 0
    count += 1
    await env.PUSH_KV.put(coalesceKey, String(count), {
      expirationTtl: ACTIVITY_COALESCE_TTL_SECONDS,
    })

    // Build the notification payload — coalesced on 3rd+ event.
    let payloadJson
    if (count >= 3) {
      payloadJson = JSON.stringify({
        body: `${authorHandle} added ${count} expenses to ${tripName}`,
        data: { url: tapUrl },
        tag: `shared-trip-activity:${tripId}:${authorEmail}`,
        title: tripName,
      })
    } else {
      let body
      if (action === 'add') {
        const noteClip = note && note.trim()
          ? ' — ' + note.trim().slice(0, 40)
          : ''
        body = `${authorHandle} added $${amount.toFixed(2)} to ${tripName}${noteClip}`
      } else if (action === 'edit') {
        body = `${authorHandle} edited an expense on ${tripName}`
      } else {
        body = `${authorHandle} voided a $${amount.toFixed(2)} expense on ${tripName}`
      }
      payloadJson = JSON.stringify({
        body,
        data: { url: tapUrl },
        tag: `shared-trip-activity:${tripId}:${authorEmail}`,
        title: tripName,
      })
    }

    // Fan out to every device registered for this member.
    let cursor
    do {
      const page = await env.PUSH_KV.list({
        cursor,
        prefix: `${PUSH_PREFIX}${member.toLowerCase()}:`,
      })
      for (const k of page.keys) {
        const subRaw = await env.PUSH_KV.get(k.name)
        if (!subRaw) continue
        const stored = JSON.parse(subRaw)
        const prefKey = k.name.replace(PUSH_PREFIX, PREF_PREFIX)
        const prefRaw = await env.PUSH_KV.get(prefKey)
        const prefs = prefRaw ? JSON.parse(prefRaw) : DEFAULT_PREFS
        if (!prefs.sharedTripActivity) continue

        const subscription = {
          endpoint: stored.endpoint,
          expirationTime: null,
          keys: { auth: stored.auth, p256dh: stored.p256dh },
        }
        try {
          const req = await build(
            { data: payloadJson, options: { ttl: 3600 } },
            subscription,
            vapid,
          )
          const res = await fetch(stored.endpoint, req)
          if (res.status === 404 || res.status === 410) {
            await env.PUSH_KV.delete(k.name)
            await env.PUSH_KV.delete(prefKey)
          } else if (!res.ok) {
            console.error('shared-trip activity push failed', {
              action,
              member,
              status: res.status,
            })
          }
        } catch (err) {
          console.error('shared-trip activity push threw', {
            action,
            member,
            err: String(err),
          })
        }
      }
      cursor = page.list_complete ? undefined : page.cursor
    } while (cursor)
  }
}

// Record that a user's sync was successful at `nowMs` (defaults to now).
// Clears any existing stall dedup key so the next real gap fires fresh.
// Call from the auth verify-code success path and from any endpoint that
// confirms a healthy sync.
export async function recordSuccessfulSync(env, email, nowMs = Date.now()) {
  await env.PUSH_KV.put(`sync:lastsync:${email.toLowerCase()}`, String(nowMs))
  await env.PUSH_KV.delete(`${STALL_DEDUP_PREFIX}${email.toLowerCase()}`)
}

// Record that an auth failure occurred for `email`. The timestamp is written
// once (if no prior failure is tracked); subsequent failures within the same
// 7-day window don't overwrite it, so the "first failure" time is preserved.
// Call from any endpoint that receives a CouchDB 401/403 for the user.
export async function recordAuthFailure(env, email, nowMs = Date.now()) {
  const key = `auth:failed:${email.toLowerCase()}`
  const existing = await env.PUSH_KV.get(key)
  if (!existing) {
    await env.PUSH_KV.put(key, String(nowMs), {
      expirationTtl: DEDUP_TTL_SECONDS,
    })
  }
}

// Clear the auth-failure record on a successful sign-in. Also clears the
// auth-expired dedup key so the next real expiry fires fresh.
export async function clearAuthFailure(env, email) {
  const lower = email.toLowerCase()
  await env.PUSH_KV.delete(`auth:failed:${lower}`)
  await env.PUSH_KV.delete(`${AUTH_EXPIRED_DEDUP_PREFIX}${lower}`)
}

// Send a push notification to a single user when their shared-trip access
// changes: either they were removed from a trip, or they became the new
// billing owner via a transfer.
//
// `kind` is either `'removed'` or `'transfer'`. For `'transfer'`, supply
// `prevOwnerEmail` — the previous owner's email — so the body can render
// their `@handle`. For `'removed'` and `'transfer'` the tap URL is
// `/settings` (the SharedTrips section there will reflect the new state).
//
// No dedup — removal and transfer are one-shot events. If alice removes bob,
// re-adds him, and removes him again, all three events are real.
//
// Fan-out to every device registered for `recipientEmail`; checks
// `sharedTripAccessChange` pref per device. 404/410 → KV cleanup.
//
// `env.__buildPushPayload` is the same test hook used by the other push fns.
export async function sendSharedTripAccessChangePush(
  env,
  { kind, prevOwnerEmail, recipientEmail, tripName },
) {
  if (!env.PUSH_KV) return
  const build = env.__buildPushPayload || buildPushPayload
  const vapid = {
    privateKey: env.VAPID_PRIVATE_KEY,
    publicKey: env.VAPID_PUBLIC_KEY,
    subject: env.VAPID_SUBJECT,
  }

  let payloadJson
  if (kind === 'removed') {
    payloadJson = JSON.stringify({
      body: 'Your local copy is read-only',
      data: { url: '/settings' },
      tag: `shared-trip-access-change:${recipientEmail}`,
      title: `You were removed from ${tripName}`,
    })
  } else {
    // kind === 'transfer'
    const prevHandle = emailHandle(prevOwnerEmail)
    payloadJson = JSON.stringify({
      body: `${prevHandle} made you the billing owner of ${tripName}`,
      data: { url: '/settings' },
      tag: `shared-trip-access-change:${recipientEmail}`,
      title: tripName,
    })
  }

  const lower = recipientEmail.toLowerCase()
  let cursor
  do {
    const page = await env.PUSH_KV.list({
      cursor,
      prefix: `${PUSH_PREFIX}${lower}:`,
    })
    for (const k of page.keys) {
      const subRaw = await env.PUSH_KV.get(k.name)
      if (!subRaw) continue
      const stored = JSON.parse(subRaw)
      const prefKey = k.name.replace(PUSH_PREFIX, PREF_PREFIX)
      const prefRaw = await env.PUSH_KV.get(prefKey)
      const prefs = prefRaw ? JSON.parse(prefRaw) : DEFAULT_PREFS
      if (!prefs.sharedTripAccessChange) continue

      const subscription = {
        endpoint: stored.endpoint,
        expirationTime: null,
        keys: { auth: stored.auth, p256dh: stored.p256dh },
      }
      try {
        const req = await build(
          { data: payloadJson, options: { ttl: 3600 } },
          subscription,
          vapid,
        )
        const res = await fetch(stored.endpoint, req)
        if (res.status === 404 || res.status === 410) {
          await env.PUSH_KV.delete(k.name)
          await env.PUSH_KV.delete(prefKey)
        } else if (!res.ok) {
          console.error('access-change push send failed', {
            kind,
            recipientEmail,
            status: res.status,
          })
        }
      } catch (err) {
        console.error('access-change push send threw', {
          kind,
          recipientEmail,
          err: String(err),
        })
      }
    }
    cursor = page.list_complete ? undefined : page.cursor
  } while (cursor)
}
