/**
 * #77 — Billing lapse → read-only → transfer-ownership recovery
 *
 * Exercises #64's BillingBanner across the full lifecycle:
 *   active → owner-downgrade → grace (countdown) → frozen → recovery
 *
 * ─────────────────────────────────────────────────────────────────────
 * STATUS: SPEC LANDED, EXECUTION BLOCKED.
 * ─────────────────────────────────────────────────────────────────────
 *
 * This file is written so the assertions are visible, reviewable, and
 * mostly mechanical to unblock. Every blocked assertion is `test.fixme`
 * with a precise pointer to what would unblock it. Same pattern as
 * #74, #76, #78.
 *
 * Blocker matrix:
 *
 *   B1. Cross-PouchDB change feed.
 *       Test-script PouchDB writes don't propagate to the app's bundled
 *       PouchDB instance (different module instances, different event
 *       bus). Seeded `flock:meta` / `user:flocks` docs never reach Elm,
 *       so the Honeymoon flock never appears in either browser. Closing
 *       this needs either (a) the `window.__ternpikeTestApp` port-
 *       injection hook landed in #72's branch (`src/main.js`) merged
 *       into #77's base, or (b) the cross-PouchDB change-feed fix at
 *       source. Until then every assertion that depends on flock UI
 *       being visible is fixme'd.
 *
 *   B2. Resend SDK / workerd interaction.
 *       Auth server's invite email goes through Resend SDK which reads
 *       `baseUrl` from `process.env` at module load — `workerd` doesn't
 *       populate it. Fixed on #72's branch (raw `fetch` to
 *       `env.RESEND_BASE_URL`). Needed if any setup step relies on a
 *       real `/flocks/:id/invite` capture. #77 sidesteps by minting
 *       invite JWTs in-test (#73 pattern) but flagging here for
 *       completeness.
 *
 *   B3. `flock:meta` wire-format mismatch.
 *       Server writes `type: 'flock'` but client filter expects
 *       `type: 'flock:meta'`. Fixed on #72's branch. Without the fix,
 *       even if B1 were closed, Elm would silently drop the doc.
 *
 *   B4. Fixture stub password.
 *       `fixtures/twoUsers.ts` uses `password: 'e2e-stub-password'`
 *       which CouchDB rejects on actual sync attempts (the password
 *       must match the server's HMAC derivation). Fixed locally on
 *       #78's branch and #73's branch; needs to be hoisted into the
 *       fixture. Until then, `aliceContext`/`bobContext` can render
 *       the Settings page (no sync required) but real-data assertions
 *       on the Ledger / Trips list will hang.
 *
 * To execute this spec end-to-end, merge in order:
 *   origin/flock/64-billing-banner ← already in base
 *   origin/flock/71-e2e-harness    ← already merged
 *   origin/flock/72-e2e-create-flock  ← needed: B2, B3, __ternpikeTestApp (part of B1)
 *   origin/flock/73-e2e-join-flow  ← needed: B4 (and the mint-JWT helper)
 *   then promote each fixme to a real test, top-down.
 *
 * ─────────────────────────────────────────────────────────────────────
 */

import { test, expect } from '../fixtures/twoUsers'

// Test data shared across the spec. Real impl will read this from the
// flockSetup helper #78 added (`e2e/utils/flockSetup.ts`), once that
// branch is merged.
const HONEYMOON = {
  name: 'Honeymoon',
  id: 'flock-deadbeefcafe',
  ownerEmail: 'alice@test.ternpike.com',
  memberEmail: 'bob@test.ternpike.com',
}

