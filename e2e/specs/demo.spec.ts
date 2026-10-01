import { expect, test } from '@playwright/test'

// Regression guard for the /demo runtime (src/demo.js). No backend: demo mode
// answers pouchOut from the in-memory seed in src/demo-data.js, so this runs in
// the backend-free verify harness (e2e/verify.config.ts) against dist/.
//
// Elm loads every trip's expenses with one bulk `GetAllTripExpenses` request
// (#445) and marks each trip as loading. If demo.js drops that tag, every
// Ledger stays on "Loading…" and every trip shows $0 spent. Navigate in-app,
// not by deep link: a deep link fires a per-trip `GetTripExpenses` for the
// routed trip, which hides the bug for that trip.

const DEMO_TRIPS = [
  'Hoovers to Redondo Beach',
  'Operation Tape Recovery',
  'Mutt Cutts Express',
  'Walley World or Bust',
  'Savage Journey to the Heart of the American Dream',
]

test('every demo trip loads its expenses', async ({ page }) => {
  await page.goto('/demo')
  const nav = (label: string) => page.getByRole('link', { name: label, exact: true })

  for (const name of DEMO_TRIPS) {
    await nav('Trips').click()
    await page.getByText(name, { exact: true }).last().click()
    await nav('Ledger').click()
    await expect(page.getByText(/[1-9]\d* entries/i).first()).toBeVisible()
    await expect(page.getByText(/loading/i)).toHaveCount(0)
  }
})
