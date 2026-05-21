// Flock provisioning, membership, and billing-grace machinery.
//
// Scheduled freeze choice: Cloudflare Worker Cron Trigger (hourly), not
// Durable Object alarms. DOs require migrations + per-flock object
// instantiation; a single cron handler that scans flocks in `grace` and
// freezes any whose `billingLapsedAt + 14d <= now` is the smaller change and
// scales fine at our user volume. See `scheduled()` at the bottom.

import { Resend } from 'resend'

import {
  FLOCK_DESIGN_DOC_ID,
  buildFlockDesignDoc,
} from './couch/flockValidator.js'
import { signJwt, verifyJwt } from './jwt.js'

const encoder = new TextEncoder()
const GRACE_PERIOD_MS = 14 * 24 * 60 * 60 * 1000
const INVITE_EXPIRY_SECONDS = 7 * 24 * 60 * 60
const APP_JOIN_URL = 'https://app.ternpike.com/flocks/join'

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

const constantTimeEqual = (a, b) => {
  let acc = 0
  const len = Math.min(a.length, b.length)
  for (let i = 0; i < len; i++) acc |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return acc === 0 && a.length === b.length
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

const randomFlockId = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(6))
  return bytesToHex(bytes)
}

const flockDbName = (flockId) => `flock-${flockId}`

const personalDbName = (email) =>
  'ternpike-' + email.toLowerCase().replace(/[^a-z0-9_$()+/-]/g, '-')

const nowIso = () => new Date().toISOString()

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

async function authenticateCaller(c) {
  try {
    const header =
      c.req.header('authorization') || c.req.header('Authorization')
    if (!header || !header.startsWith('Basic ')) return null
    if (!c.env.SERVER_SECRET) return null
    let decoded
    try {
      decoded = atob(header.slice(6))
    } catch {
      return null
    }
    const sep = decoded.indexOf(':')
    if (sep === -1) return null
    const email = decoded.slice(0, sep).toLowerCase()
    const password = decoded.slice(sep + 1)
    if (!email.includes('@') || !password) return null
    const expected = await derivePassword(email, c.env.SERVER_SECRET)
    if (!constantTimeEqual(password, expected)) return null
    return { email }
  } catch (err) {
    console.error('authenticateCaller:', err)
    return null
  }
}

async function getTier(env, email) {
  if (!env.TIERS_KV) return 'fledgling'
  const v = await env.TIERS_KV.get(email.toLowerCase())
  if (v === 'fly' || v === 'trailblazer') return v
  return 'fledgling'
}

async function setTier(env, email, tier) {
  if (!env.TIERS_KV) throw new Error('TIERS_KV not bound')
  await env.TIERS_KV.put(email.toLowerCase(), tier)
}

const isPaidTier = (tier) => tier === 'fly' || tier === 'trailblazer'

async function couchGetJson(env, path) {
  const r = await couchAdmin(env, path)
  if (!r.ok) {
    const text = await r.text()
    const err = new Error(`couch GET ${path} ${r.status}: ${text}`)
    err.status = r.status
    throw err
  }
  return r.json()
}

async function couchPutJson(env, path, body) {
  const r = await couchAdmin(env, path, {
    method: 'PUT',
    body: JSON.stringify(body),
  })
  if (!r.ok) {
    const text = await r.text()
    const err = new Error(`couch PUT ${path} ${r.status}: ${text}`)
    err.status = r.status
    throw err
  }
  return r.json()
}

async function readFlockMeta(env, dbName) {
  return couchGetJson(env, `/${dbName}/flock%3Ameta`)
}

async function writeFlockMeta(env, dbName, meta) {
  return couchPutJson(env, `/${dbName}/flock%3Ameta`, meta)
}

async function readSecurity(env, dbName) {
  const r = await couchAdmin(env, `/${dbName}/_security`)
  if (!r.ok) {
    const err = new Error(`couch GET _security ${r.status}`)
    err.status = r.status
    throw err
  }
  return r.json()
}

