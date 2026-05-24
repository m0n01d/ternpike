/**
 * E2E for issue #72 — Alice (Fly) creates a flock from Settings → Flocks
 * and invites Bob by email. Verifies the UI states throughout the flow and
 * the mock Resend captures the outbound invite email.
 *
 * Wiring notes:
 *
 *  - The Elm `Http.FlockApi` module targets `https://api.ternpike.com`,
 *    hard-coded. The `twoUsers` fixture intercepts that host per
 *    BrowserContext and proxies to the locally-bound wrangler dev port.
 *  - Stub auth credentials use the real `derivePassword` HMAC so the
 *    server's `authenticateCaller` accepts them.
 *  - The Resend Worker SDK reads its baseUrl from `process.env` at module
 *    load, which `workerd` does not populate. This branch replaces the SDK
 *    usage in `server/flocks.js` with a raw `fetch` against
 *    `env.RESEND_BASE_URL`, which the harness wires up via `--var`.
 *  - PouchDB live sync still points at production `couch.ternpike.com` so
 *    the post-create flock card will not appear via the natural sync path
 *    in this test environment. We instead simulate what sync would do by
 *    writing `user:flocks` into the personal PouchDB and `flock:meta`
 *    into the per-flock PouchDB directly after the server confirms the
 *    create. The local PouchDB `changes` listener (`src/pouch.js`) fires
 *    the same `FlockMeta` / `FlocksReconciled` ports as a real sync.
 */

import { test, expect, deriveStubPassword } from '../fixtures/twoUsers'
import { readHarnessState } from '../utils/state'

import type { Page } from '@playwright/test'

const ALICE_EMAIL = 'alice@test.ternpike.com'
const BOB_EMAIL = 'bob@test.ternpike.com'

const personalDbName = (email: string): string =>
  'ternpike-' + email.toLowerCase().replace(/[^a-z0-9_$()+/-]/g, '-')

/**
 * Pre-create both users' personal CouchDB databases so the auth server's
 * `appendUserFlocks` write doesn't 404. The real production flow gets
 * these for free at signup; the stub-auth path skips signup entirely.
 */
const ensurePersonalDbs = async (
  emails: string[],
): Promise<void> => {
  const state = readHarnessState()
  const auth =
    'Basic ' +
    Buffer.from(`${state.couchAdminUser}:${state.couchAdminPassword}`).toString(
      'base64',
    )
  for (const email of emails) {
    const db = personalDbName(email)
    const res = await fetch(`${state.couchUrl}/${db}`, {
      method: 'PUT',
      headers: { Authorization: auth },
    })
    // 412 is "DB already exists" — acceptable across re-runs.
    if (!res.ok && res.status !== 412) {
      throw new Error(`could not pre-create ${db}: ${res.status} ${await res.text()}`)
    }
  }
}

/**
 * Sets a user's server-side tier via the test webhook on the auth Worker.
 * The webhook secret is hard-coded in `e2e/global-setup.ts` and the route
 * lives at `POST /flocks/test/tier-changed`. Server-side `TIERS_KV` is the
 * source of truth for `/flocks`'s tier gate; the client tier flag in
 * `auth_creds` only controls UI affordances.
 */
const setServerTier = async (
  email: string,
  tier: 'tern' | 'osprey' | 'trailblazer',
): Promise<void> => {
  const state = readHarnessState()
  const res = await fetch(
    `http://127.0.0.1:${state.serverPort}/flocks/test/tier-changed`,
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
    throw new Error(
      `could not set ${email} → ${tier}: ${res.status} ${await res.text()}`,
    )
  }
}

type CreateFlockResponseBody = {
  ok: boolean
  flockId?: string
  dbName?: string
}

/**
 * Watches the page for a successful response from the create-flock
 * endpoint (proxied to the local auth server via `routeApiTernpikeToLocal`).
 * The browser's `response` event reports the proxied URL host
 * (`api.ternpike.com`), so we filter on path. We poll the response body
 * via `body()` because `json()` can race with the fulfilled response on
 * fast iterations.
 */
