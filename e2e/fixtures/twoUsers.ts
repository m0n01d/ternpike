import { test as base, type BrowserContext } from '@playwright/test'

import { stubAuthCreds } from '../utils/auth-stub'
import { makeResendClient, type ResendMockClient } from '../utils/resend'
import { interceptPouchdbCdn, seedPouchDB, type SeedData } from '../utils/seed'
import { readHarnessState } from '../utils/state'

import type { CouchClient } from '../utils/couch'

export type Tier = 'Fledgling' | 'Fly' | 'Trailblazer'

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

const buildContext = async (
  browser: import('@playwright/test').Browser,
  spec: UserSpec,
  viewport: { height: number; width: number },
): Promise<BrowserContext> => {
  const ctx = await browser.newContext({ viewport })
  await interceptPouchdbCdn(ctx)
  await stubAuthCreds(ctx, {
    dbName: `ternpike-${spec.email.replace(/[^a-z0-9]/gi, '-').toLowerCase()}`,
    email: spec.email,
    password: 'e2e-stub-password',
  })
  if (spec.seed) {
    await seedPouchDB(ctx, spec.seed)
  }
  return ctx
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
      tier: 'Fly',
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
      tier: 'Fledgling',
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
