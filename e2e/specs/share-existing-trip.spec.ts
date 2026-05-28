/**
 * E2E for #323 — "Share this trip": Alice (Osprey) promotes an existing
 * PERSONAL trip into a shared trip from the Trips header and invites Bob.
 *
 * Harness shape (see e2e/README.md + create-sharedtrip.spec.ts): PouchDB live
 * sync still targets production `couch.ternpike.com`, so client-seeded docs
 * never reach the test CouchDB and cross-user sync can't be observed here
 * (that's why shared-roundtrip.spec stays on test.fixme). The adopt flow,
 * however, is *server-authoritative*: the Share button fires real
 * `POST /sharedtrips` + `POST /sharedtrips/:id/adopt-trip` at the local
 * Worker, which moves the trip's docs between databases in the test CouchDB.
 *
 * So this spec asserts the testable invariant end-to-end:
 *   real Share UI → real create + adopt + invite →
 *     - the trip + its expenses + amendment now live in the shared-trip DB,
 *     - they're gone from Alice's personal DB (the hard-delete),
 *     - Bob received an invite email.
 *
 * The client PouchDB holds the same trip id (fixture seed) so the Share
 * button renders; the test CouchDB holds the same id (admin seed) so the
 * server can move it.
 */

import { test, expect } from '../fixtures/twoUsers'
import { readHarnessState } from '../utils/state'

import type { Page } from '@playwright/test'

const ALICE_EMAIL = 'alice@test.ternpike.com'
const BOB_EMAIL = 'bob@test.ternpike.com'

// A pinned trip id shared by the client PouchDB seed and the server CouchDB
// seed, plus the expenses + amendment the adopt endpoint must carry over.
const TRIP_ID = 'trip::2026-03-01T00:00:00.000Z::adoptme0'
const EXP_ID = 'expense::2026-03-02T00:00:00.000Z::exp00001'
const EXP_ID2 = 'expense::2026-03-03T00:00:00.000Z::exp00002'
const AMEND_ID = `amend::${EXP_ID}::amd00001`

const personalDbName = (email: string): string =>
  'ternpike-' + email.toLowerCase().replace(/[^a-z0-9_$()+/-]/g, '-')

const adminFetch = (path: string, init: RequestInit = {}): Promise<Response> => {
  const state = readHarnessState()
  const auth =
    'Basic ' +
    Buffer.from(`${state.couchAdminUser}:${state.couchAdminPassword}`).toString(
      'base64',
    )
  return fetch(`${state.couchUrl}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: auth,
      ...(init.headers || {}),
    },
  })
}

const setServerTier = async (
  email: string,
  tier: 'tern' | 'osprey' | 'trailblazer',
): Promise<void> => {
  const state = readHarnessState()
  const res = await fetch(
    `http://127.0.0.1:${state.serverPort}/sharedtrips/test/tier-changed`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-webhook-secret': 'e2e-webhook-secret',
      },
      body: JSON.stringify({ email, tier }),
    },
  )
  if (!res.ok) {
    throw new Error(`set tier ${email}→${tier}: ${res.status} ${await res.text()}`)
  }
}

/** Seed Alice's server-side personal DB with the trip + expenses + amendment. */
const seedCouchTrip = async (email: string): Promise<void> => {
  const db = personalDbName(email)
  // Recreate the personal DB fresh so the pinned doc ids never conflict across
  // runs/retries (the docs use fixed _ids, and a prior run leaves tombstones).
  await adminFetch(`/${db}`, { method: 'DELETE' })
  const create = await adminFetch(`/${db}`, { method: 'PUT' })
  if (!create.ok) {
    throw new Error(`personal db PUT ${create.status} ${await create.text()}`)
  }
  const docs = [
    {
      _id: TRIP_ID,
      type: 'trip',
      name: 'Road Trip',
      description: '',
      coverPhotoUrl: '',
      budget: 0,
      startDate: '2026-03-01',
      endDate: '2026-03-10',
    },
    {
      _id: EXP_ID,
      type: 'expense',
      tripId: TRIP_ID,
      amount: 12,
      category: 'Food',
      date: '2026-03-02',
      merchant: 'Cafe',
      note: 'lunch',
      longNote: '',
      lat: null,
      lon: null,
      createdAt: '2026-03-02T00:00:00.000Z',
    },
    {
      _id: EXP_ID2,
      type: 'expense',
      tripId: TRIP_ID,
      amount: 40,
      category: 'Fuel',
      date: '2026-03-03',
      merchant: 'Shell',
      note: 'gas',
      longNote: '',
      lat: null,
      lon: null,
      createdAt: '2026-03-03T00:00:00.000Z',
    },
    {
      _id: AMEND_ID,
      type: 'amend',
      targetId: EXP_ID,
      amount: 15,
      createdAt: '2026-03-04T00:00:00.000Z',
    },
  ]
  const res = await adminFetch(`/${db}/_bulk_docs`, {
    method: 'POST',
    body: JSON.stringify({ docs }),
  })
  if (!res.ok) throw new Error(`seed _bulk_docs ${res.status} ${await res.text()}`)
  const rows = (await res.json()) as { ok?: boolean; error?: string }[]
  const failed = rows.filter((r) => !r.ok)
  if (failed.length) throw new Error(`seed failures ${JSON.stringify(failed)}`)
}

