/**
 * #76 — Tier-gated UI: a Fledgling member of a Fly-owned flock.
 *
 * The headline UX this guards against regressing: Bob (Fledgling) sees a
 * locked "Create Flock" upgrade prompt for his personal account, but full
 * access (including paid features) once he opens a trip that lives inside
 * Alice's Fly-owned Honeymoon flock. The split falls out of
 * `Trip.effectiveTier` (#61) — anything that accidentally reads `as_.tier`
 * instead of `effectiveTier trip as_` will break either the "in flock"
 * paid path or the "on personal data" Fledgling path; this spec is the
 * regression net.
 *
 * Several assertions on the issue body lean on UI / harness machinery that
 * hasn't landed yet:
 *
 *   - The Scan page does not yet consume `Trip.canUseProxiedOCR` /
 *     `Trip.canBatchScan`. The helpers exist in `src/Data/Trip.elm` but
 *     `src/Pages/Scan.elm` still treats every trip the same. That wiring
 *     is the #63 follow-up; the visual goldens here freeze the current
 *     state so the diff will catch the wiring when it lands.
 *
 *   - The proxied-OCR network path (`POST /scan` on the worker) is #14
 *     work. There is nothing to intercept yet, so the "scan request hits
 *     the proxied endpoint" assertion from #76 is deferred.
 *
 *   - The Honeymoon flock card requires either a real CouchDB sync
 *     round-trip OR a port-level test seam to deliver a `FlockMeta`
 *     event. Cross-PouchDB-instance change-feed propagation only fires
 *     reliably for the personal `user:flocks` doc — `flock:meta` writes
 *     into the per-flock DB land in IndexedDB but the app's bundled
 *     PouchDB doesn't observe them across separate library instances.
 *     That gap is captured separately so it can grow its own fixture.
 *
 * What's still strong here: the Fledgling Settings view DOES render the
 * Create-Flock-disabled state via `Data.Tier.isPaid as_.tier`, and the
 * Scan view is captured on both a personal trip and a (hypothetically)
 * flock-tagged trip. A regression that flips `Tier.isPaid` or that
 * accidentally hides the FLOCKS section from Fledgling users fails the
 * first test; a regression that changes Scan styling on either trip
 * fails the visual goldens.
 */
import { test, expect } from '../fixtures/twoUsers'

const ALICE_EMAIL = 'alice@test.ternpike.com'
const BOB_EMAIL = 'bob@test.ternpike.com'
const HONEYMOON_FLOCK_ID = 'abcdef012345'

test.use({
  bobSpec: {
    email: BOB_EMAIL,
    seed: {
      trips: [
        {
          // Bob's own personal trip — no flockId, evaluated against
          // Bob's own `as_.tier` (= Fledgling).
          description: '',
          endDate: '2026-03-31',
          name: 'Solo weekend',
          startDate: '2026-03-01',
        },
        {
          // Italy is conceptually the flock trip. We seed `flockId` on
          // the trip doc, but in production the tagging happens at the
          // port boundary in `src/pouch.js` based on which per-flock
          // PouchDB the doc lives in (`GetAllTrips` does
          // `{ ...doc, flockId: handle.flockId }`). Until the harness
          // can stand up a real per-flock PouchDB handle with a synced
          // `flock:meta` doc, the Italy trip surfaces in Elm as
          // personal. The visual golden still captures the page so
          // we'll notice when the wiring changes.
          description: '',
          endDate: '2026-06-21',
          flockId: HONEYMOON_FLOCK_ID,
          name: 'Italy',
          startDate: '2026-06-14',
        },
      ],
    },
    tier: 'Fledgling',
  },
})

const waitForSettings = async (page: import('@playwright/test').Page): Promise<void> => {
  await expect(page.getByText('Local-first preferences')).toBeVisible({
    timeout: 30_000,
  })
  // Flocks section header is the cheapest sentinel that flock-rendering
  // has had a chance to run (it sits beneath the regular settings panel).
  await expect(page.getByText('FLOCKS', { exact: true })).toBeVisible({
    timeout: 30_000,
  })
}

