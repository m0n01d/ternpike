# Key & secret rotation runbook

The canonical, single-source list of every secret Ternpike uses, where it lives,
how to confirm it's set, and how to rotate it safely. Work top-to-bottom when
doing a full rotation; jump to a single row when rotating one credential.

**Rules that never change:**

- Real secret **values never go in this repo.** Not in this file, not in
  `wrangler.toml`, not in any `.example`. The repo holds names and placeholders
  only. Back up actual values in a password manager (see "Backing up," below).
- **All runtime secrets live as Cloudflare Worker secrets on the `ternpike-auth`
  Worker** (`api.ternpike.com`), set via `wrangler secret put NAME` from
  `server/`. The two Pages projects (app + marketing) carry no secrets.
- **Deployment is manual** — there are no Cloudflare deploy credentials in CI.
  Rotating a secret takes effect on the next `wrangler deploy` from `server/`
  (a secret set with `wrangler secret put` is live immediately; a value changed
  in `.dev.vars` only affects local `wrangler dev`).

---

## 0. First: see what's currently set

```bash
cd server
wrangler secret list          # names currently set on ternpike-auth (values are never shown)
```

Compare that list against the "Full inventory" table below. Anything in the
table but missing from `wrangler secret list` is **unset** and needs setting.

`wrangler.toml` also carries a few **plaintext** config values (not secrets):
`COUCH_URL`, `RESEND_AUDIENCE_ID`, `STRIPE_RECEIPT_COUPON_ID` (currently empty).
Those are committed on purpose and don't rotate.

---

## 1. Full inventory

Legend for **Rotate**:
🟢 rotate anytime (external API key, no user-visible impact)
🟡 rotate deliberately (self-issued shared secret; update every caller)
🔴 rotate only with a plan (invalidates live user state)
⚪ not a secret / never rotate

| Secret | Owner | Rotate | Blast radius if rotated | Set via |
|---|---|---|---|---|
| `ANTHROPIC_API_KEY` | Anthropic | 🟢 | none (server OCR proxy picks up new key next request) | `wrangler secret put` |
| `RESEND_API_KEY` | Resend | 🟢 | none (verification-code + shared-trip emails) | `wrangler secret put` |
| `RESEND_WAITLIST_API_KEY` | Resend (scoped) | 🟢 | none (marketing waitlist writes only) | `wrangler secret put` |
| `STRIPE_SECRET_KEY` | Stripe | 🟢 | none (billing API calls) | `wrangler secret put` |
| `STRIPE_WEBHOOK_SECRET` | Stripe | 🟢 | brief window — see Stripe rotation note | `wrangler secret put` |
| `GOOGLE_GEOCODING_API_KEY` | Google Cloud | 🟢 | none — **move to the new Google account, see §4** | `wrangler secret put` |
| `COUCH_ADMIN_PASS` | CouchDB | 🟢 | must change on the CouchDB side in the same step | `wrangler secret put` |
| `COUCH_ADMIN_USER` | CouchDB | ⚪ | username, not usually rotated | `wrangler secret put` |
| `ADMIN_SECRET` | self-issued | 🟡 | re-login the admin TUI (`scripts/admin/.env`) | `wrangler secret put` |
| `TIER_WEBHOOK_SECRET` | self-issued | 🟡 | update any caller of the legacy tier-flip webhook | `wrangler secret put` |
| `SERVER_SECRET` | self-issued | 🔴 | **forces every user to re-login** — see §3 | `wrangler secret put` |
| `VAPID_PRIVATE_KEY` | self-issued | 🔴 | **kills every push subscription** — see §3 | `wrangler secret put` |
| `VAPID_PUBLIC_KEY` | self-issued | 🔴 | paired with the private key; rotate together | `wrangler secret put` |
| `VAPID_SUBJECT` | — | ⚪ | just a `mailto:` contact string | `wrangler secret put` |
| `VITE_VAPID_PUBLIC_KEY` | — | ⚪ | client build copy of the VAPID public key; keep in sync | Vite env (`.env.local`) |
| `STRIPE_PRICE_OSPREY_MONTHLY` | Stripe | ⚪ | `price_…` config id, not a secret | `wrangler secret put` |
| `STRIPE_PRICE_OSPREY_YEARLY` | Stripe | ⚪ | `price_…` config id | `wrangler secret put` |
| `STRIPE_PRICE_TRAILBLAZER` | Stripe | ⚪ | `price_…` config id | `wrangler secret put` |
| `RESEND_AUDIENCE_ID` | Resend | ⚪ | resource id, committed in `wrangler.toml` | `[vars]` |
| `STRIPE_RECEIPT_COUPON_ID` | Stripe | ⚪ | optional coupon id, committed in `wrangler.toml` | `[vars]` |
| `TURNSTILE_SECRET_KEY` | Cloudflare | ⚪ | **DEAD** — not read by any current code; ignore/delete | — |

