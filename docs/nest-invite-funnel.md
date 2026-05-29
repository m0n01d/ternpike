# Nest Invite Funnel

> Status: **spec / planned.** This document is the design; the work is tracked as a multi-issue
> track (see "Issue track" at the bottom). No funnel code has shipped yet.

A "Nest" is a shared trip ledger that several people contribute to. This funnel turns a tapped
invite link into a retained, registered crewmate, with the lowest friction the web allows. It is
deliberately **more restrictive than full guest write access**: a guest may *view a redacted
preview* and *try one receipt scan*, but nothing is saved until they convert.

This is web, not native — there is no install wall. The link opens the trip in-browser. The hard
part is **retention**, not access.

## Goals & constraints

- Inviter path is **2 taps, no typing** (open trip → "Invite crew" → `navigator.share`).
- Guest reaches a value moment in **~10 seconds** (a live preview, optionally a scan).
- **Warm invites:** optimize for trust and speed, not fraud defense — but tokens must still
  **expire and be revocable**.
- **Offline-first:** the preview and scan degrade gracefully (they're network-only and say so);
  nothing about the funnel breaks the local-first app once the user converts.

## What already exists (reused, not rebuilt)

The crypto, validation, rendering, and PWA plumbing are already in place:

- `server/jwt.js` — `signJwt` / `verifyJwt` (HS256 over `SERVER_SECRET`). Today `verifyJwt` only
  pins the **header** `typ: "JWT"`; this funnel adds **payload** `typ` claims and every consumer
  must check them explicitly.
- `server/sharedTrips.js` — the existing email-bound invite (`POST /sharedtrips/:id/invite`, 7-day
  token `{flockId, inviteeEmail, inviter, iat, exp}`) and `POST /sharedtrips/join` (email-match
  redemption, adds the caller to CouchDB `_security.members` + `sharedtrip:meta.members`).
- `server/scan.js` (paid hosted OCR proxy) and `server/scanDemo.js` (public, email-gated, per-email
  daily rate-limit) — the templates for `/scan-guest`.
- `src/Data/Entry.elm` `Entry.resolve` and `src/Helpers.elm` `encodeWaypoints` — **pure**, no
  PouchDB/AuthState dependency; the post-join full ledger and map reuse them unchanged.
- `src/UI/MoneyView.elm` / `src/UI/DateView.elm` (`<tp-amount>` / `<relative-time>` web components,
  registered globally in `src/main.js`) — render in the guest tree with no auth dependency.
- PWA: `beforeinstallprompt` → `canInstall` port → `TriggerInstallPrompt`; `subscribePush` /
  `notificationState` ports + `server` `/notifications/*` (VAPID via `@block65/webcrypto-web-push`);
  iOS standalone gating in `src/Pages/Settings.elm`.

Two things that do **not** exist and the funnel must add as foundations: the guest view is **not
route-aware** today (`src/Pages/Guest.elm` always renders the login form), and `Pages.Ledger`'s
views are entangled with `AuthState` (tier gating, edit menus, member chips) so they **cannot** be
reused for a guest — the redacted teaser sidesteps this with a purpose-built card.

## A. Token model

Three token types, each pinned by a payload `typ` claim that every consumer verifies.

### Share token — `typ: "share"` (new, recipient-agnostic)

```
{ typ: "share", flockId, inviter, epoch, jti, iat, exp }   exp = iat + 30d
```

- **No `inviteeEmail`.** One link, anyone can open it — this is what makes the inviter path
  "2 taps, no typing." Minted by `POST /sharedtrips/:id/share-link` (owner-only).
- Authorizes `POST /invite/resolve` (redacted preview), `POST /scan-guest`, and — because the
  product intentionally chose shareable warm invites — `POST /sharedtrips/join` (any authenticated
  user holding a valid, non-revoked share token for the trip joins; **no email match**).
- **Accepted tradeoff:** anyone with the link can join. Bounded by (1) the preview being redacted,
  (2) revocation, (3) the frozen-trip check, and (4) the warm-invite assumption. This is a
  deliberate relaxation of "preview ≠ member grant" in favor of the share UX.

### Magic token — `typ: "magic"` (new, hardened)

```
{ typ: "magic", email, jti, iat, exp }   exp = iat + 5m
```

- Passwordless signup only. **One-time use** (consumed `jti` → KV deny-list). **Email-confirm at
  redemption** — `/auth/verify-magic-link` requires the user to re-submit the email and the server
  enforces the match. This defeats the forwarding login-CSRF (forwarding the email link must not let
  a third party create an account under the original recipient's address).
- Does **not** carry the invite; the share token (carried through the round-trip — see §D) drives
  auto-join after signup.

### Legacy email-bound invite — `typ: "invite"` / absent

- The existing `/sharedtrips/:id/invite` email path is unchanged. `/sharedtrips/join` keeps the
  email-match check for these tokens.
- **Back-compat:** 7-day invite tokens already in the wild have no payload `typ`. Treat an absent
  `typ` as `"invite"` so they keep working after this ships.

### Revocation

- **Per-trip `inviteEpoch`** (int) stored on `sharedtrip:meta`, baked into every share token at mint.
  The owner's "reset links" action bumps it; consumers compare token `epoch` to the live meta and
  reject on mismatch (403 `revoked`). One bump invalidates every outstanding share link at once.
- **Per-`jti` KV deny-list** (`INVITE_KV` key `revoked:<jti>`, TTL = remaining life) for killing a
  single leaked link and for magic-token single-use.

### Frozen trips & enumeration

- `/invite/resolve` and `/sharedtrips/join` **reject** `billingStatus === "frozen"` with
  403 `trip_frozen`.
- A deleted/nonexistent trip returns **403, not 404**, so an attacker cannot enumerate trip ids
  through the unauthenticated resolve endpoint.

## B. Invitee state machine

```
   share link in URL
        │
        ▼
  ┌──────────────┐  resolve 403/410/frozen
  │ S0 Resolving │ ───────────────────────► S6 InviteDead
  └──────────────┘
        │ resolve 200 { teaser, gate }
        ▼
  ┌────────────────────┐
  │ S1 RedactedPreview │  totals · counts · date range · placeholder map
  └────────────────────┘
     │ gate=view_only            │ gate=view_scan_preview
     │ (scan hidden)             ▼
     │                    ┌──────────────────┐  /scan-guest 200  ┌────────────────────┐
     │                    │ S2 GuestScanTry  │ ────────────────► │ S3 ScanResult +CTA │
     │                    └──────────────────┘                   └────────────────────┘
     │  "Join to save + see the full trip"  ◄──────────────────────────────┘
     ▼
  ┌────────────────────┐  request-magic-link 200 → email
  │ S4 ConversionWall  │ ───────────────────────────────► "check your email"
  └────────────────────┘
        │ verify-magic-link 200 (email-confirmed) → creds
        ▼
  ┌──────────────┐  auto POST /sharedtrips/join (share token)   409 → deep-link into trip
  │ S5 Converting│ ─────────────────────────────────────────────────────────────────────►
  └──────────────┘
        ▼
   AuthModel /trip/ledger?tripId=…  (full ledger + map, member)
```

| State | Model | View | Offline |
|---|---|---|---|
| S0 Resolving | `GuestModel` (new `RouteNestPreview`) | spinner | "needs a connection" |
| S1 RedactedPreview | `GuestModel` | new `Pages.NestPreview` teaser card | renders once fetched; nothing persisted |
| S2 GuestScanTry | `GuestModel` | scan dropzone (reuses `prepareOcrImage`) | dropzone disabled offline |
| S3 ScanResult | `GuestModel` | parsed fields + "Join to save" CTA | in-memory only |
| S4 ConversionWall | `GuestModel` | email entry → magic link | submit disabled offline |
| S5 Converting | `GuestModel → AuthModel` | brief spinner | (fresh load on link click) |
| Retained | `AuthModel` | existing `Pages.Ledger` full view | standard app behavior |
| S6 InviteDead | `GuestModel` | dead-invite card | n/a |

`S0–S4 are all `GuestModel`. S5 is the single `GuestModel → AuthModel` transition. The post-scan CTA
in S3 is load-bearing: without it a discarded scan is a dead-end. The scan-try is also the value hook
for **empty trips** (S1 with zero entries shows "No expenses yet — try a scan").

## C. API surface

**Reused unchanged:** `/auth/request-code`, `/auth/verify-code`, `/me`, `/scan`, `/scan-demo`,
`/sharedtrips/:id/invite` (the email-invite path stays).

**Modified — `POST /sharedtrips/join`:** accept `typ:"share"` (recipient-agnostic, no email match)
*and* legacy `typ:"invite"`/absent (email match); reject frozen; on **409 already-member** return the
`flockId` + `dbName` so the client can deep-link straight into the trip instead of dead-ending.

**New endpoints:**

| Method | Path | Auth | Returns / notes |
|---|---|---|---|
| POST | `/sharedtrips/:id/share-link` | Basic, owner | `{ ok, url }` with a `typ:"share"` token. Drives `navigator.share`. |
| POST | `/invite/resolve` | none (share token in body) | **Redacted teaser only** (below). `typ:"share"` pinned; frozen/enumeration handling. |
| POST | `/scan-guest` | share token in body | Inline `{ ok, ocr, remaining }`. Rate-limited (below). Never persists. |
| POST | `/auth/request-magic-link` | none | Mints `typ:"magic"` (+5m), emails `…/auth/magic?token=…&next=<shareToken>`. Always 200. |
| POST | `/auth/verify-magic-link` | none | Requires `{ token, email }`, enforces the email, single-use `jti`; provisions exactly like `/auth/verify-code` (same response body → reuse the `Creds` path). |

### Notification channels

Two channels coexist without double-notifying (#341):

| Channel | Endpoint | Email | Push |
|---|---|---|---|
| **Primary — share-link** | `POST /sharedtrips/:id/share-link` | None | None |
| **Secondary — email-invite** | `POST /sharedtrips/:id/invite` | Yes (Resend) | Yes (`sendSharedTripInvitePush`, 24h dedup) |

**Share-link is silent by design.** The server mints a `typ:"share"` JWT and returns the URL; the
inviter calls `navigator.share` client-side. No email is sent, no push is fired. The recipient
receives the link through whatever channel the inviter chose (iMessage, WhatsApp, etc.).

**Email-invite fires both email and push.** `POST /sharedtrips/:id/invite` sends a Resend email to
the named invitee and calls `sendSharedTripInvitePush` (fire-and-forget via `waitUntil`). The push
is deduplicated: if the same `(inviterEmail, inviteeEmail, sharedTripId)` tuple has already
triggered a push within the last 24h, the second call returns early. Dedup key format:
`push:invite-dedup:<inviter>:<invitee>:<tripId>` in `PUSH_KV` (TTL = 86400 s).

This means an owner can share a link and also send a direct email invite to the same person — the
two actions are independent and only the email-invite path produces server-side notifications.

**Redacted teaser** (`/invite/resolve` 200 body):

```jsonc
{
  "ok": true,
  "gate": "view_scan_preview",       // §F
  "tripName": "Honeymoon",
  "inviterName": "Alice",            // first name / display name — NOT the email
  "totalSpent": 1234.56,             // Float dollars (Money wire shape)
  "entryCount": 18,
  "dayCount": 6,
  "startDate": "2026-05-21",         // DateField wire shape
  "endDate": "2026-05-27",
  "memberCount": 2                   // a number, never the email list
}
```

Deliberately **omitted**: per-line amounts, merchant names, notes/`longNote`, exact `lat`/`lon`,
member emails, the inviter's email. The map in S1 is a placeholder ("N stops across M days"), not real
pins. Full data (decoded by the existing `Data.Expense`/`Amendment`/`Void` decoders, rendered by the
existing `Pages.Ledger`) arrives only **after join**, inside `AuthModel`.

**`/scan-guest` rate limiting** (no invitee email to key on under the recipient-agnostic model):
`scan-guest:<jti>:<utcDate>` (per token) **+** `scan-guest-ip:<ip>:<utcDate>` (per IP) **+** a global
`scan-guest:global:<utcDate>` daily circuit-breaker to cap total spend on Ternpike's Anthropic key.
The `ocr` shape mirrors `parseFirstReceipt` in `server/scanDemo.js`; `max_tokens` clamped as in
`server/scan.js`. **Ternpike's key never reaches the browser** (CLAUDE.md critical rule).

**CORS:** add `app.use('/invite/*', corsConfig)` and `app.use('/scan-guest', corsConfig)`; `/auth/*`
is already covered.

## D. Guest session handling

Recipient-agnostic means **no anonymous identity and no email pre-binding** — so the email-mismatch
dead-end (invited at one address, signs up with another, final join 403s) cannot occur; there is no
bound email to mismatch. The **share token is the session credential**; the teaser and any scan result
live in-memory on new `GuestState` fields (`invitePreview`, `guestScan`, `pendingShareToken`).

The magic-link click is a **fresh page load**, so the share token must survive the round-trip — carry
it as the `next` URL param on the magic link (and/or persist in IndexedDB like `pending_ref`). After
`verify-magic-link` returns creds, the client constructs `AuthModel`, starts sync, and **auto-POSTs**
`/sharedtrips/join` with the carried share token (one-tap conversion).

For variant (a) nothing is persisted, so claim/migration is a no-op. The seam for a future
`temp_session` (variant b) is a typed `GuestScanState = NoScan | Scanned OcrData` plus a
`claimGuestScan` function that (a) no-ops and (b) would replay the held `OcrData` as a `SaveExpense`
on the freshly-joined shared-trip handle.

## E. A2HS + web push (retention)

- **A2HS** prompt fires at **S5 → Retained** — the moment of maximal commitment. Reuses
  `showInstallPrompt` / `TriggerInstallPrompt`. Never prompted during S1–S4.
- **Push opt-in** is offered only when `notificationState.standalone` is true (iOS requires an
  installed PWA). Reuses `subscribePush`.
- **iOS reality (documented gap, push-only):** an iOS user previewing in Safari gets no
  `beforeinstallprompt` and no push until they manually install. We show an explicit "Add to Home
  Screen via the Share menu to get crew alerts" guidance card and **accept** that non-installers get
  no push retention. (No email-digest fallback in this track.)
- **Tier interaction:** shared-trip push is gated on the **billing owner's** tier on the server
  send-path, so a freshly-converted free (Tern) user joining an Osprey-owned trip still receives
  crew-activity push for that trip.

## F. The guest preview gate (config flag)

A single flag with three values tunes restrictiveness without reworking the flow:

- **Server:** constant `GUEST_PREVIEW_GATE = 'view_scan_preview'` (later optionally per-trip on
  `sharedtrip:meta.previewGate`), returned verbatim in `/invite/resolve`.
- **Elm:** `Data.GuestPreviewGate` = `ViewScanPreview | ViewOnly | TempSession`, decoder maps unknown
  → `ViewOnly` (safe default).
- **Routing through §B:** `ViewScanPreview` → full S1→S2→S3→S4; `ViewOnly` → scan affordance hidden,
  S1→S4 only; `TempSession` (future) → same surface, conversion replays the held scan via
  `claimGuestScan`. The Elm view branches on it exactly once (show/hide the scan dropzone).

## Security posture (summary)

This funnel inverts the existing flow's "reveal nothing until authenticated" stance, so the
mitigations are explicit and load-bearing:

1. **Redacted teaser** — the unauthenticated endpoint returns counts/totals/names only, never the
   per-entry ledger, GPS, notes, or member emails.
2. **Recipient-agnostic by design** — removes the email-mismatch dead-end; the share link is meant to
   be forwarded among the crew.
3. **Hardened magic link** — single-use `jti`, 5-minute expiry, and email-confirm at redemption defeat
   the forwarding login-CSRF.
4. **`typ` pinning everywhere** + absent-`typ`-is-`invite` back-compat.
5. **Revocation** — per-trip epoch (revoke-all) + per-`jti` deny-list (revoke-one).
6. **Frozen-trip reject + 403-not-404** anti-enumeration.
7. **`/scan-guest` cost control** — per-token + per-IP + global daily circuit-breaker; server-side key.

## Issue track

Filed as a 15-issue track (`[Invite]` / `[Auth]` / `[PWA]` / `[Analytics]` / `[Notifications]`),
sequenced in four waves:

- **Wave 0 (foundations):** guest route-awareness; server token + share-link + revocation
  scaffolding; Elm routes + `GuestPreviewGate`; `GuestState` fields + Msg anchors.
- **Wave 1:** `/invite/resolve` (redacted); `Data.NestPreview` decoder; hardened magic-link
  endpoints; `/sharedtrips/join` recipient-agnostic + back-compat.
- **Wave 2 (UI, serial on `Pages.NestPreview`):** redacted teaser + dead-invite; guest scan-try +
  `/scan-guest` + CTA; conversion wall + magic-link client + one-tap auto-join.
- **Wave 3:** post-join A2HS + push + iOS guidance; owner share-link management; funnel analytics;
  share-link vs email-invite channel reconciliation.

See the linked issues for per-unit What/Why/How, dependencies, and mockups.
