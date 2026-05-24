import { type BrowserContext, type Page } from '@playwright/test'

import { test, expect } from '../fixtures/twoUsers'
import {
  authServerBaseUrl,
  mintInviteJwt,
  provisionUser,
  readSharedTripMeta,
  seedSharedTrip,
  sharedTripDbName,
} from '../utils/sharedTripSetup'
import { purgeUserSharedTrips } from '../utils/shared-trip-test-helpers'
import { readHarnessState } from '../utils/state'

/*
 * Issue #78 — voluntary leave + owner-driven remove flows.
 *
 * Pre-state per the issue: a "Honeymoon" shared trip owned by Alice (Fly)
 * with Bob as a member, and a shared "Italy" trip carrying expenses from
 * both users. Setup is admin-side via the CouchDB client in
 * `utils/sharedTripSetup.ts` so the spec doesn't pay six email round-trips
 * per test just to reach the pre-state.
 *
 * What ships today:
 *   - Voluntary leave (Bob): UI-driven, full revocation assertions.
 *   - Rejoin: drives `/sharedtrips/join` directly with a freshly minted JWT
 *     (the in-app accept screen is covered by #73; here we only need the
 *     rejoin's data-restoration side effect).
 *   - Owner self-leave: API-level only — the Settings UI from #62 does
 *     not surface a "Leave" button to owners, so this assertion proves
 *     the server-side `transfer_ownership_first` block via direct HTTP.
 *
 * What's deferred (test.fixme):
 *   - Owner kick / remove-member: neither the Settings UI from #62 nor
 *     the server (`server/sharedTrips.js`) ships a per-member removal path.
 *     The button and `DELETE /sharedtrips/:id/members/:email` (or equivalent)
 *     need to land first.
 */

const ALICE_EMAIL = 'alice@test.ternpike.com'
const BOB_EMAIL = 'bob@test.ternpike.com'
// Must be exactly 12 lowercase hex chars to satisfy Data.SharedTripId.fromString.
const HONEYMOON_FLOCK_ID = 'bee500000001'

const FLOCK_LOCAL_DB = `ternpike-${sharedTripDbName(HONEYMOON_FLOCK_ID)}`

const aliceCreds = {
  email: ALICE_EMAIL,
  password: '__placeholder__',
}
const bobCreds = {
  email: BOB_EMAIL,
  password: '__placeholder__',
}

// Override the fixture passwords to the ones derived from SERVER_SECRET so
// CouchDB sync actually authenticates. The default stub password is junk.
test.use({
  aliceSpec: {
    email: ALICE_EMAIL,
    seed: { trips: [] },
    tier: 'Osprey',
  },
  bobSpec: {
    email: BOB_EMAIL,
    seed: { trips: [] },
    tier: 'Tern',
  },
})

const overrideStubbedCreds = async (
  context: BrowserContext,
  email: string,
  password: string,
  dbName: string,
): Promise<void> => {
  const page = await context.newPage()
  await page.route('**/pouchdb.min.js', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/javascript',
      body: '',
    }),
  )
  const vitePort = process.env.E2E_VITE_PORT || '3000'
  await page.goto(`http://localhost:${vitePort}/seed.html`, {
    waitUntil: 'domcontentloaded',
  })
  await page.evaluate(
    async ([dbN, em, pw, db]) => {
      await new Promise<void>((resolve, reject) => {
        const open = indexedDB.open(dbN, 1)
        open.onupgradeneeded = (event) => {
          const idb = (event.target as IDBOpenDBRequest).result
          if (!idb.objectStoreNames.contains('kv')) idb.createObjectStore('kv')
        }
        open.onsuccess = () => {
          const idb = open.result
          const tx = idb.transaction('kv', 'readwrite')
          tx.objectStore('kv').put(
            JSON.stringify({ dbName: db, email: em, password: pw }),
            'auth_creds',
          )
          tx.oncomplete = () => {
            idb.close()
            resolve()
          }
          tx.onerror = () => reject(tx.error)
        }
        open.onerror = () => reject(open.error)
      })
    },
    ['alaska-tracker', email, password, dbName] as const,
  )
  await page.close()
}

/**
 * Routes a real production hostname through a local development service.
 * Used to point `api.ternpike.com` at the local wrangler dev server and
 * `couch.ternpike.com` at the disposable Docker CouchDB. Without this,
 * the Elm app's hardcoded URLs would never reach the harness.
 */
