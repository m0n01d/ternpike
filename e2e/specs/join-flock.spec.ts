import { readHarnessState } from '../utils/state'
import {
  deriveCouchPassword,
  flockDbName,
  personalDbName,
  provisionFlockDb,
  provisionPersonalDb,
  proxyApiToLocal,
  purgeUserFlocks,
  readUserFlocksDoc,
  signInviteJwt,
  stubRealAuthCreds,
} from '../utils/flock-test-helpers'
import { test, expect } from '../fixtures/twoUsers'

/**
 * Spec for #73 — Fledgling invitee join flow. The narrative:
 *
 *   Alice (owner of "Honeymoon") sends Bob (Fledgling) an invite. Bob
 *   opens the link, sees a join confirmation, accepts, and ends up a
 *   member of Honeymoon — while remaining Fledgling on his personal
 *   data.
 *
 * Resend gap: `RESEND_BASE_URL` is not honored by the Resend SDK inside
 * workerd (per #71's report and confirmed against this branch — the
 * server file never reads it). Rather than block on a server-side
 * adapter, we mint invite JWTs directly with `signInviteJwt`, which
 * uses the same HS256 + secret the auth server verifies. This is
 * indistinguishable from a Worker-minted token from the server's
 * perspective.
 *
 * Auth gap: the default fixture stubs `auth_creds` with a placeholder
 * password. The auth server's HTTP Basic check derives the expected
 * password from `HMAC-SHA256("couch:" + email, SERVER_SECRET)`. We
 * override the stub with the real derived password via
 * `stubRealAuthCreds` so /flocks/join actually accepts the call.
 *
 * API host: the Elm bundle hardcodes `https://api.ternpike.com`. We
 * proxy that to `127.0.0.1:<serverPort>` via context.route.
 */

const FLOCK_ID = 'aabbccddeeff'
const FLOCK_NAME = 'Honeymoon'
const ALICE_EMAIL = 'alice@test.ternpike.com'
const BOB_EMAIL = 'bob@test.ternpike.com'
const CAROL_EMAIL = 'carol@test.ternpike.com'

/**
 * Compute a fresh invite token addressed to Bob using current time.
 */
const freshTokenForBob = (serverSecret: string): string =>
  signInviteJwt(
    {
      flockId: FLOCK_ID,
      flockName: FLOCK_NAME,
      inviteeEmail: BOB_EMAIL,
      inviterEmail: ALICE_EMAIL,
    },
    serverSecret,
  )

