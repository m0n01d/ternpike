module Http.Billing exposing
    ( CheckoutResult(..)
    , PortalResponse
    , TrailblazerStatus
    , checkout
    , portal
    , trailblazerStatus
    )

{-| HTTP client for the three Stripe-fronted billing endpoints on
`api.ternpike.com`.

  - `POST /billing/checkout` — start a Stripe Checkout session for an
    Osprey subscription (`osprey_monthly` / `osprey_yearly`) or the
    one-time Trailblazer purchase. Success hands back a hosted Stripe
    URL the caller redirects the browser to via
    `Browser.Navigation.load`. Trailblazer has two failure modes worth
    distinguishing from "generic error" — `409 sold_out` and
    `403 already_trailblazer` — so the response type is a tagged sum
    rather than a `Result Http.Error CheckoutResponse`.
  - `POST /billing/portal` — open the Stripe Customer Portal so the
    user can update card / cancel / view receipts via Stripe-hosted UI.
    Same redirect pattern: server returns a URL, caller `load`s it.
  - `GET /billing/trailblazer-status` — public, no auth. Drives the
    "X of 500 left" countdown on the Tern upgrade buttons.

All three call through the configured `AppConfig.backendUrl` so dev /
preview / prod hit the right host. Auth uses HTTP Basic with the
per-user CouchDB credentials already on `Creds`, same scheme as
`Http.SharedTripApi` and `Http.Me`.

The browser sets `Origin` automatically; we don't override it. The
server's allow-list (`http://localhost:3000` + `https://app.ternpike.com`)
accepts whichever origin the page itself is served from.

-}

import Data.Auth exposing (AppConfig, Creds)
import Http
import Http.SharedTripApi
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode


{-| Outcome of a `POST /billing/checkout` call.

  - `CheckoutOk` — Stripe handed us a hosted Checkout URL; redirect there.
    `number` is `Just n` for Trailblazer reservations (so the caller can
    show "you're #N" pre-payment if it wants) and `Nothing` for Osprey.
  - `CheckoutSoldOut` — Trailblazer-only. The 500-slot Durable Object
    declined the reservation (`409 {ok: false, remaining: 0}`).
  - `CheckoutAlreadyTrailblazer` — server saw the caller is already a
    Trailblazer and refused to start a second checkout
    (`403 {reason: "already_trailblazer"}`). UI surfaces a friendly
    "you're already a Trailblazer" chip rather than the generic error.
  - `CheckoutError` — network failure, 4xx that isn't one of the above,
    5xx, or a malformed response. Wraps a short user-facing message.

-}
type CheckoutResult
    = CheckoutAlreadyTrailblazer
    | CheckoutError String
    | CheckoutOk { number : Maybe Int, url : String }
    | CheckoutSoldOut


{-| `POST /billing/portal` success body — Stripe-hosted Customer Portal URL.
-}
type alias PortalResponse =
    { url : String
    }


{-| `GET /billing/trailblazer-status` response: how many of the 500
slots are still claimable.
-}
type alias TrailblazerStatus =
    { available : Int
    , total : Int
    }


{-| Fire `POST {backendUrl}/billing/checkout` with `{ "plan": "<plan>" }`.

Valid `plan` values per the server: `"osprey_monthly"`,
`"osprey_yearly"`, `"trailblazer"`. Anything else round-trips as a
`CheckoutError` (the server returns `400 invalid_plan`).

-}
checkout :
    AppConfig
    -> Creds
    -> { plan : String }
    -> (CheckoutResult -> msg)
    -> Cmd msg
checkout config creds { plan } toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.SharedTripApi.authHeader creds ]
        , url = config.backendUrl ++ "/billing/checkout"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ ( "plan", Json.Encode.string plan ) ]
                )
        , expect =
            Http.expectStringResponse (toMsg << unwrapCheckoutResult)
                (Ok << checkoutResponseToResult)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| `expectStringResponse` requires its decoder to return
`Result x a` and its handler to take `Result x a -> msg`. Our
`checkoutResponseToResult` already produces every relevant outcome as a
single `CheckoutResult` value (including network / 5xx errors as
`CheckoutError`), so we wrap it in `Ok` for the type signature and then
unwrap right back to the caller. The `Err` branch is structurally
unreachable — anything `Http` itself could have flagged as an error has
already been mapped through `checkoutResponseToResult`.
-}
unwrapCheckoutResult : Result Never CheckoutResult -> CheckoutResult
unwrapCheckoutResult r =
    case r of
        Ok v ->
            v

        Err n ->
            never n


{-| Fire `POST {backendUrl}/billing/portal`.

Returns a `Result Http.Error PortalResponse` — there's no special-case
status the way checkout has (the only "weird" outcome is `404 no_customer`
which the call site folds into a generic "couldn't open the billing
portal" chip).

-}
portal :
    AppConfig
    -> Creds
    -> (Result Http.Error PortalResponse -> msg)
    -> Cmd msg
portal config creds toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.SharedTripApi.authHeader creds ]
        , url = config.backendUrl ++ "/billing/portal"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg portalDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Fire `GET {backendUrl}/billing/trailblazer-status`. Public — no auth.

Drives the "X of 500 left" copy on the Tern upgrade button. Silent
failure at the call site is fine; the countdown just doesn't render.

-}
trailblazerStatus :
    AppConfig
    -> (Result Http.Error TrailblazerStatus -> msg)
    -> Cmd msg
trailblazerStatus config toMsg =
    Http.request
        { method = "GET"
        , headers = []
        , url = config.backendUrl ++ "/billing/trailblazer-status"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg trailblazerStatusDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


checkoutResponseToResult : Http.Response String -> CheckoutResult
checkoutResponseToResult response =
    case response of
        Http.BadUrl_ url ->
            CheckoutError ("Bad URL: " ++ url)

        Http.Timeout_ ->
            CheckoutError "Checkout request timed out — try again"

        Http.NetworkError_ ->
            CheckoutError "Network error — check your connection and try again"

        Http.BadStatus_ meta body ->
            case meta.statusCode of
                403 ->
                    case Json.Decode.decodeString (Json.Decode.field "reason" Json.Decode.string) body of
                        Ok "already_trailblazer" ->
                            CheckoutAlreadyTrailblazer

                        _ ->
                            CheckoutError ("Checkout refused (HTTP " ++ String.fromInt meta.statusCode ++ ")")

                409 ->
                    CheckoutSoldOut

                status ->
                    CheckoutError ("Checkout failed (HTTP " ++ String.fromInt status ++ ")")

        Http.GoodStatus_ _ body ->
            case Json.Decode.decodeString checkoutOkDecoder body of
                Ok payload ->
                    CheckoutOk payload

                Err _ ->
                    CheckoutError "Couldn't read the checkout response"


checkoutOkDecoder : Json.Decode.Decoder { number : Maybe Int, url : String }
checkoutOkDecoder =
    Json.Decode.succeed (\number url -> { number = number, url = url })
        |> Pipeline.optional "number" (Json.Decode.nullable Json.Decode.int) Nothing
        |> Pipeline.required "url" Json.Decode.string


portalDecoder : Json.Decode.Decoder PortalResponse
portalDecoder =
    Json.Decode.succeed PortalResponse
        |> Pipeline.required "url" Json.Decode.string


trailblazerStatusDecoder : Json.Decode.Decoder TrailblazerStatus
trailblazerStatusDecoder =
    Json.Decode.succeed TrailblazerStatus
        |> Pipeline.required "available" Json.Decode.int
        |> Pipeline.required "total" Json.Decode.int
