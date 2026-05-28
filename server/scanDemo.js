// POST /scan-demo — public, rate-limited OCR demo for the marketing site.
//
// This is the unauthenticated cousin of /scan (server/scan.js). The
// marketing home page lets a visitor drop a receipt photo and renders
// the extracted fields — proof that the OCR pipeline actually works,
// without making them sign up first.
//
// Abuse gate is two-layer:
//   1. Cloudflare Turnstile token (invisible challenge on the page).
//   2. Per-IP daily cap stored in CODES_KV under a `scan-demo:` prefix.
//      2 successful scans per IP per UTC day. CODES_KV is reused (rather
//      than provisioning a new namespace) because the records are short-
//      TTL and the existing namespace is already wired up.
//
// The client only sends `{ turnstileToken, base64, mimeType }`. The
// model, system prompt, and max_tokens are all server-controlled — the
// demo doesn't need /scan's pass-through flexibility.

const ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
const ANTHROPIC_VERSION = '2023-06-01'
const TURNSTILE_VERIFY_URL =
  'https://challenges.cloudflare.com/turnstile/v0/siteverify'

const MODEL = 'claude-sonnet-4-6'
const MAX_TOKENS = 2048
const DAILY_LIMIT = 2
const ONE_DAY_SECONDS = 86400
// Mirrors `ocrMaxBase64Bytes` in src/Main.elm — Anthropic enforces ~5 MiB
// on the base64 string; we cap at 4 MiB so JPEG jitter can't push us over.
const MAX_BASE64_BYTES = 4 * 1024 * 1024

// Keep in sync with `ocrSystemPrompt` in src/Main.elm.
const SYSTEM_PROMPT =
  'You are a receipt parser. The image may contain one or many receipts (e.g. laid out on a table). Extract expense info for EVERY receipt visible and return ONLY a raw valid JSON array with no markdown, no code fences, no explanation. Each element of the array is one receipt, formatted exactly: {"amount": <number>, "category": "<activities|camp|ferry|food|fuel|gear|lodging|medical|misc|parks|shopping|transport>", "note": "<brief description max 50 chars>", "longNote": "<detailed description max 560 chars, include what was purchased, where, any relevant context>", "merchant": "<store name>", "address": "<street address as printed on receipt, include city and state/region when visible, or null if not visible>", "date": "<YYYY-MM-DD or null if not visible on receipt>", "paymentMethod": "<cash|credit|null>"}. If only one receipt is visible, still return a one-element array. For paymentMethod: use cash if receipt shows cash tendered/change; use credit if receipt shows card/credit/debit/visa/mastercard/chip; use null if unclear. Choose the best matching category. Use parks for national/state park entry fees. Use these note formats by category — fuel: "$X.XX/gal Xgal Grade" (e.g. "$4.29/gal 12.3gal Regular"); camp: "$XX/night HookupType" (e.g. "$35/night Full"); lodging: "$XX/night Xnights" (e.g. "$89/night 2nights"); ferry: "Origin→Dest vehicle|foot" (e.g. "Juneau→Haines car"); parks: "PassType ParkName" (e.g. "Day Pass Denali"); activities: "Xppl Activity" (e.g. "2ppl Kayaking"); food: "Xppl MealType" (e.g. "3ppl Dinner"); all others: brief description.'

async function verifyTurnstile(token, secret, remoteip) {
  if (!token || typeof token !== 'string') return false
  const form = new URLSearchParams()
  form.set('secret', secret)
  form.set('response', token)
  if (remoteip) form.set('remoteip', remoteip)
  try {
    const res = await fetch(TURNSTILE_VERIFY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString(),
    })
    if (!res.ok) return false
    const body = await res.json()
    return body && body.success === true
  } catch (err) {
    console.error('turnstile verify error:', err)
    return false
  }
}

function utcDateKey() {
  return new Date().toISOString().slice(0, 10)
}

function stripCodeFence(s) {
  const trimmed = s.trim()
  if (!trimmed.startsWith('```')) return trimmed
  const lines = trimmed.split('\n')
  lines.shift()
  if (lines.length && lines[lines.length - 1].startsWith('```')) lines.pop()
  return lines.join('\n').trim()
}