**KV namespace ids, the `TRAILBLAZER_SLOTS` Durable Object, and all `*_BASE_URL`
overrides are infrastructure, not secrets — don't rotate them.**

---

## 2. Standard rotation (the 🟢 / 🟡 rows)

Same shape for every external key. Example with Anthropic:

```bash
# 1. Mint a new key in the provider dashboard (see per-provider links below),
#    keeping the old one alive for now.
# 2. Set it on the Worker:
cd server
wrangler secret put ANTHROPIC_API_KEY      # paste the new value at the prompt
# 3. Deploy (secrets are live immediately, but deploy to be certain the running
#    code is current) and smoke-test the feature that uses it (see §6).
wrangler deploy
# 4. Revoke/delete the OLD key in the provider dashboard once the smoke test passes.
# 5. Mirror the new value into your local server/.dev.vars and your password manager.
```

Provider dashboards:

- **Anthropic** (`ANTHROPIC_API_KEY`) — console.anthropic.com → API Keys.
- **Resend** (`RESEND_API_KEY`, `RESEND_WAITLIST_API_KEY`) — resend.com → API Keys.
  The waitlist key is a *separate, scoped* token; rotate the two independently.
- **Stripe** (`STRIPE_SECRET_KEY`) — dashboard.stripe.com → Developers → API keys →
  "Roll key" (Stripe keeps the old one valid for a grace window you control).
- **Stripe webhook** (`STRIPE_WEBHOOK_SECRET`) — Developers → Webhooks → your
  endpoint → "Roll signing secret." **There's a brief window where in-flight
  events may be signed with the old secret**; roll it during a quiet period and
  redeploy promptly.
- **Google Geocoding** (`GOOGLE_GEOCODING_API_KEY`) — see §4 (this is the account-move one).
- **CouchDB** (`COUCH_ADMIN_PASS`) — change the admin password on the CouchDB
  server (`couch.ternpike.com`) **and** `wrangler secret put COUCH_ADMIN_PASS`
  in the same maintenance step, or admin sync operations will 401 in between.
- **`ADMIN_SECRET` / `TIER_WEBHOOK_SECRET`** (self-issued) — generate with
  `openssl rand -hex 32`, `wrangler secret put`, then update every caller
  (for `ADMIN_SECRET`: your local `scripts/admin/.env`).

---

## 3. The careful ones (🔴 — read before touching)

### `SERVER_SECRET`

HMAC-derives every user's CouchDB password **and** signs JWTs. Rotating it means
every stored credential and every issued token becomes invalid → **every user is
forced to re-login**, and their locally-derived CouchDB creds stop matching until
they do. Only rotate this if it's actually been exposed. If you must:

- Do it during a low-traffic window and communicate the forced re-login.
- Expect a support wave; there is no gradual/dual-key path in the current code.

### `VAPID_PRIVATE_KEY` / `VAPID_PUBLIC_KEY`

The web-push keypair is **permanent by design.** Re-keying invalidates every
existing push subscription (all devices silently stop receiving notifications
until each re-subscribes). Regenerate only if the private key leaked:

