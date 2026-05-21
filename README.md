# Ternpike

Local-first trip expense tracker — scan receipts, log expenses, see totals per trip.

## Stack

- Elm 0.19.1 — `src/Main.elm` plus `src/Pages/`, `src/UI/`, `src/Data/`, `src/Types.elm`, `src/Helpers.elm`
- Vite 8 + `vite-plugin-elm`
- Tailwind CSS v4 via `@tailwindcss/postcss` (theme in `src/global.css`)
- PouchDB for local storage (CouchDB sync planned)
- Leaflet for waypoint maps; `exifr` for photo EXIF
- Anthropic API called directly from the browser for receipt OCR
- Cloudflare Pages deploys `dist/` (app) and `marketing/` (landing); auth API runs as a Cloudflare Worker in `server/`

See `CLAUDE.md` for the architectural notes (model split, append-only doc scheme).

## Prerequisites

- Node 22 (see `.tool-versions`)
- Elm 0.19.1

## Run locally

```bash
npm install
npm run dev
```

## Build

```bash
npm run build      # outputs to dist/
npm run preview    # serve the built dist/ locally
```

## Test

```bash
npm test           # runs elm-test; suites in tests/
```

## Sign in

Passwordless email + one-time code:

1. Enter your email.
2. Receive a code by email.
3. Enter the code. The session is persisted to PouchDB and survives reloads; Sign Out clears it.

## Receipt OCR (optional)

Paste an Anthropic API key into Settings. It's stored in the session config (PouchDB) and used directly from the browser by the Scan flow — no server in between.

## Tabs

| Tab | Purpose |
|-----|---------|
| Trips | Create or select a trip (budget, cover photo, dates). |
| Add | Manual expense entry — amount, category, note, date, geo. |
| Scan | Photo → Claude reads the receipt → pre-fills the form. Queues multiple images. |
| Ledger | Expenses grouped by date with daily totals; optional waypoint map. |
| Stats | Totals, category chart, daily and cumulative charts, top 5 expenses. |
| Settings | Anthropic key, sign out. |

## Categories

`Activities` · `Camp` · `Ferry` · `Food` · `Fuel` · `Gear` · `Lodging` · `Medical` · `Misc` · `Shopping` · `Transport`

## Storage

Append-only PouchDB documents: `trip`, `expense`, `amend`, `void`. Edits and deletions are recorded as new docs rather than mutating originals — see `CLAUDE.md` for the rationale and the planned CouchDB sync tiers.

## Deploy

Push to `main`. Cloudflare Pages picks up the commit via its Git integration and runs `npm run build`, publishing `dist/` to `app.ternpike.com`. SPA routing falls back through `public/_redirects` (`/* /index.html 200`). The marketing page (`marketing/`) deploys as a separate Pages project at `ternpike.com`. The auth Worker in `server/` deploys via `wrangler deploy` to `api.ternpike.com`.
