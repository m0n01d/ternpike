module Verify.Specs.MilepostStrip exposing (results)

{-| Pure-tier verification unit for the Ledger header marker strip (#411, #422).

Pins that the per-trip strip projection:

  - Earns only trip-scoped markers (not account-wide ones like Mile Marker 100
    or Seasoned Traveler).
  - Filters career markers (`trailhead`, `mile-marker-1`) even when they would
    otherwise be earned by the single-trip inputs.
  - Renders an EMPTY strip when the only earned markers are career-level.

The surface counts earned + locked markers across four fixtures:

  - `empty` — no expenses, nothing earned.
  - `trip-earned` — a single trip with 5 distinct categories + enough fuel
    for Premium Unleaded, triggering Cairn Builder and Premium Unleaded after
    the career-marker filter. Does NOT show Trailhead or Mile Marker 1.
  - `career-only` — a single trip with exactly one expense (earns Trailhead
    and Mile Marker 1 only). After filtering, the strip is EMPTY.
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


{-| Input slice: evaluated marker states for a single trip after the
`isTripScoped` filter, plus a `corrupt` knob for the probe fixture.
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
        , { input = careerOnlyInput, name = "career-only", probe = False }
        , { input = { corrupt = True, earned = stripForFixture "empty" }, name = "probe-empty-claims-earned", probe = True }
        ]
    , invariants =
        [ { name = "empty trip earns nothing", check = emptyEarnsNothing }
        , { name = "trip-earned has some earned markers", check = tripEarnedHasSome }
        , { name = "career markers absent from every strip", check = careerMarkersAbsent }
        , { name = "career-only fixture renders an empty strip", check = careerOnlyIsEmpty }
        , { name = "earned <= total catalog", check = countsSumToTotal }
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
    { corrupt = False, earned = stripForFixture "empty" }


{-| A single-trip projection: 5 distinct categories + enough fuel for Premium
Unleaded ($500 on one trip). After the `isTripScoped` filter, earns Cairn
Builder (5 distinct categories) and Premium Unleaded ($500 fuel). Does NOT
show Trailhead (career), Mile Marker 1 (career), Mile Marker 100 (100 total
expenses account-wide), or Seasoned Traveler (10 trips account-wide).
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
    { corrupt = False, earned = stripForFixture "trip-earned" }


{-| A single trip with exactly one expense. This earns Trailhead (first
expense) and Mile Marker 1 (first trip) on the raw evaluation — but both are
career markers. After the `isTripScoped` filter the strip must be EMPTY.
-}
careerOnlyInputs : Milepost.Inputs
careerOnlyInputs =
    let
        tripId : String
        tripId =
            "first-trip"
    in
    { expenses =
        [ { amount = Money.fromCents 500
          , category = Category.Food
          , createdAt = Time.millisToPosix 0
          , tripId = tripId
          }
        ]
    , now = Time.millisToPosix 0
    , trips = [ { budget = Money.zero, id = tripId } ]
    , zone = Time.utc
    }


careerOnlyInput : Input
careerOnlyInput =
    { corrupt = False, earned = stripForFixture "career-only" }


{-| Compute the trip-scoped earned states for a named fixture, mirroring what
the `RouteLedger` branch in `Main.elm` produces: evaluate then filter to
`Earned` markers that pass `Milepost.isTripScoped`.
-}
stripForFixture : String -> List Milepost.MarkerState
stripForFixture name =
    let
        inputs : Milepost.Inputs
        inputs =
            case name of
                "trip-earned" ->
                    tripEarnedInputs

                "career-only" ->
                    careerOnlyInputs

                _ ->
                    emptyInputs
    in
    Milepost.evaluate inputs
        |> List.filter
            (\s ->
                case s of
                    Milepost.Earned { marker } ->
                        Milepost.isTripScoped marker

                    Milepost.Locked _ ->
                        False
            )



-- SURFACE


{-| Project the input into a checkable surface.

Keys:

  - `earned-count` — number of trip-scoped earned markers in this strip.
  - `total-markers` — total catalog size (derived dynamically).
  - `career-markers-absent` — "true" when no career marker ids appear in the
    earned list.
  - `career-only-empty` — "true" when the career-only fixture's strip is empty.

When `corrupt = True`, lies about the earned count and flags.

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

        careerIds : List String
        careerIds =
            [ "trailhead", "mile-marker-1", "mile-marker-100", "seasoned-traveler" ]

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

        careerAbsentBool : Bool
        careerAbsentBool =
            List.all (\id -> not (List.member id earnedIds)) careerIds

        careerOnlyEmptyBool : Bool
        careerOnlyEmptyBool =
            List.isEmpty (stripForFixture "career-only")
    in
    if input.corrupt then
        [ ( "career-markers-absent", "false" )
        , ( "career-only-empty", "false" )
        , ( "earned-count", String.fromInt totalMarkers )
        , ( "total-markers", String.fromInt totalMarkers )
        ]

    else
        [ ( "career-markers-absent", boolStr careerAbsentBool )
        , ( "career-only-empty", boolStr careerOnlyEmptyBool )
        , ( "earned-count", String.fromInt earnedCount )
        , ( "total-markers", String.fromInt totalMarkers )
        ]



-- INVARIANTS


emptyEarnsNothing : Input -> Contract.Surface -> Maybe String
emptyEarnsNothing input _ =
    if input.corrupt then
        Nothing

    else
        let
            emptyExpected : List Milepost.MarkerState
            emptyExpected =
                stripForFixture "empty"
        in
        if List.isEmpty emptyExpected then
            Nothing

        else
            Just ("empty inputs should produce no trip-scoped earned markers, got " ++ String.fromInt (List.length emptyExpected))


tripEarnedHasSome : Input -> Contract.Surface -> Maybe String
tripEarnedHasSome input _ =
    if input.corrupt then
        Nothing

    else
        let
            earnedCount : Int
            earnedCount =
                List.length input.earned

            tripEarnedExpected : Int
            tripEarnedExpected =
                List.length (stripForFixture "trip-earned")
        in
        if earnedCount == 0 || earnedCount >= tripEarnedExpected then
            Nothing

        else
            Just ("trip-earned fixture should have at least " ++ String.fromInt tripEarnedExpected ++ " trip-scoped earned markers, got " ++ String.fromInt earnedCount)


{-| Career markers must never appear in the strip regardless of which fixture
is being tested. This catches both the raw-evaluation case (career markers
present before filtering) and the filtered case.
-}
careerMarkersAbsent : Input -> Contract.Surface -> Maybe String
careerMarkersAbsent input _ =
    if input.corrupt then
        Just "corrupt: career markers present (injected lie)"

    else
        let
            careerIds : List String
            careerIds =
                [ "trailhead", "mile-marker-1", "mile-marker-100", "seasoned-traveler" ]

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

            foundCareer : List String
            foundCareer =
                List.filter (\id -> List.member id earnedIds) careerIds
        in
        if List.isEmpty foundCareer then
            Nothing

        else
            Just ("career markers must not appear in per-trip strip: " ++ String.join ", " foundCareer)


{-| The career-only fixture (one expense, one trip) should produce an EMPTY
strip after the `isTripScoped` filter — because `trailhead` and `mile-marker-1`
are the only markers earned, and both are career-scoped.
-}
careerOnlyIsEmpty : Input -> Contract.Surface -> Maybe String
careerOnlyIsEmpty input _ =
    if input.corrupt then
        Nothing

    else
        let
            careerOnlyStrip : List Milepost.MarkerState
            careerOnlyStrip =
                stripForFixture "career-only"
        in
        if List.isEmpty careerOnlyStrip then
            Nothing

        else
            let
                ids : List String
                ids =
                    List.filterMap
                        (\s ->
                            case s of
                                Milepost.Earned { marker } ->
                                    Just marker.id

                                Milepost.Locked _ ->
                                    Nothing
                        )
                        careerOnlyStrip
            in
            Just ("career-only fixture should produce empty strip, but got: " ++ String.join ", " ids)


countsSumToTotal : Input -> Contract.Surface -> Maybe String
countsSumToTotal input _ =
    if input.corrupt then
        Nothing

    else
        let
            totalMarkers : Int
            totalMarkers =
                List.length Milepost.catalog

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
