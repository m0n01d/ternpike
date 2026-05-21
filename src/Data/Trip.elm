module Data.Trip exposing
    ( Trip
    , TripField(..)
    , TripForm
    , canBatchScan
    , canUseProxiedOCR
    , decoder
    , effectiveTier
    , encoder
    , validator
    )

{-| A trip — the top-level container that expenses belong to.

Three types live here:

  - `Trip` — the saved document (immutable in practice; we overwrite the
    whole doc on edit rather than using amendments, because trips are
    rarely edited and the data is small).
  - `TripForm` — the in-progress draft used by the new/edit modal.
    Strings rather than typed fields so the user can type freely; the
    `validator` is what gates submission.
  - `TripField` — the tag passed to `TripFieldChanged` so one `Msg`
    handler can route updates to the right field on `TripForm`.


# Asymmetry: `flockId`

`flockId : Maybe FlockId` is in-memory only. It is **not** stored on
disk and the encoder does not write it; the decoder accepts and uses
the field when present (so values round-trip cleanly through the
`pouchIn` change feed, which post-#59 tags trips with their source
flock at the port boundary) but treats missing values as
`Nothing` (legacy / personal trips). The source of truth is the
PouchDB handle a doc arrived on, decorated by `src/pouch.js` —
storing it inside the doc would let it diverge from the database it
actually lives in.

-}

import Data.Flock
import Data.FlockId
import Data.Flocks exposing (Flocks)
import Data.Tier exposing (Tier)
import Data.TripId as TripId exposing (TripId)
import Json.Decode as D
import Json.Decode.Pipeline as Pipeline
import Json.Encode as E
import Validate


type alias Trip =
    { budget : Float
    , coverPhotoUrl : String
    , description : String
    , endDate : String
    , flockId : Maybe Data.FlockId.FlockId
    , id : TripId
    , name : String
    , startDate : String
    }


type alias TripForm =
    { budget : String
    , coverPhotoUrl : String
    , description : String
    , editing : Maybe Trip
    , endDate : String
    , errors : List String
    , name : String
    , startDate : String
    }


type TripField
    = TripBudget
    | TripCoverPhoto
    | TripDescription
    | TripEndDate
    | TripName
    | TripStartDate


validator : Validate.Validator String TripForm
validator =
    Validate.all
        [ Validate.ifBlank .name "Trip name is required."
        , Validate.ifTrue (\f -> f.budget /= "" && String.toFloat f.budget == Nothing) "Budget must be a number."
        , Validate.ifTrue (\f -> f.endDate /= "" && f.endDate < f.startDate) "End date must be after start date."
        ]


encoder : Trip -> E.Value
encoder t =
    E.object
        [ ( "_id", TripId.encode t.id )
        , ( "budget", E.float t.budget )
        , ( "coverPhotoUrl", E.string t.coverPhotoUrl )
        , ( "description", E.string t.description )
        , ( "endDate", E.string t.endDate )
        , ( "name", E.string t.name )
        , ( "startDate", E.string t.startDate )
        , ( "type", E.string "trip" )
        ]


decoder : D.Decoder Trip
decoder =
    D.succeed Trip
        |> Pipeline.required "budget" D.float
        |> Pipeline.required "coverPhotoUrl" D.string
        |> Pipeline.required "description" D.string
        |> Pipeline.required "endDate" D.string
        |> Pipeline.optional "flockId" (D.nullable Data.FlockId.decoder) Nothing
        |> Pipeline.required "_id" TripId.decode
        |> Pipeline.required "name" D.string
        |> Pipeline.required "startDate" D.string



-- TIER GATING


{-| Tier to consult when asking "can this user do X on THIS TRIP?"

For a personal trip (`flockId == Nothing`) the answer is the user's own
`tier`. For a flock trip, the answer is the flock's billing-owner tier,
which we don't carry locally — but `billingStatus = Active` is sufficient
evidence that the owner is at least `Fly`, so any active flock counts as
`Fly` for capability. `Grace` and `Frozen` flocks fall back to the user's
own tier (the lapsed-billing banner from #64 mostly disables writes in
those cases anyway). A trip referencing a flock we don't have data for
(stale sync, mid-load) defensively falls back to the user's tier rather
than crashing.

`Trailblazer` is a billing distinction, not a feature distinction (see
`CLAUDE.md`), so collapsing "active flock" to `Fly` does not lose
capability — it just means we don't pretend the owner is `Trailblazer`
when we can't actually tell.

Takes an extensible record so it can be called with either an `AuthState`
or a smaller record carrying just `tier` and `flocks` (avoids the
`Data.Trip -> Types -> Data.Trip` import cycle that a literal `AuthState`
parameter would create).

-}
effectiveTier : Trip -> { a | flocks : Flocks, tier : Tier } -> Tier
effectiveTier trip as_ =
    case trip.flockId of
        Nothing ->
            as_.tier

        Just fid ->
            case Data.Flocks.get fid as_.flocks of
                Just flock ->
                    case flock.billingStatus of
                        Data.Flock.Active ->
                            Data.Tier.Fly

                        Data.Flock.Frozen ->
                            as_.tier

                        Data.Flock.Grace ->
                            as_.tier

                Nothing ->
                    as_.tier


{-| True when the user can route OCR through the Ternpike-hosted Anthropic
proxy on this trip. Equivalent to `Tier.isPaid (effectiveTier trip as_)` —
a Fledgling user on an active flock trip gets `True` because the flock's
billing owner is paying.
-}
canUseProxiedOCR : Trip -> { a | flocks : Flocks, tier : Tier } -> Bool
canUseProxiedOCR trip as_ =
    Data.Tier.isPaid (effectiveTier trip as_)


{-| True when the user can use batch scanning on this trip. Same predicate
as `canUseProxiedOCR` today; kept distinct so future feature gating can
diverge without churning call sites.
-}
canBatchScan : Trip -> { a | flocks : Flocks, tier : Tier } -> Bool
canBatchScan trip as_ =
    Data.Tier.isPaid (effectiveTier trip as_)
