module Verify.Specs.MilepostScreen exposing (Input, results, statesForFixture, surfaceFor)

{-| DOM-tier verification unit for "The Milepost" collection screen (#409).

`Pages.Milepost.viewTab` renders `AuthState.milepostStates` grouped by family,
with an earned/total progress bar and a distinct empty state. This unit pins
that projection: the page and the invariants both read `surfaceFor`, so the
rendered `data-verify-*` attributes can't drift from what the checks assert.

Fixtures: `empty` (all locked → empty-state branch), `partial` (some earned),
`all-earned` (every marker earned), plus a `probe` that lies (claims everything
earned on empty states) so one fixture must FAIL.

DOM seeding: `Main.applyUnitSeed`'s `"MilepostScreen"` arm sets
`milepostStates = statesForFixture name` + `route = RouteMilepost`, and
`Pages.Milepost` attaches `Verify.Contract.verifyAttrs "MilepostScreen"`.

@docs Input, results, statesForFixture, surfaceFor

-}

import Data.Category as Category
import Data.Milepost as Milepost
import Data.Money as Money
import Time
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


{-| The slice this unit observes: the evaluated marker states the screen
renders, plus a `corrupt` knob that only the probe sets.
-}
type alias Input =
    { corrupt : Bool
    , states : List Milepost.MarkerState
    }


{-| The pure-tier results for this unit, collected by `Verify.Registry`.
-}
results : List Core.RunResult
results =
    Runner.runUnit spec


spec : Spec.UnitSpec Input
spec =
    { fixtures =
        [ { input = honest "empty", name = "empty", probe = False }
        , { input = honest "partial", name = "partial", probe = False }
        , { input = honest "all-earned", name = "all-earned", probe = False }
        , { input = { corrupt = True, states = statesForFixture "empty" }, name = "probe-empty-claims-earned", probe = True }
        ]
    , invariants =
        [ { name = "earned + locked = total", check = countsSumToTotal }
        , { name = "empty fixture earns nothing", check = emptyEarnsNothing }
        , { name = "per-family earned never exceeds family total", check = familyWithinTotal }
        , { name = "earned == total iff every family is full", check = allEarnedConsistent }
        ]
    , name = "MilepostScreen"
    , surface = surface
    }


honest : String -> Input
honest name =
    { corrupt = False, states = statesForFixture name }


{-| Map a fixture name to the evaluated `List MarkerState` the screen renders.
Single source of truth for both the spec fixtures and `Main.applyUnitSeed`.
-}
statesForFixture : String -> List Milepost.MarkerState
statesForFixture name =
    Milepost.evaluate (inputsForFixture name)


inputsForFixture : String -> Milepost.Inputs
inputsForFixture name =
    case name of
        "partial" ->
            partialInputs

        "all-earned" ->
            allEarnedInputs

        _ ->
            -- "empty" and any unknown fixture: nothing logged → all locked.
            { expenses = [], now = Time.millisToPosix 0, trips = [], zone = Time.utc }


{-| A handful of expenses across one trip: earns the early TrailDiscipline /
MileMarkers markers but leaves the dollar + streak markers locked.
-}
partialInputs : Milepost.Inputs
partialInputs =
    let
        makeExpense : Category.Category -> Milepost.ExpenseFacts
        makeExpense cat =
            { amount = Money.fromCents 1000
            , category = cat
            , createdAt = Time.millisToPosix 0
            , isAmended = False
            , tripId = "trip-1"
            }
    in
    { expenses =
        [ makeExpense Category.Fuel
        , makeExpense Category.Food
        , makeExpense Category.Camp
        , makeExpense Category.Lodging
        , makeExpense Category.Transport
        ]
    , now = Time.millisToPosix 0
    , trips = [ { budget = Money.zero, durationDays = 0, id = "trip-1" } ]
    , zone = Time.utc
    }


{-| Mirrors the all-earned fixture from `Verify.Specs.Milepost`: enough trips,
expenses, fuel dollars, a 30-day streak, and an over-budget trip to earn every
marker in the catalog.
-}
allEarnedInputs : Milepost.Inputs
allEarnedInputs =
    let
        numTrips : Int
        numTrips =
            10

        heroTripId : String
        heroTripId =
            "trip-1"

        bigFuelExpenses : List Milepost.ExpenseFacts
        bigFuelExpenses =
            List.range 1 6
                |> List.map
                    (\_ ->
                        { amount = Money.fromCents 10000
                        , category = Category.Fuel
                        , createdAt = Time.millisToPosix 0
                        , isAmended = False
                        , tripId = heroTripId
                        }
                    )

