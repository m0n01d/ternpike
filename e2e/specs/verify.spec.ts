import { expect, test, type Page } from '@playwright/test'

// DOM tier for the Verify track. These probes confirm the *shipped artifact*
// renders the same surface the pure-tier matrix (tests/MatrixTest.elm) verifies
// hermetically. No backend: the /verify routes mount seeded fixture models and
// JS skips attachPouch, so this runs against a plain `vite preview` of dist/.
//
// Each case asserts both the data-verify-* attributes on the real create-row
// element AND the window.__verify verdict Elm pushed for the mounted fixture.

type VerifyCurrent = {
  unit?: string
  fixture?: string
  verdict?: string
  surface?: Record<string, string>
  domSurface: Record<string, string> | null
}

async function gotoVerify(page: Page, fixture: string) {
  await page.goto(`/verify/TierGating/${fixture}`)
  // The create-row carries data-verify-unit once the seeded model renders.
  await page.waitForSelector('[data-verify-unit="TierGating"]')
}

test.describe('Verify DOM tier', () => {
  test('free tier locks the create-flock gate', async ({ page }) => {
    await gotoVerify(page, 'tern')

    const el = page.locator('[data-verify-unit="TierGating"]')
    await expect(el).toHaveAttribute('data-verify-create-flock', 'locked')
    await expect(el).toHaveAttribute('data-verify-upgrade-copy', 'osprey')

    const current: VerifyCurrent = await page.evaluate(() => (window as any).__verify.current())
    expect(current.verdict).toBe('PASS')
    expect(current.domSurface?.['create-flock']).toBe('locked')
  })

  test('osprey unlocks the create-flock gate', async ({ page }) => {
    await gotoVerify(page, 'osprey')

    const el = page.locator('[data-verify-unit="TierGating"]')
    await expect(el).toHaveAttribute('data-verify-create-flock', 'unlocked')
    await expect(el).toHaveAttribute('data-verify-upgrade-copy', 'none')

    const current: VerifyCurrent = await page.evaluate(() => (window as any).__verify.current())
    expect(current.verdict).toBe('PASS')
  })

  test('trailblazer unlocks the create-flock gate', async ({ page }) => {
    await gotoVerify(page, 'trailblazer')

    const el = page.locator('[data-verify-unit="TierGating"]')
    await expect(el).toHaveAttribute('data-verify-create-flock', 'unlocked')

    const current: VerifyCurrent = await page.evaluate(() => (window as any).__verify.current())
    expect(current.verdict).toBe('PASS')
  })

  test('osprey standalone, not yet subscribed → enable button', async ({ page }) => {
    await page.goto('/verify/NotificationsPaywall/can-enable')
    await page.waitForSelector('[data-verify-unit="NotificationsPaywall"]')
    const el = page.locator('[data-verify-unit="NotificationsPaywall"]')
    await expect(el).toHaveAttribute('data-verify-panel', 'enable')
    await expect(el).toHaveAttribute('data-verify-enable-button', 'enabled')
  })

  test('free tier → notifications upgrade prompt + disabled button', async ({ page }) => {
    await page.goto('/verify/NotificationsPaywall/tern')
    await page.waitForSelector('[data-verify-unit="NotificationsPaywall"]')
    const el = page.locator('[data-verify-unit="NotificationsPaywall"]')
    await expect(el).toHaveAttribute('data-verify-panel', 'upgrade')
    await expect(el).toHaveAttribute('data-verify-enable-button', 'disabled')
    await expect(el).toHaveAttribute('data-verify-upgrade-copy', 'osprey')
  })

  test('unsupported browser → no enable button', async ({ page }) => {
    await page.goto('/verify/NotificationsPaywall/unsupported')
    await page.waitForSelector('[data-verify-unit="NotificationsPaywall"]')
    const el = page.locator('[data-verify-unit="NotificationsPaywall"]')
    await expect(el).toHaveAttribute('data-verify-panel', 'unsupported')
    await expect(el).toHaveAttribute('data-verify-enable-button', 'absent')
  })

  test('the full matrix is exposed and the probe fixture FAILS', async ({ page }) => {
    await gotoVerify(page, 'tern')

    const manifest: Array<{ unit: string; fixture: string; verdict: string }> =
      await page.evaluate(() => (window as any).__verify.manifest())

    // Every honest fixture passes; the adversarial probe must fail.
    const probe = manifest.find((m) => m.fixture.startsWith('probe'))
    expect(probe, 'a probe fixture should exist').toBeTruthy()
    expect(probe?.verdict).toContain('FAIL')

    const honest = manifest.filter((m) => !m.fixture.startsWith('probe'))
    expect(honest.length).toBeGreaterThan(0)
    for (const m of honest) {
      expect(m.verdict, `${m.unit}/${m.fixture}`).toBe('PASS')
    }
  })

  test('join: expired token surfaces the mapped error', async ({ page }) => {
    await page.goto('/verify/JoinSharedTrip/expired')
    await page.waitForSelector('[data-verify-unit="JoinSharedTrip"]')
    const el = page.locator('[data-verify-unit="JoinSharedTrip"]')
    await expect(el).toHaveAttribute('data-verify-accept', 'shown')
    await expect(el).toHaveAttribute('data-verify-error', /expired/)
  })

  test('join: in-flight shows a busy accept button', async ({ page }) => {
    await page.goto('/verify/JoinSharedTrip/loading')
    await page.waitForSelector('[data-verify-unit="JoinSharedTrip"]')
    await expect(page.locator('[data-verify-unit="JoinSharedTrip"]')).toHaveAttribute(
      'data-verify-accept',
      'busy',
    )
  })

  test('shared-trip card: owner sees the Owner badge', async ({ page }) => {
    await page.goto('/verify/SharedTripCard/owner')
    await page.waitForSelector('[data-verify-unit="SharedTripCard"]')
    await expect(page.locator('[data-verify-unit="SharedTripCard"]')).toHaveAttribute(
      'data-verify-role',
      'owner',
    )
  })

  test('the /verify dashboard lists every fixture with deep links', async ({ page }) => {
    await page.goto('/verify')
    await page.waitForSelector('a[href*="/verify/"]')
    const links = await page.locator('a[href*="/verify/"]').evaluateAll((els) =>
      els.map((e) => e.getAttribute('href')),
    )
    // One row per registered unit × fixture.
    const manifest: Array<unknown> = await page.evaluate(() => (window as any).__verify.runAll())
    expect(links.length).toBe(manifest.length)
    expect(links.some((h) => h?.includes('/verify/TierGating/'))).toBe(true)
  })
})
