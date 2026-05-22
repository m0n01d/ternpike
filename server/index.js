import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { Resend } from 'resend'

import { registerFlockRoutes, runGraceFreezeSweep } from './flocks.js'

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

const corsConfig = cors({
  origin: (origin) => {
    if (!origin) return null
    if (STATIC_ORIGINS.has(origin)) return origin
    if (PREVIEW_ORIGIN.test(origin)) return origin
    return null
  },
  allowMethods: ['POST', 'OPTIONS'],
  allowHeaders: ['Authorization', 'Content-Type', 'X-Webhook-Secret'],
  maxAge: 86400,
})

app.use('/auth/*', corsConfig)
app.use('/flocks/*', corsConfig)
app.use('/flocks', corsConfig)
app.use('/marketing/*', corsConfig)

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
    return c.json({ ok: true, email, password, dbName })
  } catch (err) {
    console.error('provision:', err)
    return c.json({ ok: false }, 500)
  }
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

registerFlockRoutes(app)

export default {
  fetch: app.fetch,
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(runGraceFreezeSweep(env))
  },
}
