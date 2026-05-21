module Data.Guest exposing (GuestReason(..), GuestSession)

{-| Pre-login state machine.

The guest flow is an email-code dance: enter email → server sends a
6-digit code → enter code → server returns `Creds`. `GuestReason`
discriminates the screens of that flow, plus two "boundary" states:
`NotLoggedIn` (the fresh-visit default) and `SessionExpired` (set when
any 401 kicks the user back from `AuthModel`).

`GuestSession` bundles the `AppConfig` with the current reason so that
`GuestState` only carries a single nested record instead of duplicating
config across both states.

Why `GuestReason` and not `model.error`: auth-flow messaging
("verifying…", "session expired — sign in to continue") is part of the
state machine, not an error. Real errors (network failure, wrong code)
go in `GuestState.authError` and are cleared on the next transition.

-}

import Data.Auth exposing (AppConfig)


{-| Where the user is in the email-code flow.

  - `NotLoggedIn` — fresh visit, no creds in IndexedDB.
  - `RequestingCode email` — POST to `/auth/request-code` in flight.
  - `AwaitingCode email` — server accepted the email; show the code
    input.
  - `VerifyingCode email code` — POST to `/auth/verify-code` in
    flight.
  - `SessionExpired` — kicked here from `AuthModel` by a 401; the UI
    shows a "session expired" chip so the user knows to sign in again.

-}
type GuestReason
    = AwaitingCode String
    | NotLoggedIn
    | RequestingCode String
    | SessionExpired
    | VerifyingCode String String


{-| The slice of guest state that survives every transition: the runtime
config plus the current step. Lives at `GuestState.session` so
config-mutating updates (e.g. the API-key field in the guest settings
panel) only touch one nested field.
-}
type alias GuestSession =
    { config : AppConfig
    , reason : GuestReason
    }
