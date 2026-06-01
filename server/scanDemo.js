// POST /scan-demo — public, email-gated OCR demo for the marketing site.
//
// Visitor uploads a receipt + enters their email; we run the same OCR
// pipeline /scan uses and deliver the parsed fields in a branded email
// with a Stripe single-use promo code and a signup CTA. The endpoint
// returns `{ ok: true }` only — the email IS the payload, not the
// JSON body.
//
// Abuse gate is per-email: max 3 successful scans per email per UTC day,
// stored in CODES_KV under the `scan-demo:<email>:<date>` prefix with
// a 24h TTL. Email format is checked but not verified — anyone can put
// in someone else's address, but the most they'll do is send that
// person 3 receipts and burn 3 promo codes.
//
// Client posts `{ email, base64, mimeType }`. The model, system prompt,
// and max_tokens are all server-controlled.

export const ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
export const ANTHROPIC_VERSION = '2023-06-01'
const STRIPE_API_BASE = 'https://api.stripe.com'
const RESEND_API_BASE = 'https://api.resend.com'

export const MODEL = 'claude-sonnet-4-6'
export const MAX_TOKENS = 2048
const DAILY_LIMIT = 3
const ONE_DAY_SECONDS = 86400
const PROMO_EXPIRY_DAYS = 30
export const MAX_BASE64_BYTES = 4 * 1024 * 1024

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/

// Keep in sync with `ocrSystemPrompt` in src/Page/Scan.elm.
export const SYSTEM_PROMPT =
  'You are a receipt and fuel-pump parser. The image is either one or many printed receipts (e.g. laid out on a table) OR the LCD/LED display on a fuel pump. A pump display has NO merchant, date, or address — just the sale total, the volume dispensed, the unit price, and sometimes the grade — so for a pump leave merchant/address/date/paymentMethod null rather than guessing. Extract expense info for EVERY receipt or pump visible and return ONLY a raw valid JSON array with no markdown, no code fences, no explanation. Each element of the array is one receipt or pump, formatted exactly: {"amount": <number: the TOTAL sale, i.e. dollars/pesos charged — labeled SALE/TOTAL/$, the settled amount; NOT the per-unit price>, "category": "<activities|camp|ferry|food|fuel|gear|lodging|medical|misc|parks|shopping|transport>", "currency": "<ISO-4217 code inferred from symbols and language, e.g. USD|CAD|MXN|GTQ|CRC; PESOS or LITROS strongly imply MXN; a bare $ with GALLONS implies USD; null if genuinely unsure>", "note": "<brief description max 50 chars>", "longNote": "<detailed description max 560 chars, include what was purchased, where, any relevant context>", "merchant": "<store name, or null on a pump display>", "address": "<street address as printed, include city and state/region when visible, or null if not visible>", "date": "<YYYY-MM-DD or null if not visible>", "paymentMethod": "<cash|credit|null>", "gallons": <fuel only, US/imperial pumps: the volume in gallons as a number, e.g. 12.345; null otherwise or when metric>, "pricePerGallon": <fuel only, US/imperial pumps: the per-gallon unit price as a number, including the trailing 9/10 cent when printed, e.g. 4.299; null otherwise or when metric>, "liters": <fuel only, metric pumps (labeled LITROS/LITRES/L): the volume in liters as a number, e.g. 38.21; null otherwise or when in gallons>, "pricePerLiter": <fuel only, metric pumps: the per-liter unit price as a number, e.g. 23.459; null otherwise or when in gallons>, "grade": "<fuel only: regular|midgrade|premium|diesel, or the grade exactly as printed; null otherwise>"}. Report volume + unit price as EITHER the gallons pair OR the liters pair — whichever the image actually shows, never both. If only one receipt/pump is visible, still return a one-element array. For paymentMethod: use cash if the receipt shows cash tendered/change; use credit if it shows card/credit/debit/visa/mastercard/chip; use null if unclear or on a pump display. Choose the best matching category. Use parks for national/state park entry fees. Use these note formats by category — fuel: "$X.XX/gal Xgal Grade" (e.g. "$4.29/gal 12.3gal Regular"); camp: "$XX/night HookupType" (e.g. "$35/night Full"); lodging: "$XX/night Xnights" (e.g. "$89/night 2nights"); ferry: "Origin→Dest vehicle|foot" (e.g. "Juneau→Haines car"); parks: "PassType ParkName" (e.g. "Day Pass Denali"); activities: "Xppl Activity" (e.g. "2ppl Kayaking"); food: "Xppl MealType" (e.g. "3ppl Dinner"); all others: brief description.'