        extraFuelTrip2 : List Milepost.ExpenseFacts
        extraFuelTrip2 =
            List.range 1 5
                |> List.map
                    (\_ ->
                        { amount = Money.fromCents 10000
                        , category = Category.Fuel
                        , createdAt = Time.millisToPosix 0
                        , isAmended = False
                        , tripId = "trip-2"
                        }
                    )

        miscExpensesTrip1 : List Milepost.ExpenseFacts
        miscExpensesTrip1 =
            [ { amount = Money.fromCents 100000, category = Category.Food, createdAt = Time.millisToPosix 0, isAmended = False, tripId = heroTripId }
            , { amount = Money.fromCents 150000, category = Category.Lodging, createdAt = Time.millisToPosix 0, isAmended = False, tripId = heroTripId }
            , { amount = Money.fromCents 100000, category = Category.Camp, createdAt = Time.millisToPosix 0, isAmended = False, tripId = heroTripId }
            , { amount = Money.fromCents 200000, category = Category.Transport, createdAt = Time.millisToPosix 0, isAmended = False, tripId = heroTripId }
            ]

        streakExpenses : List Milepost.ExpenseFacts
        streakExpenses =
            List.range 0 29
                |> List.map
                    (\dayOffset ->
                        { amount = Money.fromCents 100
                        , category = Category.Misc
                        , createdAt = Time.millisToPosix (dayOffset * 86400000)
                        , isAmended = False
                        , tripId = heroTripId
                        }
                    )

        extraExpenses : List Milepost.ExpenseFacts
        extraExpenses =
            List.range 2 numTrips
                |> List.concatMap
                    (\n ->
                        List.range 1 7
                            |> List.map
                                (\_ ->
                                    { amount = Money.fromCents 200
                                    , category = Category.Misc
                                    , createdAt = Time.millisToPosix 0
                                    , isAmended = False
                                    , tripId = "trip-" ++ String.fromInt n
                                    }
                                )
                    )

        -- Single Misc splurge >= $250 → Souvenir Tax; amended → Detour.
        souvenirExpense : Milepost.ExpenseFacts
        souvenirExpense =
            { amount = Money.fromCents 30000
            , category = Category.Misc
            , createdAt = Time.millisToPosix 0
            , isAmended = True
            , tripId = heroTripId
            }

