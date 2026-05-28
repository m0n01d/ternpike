module Data.SubscriptionStatus exposing
    ( SubscriptionStatus(..)
    , fromString, toString, label
    , decoder, encoder
    )

{-| The Stripe-driven subscription status for the current user.

Mirrors the wire shape the server stores in `TIERS_KV` under
`user:<email>` and returns from `/auth/verify-code` and `/me` (see
`server/users.js` — `VALID_SUBSCRIPTION_STATUSES`).

Wire format: `"active" | "canceled" | "past_due" | "trialing"`. The
server uses `null` for "no subscription" (free tier, never subscribed,
or subscription fully expired); on the Elm side that's the absence of
a value — represented as `Maybe SubscriptionStatus` at the call site
rather than a `None` constructor here.

This type is server-authoritative and refreshed from the `/me`
endpoint on startup (and after a `?checkout=success` return), never
persisted to PouchDB — see `CLAUDE.md` "Storage tiers".


# Type

@docs SubscriptionStatus


# Conversions

@docs fromString, toString, label


# JSON

@docs decoder, encoder

-}

import Json.Decode
import Json.Encode


{-| The subscription state for the current user.

  - `Active` — subscription paid up; paid features unlocked.
  - `Canceled` — subscription was canceled; usually paired with a
    server-side downgrade to `Tern` once Stripe stops billing.
  - `PastDue` — Stripe failed to charge; the user is still in the grace
    window. The Settings billing UI surfaces a warning chip.
  - `Trialing` — Stripe-managed free trial; paid features unlocked
    until the trial ends.

Constructors alphabetized per the style guide.

-}
type SubscriptionStatus
    = Active
    | Canceled
    | PastDue
    | Trialing


{-| Wire form (lowercase, matches the Stripe enum the server stores).

    toString Active
    --> "active"

    toString Canceled
    --> "canceled"

    toString PastDue
    --> "past_due"

    toString Trialing
    --> "trialing"

-}
toString : SubscriptionStatus -> String
toString status =
    case status of
        Active ->
            "active"

        Canceled ->
            "canceled"

        PastDue ->
            "past_due"

        Trialing ->
            "trialing"


{-| Parse the lowercase wire form. Returns `Nothing` for any other
input — fails closed so an unknown status never silently grants
paid features. Callers decide whether to default (typically to
`Nothing` on the field) or surface an error.

    fromString "active"
    --> Just Active

    fromString "canceled"
    --> Just Canceled

    fromString "past_due"
    --> Just PastDue

    fromString "trialing"
    --> Just Trialing

    fromString "unknown"
    --> Nothing

-}
fromString : String -> Maybe SubscriptionStatus
fromString s =
    case s of
        "active" ->
            Just Active

        "canceled" ->
            Just Canceled

        "past_due" ->
            Just PastDue

        "trialing" ->
            Just Trialing

        _ ->
            Nothing


{-| Display form, suitable for chips/badges in the Settings billing UI.

    label Active
    --> "Active"

    label Canceled
    --> "Canceled"

    label PastDue
    --> "Past due"

    label Trialing
    --> "Trialing"

-}
label : SubscriptionStatus -> String
label status =
    case status of
        Active ->
            "Active"

        Canceled ->
            "Canceled"

        PastDue ->
            "Past due"

        Trialing ->
            "Trialing"


{-| Decode the lowercase wire form, rejecting unknown values with a
descriptive error. Pair with `Json.Decode.nullable` at the call site
to absorb the server's `null` for "no subscription".
-}
decoder : Json.Decode.Decoder SubscriptionStatus
decoder =
    Json.Decode.string
        |> Json.Decode.andThen
            (\raw ->
                case fromString raw of
                    Just status ->
                        Json.Decode.succeed status

                    Nothing ->
                        Json.Decode.fail ("Unknown subscriptionStatus: " ++ raw)
            )


{-| Encode to the lowercase wire form. Mirrors `decoder` so a round-trip
preserves the value. Use `Json.Encode.null` at the call site for the
"no subscription" case.
-}
encoder : SubscriptionStatus -> Json.Encode.Value
encoder status =
    Json.Encode.string (toString status)
