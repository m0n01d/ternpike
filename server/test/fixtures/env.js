// In-memory implementations of the Cloudflare bindings the worker reads from
// `c.env`. Just enough surface area for the endpoints under test.

export function memoryKv() {
  const store = new Map()
  return {
    async get(key) {
      const e = store.get(key)
      if (!e) return null
      if (e.expiresAt && e.expiresAt <= Date.now()) {
        store.delete(key)
        return null
      }
      return e.value
    },
    // Mimic the Workers KV `list({ prefix, cursor, limit })` shape closely
    // enough for the cron sweep to iterate. Returns one page worth of keys
    // matching `prefix`, with a cursor when more remain. Keys are sorted
    // lexicographically (matches real KV ordering).
    async list({ prefix = '', cursor, limit = 1000 } = {}) {
      const all = Array.from(store.keys())
        .filter((k) => k.startsWith(prefix))
        .sort()
      const startIdx = cursor ? Number(cursor) : 0
      const slice = all.slice(startIdx, startIdx + limit)
      const nextIdx = startIdx + slice.length
      const list_complete = nextIdx >= all.length
      return {
        cursor: list_complete ? undefined : String(nextIdx),
        keys: slice.map((name) => ({ name })),
        list_complete,
      }
    },
    async put(key, value, opts) {
      const expiresAt = opts?.expirationTtl
        ? Date.now() + opts.expirationTtl * 1000
        : null
      store.set(key, { value, expiresAt })
    },
    async delete(key) {
      store.delete(key)
    },
    _dump: () => Array.from(store.entries()),
  }
}

// Capture every Resend email send instead of contacting the real API. We
// patch `globalThis.fetch` so the Resend SDK (which uses fetch under the
// hood) hits us first; everything else falls through to the real network.
export function installResendCapture() {
  const sent = []
  const realFetch = globalThis.fetch
  globalThis.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input.url
    if (url.startsWith('https://api.resend.com')) {
      let body = null
      try {
        body = init?.body ? JSON.parse(init.body) : null
      } catch {
        body = init?.body
      }
      sent.push({ url, body })
      return new Response(
        JSON.stringify({ id: 'mock-email-id' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    }
    return realFetch(input, init)
  }
  return {
    sent,
    reset: () => {
      sent.length = 0
    },
    uninstall: () => {
      globalThis.fetch = realFetch
    },
  }
}

export function buildEnv(couch, overrides = {}) {
  return {
    COUCH_URL: couch.baseUrl,
    COUCH_ADMIN_USER: couch.adminUser,
    COUCH_ADMIN_PASS: couch.adminPass,
    SERVER_SECRET: 'test-server-secret-do-not-use-in-production',
    RESEND_API_KEY: 'test-resend-key',
    TIER_WEBHOOK_SECRET: 'test-webhook-secret',
    CODES_KV: memoryKv(),
    TIERS_KV: memoryKv(),
    INVITE_KV: memoryKv(),
    ...overrides,
  }
}
