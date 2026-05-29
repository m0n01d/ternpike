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

test.describe('Verify DOM tier — TierGating', () => {
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
})
