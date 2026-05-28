module Data.Me exposing
    ( MeResponse
    , decoder
    )

{-| The response shape returned by `GET /me` on the auth server.

`/me` is the server-authoritative refresh path for everything tier- and
billing-related: it's called on startup (so a tier change made via the
Stripe webhook between sessions is picked up) and after the Settings
billing UI returns from Stripe Checkout (`?checkout=success`). See
`server/index.js` (`app.get('/me', ...)`) for the response body and
`CLAUDE.md` "Storage tiers" for why none of these fields are cached in
PouchDB.

The wire body also includes `email` and `subscriptionId`, but the Elm
client ignores them — `email` is already on `AuthState.creds`, and
`subscriptionId` is a server-only handle for the Stripe API.

-}

import Data.SubscriptionStatus as SubscriptionStatus exposing (SubscriptionStatus)
import Data.Tier as Tier exposing (Tier)
import Json.Decode


{-| The four mutable fields the client cares about, decoded from the
`/me` body. Alphabetised per the style guide.

  - `stripeCustomerId` — present after the first successful Checkout;
    `Nothing` for users who've never paid. Surfaced in the Settings
    billing UI as a confirmation that the Stripe link is wired up.
  - `subscriptionStatus` — Stripe-driven status, `Nothing` for free
    users.
  - `tier` — the authoritative tier; never trusted from the client.
  - `trailblazerNumber` — `Just n` (1..500) for confirmed Trailblazer
    purchases, `Nothing` for everyone else.

-}
type alias MeResponse =
    { stripeCustomerId : Maybe String
    , subscriptionStatus : Maybe SubscriptionStatus
    , tier : Tier
    , trailblazerNumber : Maybe Int
    }


{-| Decode the body of `GET /me`. Fields that the wire schema marks as
nullable are decoded with `Json.Decode.nullable`; `tier` defaults to
`Tern` if the field is missing or unrecognised — matches the
fail-closed convention used for the verify-code decoder so an unknown
tier never silently grants paid features.
-}
decoder : Json.Decode.Decoder MeResponse
decoder =
    Json.Decode.map4 MeResponse
        (Json.Decode.field "stripeCustomerId" (Json.Decode.nullable Json.Decode.string))
        (Json.Decode.field "subscriptionStatus" (Json.Decode.nullable SubscriptionStatus.decoder))
        tierField
        (Json.Decode.field "trailblazerNumber" (Json.Decode.nullable Json.Decode.int))


tierField : Json.Decode.Decoder Tier
tierField =
    Json.Decode.oneOf
        [ Json.Decode.field "tier" Json.Decode.string
            |> Json.Decode.map (Tier.fromString >> Maybe.withDefault Tier.Tern)
        , Json.Decode.succeed Tier.Tern
        ]
