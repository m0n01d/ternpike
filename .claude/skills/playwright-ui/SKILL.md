---
name: playwright-ui
description: Take real browser screenshots of the Ternpike Elm app to vet a UI change or surface the current state of a page. Use after implementing a visual change, before reporting a UI task done, or during planning to show pixels rather than describe them. Handles the seed + auth stub + browser launch for auth-gated routes (Ledger, Stats, Scan, Add).
---

# Playwright UI vetting

Real browser screenshots of the Ternpike app. The dev server gates most pages on `auth_creds` in IndexedDB, so this skill handles the seed + auth stub + launch.

## When to use

- **After implementing a UI change** — screenshot the affected route and send with `SendUserFile` before reporting done. Don't describe pixels in prose when you can show them.
- **During planning** — capture the current state so the user sees what's changing.

## When *not* to use

- Logic-only changes (data shape, port plumbing, no visible diff). Don't run the browser just to confirm the app still loads.
- Auth-gated routes when there's no real session and you can't justify the IDB stub (rare; the stub below works).

## Prerequisites

```bash
npm install                                    # populates node_modules (~30s)
npx playwright install chromium                # one-shot, ~30s download
```

Both have to succeed before screenshots will work.

## Start the dev server

```bash
npm run dev:vite &                             # background, port 3000
until curl -sf http://localhost:3000/ > /dev/null; do sleep 1; done
```

`npm run dev` also starts the auth server on :4000 (via concurrently). Vite alone is enough for screenshots — the app degrades gracefully when the auth server is down.

## The minimal screenshot script

Write `scripts/screenshot.js` on demand (it's *not* checked in — delete when done; the stop hook flags untracked files):

```js
// node scripts/screenshot.js <route> <outfile> [tripName]
import { chromium } from 'playwright'
import { readFileSync } from 'node:fs'

const [, , route = '/trips', out = '/tmp/screenshot.png', tripName] = process.argv

// seed.html loads PouchDB from cdn.jsdelivr.net — sandboxed envs often
// can't reach it (ERR_CERT_AUTHORITY_INVALID). Serve the local copy.
const pouchdbBody = readFileSync(
  new URL('../node_modules/pouchdb/dist/pouchdb.min.js', import.meta.url),
  'utf8',
)

const browser = await chromium.launch()
const context = await browser.newContext({ viewport: { width: 390, height: 844 } })
await context.route('**/pouchdb.min.js', r =>
  r.fulfill({ status: 200, contentType: 'application/javascript', body: pouchdbBody }),
)
const page = await context.newPage()

// 1) Seed PouchDB with 6 trips + 180+ expenses.
await page.goto('http://localhost:3000/seed.html')
await page.waitForSelector('#done', { state: 'visible', timeout: 180_000 })

// 2) Stub auth_creds so the app boots into AuthModel.
await page.evaluate(async () => {
  const open = indexedDB.open('alaska-tracker', 1)
  await new Promise((resolve, reject) => {
    open.onupgradeneeded = e => e.target.result.createObjectStore('kv')
    open.onsuccess = () => resolve()
    open.onerror = () => reject(open.error)
  })
  const tx = open.result.transaction('kv', 'readwrite')
  tx.objectStore('kv').put(
    JSON.stringify({ dbName: 'm', email: 'mock@ternpike.test', password: 't' }),
    'auth_creds',
  )
  await new Promise(r => (tx.oncomplete = r))
  open.result.close()
})

// 3) Navigate via the Trips page, not by deep-linking. Deep URLs with
//    encoded `::` colons don't reliably re-select the trip; clicking
//    the trip name does.
await page.goto('http://localhost:3000/trips')
await page.waitForLoadState('networkidle')
await page.waitForTimeout(1500)

if (tripName) {
  await page.getByText(tripName, { exact: false }).first().click()
  await page.waitForTimeout(2000)
}

// Sub-route navigation after the trip is selected (in-app links).
if (route !== '/trips') {
  await page.goto(`http://localhost:3000${route}`)
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1500)
}

// fullPage:false — fullPage on a 180-row Pan-American ledger is 67000px
// tall and unreadable. Take the viewport unless you need scroll content.
await page.screenshot({ path: out, fullPage: false })
await browser.close()
console.log(`wrote ${out}`)
```

Run it:

```bash
node scripts/screenshot.js /trip/ledger /tmp/ledger.png "Alaska Highway"
```

Then `SendUserFile` the output path.

## Gotchas (learned the hard way)

1. **CDN egress is often blocked.** `seed.html` loads PouchDB from `cdn.jsdelivr.net`. If the seed page hangs and you see `ERR_CERT_AUTHORITY_INVALID` in console errors, intercept the request with `context.route()` as above. Don't extend the timeout — the script will never finish.

2. **`fullPage: true` is a trap on the Ledger.** A trip with 180+ expenses produces a 67000px image that's useless. Use `fullPage: false` (viewport-sized) and scroll the page in script if you need to see a specific row.

3. **Deep URLs with `tripId=trip::...::...` don't re-select the trip.** The route parser handles the query string fine, but the `Trips.selectTrip` hint coming through `TripsLoading` doesn't always swap the selected trip away from the most-recent one. Click in via `/trips` instead.

4. **`networkidle` is not enough.** PouchDB `GetTripExpenses` is a port round-trip, not a network request. Add `waitForTimeout(1500-3000)` after `networkidle` to let entries render.

5. **The IDB store name is `kv` inside DB `alaska-tracker`.** Don't rename either when stubbing — the app's startup code in `src/main.js` reads from those exact names.

6. **Browser console errors are gold.** Wire `page.on('console', m => console.log('[browser]', m.type(), m.text()))` before navigation — `ERR_CERT_AUTHORITY_INVALID`, `PouchDB is not defined`, port subscribe messages all show up there and explain why a screenshot looks blank.

7. **Clean up scripts.** `.claude/settings.json` has no entries for `scripts/` and `.gitignore` doesn't cover it. Delete `scripts/screenshot*.js` before ending the turn or the stop hook will block.

## Common routes (mobile viewport 390×844)

| Route | Notes |
|---|---|
| `/trips` | Always works; the entry point. |
| `/trip/ledger` | Default tab after picking a trip; the most-screenshotted page. |
| `/trip/stats` | Charts need a populated trip; Pan-American is the densest. |
| `/trip/add` | Form page; no data dependency. |
| `/trip/scan` | Empty by default. |
| `/settings` | Reachable from the header gear icon. |

## Capturing interactive states

For menus, modals, hover, anything that needs a click: extend the script with the action *before* the screenshot.

```js
await page.getByRole('button', { name: 'Row actions' }).first().click()
await page.waitForTimeout(300)
await page.screenshot({ path: out, fullPage: false })
```

Use `getByRole` / `getByText` (accessible-name queries) rather than CSS selectors — the Elm output's class names are stable but selectors get long, and the role queries also double-check accessibility.
