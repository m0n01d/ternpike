module Verify.Specs.SharedTripCard exposing (Input, honest, surface, seededTrips, results)

{-| Client-render verification unit for the shared-trip card
(`Pages.Settings.SharedTrips.viewSharedTripCard`): the Owner/Member badge an
owner sees after creating a flock (and a member sees after joining). Reuses
`Data.SharedTrip.isOwner` so the surface can't drift from the view.

A `SharedTripId` is opaque (`fromString : String -> Maybe`), so the sample trips
are built inside a `fromString` case with an `empty`/`[]` fallback that is never
hit by the static, valid hex nonce.

@docs Input, honest, surface, seededTrips, results

-}

import Data.SharedTrip as SharedTrip exposing (SharedTrip)
import Data.SharedTripId as SharedTripId
import Data.SharedTrips as SharedTrips exposing (SharedTrips)
import Data.UserId as UserId exposing (UserId)
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


{-| The slice this unit observes. `corrupt = True` (probe only) flips the role
badge so an invariant has a real regression to catch.
-}
type alias Input =
    { corrupt : Bool
    , currentUser : UserId
    , trip : SharedTrip
    }


{-| An honest input (never corrupt) — the projection `viewSharedTripCard` feeds.
-}
honest : UserId -> SharedTrip -> Input
honest currentUser trip =
    { corrupt = False, currentUser = currentUser, trip = trip }


{-| Derive the card's observable surface. Role mirrors `SharedTrip.isOwner`.
-}
surface : Input -> Contract.Surface
surface input =
    let
        owner : Bool
        owner =
            SharedTrip.isOwner input.currentUser input.trip

        role : String
        role =
            if Basics.xor owner input.corrupt then
                "owner"

            else
                "member"
    in
    [ ( "role", role ), ( "name", input.trip.name ) ]


{-| The seeded `SharedTrips` for a fixture, used by `Main.applyUnitSeed` so the
DOM tier renders the same card the pure tier verifies. Empty fallback is
unreachable (the nonce is valid).
-}
seededTrips : String -> SharedTrips
seededTrips fixture =
    case SharedTripId.fromString sampleNonce of
        Just sid ->
            SharedTrips.fromList [ tripFor fixture sid ]

        Nothing ->
            SharedTrips.empty


{-| The pure-tier results for this unit, collected by `Verify.Registry`.
-}
results : List Core.RunResult
results =
    case SharedTripId.fromString sampleNonce of
        Just sid ->
            Runner.runUnit (spec sid)

        Nothing ->
            []



-- INTERNALS


sampleNonce : String
sampleNonce =
    "abc123abc123"


me : UserId
me =
    UserId.fromString "verify@ternpike.test"


otherUser : UserId
otherUser =
    UserId.fromString "owner@ternpike.test"


tripFor : String -> SharedTripId.SharedTripId -> SharedTrip
tripFor fixture sid =
    let
        ownerIsMe : Bool
        ownerIsMe =
            fixture /= "member"
    in
    { billingLapsedAt = Nothing
    , billingOwner =
        if ownerIsMe then
            me

        else
            otherUser
    , billingStatus = SharedTrip.Active
    , createdAt = ""
    , createdBy =
        if ownerIsMe then
            me

        else
            otherUser
    , id = sid
    , name = "Honeymoon"
    , otherMembers =
        if ownerIsMe then
            []

        else
            [ me ]
    }


spec : SharedTripId.SharedTripId -> Spec.UnitSpec Input
spec sid =
    { fixtures =
        [ { input = honest me (tripFor "owner" sid), name = "owner", probe = False }
        , { input = honest me (tripFor "member" sid), name = "member", probe = False }
        , { input = { corrupt = True, currentUser = me, trip = tripFor "owner" sid }, name = "probe-owner-shows-member", probe = True }
        ]
    , invariants =
        [ { name = "owner trip shows the owner badge", check = ownerBadge }
        , { name = "member trip shows the member badge", check = memberBadge }
        ]
    , name = "SharedTripCard"
    , surface = surface
    }


ownerBadge : Input -> Contract.Surface -> Maybe String
ownerBadge input observed =
    if not (SharedTrip.isOwner input.currentUser input.trip) then
        Nothing

    else if value "role" observed == Just "owner" then
        Nothing

    else
        Just "owner trip did not show the owner badge"


memberBadge : Input -> Contract.Surface -> Maybe String
memberBadge input observed =
    if SharedTrip.isOwner input.currentUser input.trip then
        Nothing

    else if value "role" observed == Just "member" then
        Nothing

    else
        Just "member trip did not show the member badge"


value : String -> Contract.Surface -> Maybe String
value key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
