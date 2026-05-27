// Shared authentication + tier helpers used by Worker endpoints.
//
// Lifted from `sharedTrips.js` so new endpoints (`geocode.js` and beyond)
// don't reinvent the wheel. `sharedTrips.js` still has its own private
// copies for now — migrating it to consume this module is a separate
// follow-up so the geocode PR diff stays focused on the new endpoint.

const encoder = new TextEncoder()

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

export const derivePassword = async (email, secret) => {
  const key = await importHmacKey(secret)
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode('couch:' + email.toLowerCase()),
  )
  return bytesToHex(new Uint8Array(sig)).slice(0, 32)
}

// Validate the HTTP Basic header against the server-derived password.
// Returns `{ email }` on success, `null` on any failure (missing header,
// malformed base64, wrong password, missing SERVER_SECRET).
export async function authenticateCaller(c) {
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

// Read the user's tier from the server-authoritative `TIERS_KV` store.
// Defaults to `'tern'` if the binding is missing or the user has never
// been upgraded — paid features stay locked unless KV explicitly says so.
//
// New writes go to `user:<email>` as a JSON `UserRecord` (see
// `server/users.js`). Legacy writes lived at the bare `<email>` key as
// the raw tier string. We read the JSON record first and fall back to
// the legacy string so existing users keep working until the next time
// their record is upserted.
export async function getTier(env, email) {
  if (!env.TIERS_KV) return 'tern'
  const key = email.toLowerCase()
  const recordRaw = await env.TIERS_KV.get('user:' + key)
  if (recordRaw) {
    try {
      const record = JSON.parse(recordRaw)
      if (
        record?.tier === 'osprey' ||
        record?.tier === 'trailblazer' ||
        record?.tier === 'tern'
      ) {
        return record.tier
      }
    } catch (err) {
      console.error('getTier parse:', err)
    }
  }
  const v = await env.TIERS_KV.get(key)
  if (v === 'osprey' || v === 'trailblazer') return v
  return 'tern'
}

export const isPaidTier = (tier) => tier === 'osprey' || tier === 'trailblazer'
