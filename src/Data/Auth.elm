module Data.Auth exposing (AppConfig, Creds)

{-| Session credentials and runtime configuration.

`Creds` is the post-login bundle the auth server hands back: enough to
authenticate against the user's per-account CouchDB database. It's
stored in IndexedDB (`auth_creds`) so a returning visit can skip the
email-code dance, and it's cleared on sign-out or any 401.

`AppConfig` holds the values injected via the Vite flags object at
startup — the user's Anthropic API key and the backend base URL. The
Anthropic key is the user's own (BYO) and goes browser → Anthropic
directly; the Ternpike-owned key (paid tier) never appears here because
it must stay server-side. See `CLAUDE.md` for the BYO-vs-proxy split.

Neither type ships across PouchDB sync — both are device-local.

-}

import Data.AnthropicKey exposing (AnthropicKey)
import Data.SubscriptionStatus exposing (SubscriptionStatus)
import Data.Tier exposing (Tier)


{-| Per-user credentials returned by the auth server.

  - `dbName` — the user's per-account CouchDB database name.
  - `email` — the verified email address used to sign in.
  - `password` — the database password (a server-issued long token,
    not the user's typed password — the user authenticates with an
    email code, never a password).
  - `subscriptionStatus` — server-authoritative Stripe status at login
    time. `Nothing` for free users. Persisted alongside the rest of
    `Creds` so a returning visit boots with the right billing chrome
    without waiting on `/me`; refreshed via `/me` on startup.
  - `tier` — server-authoritative subscription tier at login time.
    Refreshed on every `/auth/verify-code` round-trip; persisted to
    IndexedDB alongside the rest of `Creds` so a returning visit
    boots with the right tier without waiting on `/me`.
  - `trailblazerNumber` — `Just n` (1..500) for confirmed Trailblazer
    purchases, `Nothing` for everyone else. Persisted alongside the
    rest of `Creds`; refreshed via `/me`.

-}
type alias Creds =
    { dbName : String
    , email : String
    , password : String
    , subscriptionStatus : Maybe SubscriptionStatus
    , tier : Tier
    , trailblazerNumber : Maybe Int
    }


{-| Runtime config sourced from Vite flags.

  - `anthropicKey` — the user's own Anthropic key (BYO). `Nothing`
    when not configured; the Scan tab silently skips OCR in that case.
    See `Data.AnthropicKey` for the opaque type and wire-compatible codecs.
  - `backendUrl` — base URL for the auth server (`/auth/request-code`,
    `/auth/verify-code`, eventually `/me` and `/scan`).
  - `vapidPublicKey` — the Web Push VAPID public key the JS handler
    passes to `pushManager.subscribe()`. Empty string when not
    configured (dev environments without VAPID set); the Settings
    UI's "Enable notifications" path silently no-ops in that case.

-}
type alias AppConfig =
    { anthropicKey : Maybe AnthropicKey
    , backendUrl : String
    , vapidPublicKey : String
    }
