// Mint authenticated request headers without going through the real Resend
// email + 6-digit code flow. The auth scheme is HTTP Basic with email +
// HMAC-derived password (matches the server's `authenticateCaller`), so a
// "session" is just those headers.

const encoder = new TextEncoder()

const bytesToHex = (bytes) => {
  let s = ''
  for (let i = 0; i < bytes.length; i++) {
    s += bytes[i].toString(16).padStart(2, '0')
  }
  return s
}

export async function derivePassword(email, secret) {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode('couch:' + email.toLowerCase()),
  )
  return bytesToHex(new Uint8Array(sig)).slice(0, 32)
}

export async function basicAuthHeader(email, secret) {
  const password = await derivePassword(email, secret)
  const token = Buffer.from(`${email.toLowerCase()}:${password}`).toString(
    'base64',
  )
  return `Basic ${token}`
}

// Build a malformed Basic-auth header — same email, wrong password. Used to
// assert the server rejects tampered credentials.
export function tamperedAuthHeader(email) {
  const token = Buffer.from(
    `${email.toLowerCase()}:not-the-real-password`,
  ).toString('base64')
  return `Basic ${token}`
}