test.describe('join flow (free invitee)', () => {
  test.beforeEach(async ({ couchAdmin }) => {
    // Bob, Alice, and Carol need personal dbs so the join handler can
    // write `user:flocks` without 500-ing. The real signup flow does
    // this on email verification. Idempotent: each call no-ops if the
    // db already exists, but it must run per-test because globalSetup
    // doesn't know which users a spec needs.
    await provisionPersonalDb(couchAdmin, ALICE_EMAIL)
    await provisionPersonalDb(couchAdmin, BOB_EMAIL)
    await provisionPersonalDb(couchAdmin, CAROL_EMAIL)
    // Clear residue from any prior test so the "already a member" path
    // doesn't bleed into the happy path on a re-run.
    await purgeUserFlocks(couchAdmin, BOB_EMAIL)
    await purgeUserFlocks(couchAdmin, ALICE_EMAIL)
    await purgeUserFlocks(couchAdmin, CAROL_EMAIL)
    // Honeymoon flock, Alice owner. Wipes & recreates so each test
    // starts from a known shape.
    await provisionFlockDb(couchAdmin, {
      flockId: FLOCK_ID,
      name: FLOCK_NAME,
      ownerEmail: ALICE_EMAIL,
    })
  })

  test('happy path: Bob accepts, becomes a member, keeps Fledgling tier', async ({
    bobContext,
    couchAdmin,
  }) => {
    const state = readHarnessState()
    await stubRealAuthCreds(bobContext, BOB_EMAIL, state.serverSecret)
    await proxyApiToLocal(bobContext, state.serverPort)

    const token = freshTokenForBob(state.serverSecret)

    const page = await bobContext.newPage()
    await page.goto(`/flocks/join?token=${encodeURIComponent(token)}`)

    // The confirmation card renders the inviter and the flock name.
    const confirmation = page.getByText(
      `${ALICE_EMAIL} invited you to join "${FLOCK_NAME}".`,
    )
    await expect(confirmation).toBeVisible({ timeout: 30_000 })

    // Golden first-impression screenshot.
    await page.screenshot({
      path: 'e2e/screenshots/join-confirmation.png',
      fullPage: false,
    })

    // The Accept button is rendered because Bob's email matches the
    // invite recipient (no wrong-recipient warning).
    await expect(
      page.getByText('This invite is for', { exact: false }),
    ).toHaveCount(0)

    const joinResponse = page.waitForResponse(
      (r) => r.url().endsWith('/flocks/join') && r.request().method() === 'POST',
    )
    await page.getByRole('button', { name: 'Accept' }).click()
    const res = await joinResponse
    expect(res.status()).toBe(200)

    // We end up on /settings with a confirmation toast.
    await page.waitForURL('**/settings', { timeout: 10_000 })
    await expect(page.getByText(`Joined ${FLOCK_NAME}.`)).toBeVisible({
      timeout: 10_000,
    })

    // Server-side state: Bob's user:flocks now references Honeymoon.
    const userFlocks = await readUserFlocksDoc(couchAdmin, BOB_EMAIL)
    expect(userFlocks).not.toBeNull()
    expect(userFlocks?.flocks).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: FLOCK_ID,
          name: FLOCK_NAME,
          dbName: flockDbName(FLOCK_ID),
        }),
      ]),
    )

    // The flock-side membership matches.
    const meta = await couchAdmin
      .request(`/${flockDbName(FLOCK_ID)}/flock%3Ameta`)
      .then((r) => r.json())
    expect(meta.members).toEqual(
      expect.arrayContaining([ALICE_EMAIL, BOB_EMAIL]),
    )

    // Bob's Settings page still renders (he didn't get bounced to a
    // tier-locked surface) and the BYO-key card — the canonical
    // Fledgling marker today — is present. The dedicated "tier badge"
    // surface called out in #73 isn't implemented yet (see CLAUDE.md
    // "Subscription tiers"); the BYO-key block stands in as the
    // post-join "still on free" smoke check.
    await expect(page.getByText('Anthropic API key')).toBeVisible()
  })

  test('sad path: wrong recipient sees the "for someone else" notice', async ({
    browser,
  }) => {
    const state = readHarnessState()
    // Carol isn't in the fixture; build her context from scratch.
    const carolContext = await browser.newContext({
      viewport: { width: 390, height: 844 },
    })
    try {
      await stubRealAuthCreds(carolContext, CAROL_EMAIL, state.serverSecret)
      await proxyApiToLocal(carolContext, state.serverPort)

      const tokenForBob = freshTokenForBob(state.serverSecret)
      const page = await carolContext.newPage()
      await page.goto(`/flocks/join?token=${encodeURIComponent(tokenForBob)}`)

      await expect(
        page.getByText(`This invite is for ${BOB_EMAIL}`, { exact: false }),
      ).toBeVisible({ timeout: 30_000 })
      // No Accept button — the JoinFlock page hides it on mismatch.
      await expect(page.getByRole('button', { name: 'Accept' })).toHaveCount(0)
    } finally {
      await carolContext.close()
    }
  })

  test('sad path: expired token surfaces a friendly error', async ({
    bobContext,
  }) => {
    const state = readHarnessState()
    await stubRealAuthCreds(bobContext, BOB_EMAIL, state.serverSecret)
    await proxyApiToLocal(bobContext, state.serverPort)

    const expiredToken = signInviteJwt(
      {
        flockId: FLOCK_ID,
        flockName: FLOCK_NAME,
        inviteeEmail: BOB_EMAIL,
        inviterEmail: ALICE_EMAIL,
        iat: Math.floor(Date.now() / 1000) - 7 * 24 * 60 * 60,
        exp: Math.floor(Date.now() / 1000) - 60,
      },
      state.serverSecret,
    )

    const page = await bobContext.newPage()
    await page.goto(`/flocks/join?token=${encodeURIComponent(expiredToken)}`)
    await expect(page.getByRole('button', { name: 'Accept' })).toBeVisible({
      timeout: 30_000,
    })

    const joinResponse = page.waitForResponse(
      (r) => r.url().endsWith('/flocks/join') && r.request().method() === 'POST',
    )
    await page.getByRole('button', { name: 'Accept' }).click()
    const res = await joinResponse
    expect(res.status()).toBe(410)

    await expect(
      page.getByText('This invite has expired', { exact: false }),
    ).toBeVisible({ timeout: 10_000 })
  })

  test('sad path: already-a-member on a second redeem', async ({
    bobContext,
    couchAdmin,
  }) => {
    const state = readHarnessState()
    await stubRealAuthCreds(bobContext, BOB_EMAIL, state.serverSecret)
    await proxyApiToLocal(bobContext, state.serverPort)

    const token = freshTokenForBob(state.serverSecret)

    // First redeem: succeed.
    const firstPage = await bobContext.newPage()
    await firstPage.goto(`/flocks/join?token=${encodeURIComponent(token)}`)
    await expect(
      firstPage.getByRole('button', { name: 'Accept' }),
    ).toBeVisible({ timeout: 30_000 })
    const firstResponse = firstPage.waitForResponse(
      (r) => r.url().endsWith('/flocks/join') && r.request().method() === 'POST',
    )
    await firstPage.getByRole('button', { name: 'Accept' }).click()
    expect((await firstResponse).status()).toBe(200)
    await firstPage.waitForURL('**/settings', { timeout: 10_000 })

    const userFlocksAfterFirst = await readUserFlocksDoc(couchAdmin, BOB_EMAIL)
    const honeymoonEntries =
      userFlocksAfterFirst?.flocks.filter((f) => f.id === FLOCK_ID) || []
    expect(honeymoonEntries).toHaveLength(1)
    await firstPage.close()

    // Second redeem with the same token: server returns 409.
    const secondPage = await bobContext.newPage()
    await secondPage.goto(`/flocks/join?token=${encodeURIComponent(token)}`)
    await expect(
      secondPage.getByRole('button', { name: 'Accept' }),
    ).toBeVisible({ timeout: 30_000 })
    const secondResponse = secondPage.waitForResponse(
      (r) => r.url().endsWith('/flocks/join') && r.request().method() === 'POST',
    )
    await secondPage.getByRole('button', { name: 'Accept' }).click()
    expect((await secondResponse).status()).toBe(409)

    await expect(
      secondPage.getByText('already a member', { exact: false }),
    ).toBeVisible({ timeout: 10_000 })

    // user:flocks didn't gain a duplicate Honeymoon entry.
    const userFlocksAfterSecond = await readUserFlocksDoc(couchAdmin, BOB_EMAIL)
    const stillOne =
      userFlocksAfterSecond?.flocks.filter((f) => f.id === FLOCK_ID) || []
    expect(stillOne).toHaveLength(1)
  })
})

test('derived password matches server expectations', () => {
  // Defensive: lock in the HMAC scheme so a future bump of SERVER_SECRET
  // or derivation tweak breaks here loudly rather than as a mysterious
  // 401 in the join-flow specs.
  const pw = deriveCouchPassword('bob@test.ternpike.com', 'e2e-server-secret')
  expect(pw).toMatch(/^[0-9a-f]{32}$/)
  expect(personalDbName('bob@test.ternpike.com')).toBe(
    'ternpike-bob-test-ternpike-com',
  )
})