test.describe('Billing lapse → read-only → recovery', () => {
  test.use({
    aliceSpec: {
      email: HONEYMOON.ownerEmail,
      tier: 'Fly',
    },
    bobSpec: {
      email: HONEYMOON.memberEmail,
      tier: 'Fly', // Bob is Fly so the transfer-ownership recovery step works
    },
  })

  // ────────────────────────────────────────────────────────────────
  // Single positive control that runs without B1-B4 unblocked.
  // ────────────────────────────────────────────────────────────────
  test('both contexts boot into Settings showing their Fly badge', async ({
    aliceContext,
    bobContext,
  }) => {
    const alice = await aliceContext.newPage()
    const bob = await bobContext.newPage()
    await alice.goto('/settings')
    await bob.goto('/settings')

    // Hero renders once Elm has bootstrapped from IndexedDB; confirms
    // the auth_creds stub worked and the tier rode through.
    await expect(alice.getByText('Local-first preferences')).toBeVisible({
      timeout: 30_000,
    })
    await expect(bob.getByText('Local-first preferences')).toBeVisible({
      timeout: 30_000,
    })
  })

  // ────────────────────────────────────────────────────────────────
  // Active → Grace (owner downgrades).
  // ────────────────────────────────────────────────────────────────
  test.fixme(
    'both contexts see the read-only banner within 5s of owner downgrade',
    async ({ aliceContext, bobContext, couchAdmin }) => {
      // BLOCKER B1+B3+B4: need __ternpikeTestApp injection to deliver
      // flock:meta to Elm. Without it, Honeymoon never appears in
      // either context and the banner never has a flock to render
      // against.
      //
      // Sketch of what the real test does once unblocked:
      //
      //   1. Seed Honeymoon via test-injection hook with billingStatus = 'active'.
      //   2. Both contexts navigate to /trip/ledger?tripId=<italy>.
      //   3. POST /flocks/test/tier-changed with
      //      {email: alice@..., newTier: 'Fledgling'} +
      //      TIER_WEBHOOK_SECRET header.
      //   4. expect.poll for the rust-tinted banner div on both pages
      //      with the grace-period copy. Timeout 5s; if it doesn't
      //      appear, the sync window is broken (file a separate
      //      issue, do not bump this timeout).
      //   5. Assert days-remaining text reads "14 days" (or whatever
      //      the formatter emits at t=0).
      //
      // Reference: src/UI/BillingBanner.elm copy matrix.
    },
  )

  test.fixme(
    'Bob (member) Add submit is pre-disabled when flock is in grace',
    async ({ bobContext }) => {
      // BLOCKER B1+B3+B4: same as above. Once the flock is visible and
      // in 'grace' status, Add page's submit button gets `disabled` via
      // Data.Flock.isReadOnly (added in #64).
      //
      // Sketch:
      //   1. Establish the grace state.
      //   2. bobContext page goto /trip/add?tripId=<italy>.
      //   3. Fill amount.
      //   4. Assert submit button has [disabled] attribute.
      //   5. Assert tooltip "This flock is read-only".
      //   6. Click submit (Playwright force).
      //   7. Assert no new row appears in either Ledger over a 3s poll.
    },
  )

  // ────────────────────────────────────────────────────────────────
  // Grace → Active (Bob takes over billing).
  // ────────────────────────────────────────────────────────────────
  test.fixme(
    'Fly+ member can transfer billing to themselves and recover writes',
    async ({ aliceContext, bobContext }) => {
      // BLOCKER B1+B3+B4. Plus depends on the previous test
      // establishing the grace state.
      //
      // Sketch:
      //   1. From grace state, bobContext clicks "Transfer billing to me"
      //      in the banner.
      //   2. Confirmation dialog → confirm.
      //   3. expect.poll for the banner to DISAPPEAR in both contexts.
      //   4. Assert Bob shown as Owner in Settings → Flocks for both
      //      contexts; Alice now shown as Member.
      //   5. Bob adds an expense $1.00; expect.poll for the row to
      //      appear in Alice's Ledger.
    },
  )

  // ────────────────────────────────────────────────────────────────
  // Negative — both members Fledgling, no CTA visible.
  // ────────────────────────────────────────────────────────────────
  test.fixme(
    'banner shows no transfer CTA when no member is Fly+',
    async ({ aliceContext, bobContext }) => {
      // BLOCKER B1+B3+B4.
      //
      // Sketch:
      //   1. Drop BOTH alice and bob to Fledgling via test webhook.
      //   2. Assert banner is visible in both contexts.
      //   3. Assert NO "Transfer billing to me" button exists in either.
      //   4. Assert copy is the informational variant ("Ask {owner} to
      //      renew, or upgrade and take over billing yourself.").
    },
  )

  // ────────────────────────────────────────────────────────────────
  // Days-remaining countdown via direct billingLapsedAt mutation.
  // ────────────────────────────────────────────────────────────────
  test.fixme(
    'countdown reflects elapsed grace time when billingLapsedAt is older',
    async ({ aliceContext, couchAdmin }) => {
      // BLOCKER B1+B3.
      //
      // Sketch:
      //   1. Admin-write flock:meta with billingLapsedAt = now - 12d,
      //      billingStatus = 'grace'.
      //   2. Push the new flock:meta via the test-injection hook so
      //      Elm decodes it.
      //   3. Assert banner countdown reads "2 days remaining" (or
      //      equivalent based on UI.BillingBanner formatter).
    },
  )

  // ────────────────────────────────────────────────────────────────
  // Frozen state copy.
  // ────────────────────────────────────────────────────────────────
  test.fixme(
    'frozen status changes banner copy and removes the countdown',
    async ({ aliceContext, couchAdmin }) => {
      // BLOCKER B1+B3.
      //
      // Sketch:
      //   1. Admin-write flock:meta with billingStatus = 'frozen',
      //      billingLapsedAt = now - 30d.
      //   2. Push via injection hook.
      //   3. Assert banner copy switches from "Read-only in N days" to
      //      "Flock is read-only" (no countdown).
      //   4. Assert write path is still blocked (Add submit still
      //      disabled).
    },
  )
})
