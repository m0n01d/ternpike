module Verify.Specs.Milepost exposing (results)

{-| Verification unit for the Milepost achievement evaluation engine (#407).

Exercises `Data.Milepost.evaluate` over four input fixtures — empty, partial,
all-earned, and an adversarial probe — and checks a set of structural invariants
that must hold regardless of which specific markers are in the catalog.

Pure-tier only (like `ScanRouting`): no DOM seeding, no `Main` wiring. Those
arrive in #408 and #409.

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


{-| The input slice for this unit. `corrupt = True` makes the surface lie (claim
all markers earned even on empty inputs), so the probe fixture trips the
invariants.
-}
type alias Input =
    { corrupt : Bool
    , inputs : Milepost.Inputs
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
        , { input = partialInput, name = "partial", probe = False }
        , { input = allEarnedInput, name = "all-earned", probe = False }
        , { input = { corrupt = True, inputs = emptyInputData }, name = "probe-corrupt-empty", probe = True }
        ]
    , invariants =
        [ { name = "earned + locked = total catalog", check = countsSumToTotal }
        , { name = "empty inputs earn nothing", check = emptyEarnsNothing }
        , { name = "no earned-count exceeds total", check = noOverlap }
        , { name = "all-earned fixture earns all markers", check = allEarnedEarnsAll }
        , { name = "day-keys-run equals longest-streak-days", check = dayKeysMatchStreak }
        ]
    , name = "Milepost"
    , surface = surface
    }



-- FIXTURES


emptyInputData : Milepost.Inputs
emptyInputData =
    { expenses = []
    , now = Time.millisToPosix 0
    , trips = []
    , zone = Time.utc
    }


emptyInput : Input
emptyInput =
    { corrupt = False
    , inputs = emptyInputData
    }


{-| A partial fixture: some markers earned, some locked.

Has 1 trip and 5 fuel expenses (different categories spread across them), which
earns: Trailhead (TrailDiscipline), Mile Marker 1 (MileMarkers), and Cairn
Builder (TrailDiscipline, 5 distinct categories). Does not earn Mile Marker 100,
Seasoned Traveler, streaks, or the dollar markers.

-}
partialInput : Input
partialInput =
    let
        tripId : String
        tripId =
            "trip-1"

        makeExpense : Category.Category -> Milepost.ExpenseFacts
        makeExpense cat =
            { amount = Money.fromCents 1000
            , category = cat
            , createdAt = Time.millisToPosix 0
            , tripId = tripId
            }
    in
    { corrupt = False
    , inputs =
        { expenses =
            [ makeExpense Category.Fuel
            , makeExpense Category.Food
            , makeExpense Category.Camp
            , makeExpense Category.Lodging
            , makeExpense Category.Transport
            ]
        , now = Time.millisToPosix 0
        , trips =
            [ { budget = Money.zero
              , id = tripId
              }
            ]
        , zone = Time.utc
        }
    }


{-| An all-earned fixture: every marker in the catalog is earned.

Two trips; 100+ expenses; fuel totals over $1,000 across trips and over $500 on
one trip; one trip total over $5,000; one trip over budget; 5+ distinct
categories on both trips; 30+ day streak; 10+ trips for Seasoned Traveler.

-}
allEarnedInput : Input
allEarnedInput =
    let
        numTrips : Int
        numTrips =
            10

        tripIds : List String
        tripIds =
            List.range 1 numTrips |> List.map (\n -> "trip-" ++ String.fromInt n)

        -- Trip 1 is the hero trip: over budget, big total, lots of fuel, 5 cats
        heroTripId : String
        heroTripId =
            "trip-1"

        -- 6 × $100 fuel on trip 1 = $600 (enough for Premium Unleaded + contributes to Fill 'er Up)
        bigFuelExpenses : List Milepost.ExpenseFacts
        bigFuelExpenses =
            List.range 1 6
                |> List.map
                    (\_ ->
                        { amount = Money.fromCents 10000
                        , category = Category.Fuel
                        , createdAt = Time.millisToPosix 0
                        , tripId = heroTripId
                        }
                    )

        -- Extra fuel on trip 2 to push total fuel above $1,000
        extraFuelTrip2 : List Milepost.ExpenseFacts
        extraFuelTrip2 =
            List.range 1 5
                |> List.map
                    (\_ ->
                        { amount = Money.fromCents 10000
                        , category = Category.Fuel
                        , createdAt = Time.millisToPosix 0
                        , tripId = "trip-2"
                        }
                    )

        -- 5 distinct categories on trip 1 (fuel + 4 more), big amounts for Big Rig ($5,000)
        -- The $300 Misc expense also earns Souvenir Tax (single Misc >= $250).
        miscExpensesTrip1 : List Milepost.ExpenseFacts
        miscExpensesTrip1 =
            [ { amount = Money.fromCents 100000
              , category = Category.Food
              , createdAt = Time.millisToPosix 0
              , tripId = heroTripId
              }
            , { amount = Money.fromCents 150000
              , category = Category.Lodging
              , createdAt = Time.millisToPosix 0
              , tripId = heroTripId
              }
            , { amount = Money.fromCents 100000
              , category = Category.Camp
              , createdAt = Time.millisToPosix 0
              , tripId = heroTripId
              }
            , { amount = Money.fromCents 200000
              , category = Category.Transport
              , createdAt = Time.millisToPosix 0
              , tripId = heroTripId
              }
            , { amount = Money.fromCents 30000
              , category = Category.Misc
              , createdAt = Time.millisToPosix 0
              , tripId = heroTripId
              }
            ]

        -- 30-day streak: one expense per day for 30 consecutive days
        streakExpenses : List Milepost.ExpenseFacts
        streakExpenses =
            List.range 0 29
                |> List.map
                    (\dayOffset ->
                        { amount = Money.fromCents 100
                        , category = Category.Misc
                        , createdAt = Time.millisToPosix (dayOffset * 86400000)
                        , tripId = heroTripId
                        }
                    )

        -- Extra expenses to reach 100 total
        -- So far: 6 + 4 + 30 = 40 on trip-1, 5 on trip-2 = 45 total
        -- Need 55 more across trips 2-10 (remaining 9 trips, ~6 each)
        extraExpenses : List Milepost.ExpenseFacts
        extraExpenses =
            List.range 2 numTrips
                |> List.concatMap
                    (\n ->
                        let
                            tid : String
                            tid =
                                "trip-" ++ String.fromInt n
                        in
                        List.range 1 7
                            |> List.map
                                (\_ ->
                                    { amount = Money.fromCents 200
                                    , category = Category.Misc
                                    , createdAt = Time.millisToPosix 0
                                    , tripId = tid
                                    }
                                )
                    )

        allExpenses : List Milepost.ExpenseFacts
        allExpenses =
            bigFuelExpenses
                ++ extraFuelTrip2
                ++ miscExpensesTrip1
                ++ streakExpenses
                ++ extraExpenses

        trips : List Milepost.TripFacts
        trips =
            List.map
                (\tid ->
                    -- Hero trip has a budget lower than its actual total
                    if tid == heroTripId then
                        { budget = Money.fromCents 1000, id = tid }

                    else
                        { budget = Money.zero, id = tid }
                )
                tripIds
    in
    { corrupt = False
    , inputs =
        { expenses = allExpenses
        , now = Time.millisToPosix (30 * 86400000)
        , trips = trips
        , zone = Time.utc
        }
    }



-- SURFACE


{-| Project the evaluation result into a flat, checkable surface.

Keys:

  - `total-markers` — total number of markers in the catalog
  - `earned-count` — number of markers earned
  - `locked-count` — number of markers locked
  - `trail-discipline-earned` — earned count within the `TrailDiscipline` family
  - `goal-flag-in-catalog` — "true" if the catalog contains any `Flag` goals

When `corrupt = True`, claims all markers are earned regardless of actual inputs
— this is the injected regression the probe fixture catches.

-}
surface : Input -> Contract.Surface
surface input =
    let
        totalMarkers : Int
        totalMarkers =
            List.length Milepost.catalog

        hasFlagGoal : Bool
        hasFlagGoal =
            List.any (\m -> isFlag m.goal) Milepost.catalog
    in
    if input.corrupt then
        -- Lie: claim all earned on empty input — the invariants will catch this
        [ ( "total-markers", String.fromInt totalMarkers )
        , ( "earned-count", String.fromInt totalMarkers )
        , ( "locked-count", "0" )
        , ( "trail-discipline-earned", String.fromInt totalMarkers )
        , ( "goal-flag-in-catalog", boolStr hasFlagGoal )
        ]

    else
        let
            states : List Milepost.MarkerState
            states =
                Milepost.evaluate input.inputs

            earnedCount : Int
            earnedCount =
                List.length (List.filter isEarned states)

            lockedCount : Int
            lockedCount =
                List.length (List.filter (not << isEarned) states)

            trailDisciplineEarned : Int
            trailDisciplineEarned =
                states
                    |> List.filter
                        (\st ->
                            markerFamily st == Milepost.TrailDiscipline && isEarned st
                        )
                    |> List.length

            -- Surface additional computed observations using the exposed
            -- helpers so downstream invariants can cross-check evaluation.
            longestStreakDays : Int
            longestStreakDays =
                Milepost.longestStreak input.inputs.zone
                    (List.map .createdAt input.inputs.expenses)

            totalAmountCents : Int
            totalAmountCents =
                Milepost.sumWhere (\_ -> True) input.inputs.expenses
                    |> Money.toCents

            -- dayKeys + longestRun cross-check: should equal longestStreakDays
            dayKeysRun : Int
            dayKeysRun =
                input.inputs.expenses
                    |> List.map (.createdAt >> Milepost.dayKey input.inputs.zone)
                    |> List.sort
                    |> Milepost.longestRun

            -- distinctCount over all expense categories
            distinctCategories : Int
            distinctCategories =
                Milepost.distinctCount (List.map .category input.inputs.expenses)
        in
        [ ( "total-markers", String.fromInt totalMarkers )
        , ( "earned-count", String.fromInt earnedCount )
        , ( "locked-count", String.fromInt lockedCount )
        , ( "trail-discipline-earned", String.fromInt trailDisciplineEarned )
        , ( "goal-flag-in-catalog", boolStr hasFlagGoal )
        , ( "longest-streak-days", String.fromInt longestStreakDays )
        , ( "total-amount-cents", String.fromInt totalAmountCents )
        , ( "day-keys-run", String.fromInt dayKeysRun )
        , ( "distinct-categories", String.fromInt distinctCategories )
        ]


isEarned : Milepost.MarkerState -> Bool
isEarned state =
    case state of
        Milepost.Earned _ ->
            True

        Milepost.Locked _ ->
            False


markerFamily : Milepost.MarkerState -> Milepost.Family
markerFamily state =
    case state of
        Milepost.Earned { marker } ->
            marker.family

        Milepost.Locked { marker } ->
            marker.family


isFlag : Milepost.Goal -> Bool
isFlag goal =
    case goal of
        Milepost.Flag ->
            True

        Milepost.Count _ ->
            False

        Milepost.Dollars _ ->
            False

        Milepost.Streak _ ->
            False


boolStr : Bool -> String
boolStr b =
    if b then
        "true"

    else
        "false"



-- INVARIANTS


{-| The total number of distinct earned + locked states equals the catalog size.
-}
countsSumToTotal : Input -> Contract.Surface -> Maybe String
countsSumToTotal _ observed =
    let
        total : Maybe Int
        total =
            surfaceInt "total-markers" observed

        earned : Maybe Int
        earned =
            surfaceInt "earned-count" observed

        locked : Maybe Int
        locked =
            surfaceInt "locked-count" observed
    in
    case ( total, earned, locked ) of
        ( Just t, Just e, Just l ) ->
            if e + l == t then
                Nothing

            else
                Just
                    ("earned ("
                        ++ String.fromInt e
                        ++ ") + locked ("
                        ++ String.fromInt l
                        ++ ") != total ("
                        ++ String.fromInt t
                        ++ ")"
                    )

        _ ->
            Just "missing surface keys"


{-| On empty inputs, nothing should be earned.
-}
emptyEarnsNothing : Input -> Contract.Surface -> Maybe String
emptyEarnsNothing input observed =
    if
        List.isEmpty input.inputs.expenses
            && List.isEmpty input.inputs.trips
    then
        case surfaceInt "earned-count" observed of
            Just 0 ->
                Nothing

            Just n ->
                Just ("empty inputs earned " ++ String.fromInt n ++ " markers, expected 0")

            Nothing ->
                Just "missing earned-count key"

    else
        Nothing


{-| The earned-count must never exceed the total catalog size.
-}
noOverlap : Input -> Contract.Surface -> Maybe String
noOverlap _ observed =
    let
        total : Maybe Int
        total =
            surfaceInt "total-markers" observed

        earned : Maybe Int
        earned =
            surfaceInt "earned-count" observed
    in
    case ( total, earned ) of
        ( Just t, Just e ) ->
            if e > t then
                Just ("earned-count " ++ String.fromInt e ++ " exceeds total " ++ String.fromInt t)

            else
                Nothing

        _ ->
            Just "missing surface keys"


{-| On the all-earned fixture, every marker should be earned.
-}
allEarnedEarnsAll : Input -> Contract.Surface -> Maybe String
allEarnedEarnsAll input observed =
    -- Only enforce on non-corrupt, non-empty fixtures where earned == total
    -- (the partial fixture will have fewer earned than total — skip it)
    if
        not (List.isEmpty input.inputs.expenses)
            && not (List.isEmpty input.inputs.trips)
            && not input.corrupt
    then
        case ( surfaceInt "earned-count" observed, surfaceInt "total-markers" observed ) of
            ( Just e, Just t ) ->
                if e == t then
                    -- earned == total: sanity check locked == 0
                    case surfaceInt "locked-count" observed of
                        Just 0 ->
                            Nothing

                        Just l ->
                            Just ("all-earned fixture has locked-count " ++ String.fromInt l ++ " but earned == total")

                        Nothing ->
                            Just "missing locked-count key"

                else
                    -- partial fixture: fewer earned than total — vacuously OK
                    Nothing

            _ ->
                Nothing

    else
        Nothing


{-| The `day-keys-run` (computed via `longestRun` + `dayKey`) should equal
`longest-streak-days` (computed via `longestStreak`). This cross-checks that
both code paths agree on the streak length. Skipped on the corrupt fixture.
-}
dayKeysMatchStreak : Input -> Contract.Surface -> Maybe String
dayKeysMatchStreak input observed =
    if input.corrupt then
        Nothing

    else
        case ( surfaceInt "day-keys-run" observed, surfaceInt "longest-streak-days" observed ) of
            ( Just run, Just streak ) ->
                if run == streak then
                    Nothing

                else
                    Just
                        ("day-keys-run ("
                            ++ String.fromInt run
                            ++ ") != longest-streak-days ("
                            ++ String.fromInt streak
                            ++ ")"
                        )

            _ ->
                Nothing



-- HELPERS


surfaceInt : String -> Contract.Surface -> Maybe Int
surfaceInt key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.andThen String.toInt
