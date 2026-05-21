---
name: run-ternpike
description: Build, run, test, and smoke-screenshot the Ternpike Elm app from a clean container. Use when asked to start ternpike, run its dev server, run tests, run elm-review, build dist/, or confirm the app boots. For deeper auth-gated screenshots (Ledger/Stats/Add/Scan/Settings) use the playwright-ui skill instead.
---

# Run Ternpike

Vite dev server (port 3000) serves the Elm SPA. The agent path drives the running server with `.claude/skills/run-ternpike/driver.mjs`, a Playwright smoke that fetches a route, asserts a 200, captures `pageerror`/`console.error`, and writes a screenshot.

All paths below are relative to the repo root (`ternpike/`).

## Prerequisites

Container baseline already includes Node 22 (`.tool-versions` pins `nodejs 22.16.0`; `node --version` reports `v22.22.2` here — that satisfies it) and `xvfb-run`. Chromium needs system libs for headless rendering — Playwright's bundled `chrome-headless-shell` runs on the stock container without extra `apt-get`. If a future image strips it, the canonical line is:

```bash
sudo apt-get update
sudo apt-get install -y libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
  libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
  libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2t64
```

## Setup

```bash
npm install                       # ~30s; populates node_modules, includes elm 0.19.1-6 and playwright 1.60
npx playwright install chromium   # ~30s; downloads chrome-headless-shell to /opt/pw-browsers/
```

The `server/` Cloudflare Worker has its own `package.json` — only install it if you need the auth server (`npm --prefix server install`). The Vite dev server alone is enough for the agent path; the app degrades gracefully when `:4000` is down.

No env vars are required for `npm run build`, `npm test`, or `npm run dev:vite`.

## Build

```bash
npm run build       # vite build → dist/, ~7s
```

Emits a `[plugin builtin:vite-reporter]` warning that `dist/assets/index.dev.js` is >500 kB. That's noise — the build still succeeds and writes `dist/index.html` + the asset bundle.

## Run (agent path)

Start Vite, wait for it, then drive it with the smoke driver. The driver fails loudly (non-zero exit, browser-error dump) if the page doesn't render.

```bash
# 1. Start vite in the background (PID for later kill).
npm run dev:vite > /tmp/vite.log 2>&1 &
until curl -sf http://localhost:3000/ > /dev/null; do sleep 1; done

# 2. Smoke the landing page.
node .claude/skills/run-ternpike/driver.mjs / /tmp/shots/landing.png

# 3. (Optional) screenshot another non-auth route.
node .claude/skills/run-ternpike/driver.mjs /seed.html /tmp/shots/seed.png

# 4. Stop vite.
pkill -f "node.*vite"
```

Expected output on success:

```json
{
  "url": "http://localhost:3000/",
  "title": "Ternpike",
  "sample": "Ternpike\n\nROAD LOG FOR THE LONG WAY NORTH\n\nCONTINUE\nSETTINGS\n1",
  "screenshot": "/tmp/shots/landing.png",
  "ok": true
}
```

Exit code 0 = title is set, body has text, page responded with 2xx. Exit 1 = page never loaded or rendered blank.

| command | what it does |
|---|---|
| `driver.mjs` (no args) | GETs `/`, screenshots landing to `/tmp/shots/ternpike-smoke.png` |
| `driver.mjs <route>` | GETs `http://localhost:3000<route>` |
| `driver.mjs <route> <out.png>` | Custom screenshot path |

Screenshots → wherever you point them. `pageerror` and `console.error` are echoed to stderr; harmless `ERR_CERT_AUTHORITY_INVALID` for `cdn.jsdelivr.net/.../pouchdb.min.js` shows up on landing because the page tries to lazy-load PouchDB. Ignore it for the smoke — auth-gated routes need the local-PouchDB intercept from the `playwright-ui` skill.

**For auth-gated routes (`/trips`, `/trip/*`, `/settings`)** use the `playwright-ui` skill — it handles the `seed.html` populate + IndexedDB `auth_creds` stub + the CDN intercept. This driver intentionally does not.

## Run (human path)

```bash
npm run dev          # vite on :3000 + auth worker on :4000 (concurrently)
npm run dev:vite     # vite only — fine for UI work, the app gracefully handles the auth API being down
```

Open `http://localhost:3000/` in a browser. Useless headless — use the agent path.

## Test

```bash
npm test             # elm-verify-examples && elm-test — 36 tests, ~300ms
```

First run installs `elm-test@0.19.1-revision17` via `npx` (`npm warn exec` is expected). Subsequent runs use the cached binary.

```bash
npm run review       # elm-review against review/src/ReviewConfig.elm
npm run review:fix   # auto-fix what it can; manual fixes for unused exports / missing type annotations
npm run format:check # elm-format src --validate
```

## Gotchas

- **`npx elm-test` on first run is slow and noisy.** It prints `npm warn exec` then downloads the binary. Not a failure. The actual test output reports `TEST RUN PASSED`.
- **Landing page logs `ERR_CERT_AUTHORITY_INVALID` for `cdn.jsdelivr.net`.** The Elm app calls `clearStorage`/`requestGeolocation` ports and the bootstrap pulls PouchDB from the CDN; the certificate fails in this container's egress. The landing page itself doesn't depend on PouchDB so it still renders. For pages that *do* need PouchDB, intercept the CDN URL with `context.route('**/pouchdb.min.js', …)` and serve `node_modules/pouchdb/dist/pouchdb.min.js` (this is what `playwright-ui` does).
- **`pkill -f vite` may exit 144 (signal).** That's how Bash reports a killed child of the harness, not a failure. Confirm with `ps aux | grep vite`.
- **The build emits "chunk > 500 kB" warnings.** It's the Elm runtime; the build still succeeds. Don't try to "fix" it as part of a run task.
- **`server/` is a separate npm project.** `npm install` at the root does NOT install the Worker's deps. Use `npm --prefix server install` if you actually need `wrangler dev`.
- **Untracked files in `scripts/` block the stop hook.** If you ad-hoc a `scripts/foo.mjs`, delete it before ending the turn — `CLAUDE.md` § Git discipline.

## Troubleshooting

- **`Cannot find package 'playwright'`**: you ran the driver from outside the repo root. `cd` to `ternpike/` (or wherever the unit lives) — Node's resolver looks up from CWD.
- **`net::ERR_CONNECTION_REFUSED` from the driver**: vite isn't running. Start it (`npm run dev:vite &`) and poll `curl -sf http://localhost:3000/` until ready before invoking the driver.
- **Driver exits 1 with `"ok": false`**: page returned 2xx but body was empty. Check `/tmp/vite.log` for Elm compile errors — `vite-plugin-elm` surfaces them as 200s with an error overlay rather than 5xx.
- **`elm-test` reports `Error: Could not find a binary for elm`**: rare race during first `npx` install. Re-run `npm test` — the second run picks up the cached binary.
