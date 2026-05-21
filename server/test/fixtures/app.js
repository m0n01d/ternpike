// Drive the worker the way Cloudflare would — by calling `app.fetch(req,
// env, ctx)`. We import the real `index.js` so the test exercises the full
// route table, CORS, and the production wiring.

import worker from '../../index.js'

const BASE = 'https://test.local'

function makeCtx() {
  const pending = []
  return {
    waitUntil: (p) => {
      pending.push(p)
    },
    passThroughOnException: () => {},
    _pending: pending,
  }
}

export async function request(env, method, path, { headers = {}, body } = {}) {
  const init = {
    method,
    headers: { ...headers },
  }
  if (body !== undefined) {
    init.body = typeof body === 'string' ? body : JSON.stringify(body)
    if (!init.headers['Content-Type'] && !init.headers['content-type']) {
      init.headers['Content-Type'] = 'application/json'
    }
  }
  const req = new Request(`${BASE}${path}`, init)
  const ctx = makeCtx()
  const res = await worker.fetch(req, env, ctx)
  let parsed
  const text = await res.text()
  try {
    parsed = text.length ? JSON.parse(text) : null
  } catch {
    parsed = text
  }
  return { status: res.status, body: parsed, headers: res.headers }
}
