// Negative + happy-path coverage for `POST /scan` (#215).
//
// No CouchDB dependency — the scan endpoint only touches TIERS_KV and the
// Anthropic API, both of which we stub in-process. Each test gets a fresh
// env so KV state doesn't leak between tests.
//
// Three core cases per spec:
//   1. Unauthenticated → 401
//   2. Tern (free) JWT → 402 with { error: 'paid_only' }
//   3. Osprey (paid) → 200, Anthropic upstream called with correct headers

import { afterEach, beforeEach, describe, test } from 'node:test'
import assert from 'node:assert/strict'

import { request } from '../fixtures/app.js'
import { basicAuthHeader, tamperedAuthHeader } from '../fixtures/auth.js'
import { memoryKv } from '../fixtures/env.js'

const ALICE = 'alice@test.ternpike.com'
const BOB = 'bob@test.ternpike.com'
const SERVER_SECRET = 'test-server-secret-do-not-use-in-production'

// Stub Anthropic base URL — intercepted by the mock fetch below.
const ANTHROPIC_BASE = 'https://anthropic.test.local'

const VALID_SCAN_BODY = {
  model: 'claude-opus-4-5',
  max_tokens: 1024,
  system: 'Extract receipt data.',
  messages: [
    {
      role: 'user',
      content: [
        {
          type: 'image',
          source: {
            type: 'base64',
            media_type: 'image/jpeg',
            data: 'iVBORw0KGgo=',
          },
        },
      ],
    },
  ],
}

let env
let anthropicCalls
let anthropicHandler
let realFetch

function installAnthropicMock() {
  anthropicCalls = []
  realFetch = globalThis.fetch
  globalThis.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input.url
    if (url.startsWith(ANTHROPIC_BASE)) {
      anthropicCalls.push({ url, init })
      return anthropicHandler(url, init)
    }
    return realFetch(input, init)
  }
}

function uninstallAnthropicMock() {
  globalThis.fetch = realFetch
}

function anthropicOk(content = 'Receipt total: $12.34') {
  return new Response(
    JSON.stringify({
      id: 'msg_stub',
      type: 'message',
      role: 'assistant',
      content: [{ type: 'text', text: content }],
      model: 'claude-opus-4-5',
      stop_reason: 'end_turn',
      usage: { input_tokens: 100, output_tokens: 20 },
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  )
}

beforeEach(async () => {
  env = {
    SERVER_SECRET,
    ANTHROPIC_API_KEY: 'test-anthropic-key',
    ANTHROPIC_BASE_URL: ANTHROPIC_BASE,
    TIERS_KV: memoryKv(),
  }
  // Alice is Osprey (paid), Bob stays Tern (default).
  await env.TIERS_KV.put(ALICE.toLowerCase(), 'osprey')
  anthropicHandler = () => anthropicOk()
  installAnthropicMock()
})

afterEach(() => {
  uninstallAnthropicMock()
})

const authed = async (email) => ({
  Authorization: await basicAuthHeader(email, SERVER_SECRET),
})

describe('POST /scan', () => {
  test('unauthenticated request returns 401', async () => {
    const res = await request(env, 'POST', '/scan', {
      body: VALID_SCAN_BODY,
    })
    assert.equal(res.status, 401)
    assert.equal(anthropicCalls.length, 0)
  })

  test('tampered basic-auth password returns 401', async () => {
    const res = await request(env, 'POST', '/scan', {
      headers: { Authorization: tamperedAuthHeader(ALICE) },
      body: VALID_SCAN_BODY,
    })
    assert.equal(res.status, 401)
    assert.equal(anthropicCalls.length, 0)
  })

  test('Tern caller is rejected with 402 paid_only', async () => {
    const res = await request(env, 'POST', '/scan', {
      headers: await authed(BOB),
      body: VALID_SCAN_BODY,
    })
    assert.equal(res.status, 402)
    assert.equal(res.body.error, 'paid_only')
    assert.equal(anthropicCalls.length, 0)
  })

  test('Osprey caller receives 200 and Anthropic upstream is called', async () => {
    const res = await request(env, 'POST', '/scan', {
      headers: await authed(ALICE),
      body: VALID_SCAN_BODY,
    })
    assert.equal(res.status, 200)
    assert.equal(anthropicCalls.length, 1)
    // Response body is Anthropic's verbatim JSON.
    assert.equal(res.body.type, 'message')
    assert.equal(res.body.role, 'assistant')
  })

  test('Trailblazer caller also receives 200', async () => {
    await env.TIERS_KV.put(ALICE.toLowerCase(), 'trailblazer')
    const res = await request(env, 'POST', '/scan', {
      headers: await authed(ALICE),
      body: VALID_SCAN_BODY,
    })
    assert.equal(res.status, 200)
    assert.equal(anthropicCalls.length, 1)
  })

  test('upstream call includes x-api-key and anthropic-version headers', async () => {
    await request(env, 'POST', '/scan', {
      headers: await authed(ALICE),
      body: VALID_SCAN_BODY,
    })
    assert.equal(anthropicCalls.length, 1)
    const headers = anthropicCalls[0].init.headers
    assert.equal(headers['x-api-key'], 'test-anthropic-key')
    assert.equal(headers['anthropic-version'], '2023-06-01')
  })

  test('client max_tokens above 4096 is clamped to 4096', async () => {
    await request(env, 'POST', '/scan', {
      headers: await authed(ALICE),
      body: { ...VALID_SCAN_BODY, max_tokens: 9999 },
    })
    assert.equal(anthropicCalls.length, 1)
    const sentBody = JSON.parse(anthropicCalls[0].init.body)
    assert.equal(sentBody.max_tokens, 4096)
  })

  test('client max_tokens within bound is passed through unchanged', async () => {
    await request(env, 'POST', '/scan', {
      headers: await authed(ALICE),
      body: { ...VALID_SCAN_BODY, max_tokens: 512 },
    })
    assert.equal(anthropicCalls.length, 1)
    const sentBody = JSON.parse(anthropicCalls[0].init.body)
    assert.equal(sentBody.max_tokens, 512)
  })

  test('Anthropic 4xx is returned verbatim to the caller', async () => {
    anthropicHandler = () =>
      new Response(
        JSON.stringify({ type: 'error', error: { type: 'invalid_request_error', message: 'bad body' } }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      )
    const res = await request(env, 'POST', '/scan', {
      headers: await authed(ALICE),
      body: VALID_SCAN_BODY,
    })
    assert.equal(res.status, 400)
  })

  test('Anthropic network failure returns 502', async () => {
    anthropicHandler = () => { throw new Error('network timeout') }
    const res = await request(env, 'POST', '/scan', {
      headers: await authed(ALICE),
      body: VALID_SCAN_BODY,
    })
    assert.equal(res.status, 502)
    assert.equal(res.body.error, 'upstream')
  })

  test('non-JSON request body returns 400', async () => {
    const res = await request(env, 'POST', '/scan', {
      headers: { ...(await authed(ALICE)), 'Content-Type': 'text/plain' },
      body: 'not json',
    })
    assert.equal(res.status, 400)
    assert.equal(res.body.error, 'bad_request')
  })
})