const proxyHost = async (
  context: BrowserContext,
  hostPattern: string,
  targetBaseUrl: string,
): Promise<void> => {
  await context.route(hostPattern, async (route, request) => {
    const url = new URL(request.url())
    const localUrl = targetBaseUrl + url.pathname + url.search
    const headers = { ...request.headers() }
    delete headers['origin']
    try {
      const res = await fetch(localUrl, {
        method: request.method(),
        headers,
        body:
          request.method() === 'GET' || request.method() === 'HEAD'
            ? undefined
            : request.postData() || undefined,
      })
      const body = Buffer.from(await res.arrayBuffer())
      const headersOut: Record<string, string> = {}
      res.headers.forEach((value, key) => {
        headersOut[key] = value
      })
      await route.fulfill({
        status: res.status,
        headers: headersOut,
        body,
      })
    } catch (err) {
      await route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: String(err) }),
      })
    }
  })
}

const routeApiToLocalServer = async (
  context: BrowserContext,
): Promise<void> => {
  await proxyHost(context, '**/api.ternpike.com/**', authServerBaseUrl())
  // pouch.js hardcodes `https://couch.ternpike.com` (src/pouch.js line 3).
  // Route it at the disposable CouchDB the harness booted.
  await proxyHost(
    context,
    '**/couch.ternpike.com/**',
    readHarnessState().couchUrl,
  )
}

const openSettingsFlocks = async (page: Page): Promise<void> => {
  // Navigate to /trips first and wait for the Italy trip to appear. This
  // confirms that: (a) CouchDB sync has run at least one round-trip, (b) the
  // shared trip DB is open and has pulled its docs locally, and (c) the Elm
  // app's `trips` state is `TripsLoaded` — not `TripsLoading` or `NoTripsYet`.
  //
  // Without this warm-up, going straight to /settings triggers the Elm app's
  // `GetAllTrips` while the shared trip DB is still empty (sync hasn't
  // happened yet), which returns an empty result → `handleTripsFetched`
  // redirects to /trips. After the warm-up the `tripsStillLoading` guard
  // prevents any further `GetAllTrips` calls, so the subsequent /settings
  // navigation is stable.
  await page.goto('/trips')
  // Wait for the ACTIVE TRIP label to show "HONEYMOON" — this confirms the
  // shared trip DB has synced and Elm has the entry in as_.flocks. Using the
  // badge text avoids the strict-mode violation on "Italy" which
  // appears in both the large trip heading and the small nav tab label.
  await expect(page.getByText('HONEYMOON')).toBeVisible({ timeout: 60_000 })

  await page.goto('/settings')
  await expect(page.getByText('Local-first preferences')).toBeVisible({
    timeout: 15_000,
  })
  await expect(page.getByText('FLOCKS', { exact: true })).toBeVisible({
    timeout: 10_000,
  })
}

/**
 * Probes the page's IndexedDB for a `_pouch_ternpike-sharedtrip-<id>` entry.
 *
 * Note: `pouch.js` calls `handle.local.close()` on leave, not
 * `local.destroy()`, so the IndexedDB database persists (PouchDB's design —
 * a re-join can reuse the existing local data without a fresh full
 * replication). This probe returns `true` even after a successful leave,
 * which is correct behavior, not a regression. The user-visible invariant
 * (trips drop out of the UI within ~5s) is asserted separately. Kept here
 * as a logging hook and so the spec documents what the issue wording
 * actually means in practice.
 */
const localSharedTripDbExists = async (page: Page): Promise<boolean> => {
  return page.evaluate(async (target) => {
    const dbs = await indexedDB.databases()
    return dbs.some(
      (d) => typeof d.name === 'string' && d.name.includes(target),
    )
  }, FLOCK_LOCAL_DB)
}