const openTripScan = async (
  page: import('@playwright/test').Page,
  tripName: string,
): Promise<void> => {
  await page.goto('/trips')
  // Trip cards expose the trip name as accessible text. Click-through is
  // more reliable than deep-linking with a `tripId=trip::…::…` URL because
  // the trip ids are seeded with timestamps we don't pin in the spec.
  // The seed runs via PouchDB on context init, then the app boots and reads
  // it back — on a slow CI runner the round-trip can take >5s, so wait
  // explicitly before clicking.
  const tripLink = page.getByText(tripName, { exact: false }).first()
  await expect(tripLink).toBeVisible({ timeout: 30_000 })
  await tripLink.click()
  await page.getByRole('link', { name: /scan/i }).click()
  // The hero copy renders once Scan tab is mounted.
  await expect(page.getByText(/Tap to add receipts|Connect to scan/i)).toBeVisible({
    timeout: 15_000,
  })
}

test.describe('Fledgling-in-flock tier gating', () => {
  test('Settings: Create-Flock is locked + upgrade prompt visible', async ({
    bobContext,
  }) => {
    const bob = await bobContext.newPage()
    await bob.goto('/settings')
    await waitForSettings(bob)

    // #76 step 2 — Create Flock is rendered but disabled. This is the
    // primary regression net: it's gated on `Data.Tier.isPaid as_.tier`,
    // so swapping Bob's tier to Fly (or flipping the predicate) flips
    // this assertion.
    const createButton = bob.getByRole('button', { name: 'Create' })
    await expect(createButton).toBeVisible()
    await expect(createButton).toBeDisabled()

    // #76 step 2 — adjacent upgrade copy is visible.
    await expect(
      bob.getByText(/Upgrade to Fly to create one/i),
    ).toBeVisible()

    // #76 steps 3 & 4 — Honeymoon flock card + Leave button are deferred
    // (harness gap, see top-of-file note). When the gap is closed,
    // re-introduce:
    //   await expect(bob.getByText('Honeymoon', { exact: true })).toBeVisible()
    //   await expect(bob.getByText('Member', { exact: true })).toBeVisible()
    //   await expect(bob.getByRole('button', { name: 'Leave' })).toBeVisible()

    // Visual-regression golden. Captures the most counterintuitive
    // Settings view: a Fledgling user who sees a locked Create Flock
    // but a present FLOCKS section. A regression that "tidies up" by
    // hiding FLOCKS from Fledglings altogether fails this snapshot.
    await expect(bob).toHaveScreenshot('settings-fledgling-in-flock.png', {
      fullPage: true,
      maxDiffPixelRatio: 0.05,
    })
  })

  test('Scan view renders on a flock-owned trip (Italy)', async ({
    bobContext,
  }) => {
    const bob = await bobContext.newPage()
    await openTripScan(bob, 'Italy')

    // The hero is the upload dropzone today; `Trip.canUseProxiedOCR`
    // exists but isn't yet surfaced as a visible label on this page —
    // that's the #63 follow-up. We assert the dropzone renders so the
    // screenshot baseline is meaningful; when the paid-OCR caption
    // lands, this test will need an extra
    // `expect(...).toContainText('Hosted OCR')` line and the golden
    // will need a refresh via `npm run e2e:update-snapshots`.
    await expect(bob.getByText('Tap to add receipts')).toBeVisible()

    // #76 step 11 — batch-scan UI: not visually distinct today,
    // deferred to #14/#63 wiring. We rely on the visual diff to
    // catch it when it lands.
    await expect(bob).toHaveScreenshot(
      'scan-fledgling-in-flock-trip.png',
      { fullPage: true, maxDiffPixelRatio: 0.05 },
    )
  })

  test('Scan view renders on a personal trip', async ({ bobContext }) => {
    const bob = await bobContext.newPage()
    await openTripScan(bob, 'Solo weekend')

    await expect(bob.getByText('Tap to add receipts')).toBeVisible()

    // #76 step 10 — BYO-key prompt isn't a distinct affordance on the
    // Scan view today; the Settings page already exposes the Anthropic
    // key input as the BYO-key surface. When the Scan view starts
    // labelling its OCR provenance per `Trip.canUseProxiedOCR`, the
    // diff between this golden and `scan-fledgling-in-flock-trip.png`
    // is the regression signal.
    await expect(bob).toHaveScreenshot(
      'scan-fledgling-personal-trip.png',
      { fullPage: true, maxDiffPixelRatio: 0.05 },
    )
  })
})

// Suppress the unused-binding lint on ALICE_EMAIL — referenced by the
// flock seed once the harness gap (see top-of-file note) is closed.
void ALICE_EMAIL
