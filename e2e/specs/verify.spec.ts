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

  test('no VAPID key on the server → no enable button, and it says so', async ({ page }) => {
    // When the API reports no VAPID public key, tapping Enable could never
    // succeed. Offering the button anyway is the "does nothing" bug.
    await page.goto('/verify/NotificationsPaywall/unconfigured')
    await page.waitForSelector('[data-verify-unit="NotificationsPaywall"]')
    const el = page.locator('[data-verify-unit="NotificationsPaywall"]')
    await expect(el).toHaveAttribute('data-verify-panel', 'unconfigured')
    await expect(el).toHaveAttribute('data-verify-enable-button', 'absent')
    await expect(page.getByRole('button', { name: 'Enable notifications' })).toHaveCount(0)
    await expect(page.getByText(/aren't configured on the server/)).toBeVisible()
  })

  test('a failed subscribe shows its reason next to the button', async ({ page }) => {
    // The regression this guards: PushSubscribeReceived used to read only
    // `.ok` and drop `.error`, so every failure rendered as silence.
    await page.goto('/verify/NotificationsPaywall/subscribe-error')
    await page.waitForSelector('[data-verify-unit="NotificationsPaywall"]')
    const el = page.locator('[data-verify-unit="NotificationsPaywall"]')
    await expect(el).toHaveAttribute('data-verify-panel', 'enable')
    await expect(el).toHaveAttribute(
      'data-verify-error',
      'Registration failed - push service error',
    )
    await expect(
      page.getByText("Couldn't enable notifications: Registration failed - push service error"),
    ).toBeVisible()
  })

  test('unsupported browser → no enable button', async ({ page }) => {
    await page.goto('/verify/NotificationsPaywall/unsupported')
    await page.waitForSelector('[data-verify-unit="NotificationsPaywall"]')
    const el = page.locator('[data-verify-unit="NotificationsPaywall"]')
    await expect(el).toHaveAttribute('data-verify-panel', 'unsupported')
    await expect(el).toHaveAttribute('data-verify-enable-button', 'absent')
  })

  test('milepost screen: empty state when nothing earned', async ({ page }) => {
    await page.goto('/verify/MilepostScreen/empty')
    await page.waitForSelector('[data-verify-unit="MilepostScreen"]')
    const el = page.locator('[data-verify-unit="MilepostScreen"]')
    await expect(el).toHaveAttribute('data-verify-screen', 'empty')
    await expect(el).toHaveAttribute('data-verify-earned', '0')
  })

  test('milepost screen: all-earned populates every family', async ({ page }) => {
    await page.goto('/verify/MilepostScreen/all-earned')
    await page.waitForSelector('[data-verify-unit="MilepostScreen"]')
    const el = page.locator('[data-verify-unit="MilepostScreen"]')
    await expect(el).toHaveAttribute('data-verify-screen', 'populated')

    const current: VerifyCurrent = await page.evaluate(() => (window as any).__verify.current())
    expect(current.verdict).toBe('PASS')
    expect(current.domSurface?.['earned']).toBe(current.domSurface?.['total'])
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

  // One fixture per test: each `page.goto` in this sandbox waits out an
  // unreachable Google Fonts @import before `load` fires, so batching four
  // navigations into one case blows the 30s budget.
  test('update toast: no update renders an empty, attribute-only host', async ({ page }) => {
    // `Html.Extra.nothing` emits no element, so absence is encoded as a
    // surface VALUE on an always-rendered wrapper. If it were encoded by
    // dropping the host, this selector would hang to timeout rather than fail.
    await page.goto('/verify/UpdateToast/hidden')
    // `attached`, not `visible`: the wrapper has no box on this fixture.
    await page.waitForSelector('[data-verify-unit="UpdateToast"]', { state: 'attached' })
    const el = page.locator('[data-verify-unit="UpdateToast"]')
    await expect(el).toHaveAttribute('data-verify-reload', 'absent')
    await expect(el).toHaveAttribute('data-verify-bar-slot', 'absent')
    await expect(page.getByText('New version available')).toHaveCount(0)
  })

  test('update toast: a waiting worker offers a described Reload', async ({ page }) => {
    await page.goto('/verify/UpdateToast/waiting')
    await page.waitForSelector('[data-verify-unit="UpdateToast"]', { state: 'attached' })
    await expect(page.locator('[data-verify-unit="UpdateToast"]')).toHaveAttribute(
      'data-verify-reload',
      'ready',
    )
    await expect(page.getByText('New version available')).toBeVisible()
    // A bare "Reload" is meaningless reached by swipe.
    await expect(
      page.getByRole('button', { name: 'Reload to install the new version' }),
    ).toBeEnabled()
  })

  test('update toast: applying renders a busy, non-re-tappable Reload', async ({ page }) => {
    await page.goto('/verify/UpdateToast/applying')
    await page.waitForSelector('[data-verify-unit="UpdateToast"]', { state: 'attached' })
    await expect(page.locator('[data-verify-unit="UpdateToast"]')).toHaveAttribute(
      'data-verify-reload',
      'busy',
    )
    await expect(page.getByRole('button', { name: 'Reload' })).toBeDisabled()
  })

  test('update toast: the ordinary toast shifts off the update bar', async ({ page }) => {
    // Sharing a slot would make every ordinary toast ("Link copied", share
    // errors, ~10 toastFor sites) invisible for the rest of the session — the
    // update bar is permanent and renders later in the DOM.
    await page.goto('/verify/UpdateToast/toast-both')
    await page.waitForSelector('[data-verify-unit="UpdateToast"]', { state: 'attached' })
    const el = page.locator('[data-verify-unit="UpdateToast"]')
    await expect(el).toHaveAttribute('data-verify-bar-slot', 'lower')
    await expect(el).toHaveAttribute('data-verify-toast-slot', 'upper')

    const current: VerifyCurrent = await page.evaluate(() => (window as any).__verify.current())
    expect(current.verdict).toBe('PASS')
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