```bash
npx web-push generate-vapid-keys      # prints a new public/private pair
```

Then set **all three in lockstep** and rebuild the client so the public halves match:
`wrangler secret put VAPID_PRIVATE_KEY`, `wrangler secret put VAPID_PUBLIC_KEY`,
and update `VITE_VAPID_PUBLIC_KEY` in `.env.local` (client build). A mismatch
between the client's `VITE_VAPID_PUBLIC_KEY` and the server's `VAPID_PUBLIC_KEY`
breaks subscription silently.

---

## 4. Google Geocoding key → new dedicated Google account

`GOOGLE_GEOCODING_API_KEY` is the **only** Google credential in the whole system.
There is no Google OAuth, no service account, no Gmail/SMTP — auth is entirely
email-code based, so the new Ternpike Gmail only matters for this one key.

To move it onto the new account:

1. Sign in to Google Cloud Console with the new Ternpike Google account.
2. Create (or select) a Ternpike project → enable the **Geocoding API**.
3. Create an API key. **Restrict it**: API restriction → Geocoding API only;
   optionally add an application restriction. (This key is server-side only —
   it never ships to the browser, called from `server/geocode.js`.)
4. `cd server && wrangler secret put GOOGLE_GEOCODING_API_KEY` → paste the new key.
5. `wrangler deploy`, then smoke-test geocoding (§6).
6. Delete the old key from the old Google account once geocoding works.
7. Update `server/.dev.vars` + your password manager.

---

## 5. Local dev + backup files to keep in sync

After any rotation, update these **gitignored** local files so `npm run dev` and
the admin TUI keep working (none are committed; templates are the `.example` files):

| File | Holds | Template |
|---|---|---|
| `server/.dev.vars` | all server secrets for `wrangler dev` | `server/.dev.vars.example` |
| `scripts/admin/.env` | `ADMIN_SECRET`, `TERNPIKE_API` | `scripts/admin/.env.example` |
| `.env.local` | `VITE_VAPID_PUBLIC_KEY` (client build) | `.env.example` |

### Backing up

The durable backup of real values is **your password manager**, not this repo.
Store one entry per secret (or one secure note listing all of them) labelled
"Ternpike Worker secrets." After a full rotation, that note and `wrangler secret
list` should agree on the *names*, and the note holds the current *values*.

---

## 6. Post-rotation verification

- `cd server && wrangler secret list` → matches §1 (nothing missing).
- **OCR / Anthropic** — scan a receipt on a paid (Osprey) account; it routes
  through the Worker proxy.
- **Email / Resend** — request a login code; confirm it arrives.
- **Geocoding / Google** — batch-scan a receipt with an address, or hit the
  admin geocode path; confirm a lat/lon comes back.
- **Stripe** — trigger a test checkout and confirm the webhook is accepted
  (Stripe Dashboard → Webhooks → recent deliveries = 200).
- **CouchDB** — confirm sync still settles after an admin-pass change.
- **Push (only if VAPID rotated)** — re-subscribe on a device and send a test push.
- `cd server && npm run test:server` for a fast sanity pass on server logic.

---

## 8. Staging environment (deployed Stripe-test bed)

A second deployed Worker, `ternpike-auth-staging`, runs the same code with
**Stripe in test mode** so billing can be exercised on a real hosted URL (not
localhost). Configured as a wrangler environment in `server/wrangler.toml`
(`[env.staging]`), it does **not** touch production secrets.

**Isolation model:** KV is fully separate (test-mode webhooks can't flip real
tiers); CouchDB is shared with prod; no cron triggers. Because per-user CouchDB
passwords are `HMAC(SERVER_SECRET, email)`, staging's `SERVER_SECRET`,
`COUCH_ADMIN_USER`, and `COUCH_ADMIN_PASS` **must be copied verbatim from prod**.

### One-time bring-up

**1. Create the staging KV namespaces** and paste each returned id into the
`[env.staging]` block of `server/wrangler.toml` (replacing the `REPLACE_WITH_…`
placeholders):

