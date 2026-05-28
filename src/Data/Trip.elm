module Data.Trip exposing
    ( CreateTarget(..)
    , NewFlockDraft
    , TierContext
    , Trip
    , TripField(..)
    , TripForm
    , TripTarget(..)
    , canBatchScan
    , decoder
    , defaultNewFlockDraft
    , effectiveTier
    , encodeTarget
    , encoder
    , targetForTrip
    , validator
    )

{-| A trip — the top-level container that expenses belong to.

Four types live here:

  - `Trip` — the saved document (immutable in practice; we overwrite the
    whole doc on edit rather than using amendments, because trips are
    rarely edited and the data is small).
  - `TripForm` — the in-progress draft used by the new/edit modal.
    Strings rather than typed fields so the user can type freely; the
    `validator` is what gates submission. The submit handler in
    `Main.elm` parses the strings into typed `DateField` / `Money`
    values when constructing the `Trip` record. The
    `sharedTripRequest` field tracks the async create-shared-trip HTTP
    call when the "New shared trip" target is selected.
  - `TripField` — the tag passed to `TripFieldChanged` so one `Msg`
    handler can route updates to the right field on `TripForm`.
  - `TripTarget` — the routing tag carried on every outbound `Save*`
    PouchDB command so `pouch.js` knows which local DB to write the
    doc to. `Personal` writes to the user's solo handle; `InFlock`
    writes to the flock's handle. Derived from a trip's `flockId` via
    `targetForTrip`.


# Field types (#93)

The typed-primitives refactor flipped three fields:

  - `budget : Data.Money.Money` — was `Float`. Encoder still emits
    `Float` dollars so the wire format is unchanged. The "no budget
    set" sentinel is now `Money.zero`; consumers check via
    `Money.isZero` rather than `> 0`.
  - `startDate : Data.DateField.DateField` — was ISO `String`.
    Encoder still emits the ISO `YYYY-MM-DD` shape. The legacy `""`
    sentinel decodes to the epoch (`1970-01-01`) via
    `DateField.decoder`'s built-in fallback; consumers check
    `DateField.toIso d == "1970-01-01"` for "no date set".
  - `endDate : DateField` — same treatment as `startDate`.


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


# Tier helpers

`effectiveTier` answers "what tier should this trip's paid features
behave under?" For personal trips it's the user's own tier; for flock
trips it's the **billing owner's** tier. Inside a flock owned by a
paid user, every member's writes get paid features regardless of the
member's personal tier — that's the whole point of pooling under one
billing relationship. `canBatchScan` is a convenience predicate on top of `effectiveTier` so
call sites don't have to know whether a particular capability is
paid-only or not.

The flock's tier today is read off the **billing owner's** tier on
the active session — the simplification works because the owner is
who pays, and the only way to lose a paid feature inside a flock is
for the owner to downgrade. A future refresh round (#19) will fold
in `billingStatus` for the lapsed / frozen edge cases (#64).

-}

import Data.DateField as DateField exposing (DateField)
import Data.Money as Money exposing (Money)
import Data.SharedTrip exposing (SharedTrip)
import Data.SharedTripId
import Data.SharedTrips exposing (SharedTrips)
import Data.Tier exposing (Tier)
import Data.TripId as TripId exposing (TripId)
import Data.UserId exposing (UserId)
import Http
import Http.SharedTripApi
import Json.Decode as D
import Json.Decode.Pipeline as Pipeline
import Json.Encode as E
import RemoteData exposing (RemoteData)
import Validate


type alias Trip =
    { budget : Money
    , coverPhotoUrl : String
    , description : String
    , endDate : DateField
    , flockId : Maybe Data.SharedTripId.SharedTripId
    , id : TripId
    , name : String
    , startDate : DateField
    }


type alias TripForm =
    { budget : String
    , coverPhotoUrl : String
    , description : String
    , editing : Maybe Trip
    , endDate : String
    , errors : List String
    , groupNameOverridden : Bool
    , name : String
    , sharedTripRequest : RemoteData Http.Error Http.SharedTripApi.CreateSharedTripResponse
    , startDate : String
    , submitting : Bool
    , target : CreateTarget
    }


type TripField
    = TripBudget
    | TripCoverPhoto
    | TripDescription
    | TripEndDate
    | TripName
    | TripStartDate


{-| Where a save goes: the personal DB or a specific flock DB.

`pouch.js` keys handles by this tag — `Personal` resolves to the
user's solo handle, `InFlock` looks up the matching flock handle.
Missing target on a port message defaults to `Personal` on the JS
side so legacy / not-yet-targeted call sites keep working.

-}
type TripTarget
    = InFlock Data.SharedTripId.SharedTripId
    | Personal


{-| Form-only target tag used by the New Trip dialog's "Who's on this
trip?" picker. Distinct from `TripTarget` (which is the wire/runtime
type used by the port layer) so the encoder doesn't have to handle the
"this flock doesn't exist yet" case.

The `ToNewFlock` arm is resolved by the submit orchestration in
`Main.elm`: it fires `POST /flocks`, sends invites, opens the new
flock-local PouchDB, then rewrites the form's target to
`ToExistingFlock <newId>` so the standard trip-write path takes over.

-}
type CreateTarget
    = ToPersonal
    | ToExistingFlock Data.SharedTripId.SharedTripId
    | ToNewFlock NewFlockDraft


{-| Draft of the new flock that the "+ New shared trip" tile collects.

`groupName` defaults to the trip name (synced as the user types in the
trip-name field, unless they've explicitly overridden it). `invitees`
is the committed chip list; `inviteesDraft` is the in-progress text
input that becomes a chip on enter/tab.

-}
type alias NewFlockDraft =
    { groupName : String
    , invitees : List String
    , inviteesDraft : String
    }


{-| The empty draft used when the user first picks the "+ New shared
trip" tile. `groupName` is filled in from the trip name at view time.
-}
defaultNewFlockDraft : NewFlockDraft
defaultNewFlockDraft =
    { groupName = ""
    , invitees = []
    , inviteesDraft = ""
    }


{-| Form validator.

The form keeps `String`-typed inputs (bound directly to `<input>` elements), so
the validator works on the raw text. The submit handler in `Main.elm` parses
the strings into typed `DateField` / `Money` values when constructing the
`Trip` record; the validator's job is just to gate that conversion.

Budget rule: an empty budget is allowed (treated as "no budget set" downstream),
but a non-empty budget must parse via `Data.Money.fromDollarString`.

Date rule: when both dates are filled in, end must be ≥ start chronologically.
Empty strings are tolerated so a half-filled draft can still validate while the
user is in mid-input — both blanks become `Money.zero` / epoch downstream and
the form's other guards take over.

-}
validator : Validate.Validator String TripForm
validator =
    Validate.all
        [ Validate.ifBlank .name "Trip name is required."
        , Validate.ifTrue (\f -> f.budget /= "" && Money.fromDollarString f.budget == Nothing) "Budget must be a number."
        , Validate.ifTrue datesOutOfOrder "End date must be after start date."
        ]


datesOutOfOrder : TripForm -> Bool
datesOutOfOrder f =
    case ( DateField.fromIso f.startDate, DateField.fromIso f.endDate ) of
        ( Just start, Just end ) ->
            DateField.compare end start == LT

        _ ->
            False


encoder : Trip -> E.Value
encoder t =
    E.object
        [ ( "_id", TripId.encode t.id )
        , ( "budget", Money.encoder t.budget )
        , ( "coverPhotoUrl", E.string t.coverPhotoUrl )
        , ( "description", E.string t.description )
        , ( "endDate", DateField.encoder t.endDate )
        , ( "name", E.string t.name )
        , ( "startDate", DateField.encoder t.startDate )
        , ( "type", E.string "trip" )
        ]


decoder : D.Decoder Trip
decoder =
    D.succeed Trip
        |> Pipeline.required "budget" Money.decoder
        |> Pipeline.required "coverPhotoUrl" D.string
        |> Pipeline.required "description" D.string
        |> Pipeline.required "endDate" DateField.decoder
        |> Pipeline.optional "flockId" (D.nullable Data.SharedTripId.decoder) Nothing
        |> Pipeline.required "_id" TripId.decode
        |> Pipeline.required "name" D.string
        |> Pipeline.required "startDate" DateField.decoder



-- TARGET


{-| Derive the JS-side routing tag from a trip's `flockId`. Trips with
no flock route to `Personal`; trips with a flock route to that flock.
-}
targetForTrip : Trip -> TripTarget
targetForTrip trip =
    case trip.flockId of
        Just fid ->
            InFlock fid

        Nothing ->
            Personal


{-| Encode a `TripTarget` for `pouch.js`. Shape matches the
`targetHandle` reader in `src/pouch.js`:

  - `{ "kind": "Personal" }` for personal trips.
  - `{ "kind": "InFlock", "flockId": "<hex>" }` for flock trips.

-}
encodeTarget : TripTarget -> E.Value
encodeTarget target =
    case target of
        InFlock fid ->
            E.object
                [ ( "kind", E.string "InFlock" )
                , ( "flockId", Data.SharedTripId.encode fid )
                ]

        Personal ->
            E.object [ ( "kind", E.string "Personal" ) ]



-- TIER


{-| Context bundle: everything the tier helpers need to answer "what
tier governs this trip's paid features?"

  - `currentUser` — the session's `UserId`, derived in `Main.elm` from
    `as_.creds.email`. Used to detect the owner-is-me case so the
    session's tier is preferred over the optimistic Osprey fallback.
  - `flocks` — the loaded flock cache, looked up by `trip.flockId`.
  - `tier` — the session's tier, used both as the personal-trip
    answer and as the owner-is-me answer.

-}
type alias TierContext a =
    { a | currentUser : UserId, sharedTrips : SharedTrips, tier : Tier }


{-| The tier that gates paid features on this trip.

For personal trips this is the user's own tier. For flock trips this
is the **billing owner's** tier — so a free Tern member of a
flock owned by an Osprey user gets paid features inside that flock's
trips. If the trip claims a `flockId` we don't recognise (transient
race during sync, stale doc), we conservatively fall back to the
caller's own tier.

-}
effectiveTier : Trip -> TierContext a -> Tier
effectiveTier trip ctx =
    case trip.flockId of
        Just fid ->
            case Data.SharedTrips.get fid ctx.sharedTrips of
                Just flock ->
                    ownerTier flock ctx

                Nothing ->
                    ctx.tier

        Nothing ->
            ctx.tier


{-| The owner's tier for a flock. When the owner is the session user
we use the session's tier directly; otherwise we optimistically treat
the flock as paid — the owner must have been paid to create it, and
billing-lapsed flocks are surfaced separately via `billingStatus`
(handled by #64). Falls back to `Osprey` (optimistic paid) when the
owner is someone else.
-}
ownerTier : SharedTrip -> TierContext a -> Tier
ownerTier flock ctx =
    if flock.billingOwner == ctx.currentUser then
        ctx.tier

    else
        Data.Tier.Osprey


{-| True if the trip can run batch (parallel) receipt scanning
(paid-tier feature). Equivalent to `Tier.isPaid` on the effective
tier; named for the capability for the same reason as
`canUseProxiedOCR`.
-}
canBatchScan : Trip -> TierContext a -> Bool
canBatchScan trip ctx =
    Data.Tier.isPaid (effectiveTier trip ctx)
