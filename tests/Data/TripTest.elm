module Data.TripTest exposing (suite)

import Data.DateField as DateField exposing (DateField)
import Data.SharedTrip exposing (BillingStatus(..), SharedTrip)
import Data.SharedTripId as SharedTripId exposing (SharedTripId)
import Data.SharedTrips as SharedTrips
import Data.Money as Money
import Data.Tier as Tier
import Data.Trip as Trip exposing (Trip)
import Data.TripId as TripId
import Data.UserId as UserId exposing (UserId)
import Expect
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Trip.effectiveTier"
        [ test "personal trip returns the user's own tier" <|
            \_ ->
                Trip.effectiveTier (personalTrip "trip::1::aaaaaaaa")
                    { currentUser = member, tier = Tier.Tern, sharedTrips = SharedTrips.empty }
                    |> Expect.equal Tier.Tern
        , test "personal trip for a paid user returns Osprey" <|
            \_ ->
                Trip.effectiveTier (personalTrip "trip::2::bbbbbbbb")
                    { currentUser = member, tier = Tier.Osprey, sharedTrips = SharedTrips.empty }
                    |> Expect.equal Tier.Osprey
        , test "active flock trip elevates a Tern member to Osprey" <|
            \_ ->
                let
                    fid =
                        validSharedTripId

                    state =
                        { currentUser = member
                        , tier = Tier.Tern
                        , sharedTrips = SharedTrips.fromList [ sharedTripWith fid Active ]
                        }
                in
                Trip.effectiveTier (flockTrip "trip::3::cccccccc" fid) state
                    |> Expect.equal Tier.Osprey
        , test "active flock trip for an Osprey owner stays at Osprey" <|
            \_ ->
                let
                    fid =
                        validSharedTripId

                    state =
                        { currentUser = owner
                        , tier = Tier.Osprey
                        , sharedTrips = SharedTrips.fromList [ sharedTripWith fid Active ]
                        }
                in
                Trip.effectiveTier (flockTrip "trip::4::dddddddd" fid) state
                    |> Expect.equal Tier.Osprey
        , test "grace flock as the owner returns the owner's own tier" <|
            \_ ->
                let
                    fid =
                        validSharedTripId

                    state =
                        { currentUser = owner
                        , tier = Tier.Tern
                        , sharedTrips = SharedTrips.fromList [ sharedTripWith fid Grace ]
                        }
                in
                -- Under #63's semantics the helper doesn't read billingStatus —
                -- the lapsed-billing banner (#64) handles UX. Owner-is-me path
                -- returns ctx.tier so a downgraded owner sees their actual tier.
                Trip.effectiveTier (flockTrip "trip::5::eeeeeeee" fid) state
                    |> Expect.equal Tier.Tern
        , test "frozen flock as an Osprey owner stays Osprey" <|
            \_ ->
                let
                    fid =
                        validSharedTripId

                    state =
                        { currentUser = owner
                        , tier = Tier.Osprey
                        , sharedTrips = SharedTrips.fromList [ sharedTripWith fid Frozen ]
                        }
                in
                Trip.effectiveTier (flockTrip "trip::6::ffffffff" fid) state
                    |> Expect.equal Tier.Osprey
        , test "trip references a flock that isn't in flocks → user's tier" <|
            \_ ->
                let
                    fid =
                        validSharedTripId

                    state =
                        { currentUser = member
                        , tier = Tier.Tern
                        , sharedTrips = SharedTrips.empty
                        }
                in
                Trip.effectiveTier (flockTrip "trip::7::99999999" fid) state
                    |> Expect.equal Tier.Tern
        , test "canUseProxiedOCR is True on an active flock trip for a Tern member" <|
            \_ ->
                let
                    fid =
                        validSharedTripId

                    state =
                        { currentUser = member
                        , tier = Tier.Tern
                        , sharedTrips = SharedTrips.fromList [ sharedTripWith fid Active ]
                        }
                in
                Trip.canUseProxiedOCR (flockTrip "trip::8::88888888" fid) state
                    |> Expect.equal True
        , test "canUseProxiedOCR is False on a personal trip for a Tern" <|
            \_ ->
                Trip.canUseProxiedOCR (personalTrip "trip::9::77777777")
                    { currentUser = member, tier = Tier.Tern, sharedTrips = SharedTrips.empty }
                    |> Expect.equal False
        , test "canBatchScan is True on an active flock trip for a Tern member" <|
            \_ ->
                let
                    fid =
                        validSharedTripId

                    state =
                        { currentUser = member
                        , tier = Tier.Tern
                        , sharedTrips = SharedTrips.fromList [ sharedTripWith fid Active ]
                        }
                in
                Trip.canBatchScan (flockTrip "trip::10::66666666" fid) state
                    |> Expect.equal True
        ]



-- FIXTURES


personalTrip : String -> Trip
personalTrip id =
    { budget = Money.zero
    , coverPhotoUrl = ""
    , description = ""
    , endDate = epoch
    , flockId = Nothing
    , id = TripId.fromString id
    , name = "Personal"
    , startDate = epoch
    }


flockTrip : String -> SharedTripId -> Trip
flockTrip id fid =
    { budget = Money.zero
    , coverPhotoUrl = ""
    , description = ""
    , endDate = epoch
    , flockId = Just fid
    , id = TripId.fromString id
    , name = "Flock"
    , startDate = epoch
    }


{-| Test-only sentinel for "no date set" — mirrors the production
behaviour where `DateField.decoder` falls back to the epoch for empty
or malformed wire values.
-}
epoch : DateField
epoch =
    DateField.today Time.utc (Time.millisToPosix 0)


{-| A known-good 12-char hex SharedTripId used across the test fixtures. We
materialise it lazily through a function so the totality fallback can
recurse without tripping Elm's top-level cyclic-value check.
`SharedTripId.fromString "0123456789ab"` always returns `Just`, so the
fallback is never evaluated.
-}
validSharedTripId : SharedTripId
validSharedTripId =
    mkSharedTripId ()


mkSharedTripId : () -> SharedTripId
mkSharedTripId () =
    case SharedTripId.fromString "0123456789ab" of
        Just fid ->
            fid

        Nothing ->
            mkSharedTripId ()


sharedTripWith : SharedTripId -> BillingStatus -> SharedTrip
sharedTripWith fid status =
    { billingLapsedAt = Nothing
    , billingOwner = owner
    , billingStatus = status
    , createdAt = "2024-01-01T00:00:00Z"
    , createdBy = owner
    , id = fid
    , name = "Test Flock"
    , otherMembers = []
    }


owner : UserId
owner =
    UserId.fromString "owner@example.com"


member : UserId
member =
    UserId.fromString "member@example.com"
