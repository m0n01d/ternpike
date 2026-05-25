/**
 * #183 — Notifications paywall e2e: Settings Notifications pane state machine.
 *
 * The Settings `viewNotificationsBody` function has six visible branches
 * gated on tier, standalone mode, Notification.permission, and push
 * subscription state. This spec regression-tests five of them:
 *
 *   1. Tern user — upgrade CTA + disabled Enable button
 *   2. Osprey, permission=default, standalone=true — enabled Enable button
 *   3. Osprey, permission=granted, subscribed=true — toggle row with aria-checked
 *   4. Osprey, standalone=false (InBrowser) — install instructions copy
 *   5. Osprey, permission=denied, standalone=true — re-enable copy
 *
 * The Unsupported branch is omitted: Playwright/Chromium always reports
 * Notification as supported, so there's nothing meaningful to stub.
 *
 * Stubbing strategy: `page.addInitScript` runs before any page JS, so
 * it can redefine `Notification.permission`, `navigator.standalone`, and
 * `window.matchMedia` before `src/main.js` reads them in
 * `emitNotificationState`. The subscription state is covered by
 * stubbing `ServiceWorkerRegistration.pushManager.getSubscription`.
 *
 * Per CLAUDE.md "Visual goldens drift across machines": text/role
 * assertions only — no `toHaveScreenshot`. Deliberate.
 *
 * Per CLAUDE.md "Stale vite preview / wrangler dev from worktrees":
 * kill stragglers before running:
 *   pkill -f "vite preview"; pkill -f "wrangler dev"; sleep 1
 */

import { test, expect } from '../fixtures/twoUsers'

const ALICE_EMAIL = 'alice@test.ternpike.com'
const BOB_EMAIL = 'bob@test.ternpike.com'

/**
 * Wait for the NOTIFICATIONS kicker to appear in Settings.
 * The kicker is always rendered for all tiers/states so it's a reliable
 * sentinel that the Elm app has mounted and the initial
 * `notificationState` port event has been processed by `updateAuth`.
 */
const waitForNotifications = async (
  page: import('@playwright/test').Page,
): Promise<void> => {
  await expect(page.getByText('NOTIFICATIONS', { exact: true })).toBeVisible({
    timeout: 30_000,
  })
}

/**
 * Stub `Notification.permission`, `navigator.standalone`, and
 * `window.matchMedia('(display-mode: standalone)')` via addInitScript.
 * All overrides run synchronously before the page's own scripts, so
 * `emitNotificationState()` in `src/main.js` reads the stubbed values.
 */
const stubNotificationEnv = async (
  page: import('@playwright/test').Page,
  opts: {
    permission: 'default' | 'denied' | 'granted'
    standalone: boolean
  },
): Promise<void> => {
  await page.addInitScript(
    (overrides: { permission: string; standalone: boolean }) => {
      // Override Notification.permission (read-only in Chrome — need defineProperty)
      Object.defineProperty(Notification, 'permission', {
        configurable: true,
        get: () => overrides.permission,
      })

      // Override navigator.standalone (iOS Safari property)
      Object.defineProperty(window.navigator, 'standalone', {
        configurable: true,
        get: () => overrides.standalone,
      })

      // Override matchMedia so (display-mode: standalone) returns overrides.standalone.
      // Other media queries fall through to the real matchMedia.
      const originalMatchMedia = window.matchMedia.bind(window)
      window.matchMedia = (query: string): MediaQueryList => {
        if (query.includes('display-mode: standalone')) {
          return {
            matches: overrides.standalone,
            media: query,
            onchange: null,
            addListener: () => {},
            removeListener: () => {},
            addEventListener: () => {},
            removeEventListener: () => {},
            dispatchEvent: () => false,
          } as unknown as MediaQueryList
        }
        return originalMatchMedia(query)
      }
    },
    opts,
  )
}

/**
 * Stub `navigator.serviceWorker.ready` so `pushManager.getSubscription()`
 * returns a fake PushSubscription. Must be called before `page.goto()`.
 */
const stubPushSubscribed = async (
  page: import('@playwright/test').Page,
): Promise<void> => {
  await page.addInitScript(() => {
    const fakeSub = {
      endpoint: 'https://push.example.test/e2e-fake-endpoint',
      toJSON: () => ({
        endpoint: 'https://push.example.test/e2e-fake-endpoint',
        keys: { auth: 'aaaaaaaaaaaaaaaa', p256dh: 'pppppppppppppppp' },
      }),
      getKey: (_name: string) => null,
      options: { applicationServerKey: null, userVisibleOnly: true },
      expirationTime: null,
      unsubscribe: () => Promise.resolve(true),
    }

    // Wrap the `ready` promise to inject our fake pushManager.
    const origDescriptor = Object.getOwnPropertyDescriptor(
      ServiceWorkerContainer.prototype,
      'ready',
    )
    if (origDescriptor && origDescriptor.get) {
      const origGet = origDescriptor.get
      Object.defineProperty(navigator.serviceWorker, 'ready', {
        configurable: true,
        get() {
          return origGet.call(this).then((reg: ServiceWorkerRegistration) => {
            reg.pushManager.getSubscription = () =>
              Promise.resolve(fakeSub as unknown as PushSubscription)
            return reg
          })
        },
      })
    }
  })
}