        trips : List Milepost.TripFacts
        trips =
            List.range 1 numTrips
                |> List.map
                    (\n ->
                        let
                            tid : String
                            tid =
                                "trip-" ++ String.fromInt n
                        in
                        if tid == heroTripId then
                            { budget = Money.fromCents 1000, durationDays = 14, id = tid }

                        else
                            { budget = Money.zero, durationDays = 0, id = tid }
                    )
    in
    { expenses = bigFuelExpenses ++ extraFuelTrip2 ++ miscExpensesTrip1 ++ streakExpenses ++ extraExpenses ++ [ souvenirExpense ]
    , now = Time.millisToPosix (30 * 86400000)
    , trips = trips
    , zone = Time.utc
    }



-- SURFACE


{-| Project a `List MarkerState` into the screen's observable surface. Reused by
`Pages.Milepost.viewTab` (via the page's `verifyAttrs`) so the rendered DOM and
the invariants read the same projection.

Keys:

  - `total` — total markers rendered
  - `earned` — earned count
  - `locked` — locked count
  - `screen` — `"empty"` when nothing is earned, else `"populated"`
  - `family-<name>` — earned/total for each family, e.g. `"3/4"`

-}
surfaceFor : List Milepost.MarkerState -> Contract.Surface
surfaceFor states =
    let
        earned : Int
        earned =
            List.length (List.filter isEarned states)

        total : Int
        total =
            List.length states

        familyPair : Milepost.Family -> ( String, String )
        familyPair family =
            let
                inFamily : List Milepost.MarkerState
                inFamily =
                    List.filter (\st -> stateFamily st == family) states

                fEarned : Int
                fEarned =
                    List.length (List.filter isEarned inFamily)
            in
            ( "family-" ++ familyKey family
            , String.fromInt fEarned ++ "/" ++ String.fromInt (List.length inFamily)
            )
    in
    [ ( "total", String.fromInt total )
    , ( "earned", String.fromInt earned )
    , ( "locked", String.fromInt (total - earned) )
    , ( "screen"
      , if earned == 0 then
            "empty"

        else
            "populated"
      )
    ]
        ++ List.map familyPair families


{-| The spec surface: honest fixtures project `surfaceFor`; the probe lies by
claiming every marker earned (and a populated screen) on empty states.
-}
surface : Input -> Contract.Surface
surface input =
    if input.corrupt then
        let
            total : Int
            total =
                List.length input.states
        in
        [ ( "total", String.fromInt total )
        , ( "earned", String.fromInt total )
        , ( "locked", "0" )
        , ( "screen", "populated" )
        ]
            ++ List.map
                (\family ->
                    let
                        n : Int
                        n =
                            List.length (List.filter (\st -> stateFamily st == family) input.states)
                    in
                    ( "family-" ++ familyKey family, String.fromInt n ++ "/" ++ String.fromInt n )
                )
                families

    else
        surfaceFor input.states


families : List Milepost.Family
families =
    [ Milepost.CautionSigns
    , Milepost.MileMarkers
    , Milepost.Odometer
    , Milepost.TrailDiscipline
    ]


familyKey : Milepost.Family -> String
familyKey family =
    case family of
        Milepost.CautionSigns ->
            "caution-signs"

        Milepost.MileMarkers ->
            "mile-markers"

        Milepost.Odometer ->
            "odometer"

        Milepost.TrailDiscipline ->
            "trail-discipline"


isEarned : Milepost.MarkerState -> Bool
isEarned state =
    case state of
        Milepost.Earned _ ->
            True

        Milepost.Locked _ ->
            False


stateFamily : Milepost.MarkerState -> Milepost.Family
stateFamily state =
    case state of
        Milepost.Earned { marker } ->
            marker.family

        Milepost.Locked { marker } ->
            marker.family



-- INVARIANTS


countsSumToTotal : Input -> Contract.Surface -> Maybe String
countsSumToTotal _ observed =
    case ( surfaceInt "total" observed, surfaceInt "earned" observed, surfaceInt "locked" observed ) of
        ( Just t, Just e, Just l ) ->
            if e + l == t then
                Nothing

            else
                Just ("earned (" ++ String.fromInt e ++ ") + locked (" ++ String.fromInt l ++ ") != total (" ++ String.fromInt t ++ ")")

        _ ->
            Just "missing count keys"


emptyEarnsNothing : Input -> Contract.Surface -> Maybe String
emptyEarnsNothing input observed =
    -- Compares the surface against the actual states, INCLUDING the corrupt
    -- probe — the probe's states are all-locked, so its lying "earned" trips
    -- this invariant. That's what makes the probe fixture fail as required.
    if List.all (not << isEarned) input.states then
        case ( surfaceInt "earned" observed, value "screen" observed ) of
            ( Just 0, Just "empty" ) ->
                Nothing

            ( Just n, _ ) ->
                Just ("nothing-earned fixture reported earned=" ++ String.fromInt n ++ " / screen=" ++ Maybe.withDefault "?" (value "screen" observed))

            _ ->
                Just "missing earned/screen key"

    else
        Nothing


familyWithinTotal : Input -> Contract.Surface -> Maybe String
familyWithinTotal _ observed =
    let
        offenders : List String
        offenders =
            families
                |> List.filterMap
                    (\family ->
                        case familyPairInts ("family-" ++ familyKey family) observed of
                            Just ( e, t ) ->
                                if e > t then
                                    Just (familyKey family ++ " earned " ++ String.fromInt e ++ " > total " ++ String.fromInt t)

                                else
                                    Nothing

                            Nothing ->
                                Just (familyKey family ++ " missing")
                    )
    in
    case offenders of
        [] ->
            Nothing

        first :: _ ->
            Just first


allEarnedConsistent : Input -> Contract.Surface -> Maybe String
allEarnedConsistent _ observed =
    case ( surfaceInt "earned" observed, surfaceInt "total" observed ) of
        ( Just e, Just t ) ->
            let
                everyFamilyFull : Bool
                everyFamilyFull =
                    families
                        |> List.all
                            (\family ->
                                case familyPairInts ("family-" ++ familyKey family) observed of
                                    Just ( fe, ft ) ->
                                        fe == ft

                                    Nothing ->
                                        False
                            )
            in
            if (e == t) == everyFamilyFull then
                Nothing

            else
                Just "earned==total disagrees with per-family fullness"

        _ ->
            Just "missing earned/total key"



-- HELPERS


surfaceInt : String -> Contract.Surface -> Maybe Int
surfaceInt key observed =
    value key observed |> Maybe.andThen String.toInt


value : String -> Contract.Surface -> Maybe String
value key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second


familyPairInts : String -> Contract.Surface -> Maybe ( Int, Int )
familyPairInts key observed =
    case value key observed |> Maybe.map (String.split "/") of
        Just [ e, t ] ->
            Maybe.map2 Tuple.pair (String.toInt e) (String.toInt t)

        _ ->
            Nothing