export function utcDateKey() {
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

export function parseFirstReceipt(anthropicBody) {
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

// Mint a single-use Stripe promotion code on top of the standing coupon
// referenced by STRIPE_RECEIPT_COUPON_ID. Best-effort: any failure here
// returns null so the email still ships, just without the discount line.
async function mintPromoCode(env, email) {
  if (!env.STRIPE_SECRET_KEY || !env.STRIPE_RECEIPT_COUPON_ID) return null
  // Code is short and human-readable. Stripe enforces uppercase + length
  // constraints on `code`; uuid slice keeps it unique enough at this volume.
  const code =
    'SCAN' + crypto.randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase()
  const params = new URLSearchParams()
  params.set('coupon', env.STRIPE_RECEIPT_COUPON_ID)
  params.set('code', code)
  params.set('max_redemptions', '1')
  params.set(
    'expires_at',
    String(Math.floor(Date.now() / 1000) + PROMO_EXPIRY_DAYS * ONE_DAY_SECONDS),
  )
  params.set('metadata[source]', 'scan-demo')
  params.set('metadata[email]', email)
  try {
    const res = await fetch(`${STRIPE_API_BASE}/v1/promotion_codes`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params.toString(),
    })
    if (!res.ok) {
      console.error('stripe promo_code create:', res.status, await res.text())
      return null
    }
    const body = await res.json()
    return body.code || code
  } catch (err) {
    console.error('stripe promo_code error:', err)
    return null
  }
}

function escapeHtml(s) {
  if (s == null) return ''
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function formatField(field, value) {
  if (value == null || value === '') return '—'
  if (field === 'amount') {
    const n = Number(value)
    return Number.isFinite(n) ? '$' + n.toFixed(2) : String(value)
  }
  return String(value)
}

// Mascot SVG paths mirror src/UI/Mascot.elm. Colors are inlined hex from
// src/UI/Theme.elm because email clients don't resolve CSS vars.
const MASCOT_SVG = `<svg width="120" height="80" viewBox="0 0 120 80" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" role="presentation">
  <path d="M60 40 C40 26, 8 20, 0 29 C16 28, 38 34, 60 44Z" fill="#2d3a22"/>
  <path d="M60 40 C80 26, 112 20, 120 29 C104 28, 82 34, 60 44Z" fill="#3d4e2e"/>
  <ellipse cx="60" cy="43" rx="20" ry="7" fill="#2d3a22"/>
  <g transform="rotate(-12 42 43)">
    <path d="M42 43 L18 38" stroke="#2d3a22" stroke-width="2.5" stroke-linecap="round"/>
    <path d="M42 43 L18 48" stroke="#2d3a22" stroke-width="2" stroke-linecap="round"/>
  </g>
  <ellipse cx="76" cy="40" rx="9" ry="7" fill="#1e2818"/>
  <path d="M84 40 L96 38.5 L84 42Z" fill="#b85c38"/>
  <circle cx="79" cy="38.5" r="1.8" fill="#d4c9a8"/>
  <circle cx="79.5" cy="38.5" r="0.8" fill="#1e2818"/>
</svg>`

function buildEmailHtml({ ocr, promoCode }) {
  const fields = [
    ['Amount', formatField('amount', ocr.amount)],
    ['Merchant', formatField('merchant', ocr.merchant)],
    ['Date', formatField('date', ocr.date)],
    ['Category', formatField('category', ocr.category)],
    ['Payment', formatField('paymentMethod', ocr.paymentMethod)],
    ['Note', formatField('note', ocr.note)],
  ]
  const rows = fields
    .map(
      ([label, value]) =>
        `<tr>
          <td style="padding:12px 0;border-bottom:1px dashed rgba(212,201,168,0.7);font-family:'DM Mono',ui-monospace,Menlo,monospace;font-size:11px;letter-spacing:0.2em;text-transform:uppercase;color:#6b7c58;">${escapeHtml(label)}</td>
          <td style="padding:12px 0;border-bottom:1px dashed rgba(212,201,168,0.7);font-family:'Playfair Display',Georgia,serif;font-size:17px;font-weight:600;color:#2d3a22;text-align:right;">${escapeHtml(value)}</td>
        </tr>`,
    )
    .join('')

  const promoBlock = promoCode
    ? `<div style="margin:32px 0;padding:24px;background:#ebe5d4;border-radius:14px;text-align:center;">
        <div style="font-family:'DM Mono',ui-monospace,Menlo,monospace;font-size:11px;letter-spacing:0.22em;text-transform:uppercase;color:#b85c38;margin-bottom:10px;">A little something</div>
        <div style="font-family:'DM Mono',ui-monospace,Menlo,monospace;font-size:24px;font-weight:600;letter-spacing:0.08em;color:#2d3a22;margin-bottom:8px;">${escapeHtml(promoCode)}</div>
        <div style="font-family:'Crimson Pro',Georgia,serif;font-size:15px;font-style:italic;color:#3d4e2e;">Use this code at checkout for a discount on your first month. Single-use, expires in ${PROMO_EXPIRY_DAYS} days.</div>
      </div>`
    : ''

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Your receipt — read</title>
</head>
<body style="margin:0;padding:0;background:#faf7f0;font-family:'Crimson Pro',Georgia,serif;color:#2d3a22;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#faf7f0;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;background:#faf7f0;">
          <tr>
            <td align="center" style="padding:8px 0 24px 0;">
              ${MASCOT_SVG}
              <div style="margin-top:8px;font-family:'Playfair Display',Georgia,serif;font-size:22px;font-weight:900;letter-spacing:-0.01em;color:#2d3a22;">
                Tern<span style="color:#b85c38;">pike</span>
              </div>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 0 24px 0;">
              <div style="font-family:'DM Mono',ui-monospace,Menlo,monospace;font-size:11px;letter-spacing:0.22em;text-transform:uppercase;color:#b85c38;margin-bottom:8px;">Your scan</div>
              <h1 style="margin:0;font-family:'Playfair Display',Georgia,serif;font-size:34px;font-weight:900;line-height:1.1;letter-spacing:-0.02em;color:#2d3a22;">We read your receipt.</h1>
              <p style="margin:14px 0 0 0;font-family:'Crimson Pro',Georgia,serif;font-style:italic;font-size:17px;line-height:1.5;color:#3d4e2e;">Here's what Ternpike pulled out of it.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:24px;background:#ffffff;border-radius:14px;box-shadow:0 1px 0 rgba(212,201,168,0.6);">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                ${rows}
              </table>
            </td>
          </tr>
          <tr>
            <td>
              ${promoBlock}
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:8px 0 24px 0;">
              <a href="https://ternpike.com/#signup" style="display:inline-block;padding:14px 28px;background:#2d3a22;color:#faf7f0;text-decoration:none;border-radius:999px;font-family:'Playfair Display',Georgia,serif;font-size:16px;font-weight:700;letter-spacing:-0.01em;">Start tracking your own trips →</a>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:24px 0 8px 0;border-top:1px dashed rgba(212,201,168,0.7);">
              <div style="font-family:'Crimson Pro',Georgia,serif;font-style:italic;font-size:15px;color:#6b7c58;">Track every turn of the road.</div>
              <div style="margin-top:10px;font-family:'DM Mono',ui-monospace,Menlo,monospace;font-size:10px;letter-spacing:0.18em;text-transform:uppercase;color:#6b7c58;">
                Built on the Alaska Highway · <a href="https://ternpike.com" style="color:#6b7c58;text-decoration:underline;">ternpike.com</a>
              </div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`
}

async function sendEmail(env, { email, ocr, promoCode }) {
  const html = buildEmailHtml({ ocr, promoCode })
  const subject = ocr.merchant
    ? `Your ${ocr.merchant} receipt — read`
    : 'Your receipt — read'
  try {
    const res = await fetch(`${RESEND_API_BASE}/emails`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'Ternpike <noreply@ternpike.com>',
        to: email,
        subject,
        html,
      }),
    })
    if (!res.ok) {
      console.error('resend send:', res.status, await res.text())
      return false
    }
    return true
  } catch (err) {
    console.error('resend send error:', err)
    return false
  }
}

// Best-effort marketing-list add. Same audience as /marketing/waitlist.
async function addToAudience(env, email) {
  if (!env.RESEND_WAITLIST_API_KEY || !env.RESEND_AUDIENCE_ID) return
  try {
    await fetch(
      `${RESEND_API_BASE}/audiences/${env.RESEND_AUDIENCE_ID}/contacts`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${env.RESEND_WAITLIST_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email, unsubscribed: false }),
      },
    )
  } catch (err) {
    console.error('resend audience add:', err)
  }
}

export function registerScanDemoRoutes(app) {
  app.post('/scan-demo', async (c) => {
    const env = c.env

    if (!env.ANTHROPIC_API_KEY || !env.RESEND_API_KEY) {
      return c.json({ ok: false, error: 'misconfigured' }, 500)
    }

    let body
    try {
      body = await c.req.json()
    } catch {
      return c.json({ ok: false, error: 'bad_request' }, 400)
    }

    const { base64, email: rawEmail, mimeType } = body || {}
    if (
      typeof base64 !== 'string' ||
      typeof mimeType !== 'string' ||
      !mimeType.startsWith('image/') ||
      typeof rawEmail !== 'string'
    ) {
      return c.json({ ok: false, error: 'bad_request' }, 400)
    }
    const email = rawEmail.toLowerCase().trim()
    if (!EMAIL_RE.test(email)) {
      return c.json({ ok: false, error: 'invalid_email' }, 400)
    }
    if (base64.length > MAX_BASE64_BYTES) {
      return c.json({ ok: false, error: 'too_large' }, 413)
    }

    const rlKey = `scan-demo:${email}:${utcDateKey()}`
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
      // Quota not consumed — the user got nothing useful back.
      return c.json({ ok: false, error: 'no_receipt' }, 200)
    }

    const promoCode = await mintPromoCode(env, email)

    const sent = await sendEmail(env, { email, ocr, promoCode })
    if (!sent) return c.json({ ok: false, error: 'email' }, 502)

    await addToAudience(env, email)

    await env.CODES_KV.put(rlKey, String(current + 1), {
      expirationTtl: ONE_DAY_SECONDS,
    })

    return c.json({
      ok: true,
      remaining: Math.max(0, DAILY_LIMIT - (current + 1)),
    })
  })
}