// ---------------------------------------------------------------------------
// Test 1 — Tern user: upgrade CTA
// Uses bobSpec with tier=Tern (bob doesn't need seed data for this test).
// ---------------------------------------------------------------------------

test.describe('Tern user sees upgrade CTA', () => {
  test.use({
    bobSpec: {
      email: BOB_EMAIL,
      tier: 'Tern',
    },
  })

  test('disabled Enable button + upgrade copy visible', async ({ bobContext }) => {
    const page = await bobContext.newPage()
    await page.goto('/settings')
    await waitForNotifications(page)

    // Tern branch: upgrade helper text
    await expect(
      page.getByText('Upgrade to Osprey to enable weekly scan reminders.'),
    ).toBeVisible()

    // Disabled Enable button (the Tern paywall renders a non-interactive button)
    const enableBtn = page.getByRole('button', { name: 'Enable notifications' })
    await expect(enableBtn).toBeVisible()
    await expect(enableBtn).toBeDisabled()
  })
})

// ---------------------------------------------------------------------------
// Tests 2-5 use aliceContext with tier=Osprey (the default in twoUsers.ts).
// ---------------------------------------------------------------------------

test.describe('Osprey user notification states', () => {
  test.use({
    aliceSpec: {
      email: ALICE_EMAIL,
      tier: 'Osprey',
    },
  })

  test('permission=default + standalone => enabled Enable button', async ({
    aliceContext,
  }) => {
    const page = await aliceContext.newPage()
    // Stub before navigation so src/main.js sees the overrides at init time.
    await stubNotificationEnv(page, { permission: 'default', standalone: true })
    await page.goto('/settings')
    await waitForNotifications(page)

    // Default-permission + standalone + paid => "else" fallback renders
    // the Enable button (enabled, not disabled like the Tern paywall).
    const enableBtn = page.getByRole('button', { name: 'Enable notifications' })
    await expect(enableBtn).toBeVisible()
    await expect(enableBtn).not.toBeDisabled()

    // Helper copy above the button
    await expect(
      page.getByText('Weekly Friday reminder to scan receipts.', { exact: false }),
    ).toBeVisible()
  })

  test('permission=granted + subscribed => toggle row with aria-checked=true', async ({
    aliceContext,
  }) => {
    const page = await aliceContext.newPage()
    await stubNotificationEnv(page, { permission: 'granted', standalone: true })
    await stubPushSubscribed(page)

    // Mock the preferences endpoint so Elm reads weeklyScanReminder=true.
    // The endpoint is hit only when subscribed=true (endpoint is present).
    await page.route('**/notifications/preferences**', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ok: true, prefs: { weeklyScanReminder: true } }),
      }),
    )

    await page.goto('/settings')
    await waitForNotifications(page)

    // Granted + subscribed branch => toggle row
    await expect(page.getByText('Weekly receipt reminder')).toBeVisible()

    // The toggle (role=switch) carries aria-checked reflecting the pref value.
    const toggle = page.getByRole('switch', { name: 'Weekly receipt reminder' })
    await expect(toggle).toBeVisible()
    await expect(toggle).toHaveAttribute('aria-checked', 'true')

    // The "Enable notifications" button should NOT appear: user is subscribed.
    await expect(
      page.getByRole('button', { name: 'Enable notifications' }),
    ).toHaveCount(0)
  })

  test('standalone=false (InBrowser) => install-to-home-screen instructions', async ({
    aliceContext,
  }) => {
    const page = await aliceContext.newPage()
    // standalone=false triggers InBrowser branch regardless of permission.
    await stubNotificationEnv(page, { permission: 'default', standalone: false })
    await page.goto('/settings')
    await waitForNotifications(page)

    // InBrowser branch: install instructions
    await expect(
      page.getByText(
        'Install Ternpike to your home screen to enable notifications.',
        { exact: false },
      ),
    ).toBeVisible()

    // Enable button should NOT appear in the InBrowser branch.
    await expect(
      page.getByRole('button', { name: 'Enable notifications' }),
    ).toHaveCount(0)
  })

  test('permission=denied + standalone => re-enable instructions', async ({
    aliceContext,
  }) => {
    const page = await aliceContext.newPage()
    await stubNotificationEnv(page, { permission: 'denied', standalone: true })
    await page.goto('/settings')
    await waitForNotifications(page)

    // Denied branch: re-enable in iOS Settings copy
    await expect(
      page.getByText('Re-enable them in iOS Settings', { exact: false }),
    ).toBeVisible()

    // Enable button should NOT appear in the denied branch.
    await expect(
      page.getByRole('button', { name: 'Enable notifications' }),
    ).toHaveCount(0)
  })
})
