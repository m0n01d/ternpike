# Push Notification Setup

This document covers VAPID key generation, Worker secret provisioning, the
client-side environment variable, and the manual test-push + local-cron
workflows.

---

## Generating VAPID keys (one-time, PERMANENT)

VAPID keys identify the server to push services. They are **permanent** — if
you regenerate them, every active subscription on every user device becomes
invalid and the user must re-subscribe. Save both keys in a password manager
immediately after generating them.

```bash
npx web-push generate-vapid-keys
```

Output looks like:

```
Public Key:
BNy...

Private Key:
X0k...
```

Keep the private key secret. The public key is safe to embed in the client
bundle (it is just an identity key, not an auth credential), but it must match
what the Worker has in `VAPID_PUBLIC_KEY`.

---

## Setting Worker secrets

Run these in the `server/` directory once per environment (production, staging,
etc.). `wrangler secret put` prompts for the value interactively and never
writes it to disk.

```bash
cd server
npx wrangler secret put VAPID_PRIVATE_KEY   # paste the private key from above
npx wrangler secret put VAPID_PUBLIC_KEY    # paste the public key from above
npx wrangler secret put VAPID_SUBJECT       # mailto:ops@ternpike.com
```

`VAPID_SUBJECT` is a contact address the push service can reach if there is a
delivery problem. Use the `mailto:` scheme.

**All environments must use the same VAPID key pair.** If staging and
production use different keys, subscriptions created on one environment will
fail on the other.

---

## Client-side environment variable

The service worker needs the public key at subscribe time to create the push
subscription. It is injected as a build-time environment variable:

- **Local dev**: add to `.env` at the project root:
  ```
  VITE_VAPID_PUBLIC_KEY=BNy...
  ```
- **Production**: set `VITE_VAPID_PUBLIC_KEY` in the Cloudflare Pages build
  environment variables (Pages → Settings → Environment variables → Production).

The value must be the same base64url-encoded string as `VAPID_PUBLIC_KEY` in
the Worker.

---

## Triggering a test push manually

After subscribing a device via the Settings page, send a test push without
waiting for Friday:

```bash
curl -X POST https://api.ternpike.com/admin/test-push \
  -H 'x-admin-secret: <ADMIN_SECRET>' \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com"}'
```

A successful response looks like:

```json
{ "ok": true, "sent": 1 }
```

`sent` is the number of subscriptions that received the push (one per
subscribed device). If the email has no subscriptions, `sent` is 0 but `ok`
is still `true`. Non-paid users get:

```json
{ "ok": false, "reason": "not-paid", "sent": 0 }
```

---

## Triggering the Friday cron in local dev

Start the dev worker with the `--test-scheduled` flag:

```bash
cd server
npx wrangler dev --test-scheduled --port 4000
```

Then trigger the Friday cron pattern:

```bash
curl 'http://localhost:4000/__scheduled?cron=0+17+*+*+5'
```

This calls `sendWeeklyScanReminders(env)` with your local `wrangler.toml`
bindings. Real VAPID keys + a real subscribed device are needed for the push to
arrive; without them the sweep runs but no push is dispatched.
