import express from 'express'
import nodemailer from 'nodemailer'
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto'

const {
  COUCH_URL = 'https://couch.ternpike.com',
  COUCH_ADMIN_USER,
  COUCH_ADMIN_PASS,
  SERVER_SECRET,
  GMAIL_USER,
  GMAIL_APP_PASSWORD,
  PORT = '4000',
} = process.env

if (!COUCH_ADMIN_USER || !COUCH_ADMIN_PASS || !SERVER_SECRET || !GMAIL_USER || !GMAIL_APP_PASSWORD) {
  console.error('Missing required env vars. See .env.example.')
  process.exit(1)
}

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
})

const codes = new Map()
const CODE_TTL_MS = 10 * 60_000
const CODE_LENGTH = 6

const adminAuth =
  'Basic ' + Buffer.from(`${COUCH_ADMIN_USER}:${COUCH_ADMIN_PASS}`).toString('base64')

const hashCode = (code) =>
  createHmac('sha256', SERVER_SECRET).update(code).digest()

const derivePassword = (email) =>
  createHmac('sha256', SERVER_SECRET)
    .update('couch:' + email.toLowerCase())
    .digest('hex')
    .slice(0, 32)

const sanitizeDb = (email) =>
  'ternpike-' + email.toLowerCase().replace(/[^a-z0-9_$()+/-]/g, '-')

const couchAdmin = (path, init = {}) =>
  fetch(`${COUCH_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: adminAuth,
      ...(init.headers || {}),
    },
  })

async function ensureUser(email, password) {
  const id = `org.couchdb.user:${email}`
  const url = `/_users/${encodeURIComponent(id)}`
  const cur = await couchAdmin(url)
  const rev = cur.ok ? (await cur.json())._rev : null
  const body = {
    _id: id,
    name: email,
    password,
    roles: [],
    type: 'user',
    ...(rev && { _rev: rev }),
  }
  const put = await couchAdmin(url, { method: 'PUT', body: JSON.stringify(body) })
  if (!put.ok) throw new Error(`_users PUT ${put.status}`)
}

async function ensureDb(dbName, email) {
  const create = await couchAdmin(`/${dbName}`, { method: 'PUT' })
  if (!create.ok && create.status !== 412)
    throw new Error(`db PUT ${create.status}`)
  const security = {
    admins: { names: [], roles: [] },
    members: { names: [email], roles: [] },
  }
  const sec = await couchAdmin(`/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(security),
  })
  if (!sec.ok) throw new Error(`_security PUT ${sec.status}`)
}

const app = express()
app.use(express.json())

app.post('/auth/request-code', async (req, res) => {
  const { email } = req.body || {}
  if (typeof email !== 'string' || !email.includes('@')) {
    return res.status(400).json({ ok: false })
  }
  const code = String(randomInt(0, 10 ** CODE_LENGTH)).padStart(CODE_LENGTH, '0')
  codes.set(email.toLowerCase(), {
    hash: hashCode(code),
    exp: Date.now() + CODE_TTL_MS,
  })
  try {
    await transporter.sendMail({
      from: `Ternpike <${GMAIL_USER}>`,
      to: email,
      subject: `Your Ternpike code: ${code}`,
      text: `Your code is ${code}. It expires in 10 minutes.\n`,
    })
    res.json({ ok: true })
  } catch (err) {
    console.error('sendMail:', err)
    res.status(500).json({ ok: false })
  }
})

app.post('/auth/verify-code', async (req, res) => {
  const { email, code } = req.body || {}
  if (typeof email !== 'string' || typeof code !== 'string') {
    return res.status(400).json({ ok: false })
  }
  const key = email.toLowerCase()
  const entry = codes.get(key)
  if (!entry || entry.exp < Date.now()) return res.status(401).json({ ok: false })
  const incoming = hashCode(code)
  if (incoming.length !== entry.hash.length || !timingSafeEqual(incoming, entry.hash)) {
    return res.status(401).json({ ok: false })
  }
  codes.delete(key)

  const password = derivePassword(email)
  const dbName = sanitizeDb(email)
  try {
    await ensureUser(email, password)
    await ensureDb(dbName, email)
    res.json({ ok: true, email, password, dbName })
  } catch (err) {
    console.error('provision:', err)
    res.status(500).json({ ok: false })
  }
})

app.listen(Number(PORT), () => console.log(`auth server on :${PORT}`))