const captureCreateFlockResponse = async (
  page: Page,
): Promise<{ flockId: string; dbName: string }> => {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error('did not see POST /flocks response in time')),
      15_000,
    )
    page.on('response', async (res) => {
      const req = res.request()
      if (req.method() !== 'POST') return
      const url = req.url()
      if (!url.endsWith('/flocks')) return
      try {
        const raw = await res.text()
        const body = JSON.parse(raw || '{}') as CreateFlockResponseBody
        if (body.ok && body.flockId && body.dbName) {
          clearTimeout(timeout)
          resolve({ flockId: body.flockId, dbName: body.dbName })
        }
      } catch (err) {
        clearTimeout(timeout)
        reject(err)
      }
    })
  })
}

/**
 * Pushes the `FlocksReconciled` + `FlockMeta` port events into Elm that a
 * real CouchDB sync would deliver after `POST /flocks` lands. Replaces
 * the more invasive "spin up a second PouchDB instance and write doc"
 * approach — PouchDB's cross-instance change feed turned out not to
 * propagate reliably inside the Playwright browser context, and the
 * port-level event is what we actually want to assert against anyway.
 *
 * Reads the live Elm app off `window.__ternpikeTestApp` (set by
 * `src/main.js` only in non-production builds; see the comment there).
 */
const seedFlockLocally = async (
  page: Page,
  ownerEmail: string,
  flock: { flockId: string; dbName: string; name: string },
): Promise<void> => {
  await page.evaluate(
    async ([owner, flockId, dbName, name]) => {
      type App = {
        ports: {
          pouchIn: {
            send: (msg: unknown) => void
          }
        }
      }
      const w = window as unknown as { __ternpikeTestApp?: App }
      const start = Date.now()
      while (!w.__ternpikeTestApp) {
        if (Date.now() - start > 10_000) {
          throw new Error('Elm test app never attached to window')
        }
        await new Promise((r) => setTimeout(r, 50))
      }
      const app = w.__ternpikeTestApp

      // First: reconcile the flock list so Elm knows this flock exists.
      app.ports.pouchIn.send({ tag: 'FlocksReconciled', flockIds: [flockId] })

      // Then: ship the flock metadata as a FlockMeta event. The shape
      // mirrors what `src/pouch.js` constructs after stripping `_rev`
      // from the on-disk doc — see `Data.Flock.decoder` for the field
      // contract.
      app.ports.pouchIn.send({
        tag: 'FlockMeta',
        doc: {
          _id: 'flock:meta',
          type: 'flock:meta',
          flockId,
          name,
          members: [owner],
          billingOwner: owner,
          billingStatus: 'active',
          billingLapsedAt: null,
          createdBy: owner,
          createdAt: new Date().toISOString(),
        },
      })

      // Quiet unused-var noise — `dbName` is part of the public shape
      // even though this synthetic delivery doesn't open a real DB.
      void dbName
    },
    [
      ownerEmail.toLowerCase(),
      flock.flockId,
      flock.dbName,
      flock.name,
    ] as const,
  )
}

test.beforeAll(async () => {
  await ensurePersonalDbs([ALICE_EMAIL, BOB_EMAIL])
  // Default tiers for these E2E specs. Individual tests override below.
  await setServerTier(ALICE_EMAIL, 'osprey')
  await setServerTier(BOB_EMAIL, 'tern')
})

test.beforeEach(async ({ resendMock }) => {
  await resendMock.clear()
})

