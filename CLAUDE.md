# Alaska Expense Tracker — Claude Notes

## Stack
- Elm 0.19.1 — split across `src/Main.elm`, `src/Pages/`, `src/UI/`, `src/Data/`, `src/Types.elm`, `src/Helpers.elm`
- Vite 8 + vite-plugin-elm
- Tailwind CSS v4 via `@tailwindcss/postcss` — config in `src/global.css` `@theme {}` block
- PouchDB for local-first storage; CouchDB sync working
- Anthropic API for OCR (receipt scanning)
- GitHub Pages deployment from `dist/` (CI triggers on push to main)
- Elm binary: `elm` (via asdf at `~/.asdf/shims/elm`)
- Node.js 22 required (set via `.tool-versions`)

## Build
```
npm run dev      # Vite dev server
npm run build    # produces dist/
```

## Git discipline
Never use `git checkout <branch> -- <file>` to resolve a stash conflict — it silently replaces the file with the committed version, discarding all stash changes.

Correct sequence when a stash pop conflicts:
1. Commit (or stage) work-in-progress **before** switching branches.
2. Resolve conflict markers manually, or use `git checkout --theirs <file>` / `git checkout --ours <file>` deliberately.
3. If a stash is accidentally dropped: `git fsck --lost-found` → find the dangling commit → `git show <sha>:<file>`

## Model architecture (GuestModel / AuthModel split)
`Model = GuestModel GuestState | AuthModel AuthState`
- Compiler enforces that auth-only pages (Scan, Add, Ledger, Stats) cannot be reached while signed out.
- 401 from any HTTP call → `GuestModel (toGuestState SessionExpired as_) + clearStorage ()`. No silent re-auth — the app is unverified by Google so tokens expire aggressively.
- Auth error messages live in `GuestReason` (FreshGuest | SessionExpired | MissingConfig), NOT in `model.error`.

## Architecture doc

`docs/architecture.md` explains the app for a new developer: PouchDB wiring, port protocol, Dict-based data modeling, document ID conventions, startup/sync sequence, lazy loading, amendments, and soft deletes.

**Keep it current.** Whenever you change any of the following, update `docs/architecture.md` in the same commit:
- `AuthState` fields or types in `Types.elm`
- Port definitions or the `pouchOut`/`pouchIn` message protocol
- Document ID schemes (`ExpenseId`, `TripId`, amendment/void ID formats)
- Any `Data/*.elm` type, encoder, or decoder
- Startup/sync sequencing logic in `Main.elm`
- Route-driven fetch logic (`fetchesForRoute`)
- The `Trips` zipper structure

If a section of the doc no longer matches the code, fix the doc — don't leave it stale.

## Elm style guide
- **Alphabetize** all record fields and all type constructor lists. Apply to every new type and every edit of an existing type.
- Always fully qualify imports. If you touch a module or function whose imports are not fully qualified, refactor them. You can expose the type, but not `(..)`.

```elm
-- don't do
import Json.Decode as D
import Html exposing (..)
import Html.Attributes exposing (..)

text "hello world"

-- do
import Json.Decode
import Html exposing (Html)
import Html.Attributes

Html.div [ Html.Attributes.class "tw-flex" ] [ Html.text "hello world" ]
```

- No inline styles — rewrite any `Html.Attributes.style` calls as Tailwind classes.
- Use `Html.Attributes.classList` for conditional classes or to organize flex, animation, translation, or responsive breakpoints.
- Use semantic markup — only `<button>` elements get click handlers.
- Aggressively refactor modules you touch; clean up tech debt as you go.

## Infrastructure

### Domain
- `ternpike.com` registered via Squarespace
- Nameservers need to be pointed to Cloudflare to enable Pages/Workers/Analytics

### Hosting plan (Cloudflare)
- `app.ternpike.com` → Cloudflare Pages (Elm SPA, `dist/`)
- `ternpike.com` → Cloudflare Pages (marketing page, `marketing/index.html`)
- `api.ternpike.com` → Cloudflare Worker (auth server, replaces `server/`)
- `couch.ternpike.com` → CouchDB (already live)
- Analytics: Cloudflare Web Analytics (cookie-free, non-Google)

### Auth server
- Currently Express + Gmail/Nodemailer in `server/` — not yet deployed
- Migrating to Cloudflare Worker + Cloudflare KV (for code storage) + Resend (email)
- In-memory `Map` for verification codes is a bug — KV fixes it
- GitHub issues: #4 (Worker rewrite), #5 (analytics)

### Email
- Replacing Gmail/Nodemailer with Resend (resend.com) — 3k emails/mo free
- Domain verification via Cloudflare DNS (DKIM/SPF records)

## Sheet columns
`A=id, B=date, C=amount, D=category, E=note, F=merchant, G=createdAt, H=lat, I=lon, J=longNote` — Range: A:J