async function writeSecurity(env, dbName, security) {
  const r = await couchAdmin(env, `/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(security),
  })
  if (!r.ok) {
    const text = await r.text()
    throw new Error(`couch PUT _security ${r.status}: ${text}`)
  }
  return r.json()
}

async function installDesignDoc(env, dbName) {
  const existing = await couchAdmin(
    env,
    `/${dbName}/${encodeURIComponent(FLOCK_DESIGN_DOC_ID)}`,
  )
  let rev = null
  if (existing.ok) rev = (await existing.json())._rev
  const doc = buildFlockDesignDoc(rev)
  const put = await couchAdmin(
    env,
    `/${dbName}/${encodeURIComponent(FLOCK_DESIGN_DOC_ID)}`,
    { method: 'PUT', body: JSON.stringify(doc) },
  )
  if (!put.ok) {
    const text = await put.text()
    throw new Error(`design doc PUT ${put.status}: ${text}`)
  }
}

function securityForMembers(members, meta) {
  return {
    admins: { names: [], roles: [] },
    members: { names: members, roles: [] },
    flock: {
      billingOwner: meta.billingOwner,
      billingStatus: meta.billingStatus,
    },
  }
}

async function syncSecurity(env, dbName, members, meta) {
  await writeSecurity(env, dbName, securityForMembers(members, meta))
}

async function appendUserFlocks(env, email, entry) {
  const dbName = personalDbName(email)
  const url = `/${dbName}/user%3Aflocks`
  const cur = await couchAdmin(env, url)
  let doc
  if (cur.ok) {
    doc = await cur.json()
    const without = (doc.flocks || []).filter((f) => f.id !== entry.id)
    doc.flocks = [...without, entry]
  } else if (cur.status === 404) {
    doc = {
      _id: 'user:flocks',
      type: 'userFlocks',
      flocks: [entry],
    }
  } else {
    throw new Error(`user:flocks GET ${cur.status}`)
  }
  await couchPutJson(env, url, doc)
}

async function removeUserFlocks(env, email, flockId) {
  const dbName = personalDbName(email)
  const url = `/${dbName}/user%3Aflocks`
  const cur = await couchAdmin(env, url)
  if (!cur.ok) return
  const doc = await cur.json()
  doc.flocks = (doc.flocks || []).filter((f) => f.id !== flockId)
  await couchPutJson(env, url, doc)
}

async function listOwnedFlocksFor(env, email) {
  const dbName = personalDbName(email)
  const url = `/${dbName}/user%3Aflocks`
  const cur = await couchAdmin(env, url)
  if (!cur.ok) return []
  const doc = await cur.json()
  const owned = []
  for (const entry of doc.flocks || []) {
    try {
      const meta = await readFlockMeta(env, entry.dbName)
      if (meta.billingOwner === email.toLowerCase()) {
        owned.push({ entry, meta })
      }
    } catch {
      // skip flocks we can't read
    }
  }
  return owned
}

export function registerFlockRoutes(app) {
  app.post('/flocks', async (c) => {
    const env = c.env
    const caller = await authenticateCaller(c)
    if (!caller) return c.json({ ok: false, error: 'unauthorized' }, 401)

    const tier = await getTier(env, caller.email)
    if (!isPaidTier(tier)) {
      return c.json({ ok: false, error: 'paid_tier_required' }, 403)
    }

    let body
    try {
      body = await c.req.json()
    } catch {
      body = {}
    }
    const name = typeof body.name === 'string' ? body.name.trim() : ''
    if (!name) return c.json({ ok: false, error: 'name_required' }, 400)

    const flockId = randomFlockId()
    const dbName = flockDbName(flockId)
    const meta = {
      _id: 'flock:meta',
      type: 'flock',
      name,
      members: [caller.email],
      billingOwner: caller.email,
      billingStatus: 'active',
      billingLapsedAt: null,
      createdBy: caller.email,
      createdAt: nowIso(),
    }

    try {
      const create = await couchAdmin(env, `/${dbName}`, { method: 'PUT' })
      if (!create.ok && create.status !== 412) {
        throw new Error(`db PUT ${create.status}`)
      }
      await syncSecurity(env, dbName, [caller.email], meta)
      await installDesignDoc(env, dbName)
      await writeFlockMeta(env, dbName, meta)
      await appendUserFlocks(env, caller.email, {
        id: flockId,
        name,
        dbName,
      })
      return c.json({ ok: true, flockId, dbName }, 201)
    } catch (err) {
      console.error('flocks/create:', err)
      return c.json({ ok: false, error: 'provision_failed' }, 500)
    }
  })

  app.post('/flocks/:id/invite', async (c) => {
    const env = c.env
    const caller = await authenticateCaller(c)
    if (!caller) return c.json({ ok: false, error: 'unauthorized' }, 401)

    const flockId = c.req.param('id')
    const dbName = flockDbName(flockId)

    let meta
    try {
      meta = await readFlockMeta(env, dbName)
    } catch (err) {
      if (err.status === 404) {
        return c.json({ ok: false, error: 'not_found' }, 404)
      }
      console.error('flocks/invite read meta:', err)
      return c.json({ ok: false, error: 'read_failed' }, 500)
    }
    if (!meta.members.includes(caller.email)) {
      // 404 (not 403) — don't confirm existence to non-members. See #68.
      return c.json({ ok: false, error: 'not_found' }, 404)
    }
    if (meta.billingOwner !== caller.email) {
      // Invite is owner-only per #68. Members can join but only the
      // billing owner controls who else gets in.
      return c.json({ ok: false, error: 'not_owner' }, 403)
    }

    let body
    try {
      body = await c.req.json()
    } catch {
      body = {}
    }
    const inviteeEmail =
      typeof body.inviteeEmail === 'string'
        ? body.inviteeEmail.toLowerCase().trim()
        : ''
    if (!inviteeEmail.includes('@')) {
      return c.json({ ok: false, error: 'invalid_email' }, 400)
    }

    const now = Math.floor(Date.now() / 1000)
    const token = await signJwt(
      {
        flockId,
        inviteeEmail,
        inviter: caller.email,
        iat: now,
        exp: now + INVITE_EXPIRY_SECONDS,
      },
      env.SERVER_SECRET,
    )

    const joinUrl = `${APP_JOIN_URL}?token=${encodeURIComponent(token)}`
    try {
      const resend = new Resend(env.RESEND_API_KEY)
      await resend.emails.send({
        from: 'Ternpike <noreply@ternpike.com>',
        to: inviteeEmail,
        subject: `Join the ${meta.name} flock on Ternpike`,
        text:
          `${caller.email} invited you to join the "${meta.name}" flock on Ternpike, ` +
          `where you'll share expenses and trips together.\n\n` +
          `Open in Ternpike: ${joinUrl}\n\n` +
          `This invite expires in 7 days.\n`,
        html: inviteEmailHtml({
          flockName: meta.name,
          inviterEmail: caller.email,
          joinUrl,
        }),
      })
    } catch (err) {
      console.error('flocks/invite sendMail:', err)
      return c.json({ ok: false, error: 'email_failed' }, 500)
    }
    return c.json({ ok: true })
  })

  app.post('/flocks/join', async (c) => {
    const env = c.env
    const caller = await authenticateCaller(c)
    if (!caller) return c.json({ ok: false, error: 'unauthorized' }, 401)

    let body
    try {
      body = await c.req.json()
    } catch {
      body = {}
    }
    const token = typeof body.token === 'string' ? body.token : ''
    if (!token) return c.json({ ok: false, error: 'token_required' }, 400)

    const verified = await verifyJwt(token, env.SERVER_SECRET)
    if (!verified.ok) {
      const status = verified.reason === 'expired' ? 410 : 401
      return c.json({ ok: false, error: verified.reason }, status)
    }
    const { flockId, inviteeEmail } = verified.payload
    if (
      typeof flockId !== 'string' ||
      typeof inviteeEmail !== 'string' ||
      inviteeEmail.toLowerCase() !== caller.email
    ) {
      return c.json({ ok: false, error: 'email_mismatch' }, 403)
    }

    const dbName = flockDbName(flockId)
    let meta
    try {
      meta = await readFlockMeta(env, dbName)
    } catch (err) {
      if (err.status === 404) {
        return c.json({ ok: false, error: 'not_found' }, 404)
      }
      console.error('flocks/join read meta:', err)
      return c.json({ ok: false, error: 'read_failed' }, 500)
    }
    if (meta.members.includes(caller.email)) {
      return c.json({ ok: false, error: 'already_a_member' }, 409)
    }

    const members = [...meta.members, caller.email]
    const updatedMeta = { ...meta, members }
    try {
      await syncSecurity(env, dbName, members, updatedMeta)
      await writeFlockMeta(env, dbName, updatedMeta)
      await appendUserFlocks(env, caller.email, {
        id: flockId,
        name: meta.name,
        dbName,
      })
      return c.json({ ok: true, flockId, dbName })
    } catch (err) {
      console.error('flocks/join:', err)
      return c.json({ ok: false, error: 'join_failed' }, 500)
    }
  })

  app.post('/flocks/:id/leave', async (c) => {
    const env = c.env
    const caller = await authenticateCaller(c)
    if (!caller) return c.json({ ok: false, error: 'unauthorized' }, 401)

    const flockId = c.req.param('id')
    const dbName = flockDbName(flockId)

    let meta
    try {
      meta = await readFlockMeta(env, dbName)
    } catch (err) {
      if (err.status === 404) {
        return c.json({ ok: false, error: 'not_found' }, 404)
      }
      console.error('flocks/leave read meta:', err)
      return c.json({ ok: false, error: 'read_failed' }, 500)
    }
    if (!meta.members.includes(caller.email)) {
      // Return 404 (not 403) so we don't confirm the flock's existence to
      // a caller who has no business knowing about it. See #68.
      return c.json({ ok: false, error: 'not_found' }, 404)
    }
    if (meta.billingOwner === caller.email) {
      if (meta.members.length > 1) {
        return c.json(
          { ok: false, error: 'transfer_ownership_first' },
          409,
        )
      }
      // Sole-member owner self-leave is out of scope for v1 (delete-flock
      // is not yet implemented). Reject explicitly rather than orphan the
      // flock db. See #68.
      return c.json({ ok: false, error: 'sole_owner_cannot_leave' }, 409)
    }

    const members = meta.members.filter((m) => m !== caller.email)
    const updatedMeta = { ...meta, members }
    try {
      await syncSecurity(env, dbName, members, updatedMeta)
      await writeFlockMeta(env, dbName, updatedMeta)
      await removeUserFlocks(env, caller.email, flockId)
      return c.json({ ok: true })
    } catch (err) {
      console.error('flocks/leave:', err)
      return c.json({ ok: false, error: 'leave_failed' }, 500)
    }
  })

  app.post('/flocks/:id/transfer-ownership', async (c) => {
    const env = c.env
    const caller = await authenticateCaller(c)
    if (!caller) return c.json({ ok: false, error: 'unauthorized' }, 401)

    const flockId = c.req.param('id')
    const dbName = flockDbName(flockId)

    let body
    try {
      body = await c.req.json()
    } catch {
      body = {}
    }
    const newOwnerEmail =
      typeof body.newOwnerEmail === 'string'
        ? body.newOwnerEmail.toLowerCase().trim()
        : ''
    if (!newOwnerEmail.includes('@')) {
      return c.json({ ok: false, error: 'invalid_email' }, 400)
    }

    let meta
    try {
      meta = await readFlockMeta(env, dbName)
    } catch (err) {
      if (err.status === 404) {
        return c.json({ ok: false, error: 'not_found' }, 404)
      }
      console.error('flocks/transfer read meta:', err)
      return c.json({ ok: false, error: 'read_failed' }, 500)
    }
    if (meta.billingOwner !== caller.email) {
      return c.json({ ok: false, error: 'not_owner' }, 403)
    }
    if (newOwnerEmail === caller.email) {
      return c.json({ ok: false, error: 'cannot_transfer_to_self' }, 400)
    }
    if (!meta.members.includes(newOwnerEmail)) {
      return c.json({ ok: false, error: 'new_owner_not_a_member' }, 409)
    }
    const newOwnerTier = await getTier(env, newOwnerEmail)
    if (!isPaidTier(newOwnerTier)) {
      return c.json(
        { ok: false, error: 'new_owner_not_paid' },
        409,
      )
    }

    const updatedMeta = { ...meta, billingOwner: newOwnerEmail }
    try {
      await writeFlockMeta(env, dbName, updatedMeta)
      await syncSecurity(env, dbName, meta.members, updatedMeta)
      return c.json({ ok: true, billingOwner: newOwnerEmail })
    } catch (err) {
      console.error('flocks/transfer:', err)
      return c.json({ ok: false, error: 'transfer_failed' }, 500)
    }
  })

  // Test-only hook: flip a user's tier and run the downgrade/upgrade cascade.
  // This is the integration point the real Stripe webhook will call once
  // billing lands (#16-#22). Body: { email, tier }.
  app.post('/flocks/test/tier-changed', async (c) => {
    const env = c.env
    if (!env.TIER_WEBHOOK_SECRET) {
      return c.json({ ok: false, error: 'webhook_not_configured' }, 503)
    }
    const provided = c.req.header('x-webhook-secret')
    if (
      !provided ||
      !constantTimeEqual(provided, env.TIER_WEBHOOK_SECRET)
    ) {
      return c.json({ ok: false, error: 'unauthorized' }, 401)
    }
    let body
    try {
      body = await c.req.json()
    } catch {
      body = {}
    }
    const email =
      typeof body.email === 'string' ? body.email.toLowerCase().trim() : ''
    const tier = typeof body.tier === 'string' ? body.tier : ''
    if (
      !email.includes('@') ||
      !['fledgling', 'fly', 'trailblazer'].includes(tier)
    ) {
      return c.json({ ok: false, error: 'invalid_payload' }, 400)
    }
    try {
      await setTier(env, email, tier)
      await onTierChanged(env, email, tier)
      return c.json({ ok: true })
    } catch (err) {
      console.error('tier-changed:', err)
      return c.json({ ok: false, error: 'cascade_failed' }, 500)
    }
  })
}

