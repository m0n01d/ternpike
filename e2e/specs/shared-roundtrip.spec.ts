import { test, expect } from '../fixtures/twoUsers'

/**
 * Shared-trip + expense round-trip with attribution (issue #74).
 *
 * The headline integration test for the Flock feature. Two browser contexts
 * (Alice owner-Fly, Bob member-Fledgling) share a `Honeymoon` flock. The spec
 * walks the 10 + 1 step assertion flow from the issue:
 *
 *  1. Both contexts on /trips.
 *  2. Alice creates "Italy" assigned to Honeymoon.
 *  3. Italy appears in Bob's trip list with Honeymoon badge.
 *  4. Bob opens Italy and adds expense "Gelato $4.50" / Food.
 *  5. Gelato appears in Alice's Ledger with "B Bob" author chip.
 *  6. Alice edits the amount to $5.00.
 *  7. Bob's Ledger row updates to $5.00.
 *  8. Per-expense detail shows "added by Bob" + "amended by Alice"
 *     (skipped if amendment-history UI is not exposed in v1).
 *  9. Alice voids the expense from the row menu.
 * 10. Row disappears from BOTH ledgers within 5s.
 * 11. Negative case: Bob's New Trip dialog only offers Personal
 *     (no Honeymoon option) because Bob isn't the owner.
 *
 * BLOCKER (2026-05-21) — `test.fixme` is in force because the spec depends
 * on UI shipped by #63 ("[Flock-UI] Trip ledger + author chip + Add context
 * strip"), which is not yet on `main`. The wiring needed:
 *
 *   - `Pages.Trips`: "Where does this trip live?" segmented control inside
 *     the New Trip form (#63). Owner-only Honeymoon option for Bob = #63.
 *   - `Pages.Ledger`: author chip ("B Bob") in the row meta band (#63).
 *   - `Pages.Add`: context strip + "visible to" caption (#63).
 *   - Amendment-history view: TBD, expected to land alongside #63 or in a
 *     follow-up; step 8 stays guarded behind a feature probe.
 *
 * The pre-existing pieces — flock data types (#60), per-flock PouchDB
 * fan-out (#59), `createdBy` on expenses/amendments (#58), flock create/
 * invite endpoints (#62) — are sufficient to seed state. The spec exercises
 * the actual UI surface, not internal PouchDB shapes, so it stays paused on
 * #63.
 *
 * SEED-PIPELINE NOTE — #63's drop report flagged that the JS hydrator does
 * `local.get('flock:meta')` while `Data.FlockId.decoder` expects a 12-char
 * hex `_id`. Per the issue, we work around this by creating the flock via
 * the real `POST /flocks` endpoint, not by writing `flock:meta` directly
 * into PouchDB. That codepath is also more representative of production.
 *
 * Once #63 lands, swap `test.describe.fixme` to `test.describe` and run:
 *
 *   npm run e2e -- --grep "shared trip round-trip"
 */

const HONEYMOON_NAME = 'Honeymoon'
const TRIP_NAME = 'Italy'
const EXPENSE_NOTE = 'Gelato'
const EXPENSE_AMOUNT = 4.5
const EXPENSE_AMOUNT_EDITED = 5.0
const SYNC_TIMEOUT_MS = 5_000

test.use({
  aliceSpec: {
    email: 'alice@test.ternpike.com',
    tier: 'Osprey',
  },
  bobSpec: {
    email: 'bob@test.ternpike.com',
    // Explicitly Tern — also verifies "Tern in a flock can write"
    // (paid OCR is owner-funded, but write access doesn't require paid tier).
    tier: 'Tern',
  },
})