const couchStatus = async (db: string, id: string): Promise<number> => {
  const res = await adminFetch(`/${db}/${encodeURIComponent(id)}`)
  return res.status
}

/** Resolve the status (+ flockId, for create) of the first matching POST. */
const capturePost = (
  page: Page,
  matchUrl: (url: string) => boolean,
): Promise<{ status: number; flockId?: string }> =>
  new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error('no matching POST response in time')),
      20_000,
    )
    page.on('response', async (res) => {
      const req = res.request()
      if (req.method() !== 'POST' || !matchUrl(req.url())) return
      clearTimeout(timer)
      let body: { flockId?: string } = {}
      try {
        body = JSON.parse((await res.text()) || '{}')
      } catch {
        // non-JSON body — status is all we need
      }
      resolve({ status: res.status(), flockId: body.flockId })
    })
  })

test.use({
  aliceSpec: {
    email: ALICE_EMAIL,
    seed: {
      trips: [
        {
          id: TRIP_ID,
          name: 'Road Trip',
          startDate: '2026-03-01',
          endDate: '2026-03-10',
        },
      ],
    },
    tier: 'Osprey',
  },
})

test.beforeAll(async () => {
  await setServerTier(ALICE_EMAIL, 'osprey')
})

test.beforeEach(async ({ resendMock }) => {
  await resendMock.clear()
})

test('Alice shares a personal trip: data moves to the shared DB and Bob is invited', async ({
  aliceContext,
  resendMock,
}) => {
  // The OpenSharedTrip port opens a shared-trip handle that live-syncs against
  // production couch.ternpike.com (unreachable / not the test couch). Abort
  // those requests so they fail as benign network errors rather than hanging
  // or hitting real infra.
  await aliceContext.route('https://couch.ternpike.com/**', (r) => r.abort())

  // Seed the server-side personal DB with the trip + history to be adopted.
  await seedCouchTrip(ALICE_EMAIL)

  const page = await aliceContext.newPage()
  const created = capturePost(page, (u) => u.endsWith('/sharedtrips'))
  const adopted = capturePost(page, (u) => u.endsWith('/adopt-trip'))

  await page.goto('/trips')

  // The Share affordance renders only once the personal trip is loaded and
  // selected, so waiting for it doubles as the "trips page is ready" signal.
  const shareButton = page.getByRole('button', { name: 'Share trip' })
  await expect(shareButton).toBeVisible({ timeout: 30_000 })
  await shareButton.click()
  await expect(page.getByText('Share this trip')).toBeVisible()

  // Invite Bob (Enter commits the chip), then Share.
  await page.getByPlaceholder('name@example.com').fill(BOB_EMAIL)
  await page.keyboard.press('Enter')
  await page.getByRole('button', { name: 'Share', exact: true }).click()

  const createdRes = await created
  expect(createdRes.flockId, 'create returned a flockId').toBeTruthy()
  const adoptedRes = await adopted
  expect(adoptedRes.status, 'adopt-trip returned 200').toBe(200)

  // Success toast + modal closed.
  await expect(page.getByText('Trip shared. Syncing to everyone…')).toBeVisible({
    timeout: 5_000,
  })
  await expect(page.getByText('Share this trip')).toBeHidden()

  // The server moved every doc into the shared DB and removed it from personal.
  const sharedDb = `sharedtrip-${createdRes.flockId}`
  const personalDb = personalDbName(ALICE_EMAIL)
  for (const id of [TRIP_ID, EXP_ID, EXP_ID2, AMEND_ID]) {
    expect(await couchStatus(sharedDb, id), `${id} present in shared DB`).toBe(200)
    expect(
      await couchStatus(personalDb, id),
      `${id} removed from personal DB`,
    ).toBe(404)
  }

  // Bob received the invite email.
  await expect
    .poll(async () => await resendMock.lastSentTo(BOB_EMAIL), { timeout: 5_000 })
    .not.toBeNull()
  const captured = await resendMock.lastSentTo(BOB_EMAIL)
  expect((captured?.text ?? '') + (captured?.html ?? '')).toContain(
    '/sharedtrips/join?token=',
  )
})
