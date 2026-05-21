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

## Subscription tiers

The app is moving toward a two-tier model. Track this on `AuthState` (planned field: `tier : Tier` where `type Tier = Free | Paid { quotaUsed : Int, quotaLimit : Int }`). Tier is server-authoritative — populated from the session/JWT at login, never trusted from the client.

- **Free** — bring-your-own API key (Anthropic / OpenAI / Gemini). OCR calls go browser → provider directly. One scan in flight at a time (client-side gate via `model.scanInFlight : Maybe ItemId`). No access to Ternpike-hosted models.
- **Paid** — no key required. OCR is proxied through `api.ternpike.com/scan` (Cloudflare Worker) using Ternpike's Anthropic key. Batch scanning unlocked. Monthly quota enforced server-side in KV.

**Critical rule:** Ternpike's Anthropic key NEVER ships to the browser. Any feature that uses it must call through the Worker proxy. If you find yourself wanting a Ternpike-owned secret in Elm/JS, you're doing it wrong — add a Worker endpoint instead.

**Feature gating pattern.** When adding a paid-only feature:
1. Branch in `Main.elm` / page modules on `as_.tier` — render a different UI for `Free` vs `Paid`. The compiler will force you to handle both.
2. Free fallback for paid features should be either (a) a "Upgrade to use this" prompt, or (b) the BYO-key path if one exists for that feature.
3. Never hide the feature entirely — free users should know what paid unlocks.
4. Server endpoints back paid features must re-check tier on every request. Client-side gating is UX, not security.

Tracking issues: #13 (BYO-key infrastructure, foundation for Free tier), #14 (paid-tier proxy + batch scanning), #4 (Cloudflare Worker rewrite, required for #14).

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

## Doc comments and examples

Every exposed function in `src/Data/` must have a `{-| -}` doc comment. Every
new module needs a module-level doc comment. When you edit an existing function,
update its doc comment in the same commit.

For pure functions (`a -> b` with no JSON, opaque constructors, or effects),
include `-->` inline examples that `elm-verify-examples` can run:

```elm
{-| Convert a category to its wire-format label.

    label Fuel
    --> "fuel"
-}
label : Category -> String
```

The test pipeline is `elm-verify-examples && elm-test`. Modules with examples
are listed in `tests/elm-verify-examples.json`. Generated test files land in
`tests/VerifyExamples/` (gitignored). Add new modules to that list as you add
examples. Run with `npm test`.

**What qualifies for examples:** `Data.Category`, `Data.PaymentMethod`, and
any future pure helpers. Opaque ID types (constructors not exposed), encoders,
decoders, and HTML-returning functions don't need examples.

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
