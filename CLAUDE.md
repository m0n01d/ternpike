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

Three tiers. Tracked on `AuthState` via `tier : Tier` where:

```elm
type Tier
    = Fledgling     -- free
    | Fly           -- $2.99/mo or $24/yr
    | Trailblazer   -- $79 one-time, capped at 500
```

Tier is server-authoritative — populated from the session at login + refreshed via `/me`, never trusted from the client. BYO keys (Anthropic / OpenAI / Gemini) are available on **all** tiers — paid does not take that away. Paid is purely additive.

- **Fledgling** (free, always) — BYO key only. OCR calls go browser → provider directly. One scan in flight at a time (client-side gate via `model.scanInFlight : Maybe ItemId`).
- **Fly** ($2.99/mo or $24/yr — saves $12 annually) — everything Fledgling has, plus: access to Ternpike's hosted Anthropic key (proxied through `api.ternpike.com/scan` so the key never touches the browser), and batch scanning. No quotas.
- **Trailblazer** ($79 one-time, first 500 only) — everything Fly has, no recurring charge ever, all 1.x updates included, and a loyalty discount on v2 when it ships. Feature-equivalent to Fly; the difference is billing mechanics and a permanent flag.

**Feature gating predicate.** For "is this paid?" checks use `Data.Tier.isPaid : Tier -> Bool` which returns True for `Fly` and `Trailblazer`. For UI that surfaces the specific plan (badges, billing screen) branch on the full type so the compiler forces you to handle all three.

**Critical rule:** Ternpike's Anthropic key NEVER ships to the browser. Any feature that uses it must call through the Worker proxy. If you find yourself wanting a Ternpike-owned secret in Elm/JS, you're doing it wrong — add a Worker endpoint instead.

**Feature gating pattern.** When adding a paid-only feature:
1. View functions take `tier : Tier` and branch via `Data.Tier.isPaid` for capability, or full `case` when rendering tier-specific UI.
2. Fledgling fallback should be either (a) an "Upgrade to use this" prompt, or (b) the BYO-key path if one exists for that feature.
3. Never hide the feature entirely — free users should know what paid unlocks.
4. Server endpoints back paid features must re-check tier on every request. Client-side gating is UX, not security.
5. **Trailblazer is permanent.** Webhook code never downgrades a Trailblazer. If you're writing logic that flips Trailblazer → Fledgling, that's a bug.

Tracking issues: #13 (BYO-key infrastructure, foundation for Fledgling), #14 (paid-only proxy + batch scanning), #4 (Cloudflare Worker rewrite, required for #14). Subscription infrastructure breakdown: #16–#22.

## Storage tiers — where data lives

Three places, picked deliberately. Misplacing data here causes real problems: secrets leak via sync, tier gets stale across devices, etc.

| What | Where | Why |
|---|---|---|
| JWT / session token | IndexedDB (`auth_creds`) | Device-local. Never sync. |
| BYO API keys (Anthropic/OpenAI/Gemini) | IndexedDB (`ai_config`, see #13) | PouchDB syncs to CouchDB — keys would land on the server. **Hard no.** |
| Subscription tier / status / `stripeCustomerId` | Server (Worker KV), hydrated into `AuthState` in memory at login + via `/me` | Server is source of truth. Re-checked on every gated endpoint. |
| Identity (email, googleSub) | Server, hydrated into `AuthState` | Same as tier. |
| User preferences (default currency, fav categories, UI prefs, preferred scan source) | PouchDB doc `_id = "user:profile"` | Syncs across the user's devices. Not secret. Not server-authoritative. |
| Expense / Trip / Amendment / Void | PouchDB (existing) | Domain data. |

**Rules:**
1. **PouchDB** = things the user wants synced across their own devices, that aren't secret and aren't server-authoritative.
2. **IndexedDB** = device-local secrets and caches (JWT, API keys, ephemeral state).
3. **Server** = identity, tier, billing. Anything that gates a paid feature must be re-checked server-side on every request.

Never cache `tier` in PouchDB — it'd sync stale state across devices when a user upgrades. The `/me` call on startup (#19) is the refresh path.

## Architecture doc

`docs/architecture.md` explains the app for a new developer: PouchDB wiring, port protocol, Dict-based data modeling, document ID conventions, startup/sync sequence, lazy loading, amendments, and soft deletes.

**Keep it current.** Whenever you change any of the following, update `docs/architecture.md` in the same commit:
- `AuthState` fields or types in `Types.elm`
- Port definitions or the `pouchOut`/`pouchIn` message protocol
- Document ID schemes (`ExpenseId`, `TripId`, amendment/void ID formats, `user:profile`)
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
