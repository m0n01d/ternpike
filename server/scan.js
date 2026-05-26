// POST /scan — hosted Anthropic OCR proxy for paid-tier users.
//
// Ternpike's ANTHROPIC_API_KEY lives in the Worker secret store and never
// reaches the browser. Paid users (Osprey, Trailblazer) hit this endpoint
// instead of calling Anthropic directly, so the key stays server-side.
//
// The request body is passed through unchanged — it must be a valid
// Anthropic /v1/messages payload (`model`, `system`, `messages` with
// base64 image content). `max_tokens` is capped at 4096 server-side as a
// sanity bound regardless of what the client sends.
//
// Do NOT use the Anthropic Node SDK — workerd doesn't populate `process.env`
// at module-load time, so any SDK that reads env there silently gets
// undefined. Raw `fetch` reads `env.ANTHROPIC_API_KEY` from the Hono context
// at request time, which is correct.

import { authenticateCaller, getTier, isPaidTier } from './auth.js'

/**
 * Mirror of the Elm `Data.Scan.needsReview` predicate.
 * Returns true when any structural field — amount, merchant, or date — is
 * absent from the OCR result. Used by server-side scan notification logic
 * (see #223) to flag items that need user attention.
 *
 * @param {{ amount?: unknown, merchant?: unknown, date?: unknown }} ocr
 * @returns {boolean}
 */
export function needsReview(ocr) {
  return ocr.amount == null || ocr.merchant == null || ocr.date == null
}

const ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
const ANTHROPIC_VERSION = '2023-06-01'
const MAX_TOKENS_CAP = 4096

export function registerScanRoutes(app) {
  app.post('/scan', async (c) => {
    const env = c.env

    const caller = await authenticateCaller(c)
    if (!caller) return c.json({ ok: false, error: 'unauthorized' }, 401)

    const tier = await getTier(env, caller.email)
    if (!isPaidTier(tier)) {
      return c.json({ ok: false, error: 'paid_only' }, 402)
    }

    let body
    try {
      body = await c.req.json()
    } catch {
      return c.json({ ok: false, error: 'bad_request' }, 400)
    }

    // Enforce the max_tokens cap — pass the client's value through if it's
    // already within bounds, otherwise clamp to the cap.
    if (
      typeof body.max_tokens !== 'number' ||
      body.max_tokens > MAX_TOKENS_CAP
    ) {
      body = { ...body, max_tokens: MAX_TOKENS_CAP }
    }

    const anthropicBase =
      env.ANTHROPIC_BASE_URL || ANTHROPIC_BASE_URL

    let res
    try {
      res = await fetch(`${anthropicBase}/v1/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': env.ANTHROPIC_API_KEY,
          'anthropic-version': ANTHROPIC_VERSION,
        },
        body: JSON.stringify(body),
      })
    } catch (err) {
      console.error('scan upstream fetch error:', err)
      return c.json({ ok: false, error: 'upstream' }, 502)
    }

    // Return Anthropic's response verbatim — status + body. The Elm decoder
    // on the client side already handles Anthropic's response shape.
    const responseBody = await res.text()
    return new Response(responseBody, {
      status: res.status,
      headers: { 'Content-Type': 'application/json' },
    })
  })
}
