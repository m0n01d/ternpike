// POST /geocode — paid-tier address → coordinates proxy.
//
// The browser cannot call Nominatim directly: OSM's public usage policy
// requires a real `User-Agent` with contact info, throttles to 1 req/sec
// globally per consumer, and asks operators not to over-cache. We
// centralize all of that here so individual clients don't have to.
//
// Per-user rate limit is implemented via `GEOCODE_RL_KV` with the KV
// minimum 60s TTL — effectively 1 geocode/min/user. That's well within
// Nominatim's headroom for the current tiny user base. If demand grows
// to where users want bursts, the upgrade path is a Durable Object with
// a sub-second token bucket.
//
// Result cache lives in `GEOCODE_CACHE_KV` keyed by the SHA-256 of the
// normalized address. 30-day TTL for hits, 1-day TTL for no-match. The
// cache is shared across users (an address resolves to the same point
// regardless of who asked) which keeps the upstream call count linear in
// the number of *distinct* addresses, not the number of receipts.

import { authenticateCaller, getTier, isPaidTier } from './auth.js'

const NOMINATIM_DEFAULT_BASE_URL = 'https://nominatim.openstreetmap.org'
const MAX_ADDRESS_LENGTH = 256
const CACHE_TTL_HIT_SECONDS = 30 * 24 * 60 * 60
const CACHE_TTL_NO_MATCH_SECONDS = 24 * 60 * 60
const RATE_LIMIT_TTL_SECONDS = 60

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

async function fetchFromNominatim(env, address) {
  const baseUrl = env.NOMINATIM_BASE_URL || NOMINATIM_DEFAULT_BASE_URL
  const url = `${baseUrl}/search?q=${encodeURIComponent(address)}&format=json&limit=1`
  const userAgent = `Ternpike/${env.APP_VERSION || 'dev'} (contact@ternpike.com)`
  const res = await fetch(url, {
    method: 'GET',
    headers: {
      'User-Agent': userAgent,
      Accept: 'application/json',
      'Accept-Language': 'en',
    },
  })
  if (!res.ok) {
    throw new Error(`nominatim ${res.status}`)
  }
  const body = await res.json()
  if (!Array.isArray(body) || body.length === 0) {
    return { lat: null, lon: null }
  }
  const first = body[0]
  const lat = parseFloat(first.lat)
  const lon = parseFloat(first.lon)
  if (Number.isNaN(lat) || Number.isNaN(lon)) {
    return { lat: null, lon: null }
  }
  return { lat, lon }
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

    if (env.GEOCODE_RL_KV) {
      const rlKey = `rl:${caller.email}`
      const existing = await env.GEOCODE_RL_KV.get(rlKey)
      if (existing) {
        return c.json({ ok: false, error: 'rate_limited' }, 429)
      }
      await env.GEOCODE_RL_KV.put(rlKey, '1', {
        expirationTtl: RATE_LIMIT_TTL_SECONDS,
      })
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
            source: 'nominatim',
            cached: true,
          })
        } catch {
          // fall through to a fresh fetch on corrupted cache entries
        }
      }
    }

    let result
    try {
      result = await fetchFromNominatim(env, normalized)
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
      source: 'nominatim',
    })
  })
}
