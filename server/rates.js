// GET /rates — free foreign-exchange proxy for the spend estimate (#448).
//
// Upstream is open.er-api.com (the free, keyless endpoint of
// ExchangeRate-API). We centralize the call here rather than letting
// browsers hit it directly so we get one consistent cache across users,
// dodge CORS/ad-blocker variance, and can swap the upstream in one place
// (`RATES_BASE_URL`) without touching the client.
//
// These are mid-market daily reference rates — a card adds ~1-3% + fees —
// so the client always labels the result an estimate ("est. · as of
// <date>"). Daily granularity is plenty for a travel-spend estimate.
//
// Response shape (rates are HOME-per-foreign, i.e. units of USD per 1 unit
// of the foreign currency, so the client multiplies a native amount by the
// rate to estimate USD):
//   { ok: true, base: "usd", date: "YYYY-MM-DD",
//     rates: { cad: 0.73, mxn: 0.058, ... }, cached: bool }
//
// Cache: reuses the already-provisioned GEOCODE_CACHE_KV (a generic Worker
// KV cache) under a `rates:` key prefix, one entry per UTC day, so the
// upstream is hit ~once/day regardless of user count. Degrades gracefully
// (fetches every time) if the binding is absent.

import { authenticateCaller } from './auth.js'

const DEFAULT_BASE_URL = 'https://open.er-api.com/v6'
const CACHE_TTL_SECONDS = 24 * 60 * 60

// Mirrors the foreign half of `Data.Currency.common` (everything the picker
// offers except the USD home currency). Keep in sync with src/Data/Currency.elm.
const SUPPORTED = ['cad', 'mxn', 'gtq', 'bzd', 'hnl', 'nio', 'crc', 'pab']

const todayUtc = () => new Date().toISOString().slice(0, 10)

// open.er-api returns `{ result: "success", base_code: "USD",
// time_last_update_utc, rates: { CAD: 1.37, ... } }` where each rate is
// FOREIGN-per-USD. We invert to HOME-per-foreign and lowercase the code so
// the client can multiply directly. Unknown/missing codes are simply omitted
// (the client then reports "set/missing rate" rather than guessing).
async function fetchRates(env) {
  const baseUrl = env.RATES_BASE_URL || DEFAULT_BASE_URL
  const res = await fetch(`${baseUrl}/latest/USD`, {
    headers: { Accept: 'application/json' },
  })
  if (!res.ok) {
    throw new Error(`fx ${res.status}`)
  }
  const body = await res.json()
  if (body.result && body.result !== 'success') {
    throw new Error(`fx ${body.result}`)
  }
  const upstream = body.rates || {}
  const rates = {}
  for (const code of SUPPORTED) {
    const foreignPerUsd = upstream[code.toUpperCase()]
    if (typeof foreignPerUsd === 'number' && foreignPerUsd > 0) {
      // HOME-per-foreign = 1 / (foreign-per-home). Round to 6 sig-ish
      // decimals to keep the payload tidy; the client rounds to cents.
      rates[code] = Math.round((1 / foreignPerUsd) * 1e6) / 1e6
    }
  }
  const date =
    typeof body.time_last_update_utc === 'string'
      ? new Date(body.time_last_update_utc).toISOString().slice(0, 10)
      : todayUtc()
  return { base: 'usd', date, rates }
}

export function registerRatesRoutes(app) {
  app.get('/rates', async (c) => {
    const env = c.env
    const caller = await authenticateCaller(c)
    if (!caller) return c.json({ ok: false, error: 'unauthorized' }, 401)

    const cacheKey = `rates:usd:${todayUtc()}`
    if (env.GEOCODE_CACHE_KV) {
      const cached = await env.GEOCODE_CACHE_KV.get(cacheKey)
      if (cached) {
        try {
          const parsed = JSON.parse(cached)
          return c.json({ ok: true, ...parsed, cached: true })
        } catch {
          // fall through to a fresh fetch on a corrupted entry
        }
      }
    }

    let table
    try {
      table = await fetchRates(env)
    } catch (err) {
      console.error('rates upstream:', err)
      return c.json({ ok: false, error: 'upstream' }, 502)
    }

    if (env.GEOCODE_CACHE_KV) {
      await env.GEOCODE_CACHE_KV.put(cacheKey, JSON.stringify(table), {
        expirationTtl: CACHE_TTL_SECONDS,
      })
    }

    return c.json({ ok: true, ...table, cached: false })
  })
}
