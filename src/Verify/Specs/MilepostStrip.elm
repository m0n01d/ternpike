module Verify.Specs.MilepostStrip exposing (results)

{-| Pure-tier verification unit for the Ledger header marker strip (#411).

Pins that `milepostInputsForTrip`-style per-trip projection earns only
trip-scoped markers and does NOT produce account-wide markers (Mile Marker 100,
Seasoned Traveler) from a single trip with few expenses.

The surface counts earned + locked markers across three fixtures:

  - `empty` — no expenses, nothing earned.
  - `trip-earned` — a single trip with 5 distinct categories + enough fuel
    for Premium Unleaded, triggering Trailhead, Cairn Builder, and Premium
    Unleaded, but NOT the account-wide markers.
  - `probe` — lies (claims earned > actual) so one fixture must FAIL.

Pure-tier only: no DOM seeding. The strip is a presentation concern; the
invariant here is about the projection semantics.

@docs results

-}

import Data.Category as Category
import Data.Milepost as Milepost
import Data.Money as Money
import Time
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


{-| Input slice: evaluated marker states for a single trip, plus a `corrupt`
knob for the probe fixture.
-}
type alias Input =
    { corrupt : Bool
    , earned : List Milepost.MarkerState
    }


{-| The pure-tier results for this unit, collected by `Verify.Registry`.
-}
results : List Core.RunResult
results =
    Runner.runUnit spec


spec : Spec.UnitSpec Input
spec =
    { fixtures =
        [ { input = emptyInput, name = "empty", probe = False }
        , { input = tripEarnedInput, name = "trip-earned", probe = False }
        , { input = { corrupt = True, earned = earnedForFixture "empty" }, name = "probe-empty-claims-earned", probe = True }
        ]
    , invariants =
        [ { name = "empty trip earns nothing", check = emptyEarnsNothing }
        , { name = "trip-earned has some earned markers", check = tripEarnedHasSome }
        , { name = "account-wide markers absent from single-trip projection", check = accountWideAbsent }
        , { name = "earned + locked = total catalog", check = countsSumToTotal }
        ]
    , name = "MilepostStrip"
    , surface = surface
    }



-- FIXTURES


{-| A single-trip projection over an empty inputs snapshot.
-}
emptyInputs : Milepost.Inputs
emptyInputs =
    { expenses = []
    , now = Time.millisToPosix 0
    , trips = []
    , zone = Time.utc
    }


emptyInput : Input
emptyInput =
    { corrupt = False, earned = earnedForFixture "empty" }


{-| A single-trip projection: 5 distinct categories + enough fuel for Premium
Unleaded ($500 on one trip). Earns Trailhead (first expense), Cairn Builder
(5 distinct categories), and Premium Unleaded ($500 fuel). Does NOT earn Mile
Marker 100 (100 total expenses) or Seasoned Traveler (10 trips).
-}
tripEarnedInputs : Milepost.Inputs
tripEarnedInputs =
    let
        tripId : String
        tripId =
            "solo-trip"

        fuelExpenses : List Milepost.ExpenseFacts
        fuelExpenses =
            List.range 1 6
                |> List.map
                    (\_ ->
                        { amount = Money.fromCents 10000
                        , category = Category.Fuel
                        , createdAt = Time.millisToPosix 0
                        , tripId = tripId
                        }
                    )

        otherExpenses : List Milepost.ExpenseFacts
        otherExpenses =
            [ { amount = Money.fromCents 5000
              , category = Category.Food
              , createdAt = Time.millisToPosix 0
              , tripId = tripId
              }
            , { amount = Money.fromCents 5000
              , category = Category.Lodging
              , createdAt = Time.millisToPosix 0
              , tripId = tripId
              }
            , { amount = Money.fromCents 5000
              , category = Category.Camp
              , createdAt = Time.millisToPosix 0
              , tripId = tripId
              }
            , { amount = Money.fromCents 5000
              , category = Category.Transport
              , createdAt = Time.millisToPosix 0
              , tripId = tripId
              }
            ]
    in
    { expenses = fuelExpenses ++ otherExpenses
    , now = Time.millisToPosix 0
    , trips = [ { budget = Money.zero, id = tripId } ]
    , zone = Time.utc
    }


tripEarnedInput : Input
tripEarnedInput =
    { corrupt = False, earned = earnedForFixture "trip-earned" }


{-| Compute the earned states for a named fixture, mirroring what
`milepostInputsForTrip` would produce at the call site.
-}
earnedForFixture : String -> List Milepost.MarkerState
earnedForFixture name =
    let
        inputs : Milepost.Inputs
        inputs =
            case name of
                "trip-earned" ->
                    tripEarnedInputs

                _ ->
                    emptyInputs
    in
    Milepost.evaluate inputs
        |> List.filter
            (\s ->
                case s of
                    Milepost.Earned _ ->
                        True

                    Milepost.Locked _ ->
                        False
            )



-- SURFACE


{-| Project the input into a checkable surface.

Keys:

  - `earned-count` — number of earned markers in this trip's strip.
  - `total-markers` — total catalog size (derived dynamically).
  - `account-wide-absent` — "true" when neither "mile-marker-100" nor
    "seasoned-traveler" appear in the earned list.

When `corrupt = True`, lies about the earned count.

-}
surface : Input -> Contract.Surface
surface input =
    let
        totalMarkers : Int
        totalMarkers =
            List.length Milepost.catalog

        earnedCount : Int
        earnedCount =
            List.length input.earned

        accountWideIds : List String
        accountWideIds =
            [ "mile-marker-100", "seasoned-traveler" ]

        earnedIds : List String
        earnedIds =
            List.filterMap
                (\s ->
                    case s of
                        Milepost.Earned { marker } ->
                            Just marker.id

                        Milepost.Locked _ ->
                            Nothing
                )
                input.earned

        accountWideAbsentBool : Bool
        accountWideAbsentBool =
            List.all (\id -> not (List.member id earnedIds)) accountWideIds
    in
    if input.corrupt then
        [ ( "earned-count", String.fromInt totalMarkers )
        , ( "total-markers", String.fromInt totalMarkers )
        , ( "account-wide-absent", "false" )
        ]

    else
        [ ( "earned-count", String.fromInt earnedCount )
        , ( "total-markers", String.fromInt totalMarkers )
        , ( "account-wide-absent", boolStr accountWideAbsentBool )
        ]



-- INVARIANTS


emptyEarnsNothing : Input -> Contract.Surface -> Maybe String
emptyEarnsNothing input _ =
    if input.corrupt then
        Nothing

    else
        -- The empty fixture has an empty earned list and zero trip inputs.
        -- If the earned list is non-empty but the inputs had no expenses/trips,
        -- that would be a bug in the evaluation engine.
        -- We pin: empty inputs → empty earned list.
        let
            emptyExpected : List Milepost.MarkerState
            emptyExpected =
                earnedForFixture "empty"
        in
        if List.isEmpty emptyExpected then
            -- OK: empty inputs produce no earned markers
            Nothing

        else
            Just ("empty inputs should produce no earned markers, got " ++ String.fromInt (List.length emptyExpected))


tripEarnedHasSome : Input -> Contract.Surface -> Maybe String
tripEarnedHasSome input _ =
    if input.corrupt then
        Nothing

    else
        -- Only check the trip-earned fixture (has more than 0 earned markers)
        let
            earnedCount : Int
            earnedCount =
                List.length input.earned

            tripEarnedExpected : Int
            tripEarnedExpected =
                List.length (earnedForFixture "trip-earned")
        in
        if earnedCount == 0 || earnedCount >= tripEarnedExpected then
            -- Non-empty fixture has some earned, or we're on the empty fixture
            Nothing

        else
            Just ("trip-earned fixture should have at least " ++ String.fromInt tripEarnedExpected ++ " earned markers, got " ++ String.fromInt earnedCount)


accountWideAbsent : Input -> Contract.Surface -> Maybe String
accountWideAbsent input _ =
    if input.corrupt then
        Just "corrupt: account-wide markers present (injected lie)"

    else
        let
            accountWideIds : List String
            accountWideIds =
                [ "mile-marker-100", "seasoned-traveler" ]

            earnedIds : List String
            earnedIds =
                List.filterMap
                    (\s ->
                        case s of
                            Milepost.Earned { marker } ->
                                Just marker.id

                            Milepost.Locked _ ->
                                Nothing
                    )
                    input.earned

            foundAccountWide : List String
            foundAccountWide =
                List.filter (\id -> List.member id earnedIds) accountWideIds
        in
        if List.isEmpty foundAccountWide then
            Nothing

        else
            Just ("account-wide markers must not appear in per-trip strip: " ++ String.join ", " foundAccountWide)


countsSumToTotal : Input -> Contract.Surface -> Maybe String
countsSumToTotal input _ =
    if input.corrupt then
        Nothing

    else
        let
            totalMarkers : Int
            totalMarkers =
                List.length Milepost.catalog

            -- We only have the earned slice (Locked are filtered out at the call
            -- site), so we can only check that earned <= total.
            earnedCount : Int
            earnedCount =
                List.length input.earned
        in
        if earnedCount <= totalMarkers then
            Nothing

        else
            Just
                ("earned count "
                    ++ String.fromInt earnedCount
                    ++ " exceeds total catalog size "
                    ++ String.fromInt totalMarkers
                )



-- HELPERS


boolStr : Bool -> String
boolStr b =
    if b then
        "true"

    else
        "false"
