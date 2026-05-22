import { expect, test } from '@playwright/test'

const WAITLIST_URL_GLOB = '**/marketing/waitlist'
const LIVE_API = 'https://api.ternpike.com/marketing/waitlist'

const plusAlias = (suffix: string): string =>
  `dwight.j.doane+ternpike-${suffix}-${Date.now()}@gmail.com`

test.describe('marketing waitlist form (stubbed)', () => {
  test('submits the email and flips the button to the success label', async ({ page }) => {
    const captured: Array<{ email: string }> = []

    await page.route(WAITLIST_URL_GLOB, async (route) => {
      const body = route.request().postDataJSON() as { email: string }
      captured.push(body)
      await route.fulfill({
        body: JSON.stringify({ ok: true }),
        contentType: 'application/json',
        status: 200,
      })
    })

    await page.goto('/')

    const email = plusAlias('stub-success')
    await page.locator('.email-form .email-input').fill(email)
    await page.locator('.email-form .email-btn').click()

    await expect(page.locator('.email-form .email-btn')).toHaveText("You're in ✓")
    await expect(page.locator('.email-form .email-btn')).toHaveClass(/is-success/)
    await expect(page.locator('.email-form .email-input')).toHaveValue('')
    expect(captured).toEqual([{ email }])
  })

  test('flashes is-error on a 500 and restores the original button label', async ({ page }) => {
    await page.route(WAITLIST_URL_GLOB, (route) =>
      route.fulfill({
        body: JSON.stringify({ ok: false, error: 'stubbed failure' }),
        contentType: 'application/json',
        status: 500,
      }),
    )

    await page.goto('/')

    const input = page.locator('.email-form .email-input')
    const btn = page.locator('.email-form .email-btn')

    await input.fill(plusAlias('stub-error'))
    await btn.click()

    await expect(btn).toHaveText('Something went wrong — try again?')
    await expect(input).toHaveClass(/is-error/)
    await expect(btn).toHaveText('Notify me', { timeout: 5_000 })
  })

  test('rejects an obviously invalid email client-side without firing the request', async ({ page }) => {
    let calls = 0
    await page.route(WAITLIST_URL_GLOB, (route) => {
      calls += 1
      return route.fulfill({ status: 200, body: '{}' })
    })

    await page.goto('/')

    const input = page.locator('.email-form .email-input')
    await input.fill('nope')
    await page.locator('.email-form .email-btn').click()

    await expect(input).toHaveClass(/is-error/)
    expect(calls).toBe(0)
  })
})

test.describe('marketing waitlist form (live)', () => {
  test.skip(
    !process.env.WAITLIST_LIVE,
    'set WAITLIST_LIVE=1 to hit the real api.ternpike.com endpoint',
  )

  test('posts a unique +alias email to production and shows the success UI', async ({ page }) => {
    const email = plusAlias('live')

    const apiResponse = page.waitForResponse(
      (res) => res.url() === LIVE_API && res.request().method() === 'POST',
    )

    await page.goto('/')
    await page.locator('.email-form .email-input').fill(email)
    await page.locator('.email-form .email-btn').click()

    const res = await apiResponse
    const json = (await res.json().catch(() => ({}))) as { error?: string; ok?: boolean }
    expect(res.status(), `live endpoint returned an error: ${json.error ?? '(no body)'}`).toBe(200)
    expect(json.ok).toBe(true)

    await expect(page.locator('.email-form .email-btn')).toHaveText("You're in ✓")
    // The test address used; check Resend dashboard + inbox manually:
    // eslint-disable-next-line no-console
    console.log(`[waitlist-live] submitted ${email}`)
  })
})