```bash
cd server
for ns in CODES_KV TIERS_KV GEOCODE_RL_KV GEOCODE_CACHE_KV PUSH_KV INVITE_KV QR_KV; do
  wrangler kv namespace create "${ns}_staging"
done
```

**2. Set the staging secrets** (all per-env — secrets do not cross environments):

```bash
# --- MUST match prod (shared CouchDB) — copy the same values ---
wrangler secret put SERVER_SECRET      --env staging
wrangler secret put COUCH_ADMIN_USER   --env staging
wrangler secret put COUCH_ADMIN_PASS   --env staging

# --- Stripe TEST mode (from the Stripe dashboard in Test mode) ---
wrangler secret put STRIPE_SECRET_KEY           --env staging   # sk_test_...
wrangler secret put STRIPE_WEBHOOK_SECRET       --env staging   # whsec_... (set after step 4)
wrangler secret put STRIPE_PRICE_OSPREY_MONTHLY --env staging   # test-mode price_...
wrangler secret put STRIPE_PRICE_OSPREY_YEARLY  --env staging   # test-mode price_...
wrangler secret put STRIPE_PRICE_TRAILBLAZER    --env staging   # test-mode price_...

# --- Functional keys: reuse prod values, or use test-only keys if you have them ---
wrangler secret put ANTHROPIC_API_KEY        --env staging
wrangler secret put RESEND_API_KEY           --env staging
wrangler secret put RESEND_WAITLIST_API_KEY  --env staging
wrangler secret put GOOGLE_GEOCODING_API_KEY --env staging
wrangler secret put VAPID_PUBLIC_KEY         --env staging
wrangler secret put VAPID_PRIVATE_KEY        --env staging
wrangler secret put VAPID_SUBJECT            --env staging

# --- Staging-own (generate fresh; don't reuse prod) ---
wrangler secret put ADMIN_SECRET        --env staging   # openssl rand -hex 32
wrangler secret put TIER_WEBHOOK_SECRET --env staging   # openssl rand -hex 32
# TURNSTILE_SECRET_KEY: skip — dead code.
```

**3. Deploy staging:**

```bash
npm run deploy:staging          # == wrangler deploy --env staging
```

Note the printed URL: `https://ternpike-auth-staging.<your-subdomain>.workers.dev`.

**4. Point a Stripe TEST-mode webhook at staging:** Stripe Dashboard (Test mode
toggle ON) → Developers → Webhooks → Add endpoint →
`https://ternpike-auth-staging.<subdomain>.workers.dev/stripe/webhook`. Copy that
endpoint's signing secret (`whsec_…`) into `STRIPE_WEBHOOK_SECRET --env staging`
(step 2), then `npm run deploy:staging` again so it's picked up.

**5. Smoke-test:** hit the staging URL, start a checkout, complete it with test
card `4242 4242 4242 4242`, and confirm the webhook delivery shows `200` in the
Stripe (test) dashboard and the tier flips in the **staging** `TIERS_KV`.

### Verify / list staging secrets

```bash
wrangler secret list --name ternpike-auth-staging
```

### Rotating a staging key later

Same as §2 but with `--env staging`, e.g.
`wrangler secret put STRIPE_SECRET_KEY --env staging && npm run deploy:staging`.
Production and staging rotate independently.

### Validate the config before first deploy

`[env.*]` inheritance is easy to get subtly wrong; dry-run first:

```bash
cd server && wrangler deploy --env staging --dry-run --outdir /tmp/wrangler-staging-check
```

A clean dry-run means the bindings/migrations resolve. Placeholder KV ids will
still be rejected on a real deploy — fill them in from step 1 first.

---

## 9. Cleanup opportunity (optional)

`TURNSTILE_SECRET_KEY` is referenced only in a `wrangler.toml` comment and read
by no current code. If it's still set on the Worker you can remove it with
`wrangler secret delete TURNSTILE_SECRET_KEY` — nothing depends on it.
