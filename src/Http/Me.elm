module Http.Me exposing (fetch)

{-| HTTP client for `GET /me` on the auth server.

`/me` is the server-authoritative refresh path for tier + billing
state. Called on app startup (to absorb any tier change the Stripe
webhook applied between sessions) and after a Stripe Checkout return
(`?checkout=success` in the Settings billing UI — #21).

The response is decoded into `Data.Me.MeResponse`; see that module for
the field documentation.

Uses HTTP Basic with the per-user CouchDB credentials already on
`Creds`, same scheme as `Http.SharedTripApi`. Routes through the
configured `AppConfig.backendUrl` so dev / preview / prod all hit the
right host.

-}

import Data.Auth exposing (AppConfig, Creds)
import Data.Me as Me
import Http
import Http.SharedTripApi


{-| Issue `GET {backendUrl}/me` and decode the response.

Silent on failure is the right default at the call site — this is a
refresh path, not a hard requirement; the next call (next startup,
next post-checkout return) will retry.

-}
fetch : AppConfig -> Creds -> (Result Http.Error Me.MeResponse -> msg) -> Cmd msg
fetch config creds toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.SharedTripApi.authHeader creds ]
        , url = config.backendUrl ++ "/me"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg Me.decoder
        , timeout = Nothing
        , tracker = Nothing
        }