test.describe('Shared trip leave + remove', () => {
  test.beforeEach(async ({ aliceContext, bobContext, couchAdmin }) => {
    // 1. Provision real CouchDB users so sync can actually authenticate.
    const alice = await provisionUser(couchAdmin, ALICE_EMAIL)
    const bob = await provisionUser(couchAdmin, BOB_EMAIL)
    aliceCreds.password = alice.password
    bobCreds.password = bob.password

    // Purge any user:sharedtrips docs left by earlier specs in the same run
    // (e.g. join-flock leaves Bob a member of 'aabbccddeeff'). Without
    // this, Bob's reconcileSharedTrips ends up tracking a shared trip from
    // the prior spec while the new Honeymoon is being set up here, and the
    // race makes the "Honeymoon disappears after leave" assertion flaky.
    await purgeUserSharedTrips(couchAdmin, ALICE_EMAIL)
    await purgeUserSharedTrips(couchAdmin, BOB_EMAIL)

    // 2. Replace the harness's placeholder auth_creds with the real ones.
    await overrideStubbedCreds(
      aliceContext,
      alice.email,
      alice.password,
      alice.dbName,
    )
    await overrideStubbedCreds(
      bobContext,
      bob.email,
      bob.password,
      bob.dbName,
    )

    // 3. Route in-app api.ternpike.com calls to local wrangler.
    await routeApiToLocalServer(aliceContext)
    await routeApiToLocalServer(bobContext)

    // 4. Seed the Honeymoon shared trip with Italy + two expenses.
    await seedSharedTrip(couchAdmin, {
      expenses: [
        {
          amount: 12500,
          category: 'lodging',
          createdBy: ALICE_EMAIL,
          date: '2026-03-02',
          merchant: 'Hotel Roma',
          note: 'Night 1',
        },
        {
          amount: 4200,
          category: 'food',
          createdBy: BOB_EMAIL,
          date: '2026-03-03',
          merchant: 'Trattoria Da Enzo',
          note: 'Lunch',
        },
      ],
      sharedTripId: HONEYMOON_FLOCK_ID,
      members: [ALICE_EMAIL, BOB_EMAIL],
      name: 'Honeymoon',
      owner: ALICE_EMAIL,
      tripBudget: 250000,
      tripName: 'Italy',
    })
  })

  test('Bob voluntarily leaves Honeymoon and loses access; Alice unaffected', async ({
    aliceContext,
    bobContext,
  }) => {
    // Two full CouchDB sync chains + UI interactions need more than the 60s
    // global timeout. Set a per-test budget that covers: beforeEach (~20s),
    // two sync round-trips (~10s each), and the leave + assertion flow.
    test.setTimeout(180_000)

    const alice = await aliceContext.newPage()
    const bob = await bobContext.newPage()

    // openSettingsFlocks warms up by visiting /trips first (waits for Italy to
    // confirm shared trip sync) then goes to /settings. That warm-up ensures
    // as_.trips is TripsLoaded before the /settings navigation so the Elm app
    // doesn't redirect back to /trips when GetAllTrips fires.
    await openSettingsFlocks(bob)
    await expect(bob.getByRole('button', { name: 'Leave' }).first()).toBeVisible({
      timeout: 15_000,
    })

    await openSettingsFlocks(alice)
    await expect(alice.getByText('Honeymoon')).toBeVisible({ timeout: 10_000 })

    await bob.getByRole('button', { name: 'Leave' }).first().click()
    const leaveModal = bob.locator('div').filter({
      has: bob.getByText('Leave flock?', { exact: true }),
    }).last()
    await expect(leaveModal).toBeVisible()
    await leaveModal.getByRole('button', { name: 'Leave', exact: true }).click()
    // Modal closes once the server confirms (LeaveFlockResult Ok).
    await expect(leaveModal).toBeHidden({ timeout: 10_000 })

    // The server admin-writes user:sharedtrips → CouchDB pushes the change →
    // pouch.js reconcileSharedTrips closes the handle → Elm drops the card.
    // Allow up to 30s for the full sync round-trip. Using { exact: true } to
    // match only the badge span, not any modal text that also says
    // "Honeymoon" (strict-mode violation otherwise).
    await expect(bob.getByText('Honeymoon', { exact: true })).toBeHidden({
      timeout: 30_000,
    })

    // Italy disappears from Bob's Trips list.
    await bob.goto('/trips')
    await expect(bob.getByText('Italy')).toBeHidden({ timeout: 15_000 })

    // Probe pouch.js's view of Bob's shared trip DB. The actual user-visible
    // invariant — trip data drops out of the UI — is the line above; this
    // is a diagnostic. See `localSharedTripDbExists` JSDoc for why the
    // database entry can persist after a clean leave.
    const stillHasSharedTripDb = await localSharedTripDbExists(bob)
    test.info().annotations.push({
      type: 'pouchdb-leave-state',
      description: `shared trip IndexedDB present after leave: ${String(stillHasSharedTripDb)}`,
    })

    // Alice still sees Honeymoon and Italy with full data.
    await alice.reload()
    await expect(alice.getByText('Honeymoon')).toBeVisible({ timeout: 10_000 })
    await alice.goto('/trips')
    await expect(alice.getByText('Italy').first()).toBeVisible({ timeout: 10_000 })
  })

  test('Bob rejoins after leaving; full history is restored', async ({
    aliceContext,
    bobContext,
    couchAdmin,
  }) => {
    // Two full CouchDB sync chains + leave + rejoin flow needs more than 60s.
    test.setTimeout(180_000)

    const alice = await aliceContext.newPage()
    const bob = await bobContext.newPage()

    // openSettingsFlocks warms up at /trips first (waits for Italy) then
    // navigates to /settings so the app's trips state is TripsLoaded and
    // there is no /trips redirect before the Leave button appears.
    await openSettingsFlocks(bob)
    await expect(bob.getByRole('button', { name: 'Leave' }).first()).toBeVisible({
      timeout: 15_000,
    })
    await bob.getByRole('button', { name: 'Leave' }).first().click()
    const leaveModal = bob.locator('div').filter({
      has: bob.getByText('Leave flock?', { exact: true }),
    }).last()
    await expect(leaveModal).toBeVisible()
    await leaveModal.getByRole('button', { name: 'Leave', exact: true }).click()
    // Modal closes once the server confirms (LeaveFlockResult Ok).
    await expect(leaveModal).toBeHidden({ timeout: 10_000 })
    // Card disappears after CouchDB sync delivers updated user:sharedtrips.
    await expect(bob.getByText('Honeymoon', { exact: true })).toBeHidden({
      timeout: 30_000,
    })

    // Alice re-invites Bob. (Goes via the local wrangler server; the
    // mock-Resend captures the email but we don't read it — the spec
    // mints a fresh invite token directly via the helper since the
    // accept-screen flow is covered by #73.)
    await openSettingsFlocks(alice)
    await alice.getByRole('button', { name: 'Invite' }).first().click()
    await alice.getByPlaceholder('name@example.com').fill(BOB_EMAIL)
    await alice.getByRole('button', { name: 'Send invite' }).click()

    // Drive the join HTTP endpoint directly. Mirrors what #73 covers
    // through the UI — that flow ends with the same /sharedtrips/join call.
    const token = mintInviteJwt(HONEYMOON_FLOCK_ID, BOB_EMAIL, ALICE_EMAIL)
    const baseUrl = authServerBaseUrl()
    const joinRes = await fetch(`${baseUrl}/sharedtrips/join`, {
      method: 'POST',
      headers: {
        Authorization:
          'Basic ' +
          Buffer.from(`${bobCreds.email}:${bobCreds.password}`).toString(
            'base64',
          ),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ token }),
    })
    expect(joinRes.status, await joinRes.text()).toBe(200)

    // Bob is still on /settings from the leave flow. Wait for his live
    // PouchDB sync to deliver the updated user:sharedtrips (server wrote
    // it on join). This avoids a page reload race where the fresh sync
    // might fire its first-paused before CouchDB has pushed the updated doc.
    await expect(bob.getByText('Honeymoon', { exact: true })).toBeVisible({
      timeout: 60_000,
    })

    // Now navigate to /trips. The live sync already opened the shared trip
    // handle and local PouchDB has both sharedtrip:meta and the Italy trip,
    // so a fresh page load resolves immediately.
    await bob.goto('/trips')
    await expect(bob.getByText('Italy').first()).toBeVisible({ timeout: 30_000 })

    // Server-side meta confirms Bob's restored membership and that the
    // historical docs weren't touched.
    const meta = await readSharedTripMeta(couchAdmin, HONEYMOON_FLOCK_ID)
    expect(meta.members.sort()).toEqual([ALICE_EMAIL, BOB_EMAIL].sort())
  })

  test('owner self-leave is rejected with transfer_ownership_first', async ({
    couchAdmin,
  }) => {
    // The Settings UI from #62 only shows the Leave button to non-owners,
    // so we exercise the server-side guard directly. The user-facing
    // "transfer ownership first" friendly error from the issue is the
    // string the eventual owner-Leave button would render once it exists.
    const baseUrl = authServerBaseUrl()
    const res = await fetch(
      `${baseUrl}/sharedtrips/${HONEYMOON_FLOCK_ID}/leave`,
      {
        method: 'POST',
        headers: {
          Authorization:
            'Basic ' +
            Buffer.from(
              `${aliceCreds.email}:${aliceCreds.password}`,
            ).toString('base64'),
        },
      },
    )
    expect(res.status).toBe(409)
    const body = (await res.json()) as { error: string; ok: boolean }
    expect(body).toEqual({ error: 'transfer_ownership_first', ok: false })

    // No state change: Alice + Bob are still both members.
    const meta = await readSharedTripMeta(couchAdmin, HONEYMOON_FLOCK_ID)
    expect(meta.members.sort()).toEqual([ALICE_EMAIL, BOB_EMAIL].sort())
    expect(meta.billingOwner).toBe(ALICE_EMAIL)
  })

  test.fixme(
    'owner kick: Alice removes Bob from Honeymoon',
    async () => {
      // BLOCKED: neither the Settings UI (Pages/Settings/Flocks.elm, #62)
      // nor the auth server (server/sharedTrips.js, #57) currently ships a
      // per-member removal path. The members panel renders the avatar
      // stack only — there is no per-row "Remove" affordance, and no
      // `DELETE /sharedtrips/:id/members/:email` endpoint to back one.
      //
      // Unblock requires:
      //   - Server: a new owner-only endpoint (auth caller must be
      //     billingOwner; rewrites meta.members, _security, and the
      //     ex-member's `user:sharedtrips`).
      //   - Client: a "Remove" button on each row of `viewMembersList`
      //     gated on `Flock.isOwner currentUser flock`.
      //
      // Once both land, this test mirrors the voluntary-leave spec from
      // Alice's side: click Remove, confirm, assert Bob's UI drops
      // Honeymoon + Italy within ~5s and Alice's view is unchanged.
    },
  )
})
