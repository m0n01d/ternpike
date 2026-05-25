// Admin / dev-tools API for the ternpike-admin TUI.
//
// All endpoints sit behind `x-admin-secret` matching ADMIN_SECRET. The
// secret is the entire access model — there is no admin user record. See
// CLAUDE.md.
//
// Most endpoints are thin proxies over `couchAdmin`, since the TUI is the
// only consumer and the caller is already trusted. The user mutation
// endpoints reuse the same provisioning + cascade helpers the real auth
// flow uses (`setTier` + `onTierChanged` in sharedTrips.js).

import {
  constantTimeEqual,
  couchAdmin,
  derivePassword,
  getTier,
  onTierChanged,
  personalDbName,
  readSharedTripMeta,
  setTier,
  sharedTripDbName,
} from './sharedTrips.js'

const VALID_TIERS = ['tern', 'osprey', 'trailblazer']
const TERNPIKE_DB_PREFIXES = ['ternpike-', 'sharedtrip-']

const nowIso = () => new Date().toISOString()

const guard = (c) => {
  const env = c.env
  if (!env.ADMIN_SECRET) {
    return c.json({ ok: false, error: 'admin_not_configured' }, 503)
  }
  const provided = c.req.header('x-admin-secret')
  if (!provided || !constantTimeEqual(provided, env.ADMIN_SECRET)) {
    return c.json({ ok: false, error: 'unauthorized' }, 401)
  }
  return null
}

const couchJson = async (env, path, init) => {
  try {
    const r = await couchAdmin(env, path, init)
    const text = await r.text()
    let body = null
    try {
      body = text ? JSON.parse(text) : null
    } catch {
      body = text
    }
    return { ok: r.ok, status: r.status, body }
  } catch (err) {
    return {
      ok: false,
      status: 502,
      body: { error: 'couch_unreachable', detail: String(err.message || err) },
    }
  }
}

async function ensureCouchUser(env, email, password) {
  const id = `org.couchdb.user:${email}`
  const url = `/_users/${encodeURIComponent(id)}`
  const cur = await couchAdmin(env, url)
  const rev = cur.ok ? (await cur.json())._rev : null
  const doc = {
    _id: id,
    name: email,
    password,
    roles: [],
    type: 'user',
    ...(rev && { _rev: rev }),
  }
  const put = await couchAdmin(env, url, {
    method: 'PUT',
    body: JSON.stringify(doc),
  })
  if (!put.ok) {
    throw new Error(`_users PUT ${put.status}: ${await put.text()}`)
  }
}

async function ensurePersonalDb(env, email) {
  const dbName = personalDbName(email)
  const create = await couchAdmin(env, `/${dbName}`, { method: 'PUT' })
  if (!create.ok && create.status !== 412) {
    throw new Error(`db PUT ${create.status}: ${await create.text()}`)
  }
  const security = {
    admins: { names: [], roles: [] },
    members: { names: [email], roles: [] },
  }
  const sec = await couchAdmin(env, `/${dbName}/_security`, {
    method: 'PUT',
    body: JSON.stringify(security),
  })
  if (!sec.ok) {
    throw new Error(`_security PUT ${sec.status}: ${await sec.text()}`)
  }
  return dbName
}

async function dropCouchUser(env, email) {
  const id = `org.couchdb.user:${email}`
  const url = `/_users/${encodeURIComponent(id)}`
  const cur = await couchAdmin(env, url)
  if (!cur.ok) return
  const rev = (await cur.json())._rev
  await couchAdmin(env, `${url}?rev=${encodeURIComponent(rev)}`, {
    method: 'DELETE',
  })
}

async function dropDb(env, dbName) {
  await couchAdmin(env, `/${dbName}`, { method: 'DELETE' })
}

async function dbStats(env, dbName) {
  const info = await couchJson(env, `/${dbName}`)
  if (!info.ok) return { docCount: null, sizeBytes: null }
  return {
    docCount: info.body.doc_count ?? null,
    sizeBytes: info.body.sizes?.active ?? info.body.disk_size ?? null,
  }
}

function isTernpikeDb(name) {
  return TERNPIKE_DB_PREFIXES.some((p) => name.startsWith(p))
}

function randomId(bytes = 6) {
  const arr = crypto.getRandomValues(new Uint8Array(bytes))
  let s = ''
  for (const b of arr) s += b.toString(16).padStart(2, '0')
  return s
}

function newTripId() {
  return `trip::${nowIso()}::${randomId()}`
}

function newExpenseId() {
  return `expense::${nowIso()}::${randomId()}`
}

const SAMPLE_CATEGORIES = [
  'fuel',
  'food',
  'lodging',
  'activity',
  'supplies',
  'transit',
]
const SAMPLE_MERCHANTS = [
  'Shell',
  'Safeway',
  'KOA',
  'Salmon Glacier Tour',
  'REI',
  'Alaska Marine Highway',
]

