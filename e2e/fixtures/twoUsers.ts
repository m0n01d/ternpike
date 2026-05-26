import { createHmac } from 'node:crypto'

import { test as base, type BrowserContext } from '@playwright/test'

import { stubAuthCreds } from '../utils/auth-stub'
import { makeResendClient, type ResendMockClient } from '../utils/resend'
import { interceptPouchdbCdn, seedPouchDB, type SeedData } from '../utils/seed'
import { readHarnessState } from '../utils/state'

import type { CouchClient } from '../utils/couch'

export type Tier = 'Osprey' | 'Tern' | 'Trailblazer'

export type UserSpec = {
  email: string
  seed?: SeedData
  tier: Tier
}

type Options = {
  aliceSpec: UserSpec
  bobSpec: UserSpec
}

type Fixtures = {
  aliceContext: BrowserContext
  bobContext: BrowserContext
  couchAdmin: CouchClient
  resendMock: ResendMockClient
}

/**
 * Mirrors `server/flocks.js#derivePassword`. The auth Worker accepts HTTP
 * Basic creds where the password is `HMAC-SHA256("couch:" + email, SERVER_SECRET)`
 * hex-encoded, first 32 chars. Stub credentials must match this so the
 * spec's create/invite calls (proxied to the local auth server) pass the
 * `authenticateCaller` check.
 */
export const deriveStubPassword = (email: string, serverSecret: string): string =>
  createHmac('sha256', serverSecret)
    .update('couch:' + email.toLowerCase())
    .digest('hex')
    .slice(0, 32)

/**
 * A trivially-named placeholder trip that exists solely to keep Elm's
 * empty-trips bounce (`src/Main.elm:943-946`) from firing during boot.
 * When `selectedTrips == Nothing` and the route isn't `RouteJoinSharedTrip`,
 * `Main.elm` does `Nav.replaceUrl … "trips"` — which silently knocks any
 * spec that lands on `/settings` (or any other non-trip route) back to
 * `/trips`, producing a mystifying "element not found" failure on whatever
 * settings-page assertion follows. Specs that override `aliceSpec` /
 * `bobSpec` without providing their own `seed` get this trip injected
 * automatically. Specs that genuinely want an empty PouchDB (e.g. those
 * that hydrate trips via CouchDB shared-trip sync after the context is
 * built) opt out explicitly with `seed: { trips: [] }`.
 */
const harnessPlaceholderTrip = {
  description: '',
  endDate: '2026-01-31',
  name: 'harness placeholder',
  startDate: '2026-01-01',
} as const

const resolveSeed = (seed: SeedData | undefined): SeedData =>
  seed === undefined ? { trips: [harnessPlaceholderTrip] } : seed

const buildContext = async (
  browser: import('@playwright/test').Browser,
  spec: UserSpec,
  viewport: { height: number; width: number },
): Promise<BrowserContext> => {
  const state = readHarnessState()
  const ctx = await browser.newContext({ viewport })
  await interceptPouchdbCdn(ctx)
  await routeApiTernpikeToLocal(ctx, state.serverPort)
  await stubAuthCreds(ctx, {
    dbName: `ternpike-${spec.email.replace(/[^a-z0-9]/gi, '-').toLowerCase()}`,
    email: spec.email,
    password: deriveStubPassword(spec.email, state.serverSecret),
    tier: spec.tier.toLowerCase(),
  })
  await seedPouchDB(ctx, resolveSeed(spec.seed))
  return ctx
}

/**
 * Rewrites the production auth host to the locally-bound wrangler dev port
 * for every browser-side request the Elm `Http.FlockApi` module makes. The
 * production URL is hard-coded in `src/Http/FlockApi.elm`; rather than
 * plumbing a baseUrl override through the app just for tests, we intercept
 * at the browser. Path + body + headers are preserved.
 */
const routeApiTernpikeToLocal = async (
  ctx: BrowserContext,
  serverPort: number,
): Promise<void> => {
  await ctx.route('https://api.ternpike.com/**', async (route) => {
    const req = route.request()
    const target = req
      .url()
      .replace('https://api.ternpike.com', `http://127.0.0.1:${serverPort}`)
    const response = await ctx.request.fetch(target, {
      method: req.method(),
      headers: req.headers(),
      data: req.postDataBuffer() ?? undefined,
    })
    await route.fulfill({
      status: response.status(),
      headers: response.headers(),
      body: await response.body(),
    })
  })
}

export const test = base.extend<Options & Fixtures>({
  aliceSpec: [
    {
      email: 'alice@test.ternpike.com',
      seed: {
        trips: [
          {
            description: '',
            endDate: '2026-01-31',
            name: 'Alice Test Trip',
            startDate: '2026-01-01',
          },
        ],
      },
      tier: 'Osprey',
    },
    { option: true },
  ],
  bobSpec: [
    {
      email: 'bob@test.ternpike.com',
      seed: {
        trips: [
          {
            description: '',
            endDate: '2026-01-31',
            name: 'Bob Test Trip',
            startDate: '2026-01-01',
          },
        ],
      },
      tier: 'Tern',
    },
    { option: true },
  ],
  aliceContext: async ({ browser, aliceSpec }, use) => {
    const ctx = await buildContext(browser, aliceSpec, {
      height: 844,
      width: 390,
    })
    await use(ctx)
    await ctx.close()
  },
  bobContext: async ({ browser, bobSpec }, use) => {
    const ctx = await buildContext(browser, bobSpec, {
      height: 844,
      width: 390,
    })
    await use(ctx)
    await ctx.close()
  },
  resendMock: async ({}, use) => {
    const state = readHarnessState()
    await use(makeResendClient(state.resendMockUrl))
  },
  couchAdmin: async ({}, use) => {
    const state = readHarnessState()
    const url = state.couchUrl
    const auth =
      'Basic ' +
      Buffer.from(`${state.couchAdminUser}:${state.couchAdminPassword}`).toString(
        'base64',
      )
    const request: CouchClient['request'] = (path, init = {}) =>
      fetch(`${url}${path}`, {
        ...init,
        headers: {
          'Content-Type': 'application/json',
          Authorization: auth,
          ...(init.headers || {}),
        },
      })
    await use({
      url,
      request,
      allDbs: async () => {
        const res = await request('/_all_dbs')
        if (!res.ok) {
          throw new Error(`/_all_dbs failed: ${res.status} ${await res.text()}`)
        }
        return (await res.json()) as string[]
      },
    })
  },
})

export const expect = test.expect