// Returns the first parsed receipt object or null. Mirrors the Elm
// `parseOcrResponseBody` / `claudeTextDecoder` shape.
function parseFirstReceipt(anthropicBody) {
  try {
    const text = anthropicBody?.content?.[0]?.text
    if (typeof text !== 'string') return null
    const arr = JSON.parse(stripCodeFence(text))
    if (!Array.isArray(arr) || arr.length === 0) return null
    const r = arr[0]
    return {
      address: typeof r.address === 'string' ? r.address : null,
      amount: typeof r.amount === 'number' ? r.amount : null,
      category: typeof r.category === 'string' ? r.category : null,
      date: typeof r.date === 'string' ? r.date : null,
      longNote: typeof r.longNote === 'string' ? r.longNote : null,
      merchant: typeof r.merchant === 'string' ? r.merchant : null,
      note: typeof r.note === 'string' ? r.note : null,
      paymentMethod:
        typeof r.paymentMethod === 'string' ? r.paymentMethod : null,
    }
  } catch {
    return null
  }
}

export function registerScanDemoRoutes(app) {
  app.post('/scan-demo', async (c) => {
    const env = c.env

    if (!env.TURNSTILE_SECRET_KEY || !env.ANTHROPIC_API_KEY) {
      return c.json({ ok: false, error: 'misconfigured' }, 500)
    }

    let body
    try {
      body = await c.req.json()
    } catch {
      return c.json({ ok: false, error: 'bad_request' }, 400)
    }

    const { base64, mimeType, turnstileToken } = body || {}
    if (
      typeof base64 !== 'string' ||
      typeof mimeType !== 'string' ||
      !mimeType.startsWith('image/')
    ) {
      return c.json({ ok: false, error: 'bad_request' }, 400)
    }
    if (base64.length > MAX_BASE64_BYTES) {
      return c.json({ ok: false, error: 'too_large' }, 413)
    }

    const ip = c.req.header('cf-connecting-ip') || 'unknown'
    const ok = await verifyTurnstile(turnstileToken, env.TURNSTILE_SECRET_KEY, ip)
    if (!ok) return c.json({ ok: false, error: 'turnstile' }, 401)

    const rlKey = `scan-demo:${ip}:${utcDateKey()}`
    const current = parseInt((await env.CODES_KV.get(rlKey)) || '0', 10) || 0
    if (current >= DAILY_LIMIT) {
      return c.json({ ok: false, error: 'rate_limited' }, 429)
    }

    const anthropicBase = env.ANTHROPIC_BASE_URL || ANTHROPIC_BASE_URL
    let res
    try {
      res = await fetch(`${anthropicBase}/v1/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': env.ANTHROPIC_API_KEY,
          'anthropic-version': ANTHROPIC_VERSION,
        },
        body: JSON.stringify({
          max_tokens: MAX_TOKENS,
          messages: [
            {
              role: 'user',
              content: [
                {
                  type: 'image',
                  source: { type: 'base64', media_type: mimeType, data: base64 },
                },
                {
                  type: 'text',
                  text: 'Extract expense info from every receipt visible in this image.',
                },
              ],
            },
          ],
          model: MODEL,
          system: SYSTEM_PROMPT,
        }),
      })
    } catch (err) {
      console.error('scan-demo upstream fetch error:', err)
      return c.json({ ok: false, error: 'upstream' }, 502)
    }

    if (!res.ok) {
      console.error('scan-demo upstream non-ok:', res.status)
      return c.json({ ok: false, error: 'upstream' }, 502)
    }

    const anthropicBody = await res.json()
    const ocr = parseFirstReceipt(anthropicBody)
    if (!ocr) {
      // Don't increment the rate-limit counter — the user got nothing
      // useful back. They get to retry without burning a quota slot.
      return c.json({ ok: false, error: 'no_receipt' }, 200)
    }

    await env.CODES_KV.put(rlKey, String(current + 1), {
      expirationTtl: ONE_DAY_SECONDS,
    })

    return c.json({
      ok: true,
      ocr,
      remaining: Math.max(0, DAILY_LIMIT - (current + 1)),
    })
  })
}