test('Alice (Fly) creates a flock and invites Bob', async ({
  aliceContext,
  resendMock,
}) => {
  const page = await aliceContext.newPage()
  const responsePromise = captureCreateFlockResponse(page)

  await page.goto('/settings')

  // Boot signal: Settings hero text appears once Elm has read auth_creds.
  await expect(page.getByText('Local-first preferences')).toBeVisible({
    timeout: 30_000,
  })

  // The Fly-tier copy on the Create row confirms the tier flag was honored.
  await expect(
    page.getByText('Log expenses together with a partner or household.'),
  ).toBeVisible()

  // Open the Create Flock modal. The row Create button and the modal
  // confirm button share the same accessible name; the row one renders
  // first in DOM order so `.first()` is the row, `.last()` is the modal.
  await page.getByRole('button', { name: 'Create' }).first().click()
  await expect(page.getByText('New Flock')).toBeVisible()

  // Fill and submit (modal confirm = last "Create" button on the page).
  await page.getByPlaceholder('Honeymoon').fill('Honeymoon')
  await page.getByRole('button', { name: 'Create' }).last().click()

  // Server returned ok → modal closes, toast surfaces.
  const created = await responsePromise
  await expect(page.getByText('New Flock')).toBeHidden()
  await expect(
    page.getByText(/Flock created\. It'll show up here once sync settles\./),
  ).toBeVisible()

  // Simulate sync delivery so the flock card appears (see header comment
  // re: PouchDB sync still pointing at production couch).
  await seedFlockLocally(page, ALICE_EMAIL, {
    flockId: created.flockId,
    dbName: created.dbName,
    name: 'Honeymoon',
  })

  // The card should now render with the flock name + Owner badge.
  await expect(page.getByText('Honeymoon')).toBeVisible({ timeout: 5_000 })
  await expect(page.getByText('Owner', { exact: true })).toBeVisible({
    timeout: 5_000,
  })

  // Snapshot: flock card as the owner sees it.
  await expect(page).toHaveScreenshot('create-flock-owner-view.png', {
    fullPage: true,
    maxDiffPixelRatio: 0.05,
  })

  // Open the Invite modal.
  await page.getByRole('button', { name: 'Invite' }).click()
  await expect(page.getByText('Invite to flock')).toBeVisible()

  // Snapshot: invite modal in its initial state.
  await expect(page).toHaveScreenshot('create-flock-invite-modal.png', {
    fullPage: true,
    maxDiffPixelRatio: 0.02,
  })

  // Submit Bob's address.
  await page.getByPlaceholder('name@example.com').fill(BOB_EMAIL)
  await page.getByRole('button', { name: 'Send invite' }).click()

  // Modal closes + success toast surfaces.
  await expect(page.getByText('Invite to flock')).toBeHidden()
  await expect(page.getByText('Invite sent.')).toBeVisible()

  // Snapshot: post-send state.
  await expect(page).toHaveScreenshot('create-flock-sent.png', {
    fullPage: true,
    maxDiffPixelRatio: 0.02,
  })

  // Resend mock should have captured exactly one email to Bob whose body
  // contains the `/flocks/join?token=` URL. We poll because the server
  // sends mail after returning 200 from the route handler.
  await expect
    .poll(async () => await resendMock.lastSentTo(BOB_EMAIL), {
      timeout: 5_000,
    })
    .not.toBeNull()
  const captured = await resendMock.lastSentTo(BOB_EMAIL)
  expect(captured).not.toBeNull()
  expect(captured?.to.toLowerCase()).toBe(BOB_EMAIL)
  const bodyText = (captured?.text ?? '') + (captured?.html ?? '')
  expect(bodyText).toContain('/flocks/join?token=')
})

test('inviting the same email twice surfaces an inline error', async ({
  aliceContext,
}) => {
  const page = await aliceContext.newPage()
  const responsePromise = captureCreateFlockResponse(page)

  await page.goto('/settings')
  await expect(page.getByText('Local-first preferences')).toBeVisible({
    timeout: 30_000,
  })

  // Create the flock as in the happy path.
  await page.getByRole('button', { name: 'Create' }).first().click()
  await page.getByPlaceholder('Honeymoon').fill('Duplicate Test')
  await page.getByRole('button', { name: 'Create' }).last().click()
  const created = await responsePromise
  await expect(page.getByText('Flock created.')).toBeVisible()

  await seedFlockLocally(page, ALICE_EMAIL, {
    flockId: created.flockId,
    dbName: created.dbName,
    name: 'Duplicate Test',
  })
  await expect(page.getByText('Duplicate Test')).toBeVisible()

  // First invite — succeeds. We use a non-Bob email so the duplicate
  // assertion is the only relevant signal across re-runs.
  const target = 'duplicate-target@test.ternpike.com'
  await page.getByRole('button', { name: 'Invite' }).click()
  await page.getByPlaceholder('name@example.com').fill(target)
  await page.getByRole('button', { name: 'Send invite' }).click()
  await expect(page.getByText('Invite sent.')).toBeVisible()

  // Simulate the invitee accepting (so the server sees them as a member).
  // The cleanest way to make the duplicate-invite check fire is to push
  // the invitee into the flock-meta members list directly via the admin
  // CouchDB client, matching what `POST /flocks/join` would do.
  const state = readHarnessState()
  const auth =
    'Basic ' +
    Buffer.from(`${state.couchAdminUser}:${state.couchAdminPassword}`).toString(
      'base64',
    )
  const metaUrl = `${state.couchUrl}/flock-${created.flockId}/flock%3Ameta`
  const cur = await fetch(metaUrl, { headers: { Authorization: auth } })
  const meta = (await cur.json()) as {
    _rev: string
    members: string[]
  } & Record<string, unknown>
  const updated = { ...meta, members: [...meta.members, target] }
  const put = await fetch(metaUrl, {
    method: 'PUT',
    headers: {
      Authorization: auth,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(updated),
  })
  if (!put.ok) {
    throw new Error(`could not add member to flock-meta: ${put.status} ${await put.text()}`)
  }

  // Second invite for the same email → server 409 → modal stays open with
  // a friendly error string. `flockErrorMessage` in Main.elm maps 409 to
  // "Already a member." which is what the user sees for either of the
  // overlapping cases (already invited or already a member).
  await page.getByRole('button', { name: 'Invite' }).click()
  await page.getByPlaceholder('name@example.com').fill(target)
  await page.getByRole('button', { name: 'Send invite' }).click()
  await expect(page.getByText('Already a member.')).toBeVisible()
})

test.describe('Fledgling cannot create a flock', () => {
  test.use({
    aliceSpec: {
      email: ALICE_EMAIL,
      // A throwaway trip is required: on first sync, an empty trips
      // collection forces a `Nav.replaceUrl ".../trips"` in `Main.elm`
      // which would bounce us off `/settings` before the test can assert
      // anything. The seed has no effect on the Fledgling tier check.
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
      tier: 'Tern',
    },
  })

  test.beforeEach(async () => {
    // The default tier wired in the suite-level beforeAll is Osprey. Flip
    // Alice to Tern for this describe block so any client→server
    // attempt would 403, matching the UI affordance under test.
    await setServerTier(ALICE_EMAIL, 'tern')
  })

  test.afterEach(async () => {
    // Restore so downstream tests (re-run with --grep, etc.) keep working.
    await setServerTier(ALICE_EMAIL, 'osprey')
  })

  test('Create button is disabled and upgrade copy is visible', async ({
    aliceContext,
  }) => {
    const page = await aliceContext.newPage()
    await page.goto('/settings')
    await expect(page.getByText('Local-first preferences')).toBeVisible({
      timeout: 30_000,
    })

    // The Fledgling copy on the Create row.
    await expect(
      page.getByText(
        'Flocks let you log expenses together with a partner. Upgrade to Fly to create one.',
      ),
    ).toBeVisible()

    // The Create button is rendered as a plain disabled <button>, not the
    // primary action variant. We assert via the accessible name.
    const createBtn = page.getByRole('button', { name: 'Create' }).first()
    await expect(createBtn).toBeDisabled()

    await expect(page).toHaveScreenshot('create-flock-fledgling.png', {
      fullPage: true,
      maxDiffPixelRatio: 0.02,
    })
  })
})