function sampleTripDoc(name) {
  const id = newTripId()
  return {
    _id: id,
    type: 'trip',
    name,
    startDate: '2024-06-01',
    endDate: '2024-06-14',
    createdAt: nowIso(),
  }
}

function sampleExpenseDoc(tripId) {
  const cat =
    SAMPLE_CATEGORIES[Math.floor(Math.random() * SAMPLE_CATEGORIES.length)]
  const merchant =
    SAMPLE_MERCHANTS[Math.floor(Math.random() * SAMPLE_MERCHANTS.length)]
  const amount = Math.round((5 + Math.random() * 200) * 100) / 100
  return {
    _id: newExpenseId(),
    type: 'expense',
    tripId,
    date: '2024-06-' + String(1 + Math.floor(Math.random() * 14)).padStart(2, '0'),
    amount,
    category: cat,
    merchant,
    note: '',
    createdAt: nowIso(),
  }
}

export function registerAdminRoutes(app) {
  // --- users ---------------------------------------------------------------

  app.get('/admin/users', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    if (!c.env.TIERS_KV) return c.json({ ok: true, users: [] })
    const list = await c.env.TIERS_KV.list()
    const users = []
    for (const key of list.keys) {
      const tier = (await c.env.TIERS_KV.get(key.name)) || 'tern'
      users.push({ email: key.name, tier })
    }
    users.sort((a, b) => a.email.localeCompare(b.email))
    return c.json({ ok: true, users })
  })

  app.post('/admin/users', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const body = await c.req.json().catch(() => ({}))
    const email =
      typeof body.email === 'string' ? body.email.toLowerCase().trim() : ''
    const tier = typeof body.tier === 'string' ? body.tier : 'tern'
    if (!email.includes('@')) {
      return c.json({ ok: false, error: 'invalid_email' }, 400)
    }
    if (!VALID_TIERS.includes(tier)) {
      return c.json({ ok: false, error: 'invalid_tier' }, 400)
    }
    try {
      const password = await derivePassword(email, c.env.SERVER_SECRET)
      await ensureCouchUser(c.env, email, password)
      const dbName = await ensurePersonalDb(c.env, email)
      await setTier(c.env, email, tier)
      return c.json({ ok: true, email, tier, dbName }, 201)
    } catch (err) {
      console.error('admin/users POST:', err)
      return c.json({ ok: false, error: String(err.message || err) }, 500)
    }
  })

  app.get('/admin/users/:email', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const email = c.req.param('email').toLowerCase()
    const tier = await getTier(c.env, email)
    const dbName = personalDbName(email)
    const stats = await dbStats(c.env, dbName)
    const sharedTripsDoc = await couchJson(
      c.env,
      `/${dbName}/user%3Asharedtrips`,
    )
    const sharedTrips = sharedTripsDoc.ok
      ? sharedTripsDoc.body?.flocks || []
      : []
    return c.json({
      ok: true,
      email,
      tier,
      personalDb: dbName,
      docCount: stats.docCount,
      sizeBytes: stats.sizeBytes,
      sharedTrips,
    })
  })

  app.put('/admin/users/:email/tier', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const email = c.req.param('email').toLowerCase()
    const body = await c.req.json().catch(() => ({}))
    const tier = body.tier
    if (!VALID_TIERS.includes(tier)) {
      return c.json({ ok: false, error: 'invalid_tier' }, 400)
    }
    try {
      await setTier(c.env, email, tier)
    } catch (err) {
      return c.json(
        { ok: false, error: 'kv_failed', detail: String(err.message || err) },
        500,
      )
    }
    try {
      await onTierChanged(c.env, email, tier)
    } catch (err) {
      // Tier flipped in KV but the cascade across owned shared trips
      // partially failed (couch unreachable, etc). The next /admin call
      // will see the new tier; surface the cascade error explicitly.
      return c.json(
        {
          ok: false,
          email,
          tier,
          error: 'cascade_failed',
          detail: String(err.message || err),
        },
        502,
      )
    }
    return c.json({ ok: true, email, tier })
  })

  app.delete('/admin/users/:email', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const email = c.req.param('email').toLowerCase()
    const dbName = personalDbName(email)
    try {
      await dropCouchUser(c.env, email)
      await dropDb(c.env, dbName)
      if (c.env.TIERS_KV) await c.env.TIERS_KV.delete(email)
      return c.json({ ok: true, email })
    } catch (err) {
      console.error('admin/users DELETE:', err)
      return c.json({ ok: false, error: String(err.message || err) }, 500)
    }
  })

  // --- databases -----------------------------------------------------------

  app.get('/admin/dbs', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const list = await couchJson(c.env, '/_all_dbs')
    if (!list.ok) {
      return c.json({ ok: false, error: 'list_failed', status: list.status }, 500)
    }
    const all = c.req.query('all') === '1'
    const filtered = all
      ? list.body
      : list.body.filter(isTernpikeDb)
    const dbs = []
    for (const name of filtered) {
      const s = await dbStats(c.env, name)
      dbs.push({ name, docCount: s.docCount, sizeBytes: s.sizeBytes })
    }
    dbs.sort((a, b) => a.name.localeCompare(b.name))
    return c.json({ ok: true, dbs })
  })

  app.get('/admin/dbs/:db', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const dbName = c.req.param('db')
    const s = await dbStats(c.env, dbName)
    if (s.docCount === null) {
      return c.json({ ok: false, error: 'not_found' }, 404)
    }
    return c.json({ ok: true, name: dbName, ...s })
  })

  app.get('/admin/dbs/:db/docs', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const dbName = c.req.param('db')
    const limit = Math.min(Number(c.req.query('limit') || 200), 1000)
    const skip = Number(c.req.query('skip') || 0)
    const prefix = c.req.query('prefix') || ''
    const params = new URLSearchParams({
      include_docs: 'true',
      limit: String(limit),
      skip: String(skip),
    })
    if (prefix) {
      params.set('startkey', JSON.stringify(prefix))
      params.set('endkey', JSON.stringify(prefix + '￰'))
    }
    const r = await couchJson(c.env, `/${dbName}/_all_docs?${params}`)
    if (!r.ok) {
      return c.json({ ok: false, error: 'list_failed', status: r.status }, r.status)
    }
    const rows = (r.body.rows || []).map((row) => row.doc).filter(Boolean)
    return c.json({
      ok: true,
      total: r.body.total_rows ?? null,
      offset: r.body.offset ?? null,
      docs: rows,
    })
  })

  app.get('/admin/dbs/:db/docs/:id', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const dbName = c.req.param('db')
    const id = c.req.param('id')
    const r = await couchJson(
      c.env,
      `/${dbName}/${encodeURIComponent(id)}`,
    )
    if (!r.ok) {
      return c.json({ ok: false, error: 'not_found', status: r.status }, r.status)
    }
    return c.json({ ok: true, doc: r.body })
  })

  app.put('/admin/dbs/:db/docs/:id', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const dbName = c.req.param('db')
    const id = c.req.param('id')
    const body = await c.req.json().catch(() => null)
    if (!body || typeof body !== 'object') {
      return c.json({ ok: false, error: 'invalid_body' }, 400)
    }
    const r = await couchJson(c.env, `/${dbName}/${encodeURIComponent(id)}`, {
      method: 'PUT',
      body: JSON.stringify(body),
    })
    if (!r.ok) {
      return c.json(
        { ok: false, error: 'put_failed', status: r.status, body: r.body },
        r.status,
      )
    }
    return c.json({ ok: true, rev: r.body.rev })
  })

  app.delete('/admin/dbs/:db/docs/:id', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const dbName = c.req.param('db')
    const id = c.req.param('id')
    const rev = c.req.query('rev')
    if (!rev) return c.json({ ok: false, error: 'rev_required' }, 400)
    const r = await couchJson(
      c.env,
      `/${dbName}/${encodeURIComponent(id)}?rev=${encodeURIComponent(rev)}`,
      { method: 'DELETE' },
    )
    if (!r.ok) {
      return c.json({ ok: false, error: 'delete_failed', status: r.status }, r.status)
    }
    return c.json({ ok: true })
  })

  app.post('/admin/dbs/:db/void', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const dbName = c.req.param('db')
    const body = await c.req.json().catch(() => ({}))
    const targetId = typeof body.docId === 'string' ? body.docId : ''
    if (!targetId) return c.json({ ok: false, error: 'docId_required' }, 400)
    const voidId = `void::${targetId}::del`
    const doc = {
      _id: voidId,
      type: 'void',
      targetId,
      createdAt: nowIso(),
      createdBy: 'admin',
    }
    const r = await couchJson(c.env, `/${dbName}/${encodeURIComponent(voidId)}`, {
      method: 'PUT',
      body: JSON.stringify(doc),
    })
    if (!r.ok) {
      return c.json({ ok: false, error: 'void_failed', status: r.status, body: r.body }, r.status)
    }
    return c.json({ ok: true, voidId })
  })

  // --- shared trips --------------------------------------------------------

  app.get('/admin/sharedtrips', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const list = await couchJson(c.env, '/_all_dbs')
    if (!list.ok) {
      return c.json(
        { ok: false, error: 'list_failed', detail: list.body },
        list.status,
      )
    }
    const dbs = list.body.filter((d) => d.startsWith('sharedtrip-'))
    const trips = []
    for (const dbName of dbs) {
      try {
        const meta = await readSharedTripMeta(c.env, dbName)
        trips.push({
          id: meta.flockId,
          name: meta.name,
          dbName,
          billingOwner: meta.billingOwner,
          billingStatus: meta.billingStatus,
          members: meta.members,
          createdAt: meta.createdAt,
        })
      } catch (err) {
        trips.push({ dbName, error: String(err.message || err) })
      }
    }
    trips.sort((a, b) => (a.name || '').localeCompare(b.name || ''))
    return c.json({ ok: true, sharedTrips: trips })
  })

  // --- seed ----------------------------------------------------------------

  app.post('/admin/seed/expenses', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const body = await c.req.json().catch(() => ({}))
    const email =
      typeof body.email === 'string' ? body.email.toLowerCase().trim() : ''
    const tripCount = Math.max(1, Math.min(Number(body.tripCount || 1), 10))
    const expensesPerTrip = Math.max(
      1,
      Math.min(Number(body.expensesPerTrip || 5), 200),
    )
    if (!email.includes('@')) {
      return c.json({ ok: false, error: 'invalid_email' }, 400)
    }
    const dbName = personalDbName(email)
    const docs = []
    for (let t = 0; t < tripCount; t++) {
      const trip = sampleTripDoc(`Sample trip ${t + 1}`)
      docs.push(trip)
      for (let e = 0; e < expensesPerTrip; e++) {
        docs.push(sampleExpenseDoc(trip._id))
      }
    }
    const r = await couchJson(c.env, `/${dbName}/_bulk_docs`, {
      method: 'POST',
      body: JSON.stringify({ docs }),
    })
    if (!r.ok) {
      return c.json({ ok: false, error: 'bulk_failed', status: r.status }, r.status)
    }
    return c.json({ ok: true, written: docs.length })
  })

  // --- geocode diagnostics -------------------------------------------------

  // Smoke-test the Google upstream end-to-end without touching the cache or
  // the user-facing rate limiter. Returns the raw Google `status` +
  // `error_message` so misconfigurations (missing key, billing disabled,
  // referrer restrictions) are visible instead of being collapsed into a
  // 502 the way the user-facing endpoint does.
  app.post('/admin/geocode/test', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const env = c.env
    if (!env.GOOGLE_GEOCODING_API_KEY) {
      return c.json({ ok: false, error: 'api_key_not_configured' }, 503)
    }
    const body = await c.req.json().catch(() => ({}))
    const address = typeof body.address === 'string' ? body.address.trim() : ''
    if (!address) {
      return c.json({ ok: false, error: 'address_required' }, 400)
    }
    const baseUrl =
      env.GOOGLE_GEOCODING_BASE_URL || 'https://maps.googleapis.com'
    const url =
      `${baseUrl}/maps/api/geocode/json` +
      `?address=${encodeURIComponent(address)}` +
      `&key=${encodeURIComponent(env.GOOGLE_GEOCODING_API_KEY)}`
    let res
    try {
      res = await fetch(url, { headers: { Accept: 'application/json' } })
    } catch (err) {
      return c.json(
        { ok: false, error: 'fetch_failed', detail: String(err.message || err) },
        502,
      )
    }
    const upstreamBody = await res.json().catch(() => null)
    const loc = upstreamBody?.results?.[0]?.geometry?.location
    return c.json({
      ok: true,
      httpStatus: res.status,
      googleStatus: upstreamBody?.status || null,
      googleErrorMessage: upstreamBody?.error_message || null,
      lat: typeof loc?.lat === 'number' ? loc.lat : null,
      lon: typeof loc?.lng === 'number' ? loc.lng : null,
      formattedAddress: upstreamBody?.results?.[0]?.formatted_address || null,
    })
  })

  // Purge cached geocode entries by KV prefix. Defaults to `addr:` which
  // matches both the legacy Nominatim entries (`addr:<sha>`) and the new
  // Google entries (`addr:google:<sha>`). Pass `{prefix: "addr:google:"}`
  // to scope to just the new entries.
  app.post('/admin/geocode/cache/purge', async (c) => {
    const denied = guard(c)
    if (denied) return denied
    const env = c.env
    if (!env.GEOCODE_CACHE_KV) {
      return c.json({ ok: false, error: 'cache_not_configured' }, 503)
    }
    const body = await c.req.json().catch(() => ({}))
    const prefix = typeof body.prefix === 'string' ? body.prefix : 'addr:'
    let cursor = undefined
    let deleted = 0
    while (true) {
      const page = await env.GEOCODE_CACHE_KV.list({ prefix, cursor })
      for (const key of page.keys) {
        await env.GEOCODE_CACHE_KV.delete(key.name)
        deleted += 1
      }
      if (page.list_complete) break
      cursor = page.cursor
    }
    return c.json({ ok: true, prefix, deleted })
  })
}