export async function onTierChanged(env, email, newTier) {
  const owned = await listOwnedFlocksFor(env, email)
  for (const { entry, meta } of owned) {
    if (!isPaidTier(newTier)) {
      if (meta.billingStatus === 'active') {
        const updated = {
          ...meta,
          billingStatus: 'grace',
          billingLapsedAt: nowIso(),
        }
        await writeFlockMeta(env, entry.dbName, updated)
        await syncSecurity(env, entry.dbName, meta.members, updated)
      }
    } else {
      if (meta.billingStatus === 'grace') {
        const updated = {
          ...meta,
          billingStatus: 'active',
          billingLapsedAt: null,
        }
        await writeFlockMeta(env, entry.dbName, updated)
        await syncSecurity(env, entry.dbName, meta.members, updated)
      }
      // billingStatus === 'frozen' requires a manual re-activation; the
      // 14-day window has elapsed and the data may need reconciliation.
    }
  }
}

export async function runGraceFreezeSweep(env) {
  // Iterate every `flock-` database and freeze any whose grace window has
  // elapsed. Cheap at our scale; revisit if flock count grows past ~10k.
  const list = await couchAdmin(env, '/_all_dbs')
  if (!list.ok) {
    console.error('cron: _all_dbs failed', list.status)
    return
  }
  const dbs = (await list.json()).filter((d) => d.startsWith('flock-'))
  const cutoff = Date.now() - GRACE_PERIOD_MS
  for (const dbName of dbs) {
    try {
      const meta = await readFlockMeta(env, dbName)
      if (meta.billingStatus !== 'grace') continue
      if (!meta.billingLapsedAt) continue
      const lapsedMs = Date.parse(meta.billingLapsedAt)
      if (Number.isNaN(lapsedMs)) continue
      if (lapsedMs > cutoff) continue
      const updated = { ...meta, billingStatus: 'frozen' }
      await writeFlockMeta(env, dbName, updated)
      await syncSecurity(env, dbName, meta.members, updated)
    } catch (err) {
      console.error('cron freeze sweep', dbName, err)
    }
  }
}

function inviteEmailHtml({ flockName, inviterEmail, joinUrl }) {
  const safeFlock = escapeHtml(flockName)
  const safeInviter = escapeHtml(inviterEmail)
  return `<!doctype html>
<html><body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif; color: #222; padding: 24px;">
  <p>${safeInviter} invited you to join the <strong>${safeFlock}</strong> flock on Ternpike.</p>
  <p>You'll share expenses and trips together, in real time.</p>
  <p style="margin: 24px 0;">
    <a href="${joinUrl}" style="background:#4a5e3a; color:#fff; padding: 12px 20px; border-radius: 6px; text-decoration:none; display:inline-block;">Open in Ternpike</a>
  </p>
  <p style="font-size: 13px; color: #666;">This invite expires in 7 days.</p>
</body></html>`
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}
