# Ternpike E2E harness

Real-browser, two-user end-to-end tests for Ternpike. Used by the `[Flock-E2E]`
issue track. The fixture spins up two `BrowserContext`s (Alice, Bob), each with
its own seeded PouchDB and stubbed `auth_creds`, against a shared real auth
server backed by a disposable CouchDB.

Separate from `.claude/skills/playwright-ui/SKILL.md`:

| Tool                   | Use it for                                     |
| ---------------------- | ---------------------------------------------- |
| `playwright-ui` skill  | one-off screenshots for UI vetting             |
| `e2e/` (this directory) | automated regression suite, two-user scenarios |

## Prerequisites

- Node 22 (see `.tool-versions`).
- Docker daemon running locally. The harness boots an ephemeral CouchDB
  container via `docker run` and tears it down in global teardown.
- `npm install` at the repo root pulls Playwright + the test runner.
- Chromium installed via `npx playwright install chromium`. In sandboxed
  environments the browsers may already live at `$PLAYWRIGHT_BROWSERS_PATH`.

## Commands

```bash
npm run e2e                 # headless, full suite
npm run e2e:headed          # headed run for local debugging
npm run e2e:update-snapshots # re-baseline visual screenshots (when specs add them)
```

Failures attach Playwright traces, videos, and screenshots under
`e2e/.results/` and a viewable HTML report under `e2e/.results/html/` in CI.

## Architecture

`playwright.config.ts` declares two projects (mobile 390×844, desktop
1280×800). `globalSetup` boots in order:

1. The mock Resend server (`utils/resend.ts`, ephemeral port).
2. A disposable CouchDB container via `docker run couchdb:3.3` on a random
   host port (`utils/couch.ts`).
3. The auth server via `wrangler dev` on port 4000, with all secrets and
   `COUCH_URL` overridden through `--var`. `RESEND_BASE_URL` is wired to
   point at the mock; specs that exercise outbound email will need a small
   server-side adapter in a follow-up issue, since the Resend Worker SDK
   does not currently honor that env var inside workerd.
4. The Vite dev server on port 3000.

State that fixtures need (mock URL, couch URL, ports) is written to
`e2e/.state/setup.json`. Process IDs are written to
`e2e/.state/processes.json` so `globalTeardown` can kill the entire process
group even after a hard crash.

## The two-user fixture

`fixtures/twoUsers.ts` exposes:

- `aliceContext` and `bobContext` — `BrowserContext`s with PouchDB seeded
  and `auth_creds` stubbed.
- `aliceSpec` and `bobSpec` — Playwright options. Override per-test with
  `test.use({ bobSpec: { email: '…', tier: 'Fly', seed: { trips: […] } } })`.
- `resendMock` — client over the mock's `/__captured` and `/__ping`
  endpoints.
- `couchAdmin` — admin client against the disposable CouchDB.

Default tiers: Alice = `Fly`, Bob = `Fledgling`. Override with
`test.use(...)` per spec. (`tier` is recorded on the spec for downstream
test logic; the field is not yet plumbed into the Elm `AuthState` — see
CLAUDE.md "Subscription tiers" for the planned wiring.)

## Adding a spec

1. Create `e2e/specs/<area>.spec.ts`.
2. Import from `../fixtures/twoUsers`:

   ```ts
   import { test, expect } from '../fixtures/twoUsers'

   test.use({
     bobSpec: {
       email: 'bob@test.ternpike.com',
       tier: 'Fly',
       seed: { trips: [{ name: 'Test', startDate: '2026-01-01', endDate: '2026-01-07' }] },
     },
   })

   test('alice invites bob', async ({ aliceContext, bobContext, resendMock }) => {
     // …
   })
   ```

3. Run `npm run e2e -- --grep "alice invites bob"` while iterating.
4. If the spec asserts a visual baseline, capture with
   `await expect(page).toHaveScreenshot('flock-invite-modal.png')` and
   commit the generated golden file under `e2e/screenshots/`. `*-actual.png`
   and `*-diff.png` are gitignored.

## Debugging locally

- `npm run e2e:headed` runs the Chromium UI; helpful for finding selector
  drift after Elm view edits.
- `PWDEBUG=1 npm run e2e` opens Playwright's inspector and breaks before
  every command.
- If a previous run aborted and Docker is still holding the CouchDB
  container, `docker rm -f ternpike-e2e-couch` clears it. The next run will
  also rm it as a best-effort first step.
- Auth server logs and Vite logs stream to the parent process stdout during
  `npm run e2e`. In CI they're captured in the job log.

## CI

`.github/workflows/e2e.yml` runs `npm run e2e` on every PR. The Docker
daemon and Chromium are available on the default `ubuntu-latest` runner.
Traces and screenshots from failed runs upload as a job artifact.
