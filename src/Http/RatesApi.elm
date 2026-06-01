module Http.RatesApi exposing (fetch)

{-| HTTP client for `GET /rates` on the auth server — the free FX proxy that
backs the optional spend estimate (#448).

The Worker fetches mid-market daily reference rates from a free, keyless
upstream and caches them, so this is a cheap call. The response decodes into
a `Data.ExchangeRate.RateTable` (home-per-foreign factors + the rate date).

Silent on failure is the right default at the call site — the estimate is a
convenience, not a requirement; offline or on error we fall back to the rates
already cached in the synced `Data.UserSettings` doc, and the next startup
retries. Uses the same HTTP Basic creds + `backendUrl` routing as
`Http.Me` / `Http.SharedTripApi`.

-}

import Data.Auth exposing (AppConfig, Creds)
import Data.ExchangeRate as ExchangeRate
import Http
import Http.SharedTripApi


{-| Issue `GET {backendUrl}/rates` and decode the rate table.
-}
fetch : AppConfig -> Creds -> (Result Http.Error ExchangeRate.RateTable -> msg) -> Cmd msg
fetch config creds toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.SharedTripApi.authHeader creds ]
        , url = config.backendUrl ++ "/rates"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg ExchangeRate.httpDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