test.describe.fixme(
  'shared trip round-trip (#74) — UNBLOCK once #63 lands',
  () => {
    test('alice creates Italy in Honeymoon, bob writes, both see amend + void', async ({
      aliceContext,
      bobContext,
    }) => {
      const alice = await aliceContext.newPage()
      const bob = await bobContext.newPage()

      // Pre-state: open both contexts on /trips. The fixture has already
      // stubbed auth_creds for each, so Elm boots straight into AuthModel.
      // The Honeymoon flock with Alice as owner + Bob as member is assumed
      // to be created via the /flocks endpoint by a helper before this
      // test body runs — see the SEED-PIPELINE NOTE in the module header.
      await alice.goto('/trips')
      await bob.goto('/trips')
      await expect(alice.getByRole('heading', { name: /trips/i })).toBeVisible()
      await expect(bob.getByRole('heading', { name: /trips/i })).toBeVisible()

      // 2. Alice → New Trip → Italy → assign Honeymoon → save.
      await alice.getByRole('button', { name: /new trip/i }).click()
      await alice.getByLabel(/trip name/i).fill(TRIP_NAME)
      await alice.getByLabel(/start date/i).fill('2026-06-01')
      await alice.getByLabel(/end date/i).fill('2026-06-14')
      // #63: "Where does this trip live?" segmented control — Personal | Honeymoon.
      await alice
        .getByRole('group', { name: /where does this trip live/i })
        .getByRole('button', { name: HONEYMOON_NAME })
        .click()
      await alice.getByRole('button', { name: /^save$/i }).click()

      // 3. Bob sees Italy within 5s with the Honeymoon flock badge.
      const bobItalyRow = bob.getByRole('link', { name: new RegExp(TRIP_NAME, 'i') })
      await expect
        .poll(async () => bobItalyRow.isVisible().catch(() => false), {
          message: 'Italy should appear in Bob trips list within 5s',
          timeout: SYNC_TIMEOUT_MS,
        })
        .toBe(true)
      await expect(
        bobItalyRow.getByLabel(new RegExp(`${HONEYMOON_NAME} flock`, 'i')),
      ).toBeVisible()

      // 4. Bob opens Italy → Ledger → Add expense "Gelato $4.50" / Food.
      await bobItalyRow.click()
      await bob.getByRole('link', { name: /add/i }).click()
      await bob.getByLabel(/amount/i).fill(String(EXPENSE_AMOUNT))
      await bob.getByLabel(/category/i).selectOption('Food')
      await bob.getByLabel(/note/i).fill(EXPENSE_NOTE)
      await bob.getByRole('button', { name: /^save$/i }).click()

      // 5. Alice opens the trip and sees the row + "B Bob" author chip
      //    in the meta band within 5s.
      await alice.getByRole('link', { name: new RegExp(TRIP_NAME, 'i') }).click()
      await alice.getByRole('link', { name: /ledger/i }).click()
      const aliceGelatoRow = alice.getByRole('listitem').filter({
        hasText: EXPENSE_NOTE,
      })
      await expect
        .poll(async () => aliceGelatoRow.isVisible().catch(() => false), {
          message: 'Gelato row should appear in Alice ledger within 5s',
          timeout: SYNC_TIMEOUT_MS,
        })
        .toBe(true)
      await expect(
        aliceGelatoRow.getByLabel(/added by bob/i),
      ).toBeVisible()

      // 6. Alice taps the row → Edit → change amount to $5.00 → save.
      await aliceGelatoRow.click()
      await alice.getByRole('link', { name: /edit/i }).click()
      await alice.getByLabel(/amount/i).fill(String(EXPENSE_AMOUNT_EDITED))
      await alice.getByRole('button', { name: /^save$/i }).click()

      // 7. Bob's Ledger row updates to $5.00 within 5s.
      const bobGelatoRow = bob.getByRole('listitem').filter({
        hasText: EXPENSE_NOTE,
      })
      await expect
        .poll(async () => {
          const txt = (await bobGelatoRow.textContent()) || ''
          return /\$?5\.00/.test(txt)
        }, {
          message: 'Bob ledger row should reflect $5.00 within 5s',
          timeout: SYNC_TIMEOUT_MS,
        })
        .toBe(true)

      // 8. Amendment-history UI — skipped if not exposed in v1.
      const amendmentLink = alice.getByRole('link', { name: /history|amendments/i })
      const hasAmendmentUi = await amendmentLink.isVisible().catch(() => false)
      if (hasAmendmentUi) {
        await amendmentLink.click()
        await expect(alice.getByText(/added by bob/i)).toBeVisible()
        await expect(alice.getByText(/amended by alice/i)).toBeVisible()
      } else {
        test.info().annotations.push({
          type: 'skip-reason',
          description:
            'Step 8 skipped: amendment-history UI not exposed in v1 (#74).',
        })
      }

      // 9. Alice voids the expense via the row menu.
      await alice.goBack() // back to ledger
      await aliceGelatoRow.getByRole('button', { name: /more|menu/i }).click()
      await alice.getByRole('menuitem', { name: /void|delete/i }).click()
      await alice
        .getByRole('button', { name: /confirm|yes/i })
        .click()
        .catch(() => {
          // Confirm dialog may not exist — soft-delete may be one-tap.
        })

      // 10. Row disappears from BOTH ledgers within 5s.
      await expect
        .poll(async () => aliceGelatoRow.count(), {
          message: 'Gelato should vanish from Alice ledger within 5s',
          timeout: SYNC_TIMEOUT_MS,
        })
        .toBe(0)
      await expect
        .poll(async () => bobGelatoRow.count(), {
          message: 'Gelato should vanish from Bob ledger within 5s',
          timeout: SYNC_TIMEOUT_MS,
        })
        .toBe(0)
    })

    test('bob is not offered Honeymoon in the New Trip picker (negative case)', async ({
      bobContext,
    }) => {
      // Bob is a member, not the owner — only the owner can park trips in a
      // flock (per #63 spec). The "Where does this trip live?" segmented
      // control should only show `Personal`.
      const bob = await bobContext.newPage()
      await bob.goto('/trips')
      await bob.getByRole('button', { name: /new trip/i }).click()
      const picker = bob.getByRole('group', {
        name: /where does this trip live/i,
      })
      await expect(picker).toBeVisible()
      await expect(picker.getByRole('button', { name: /personal/i })).toBeVisible()
      await expect(
        picker.getByRole('button', { name: HONEYMOON_NAME }),
      ).toHaveCount(0)
    })
  },
)
