module Data.TripTest exposing (suite)

import Data.Flock exposing (BillingStatus(..), Flock)
import Data.FlockId as FlockId exposing (FlockId)
import Data.Flocks as Flocks
import Data.Tier as Tier
import Data.Trip as Trip exposing (Trip)
import Data.TripId as TripId
import Data.UserId as UserId exposing (UserId)
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Trip.effectiveTier"
        [ test "personal trip returns the user's own tier" <|
            \_ ->
                Trip.effectiveTier (personalTrip "trip::1::aaaaaaaa")
                    { tier = Tier.Fledgling, flocks = Flocks.empty }
                    |> Expect.equal Tier.Fledgling
        , test "personal trip for a paid user returns Fly" <|
            \_ ->
                Trip.effectiveTier (personalTrip "trip::2::bbbbbbbb")
                    { tier = Tier.Fly, flocks = Flocks.empty }
                    |> Expect.equal Tier.Fly
        , test "active flock trip elevates a Fledgling member to Fly" <|
            \_ ->
                let
                    fid =
                        validFlockId

                    state =
                        { tier = Tier.Fledgling
                        , flocks = Flocks.fromList [ flockWith fid Active ]
                        }
                in
                Trip.effectiveTier (flockTrip "trip::3::cccccccc" fid) state
                    |> Expect.equal Tier.Fly
        , test "active flock trip for a Fly owner stays at Fly" <|
            \_ ->
                let
                    fid =
                        validFlockId

                    state =
                        { tier = Tier.Fly
                        , flocks = Flocks.fromList [ flockWith fid Active ]
                        }
                in
                Trip.effectiveTier (flockTrip "trip::4::dddddddd" fid) state
                    |> Expect.equal Tier.Fly
        , test "grace flock falls back to the user's own tier" <|
            \_ ->
                let
                    fid =
                        validFlockId

                    state =
                        { tier = Tier.Fledgling
                        , flocks = Flocks.fromList [ flockWith fid Grace ]
                        }
                in
                Trip.effectiveTier (flockTrip "trip::5::eeeeeeee" fid) state
                    |> Expect.equal Tier.Fledgling
        , test "frozen flock falls back to the user's own tier" <|
            \_ ->
                let
                    fid =
                        validFlockId

                    state =
                        { tier = Tier.Fly
                        , flocks = Flocks.fromList [ flockWith fid Frozen ]
                        }
                in
                Trip.effectiveTier (flockTrip "trip::6::ffffffff" fid) state
                    |> Expect.equal Tier.Fly
        , test "trip references a flock that isn't in flocks → user's tier" <|
            \_ ->
                let
                    fid =
                        validFlockId

                    state =
                        { tier = Tier.Fledgling
                        , flocks = Flocks.empty
                        }
                in
                Trip.effectiveTier (flockTrip "trip::7::99999999" fid) state
                    |> Expect.equal Tier.Fledgling
        , test "canUseProxiedOCR is True on an active flock trip for a Fledgling" <|
            \_ ->
                let
                    fid =
                        validFlockId

                    state =
                        { tier = Tier.Fledgling
                        , flocks = Flocks.fromList [ flockWith fid Active ]
                        }
                in
                Trip.canUseProxiedOCR (flockTrip "trip::8::88888888" fid) state
                    |> Expect.equal True
        , test "canUseProxiedOCR is False on a personal trip for a Fledgling" <|
            \_ ->
                Trip.canUseProxiedOCR (personalTrip "trip::9::77777777")
                    { tier = Tier.Fledgling, flocks = Flocks.empty }
                    |> Expect.equal False
        , test "canBatchScan is True on an active flock trip for a Fledgling" <|
            \_ ->
                let
                    fid =
                        validFlockId

                    state =
                        { tier = Tier.Fledgling
                        , flocks = Flocks.fromList [ flockWith fid Active ]
                        }
                in
                Trip.canBatchScan (flockTrip "trip::10::66666666" fid) state
                    |> Expect.equal True
        ]



-- FIXTURES


personalTrip : String -> Trip
personalTrip id =
    { budget = 0
    , coverPhotoUrl = ""
    , description = ""
    , endDate = ""
    , flockId = Nothing
    , id = TripId.fromString id
    , name = "Personal"
    , startDate = ""
    }


flockTrip : String -> FlockId -> Trip
flockTrip id fid =
    { budget = 0
    , coverPhotoUrl = ""
    , description = ""
    , endDate = ""
    , flockId = Just fid
    , id = TripId.fromString id
    , name = "Flock"
    , startDate = ""
    }


{-| A known-good 12-char hex FlockId used across the test fixtures. We
materialise it lazily through a function so the totality fallback can
recurse without tripping Elm's top-level cyclic-value check.
`FlockId.fromString "0123456789ab"` always returns `Just`, so the
fallback is never evaluated.
-}
validFlockId : FlockId
validFlockId =
    mkFlockId ()


mkFlockId : () -> FlockId
mkFlockId () =
    case FlockId.fromString "0123456789ab" of
        Just fid ->
            fid

        Nothing ->
            mkFlockId ()


flockWith : FlockId -> BillingStatus -> Flock
flockWith fid status =
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
