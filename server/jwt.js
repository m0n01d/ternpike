const encoder = new TextEncoder()

const base64UrlEncode = (bytes) => {
  let s = ''
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i])
  return btoa(s).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_')
}

const base64UrlEncodeString = (str) =>
  base64UrlEncode(encoder.encode(str))

const base64UrlDecode = (str) => {
  const padded = str.replace(/-/g, '+').replace(/_/g, '/')
  const pad = padded.length % 4 === 0 ? '' : '='.repeat(4 - (padded.length % 4))
  const bin = atob(padded + pad)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

const importHmacKey = (secret, usage) =>
  crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    usage,
  )

const constantTimeEqualBytes = (a, b) => {
  if (a.length !== b.length) return false
  let acc = 0
  for (let i = 0; i < a.length; i++) acc |= a[i] ^ b[i]
  return acc === 0
}

export async function signJwt(payload, secret) {
  const header = { alg: 'HS256', typ: 'JWT' }
  const headerPart = base64UrlEncodeString(JSON.stringify(header))
  const payloadPart = base64UrlEncodeString(JSON.stringify(payload))
  const data = `${headerPart}.${payloadPart}`
  const key = await importHmacKey(secret, ['sign'])
  const sig = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, encoder.encode(data)),
  )
  return `${data}.${base64UrlEncode(sig)}`
}

export async function verifyJwt(token, secret) {
  if (typeof token !== 'string') return { ok: false, reason: 'malformed' }
  const parts = token.split('.')
  if (parts.length !== 3) return { ok: false, reason: 'malformed' }
  const [headerPart, payloadPart, sigPart] = parts
  let header
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlDecode(headerPart)))
  } catch {
    return { ok: false, reason: 'malformed' }
  }
  if (header.alg !== 'HS256' || header.typ !== 'JWT') {
    return { ok: false, reason: 'alg' }
  }
  const data = `${headerPart}.${payloadPart}`
  const key = await importHmacKey(secret, ['sign'])
  const expected = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, encoder.encode(data)),
  )
  const provided = base64UrlDecode(sigPart)
  if (!constantTimeEqualBytes(expected, provided)) {
    return { ok: false, reason: 'signature' }
  }
  let payload
  try {
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(payloadPart)))
  } catch {
    return { ok: false, reason: 'malformed' }
  }
  const nowSec = Math.floor(Date.now() / 1000)
  if (typeof payload.exp === 'number' && nowSec >= payload.exp) {
    return { ok: false, reason: 'expired' }
  }
  return { ok: true, payload }
}
