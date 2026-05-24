// POST /geocode — paid-tier address → coordinates proxy.
//
// Upstream is Google Maps Geocoding API. We centralize the call here
// rather than letting browsers hit Google directly so the API key
// never reaches the client and we get one consistent cache + rate-
// limit story across users.
//
// Per-user rate limit: 100 requests per rolling 60s window via a
// token-bucket stored as JSON in `GEOCODE_RL_KV`. A typical batch-
// scanned road-trip week (~40-50 unique merchants) clears in one
// burst; the cap is purely runaway-loop defense.
//
// Result cache lives in `GEOCODE_CACHE_KV` keyed by SHA-256 of the
// normalized address. 30-day TTL for hits, 1-day TTL for no-match.
// Shared across users (an address resolves to the same point
// regardless of who asked) so the Google call count is linear in the
// number of *distinct* addresses, not the number of receipts.

import { authenticateCaller, getTier, isPaidTier } from './auth.js'

const GOOGLE_DEFAULT_BASE_URL = 'https://maps.googleapis.com'
const MAX_ADDRESS_LENGTH = 256
const CACHE_TTL_HIT_SECONDS = 30 * 24 * 60 * 60
const CACHE_TTL_NO_MATCH_SECONDS = 24 * 60 * 60
const RATE_LIMIT_WINDOW_MS = 60_000
const RATE_LIMIT_BUCKET_TTL_SECONDS = 120
const RATE_LIMIT_PER_MINUTE = 100

const normalizeAddress = (raw) => raw.trim().toLowerCase().replace(/\s+/g, ' ')

const sha256Hex = async (s) => {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))
  const bytes = new Uint8Array(buf)
  let hex = ''
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0')
  }
  return hex
}

// Google's Geocoding API returns one of these `status` values per
// https://developers.google.com/maps/documentation/geocoding/requests-geocoding#StatusCodes.
// We map them to our `{lat, lon}` shape — ZERO_RESULTS is a normal
// "no match" (200 with nulls); everything else (OVER_QUERY_LIMIT,
// REQUEST_DENIED, INVALID_REQUEST, UNKNOWN_ERROR) throws so the
// caller returns 502.
async function fetchFromGoogle(env, address) {
  if (!env.GOOGLE_GEOCODING_API_KEY) {
    throw new Error('google api key not configured')
  }
  const baseUrl = env.GOOGLE_GEOCODING_BASE_URL || GOOGLE_DEFAULT_BASE_URL
  const url =
    `${baseUrl}/maps/api/geocode/json` +
    `?address=${encodeURIComponent(address)}` +
    `&key=${encodeURIComponent(env.GOOGLE_GEOCODING_API_KEY)}`
  const res = await fetch(url, {
    method: 'GET',
    headers: { Accept: 'application/json' },
  })
  if (!res.ok) {
    throw new Error(`google ${res.status}`)
  }
  const body = await res.json()
  if (body.status === 'ZERO_RESULTS') {
    return { lat: null, lon: null }
  }
  if (body.status !== 'OK') {
    throw new Error(`google ${body.status}`)
  }
  const loc = body.results?.[0]?.geometry?.location
  if (!loc || typeof loc.lat !== 'number' || typeof loc.lng !== 'number') {
    return { lat: null, lon: null }
  }
  // Translate Google's `lng` to our internal `lon` at the boundary so
  // nothing downstream has to care about the upstream's naming.
  return { lat: loc.lat, lon: loc.lng }
}

// Token-bucket rate limit, stored as JSON in KV. Read-modify-write is
// vulnerable to a small over-shoot under simultaneous Worker isolates
// (eventual consistency on KV writes), which is fine — the cap is for
// runaway-loop defense, not security. Returns `true` when the request
// should be admitted, `false` when rate-limited.
async function admitRateLimited(env, email) {
  if (!env.GEOCODE_RL_KV) return true
  const now = Date.now()
  const rlKey = `rl:${email}`
  const raw = await env.GEOCODE_RL_KV.get(rlKey)
  let state
  try {
    state = raw ? JSON.parse(raw) : null
  } catch {
    state = null
  }
  if (!state || now - state.windowStart >= RATE_LIMIT_WINDOW_MS) {
    state = { count: 0, windowStart: now }
  }
  if (state.count >= RATE_LIMIT_PER_MINUTE) {
    return false
  }
  state.count += 1
  await env.GEOCODE_RL_KV.put(rlKey, JSON.stringify(state), {
    expirationTtl: RATE_LIMIT_BUCKET_TTL_SECONDS,
  })
  return true
}

export function registerGeocodeRoutes(app) {
  app.post('/geocode', async (c) => {
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
    const rawAddress = typeof body.address === 'string' ? body.address : ''
    const normalized = normalizeAddress(rawAddress)
    if (!normalized || normalized.length > MAX_ADDRESS_LENGTH) {
      return c.json({ ok: false, error: 'bad_request' }, 400)
    }

    if (!(await admitRateLimited(env, caller.email))) {
      return c.json({ ok: false, error: 'rate_limited' }, 429)
    }

    const cacheKey = `addr:${await sha256Hex(normalized)}`
    if (env.GEOCODE_CACHE_KV) {
      const cached = await env.GEOCODE_CACHE_KV.get(cacheKey)
      if (cached) {
        try {
          const parsed = JSON.parse(cached)
          return c.json({
            ok: true,
            lat: parsed.lat,
            lon: parsed.lon,
            source: 'google',
            cached: true,
          })
        } catch {
          // fall through to a fresh fetch on corrupted cache entries
        }
      }
    }

    let result
    try {
      result = await fetchFromGoogle(env, normalized)
    } catch (err) {
      console.error('geocode upstream:', err)
      return c.json({ ok: false, error: 'upstream' }, 502)
    }

    if (env.GEOCODE_CACHE_KV) {
      const ttl =
        result.lat === null ? CACHE_TTL_NO_MATCH_SECONDS : CACHE_TTL_HIT_SECONDS
      await env.GEOCODE_CACHE_KV.put(cacheKey, JSON.stringify(result), {
        expirationTtl: ttl,
      })
    }

    return c.json({
      ok: true,
      lat: result.lat,
      lon: result.lon,
      source: 'google',
    })
  })
}
