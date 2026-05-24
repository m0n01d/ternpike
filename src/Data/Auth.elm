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

import Data.Tier exposing (Tier)


{-| Per-user credentials returned by the auth server.

  - `dbName` — the user's per-account CouchDB database name.
  - `email` — the verified email address used to sign in.
  - `password` — the database password (a server-issued long token,
    not the user's typed password — the user authenticates with an
    email code, never a password).
  - `tier` — server-authoritative subscription tier at login time.
    Refreshed on every `/auth/verify-code` round-trip; persisted to
    IndexedDB alongside the rest of `Creds` so a returning visit
    boots with the right tier without waiting on `/me`.

-}
type alias Creds =
    { dbName : String
    , email : String
    , password : String
    , tier : Tier
    }


{-| Runtime config sourced from Vite flags.

  - `anthropicKey` — the user's own Anthropic key (BYO). Empty string
    when not configured; the Scan tab silently skips OCR when empty.
  - `backendUrl` — base URL for the auth server (`/auth/request-code`,
    `/auth/verify-code`, eventually `/me` and `/scan`).

-}
type alias AppConfig =
    { anthropicKey : String
    , backendUrl : String
    }
