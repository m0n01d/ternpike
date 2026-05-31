module Data.Milepost exposing
    ( ExpenseFacts, Family(..), Goal(..), Inputs, Marker, MarkerId, MarkerState(..), TripFacts
    , catalog, evaluate, isTripScoped
    , dayKey, distinctCount, longestRun, longestStreak, sumWhere
    )

{-| Milestone achievements ("mileposts") for the Ternpike expense tracker.

A milepost is an achievement marker that the user earns by reaching a specific
goal. Each `Marker` belongs to a `Family` and has a `Goal`. `evaluate` takes a
snapshot of the user's expenses and trips and returns the current `MarkerState`
for every marker in the `catalog`.

This module is purely a function over `Inputs` — no ports, no HTTP, no side
effects. The caller (typically `Main`-side, issue #408) projects the live
`AuthState` into `Inputs` via `Entry.resolve`, so amendment and soft-delete
semantics are already baked in by the time `evaluate` is called.

@docs ExpenseFacts, Family, Goal, Inputs, Marker, MarkerId, MarkerState, TripFacts
@docs catalog, evaluate, isTripScoped
@docs dayKey, distinctCount, longestRun, longestStreak, sumWhere

-}

import Data.Category as Category
import Data.Money as Money
import Time



-- TYPES
-- GloveboxLibrary (the literary family) is introduced by its first markers in #412.


{-| The thematic family a marker belongs to. Used for grouping in the UI.

Constructors are alphabetized per the Elm style guide.

-}
type Family
    = CautionSigns
    | MileMarkers
    | Odometer
    | TrailDiscipline


{-| The numeric or flag goal a marker tracks. The payload drives both the
evaluation threshold and the progress label — `evaluate` reads these values
rather than re-deriving thresholds inline.
-}
type Goal
    = Count Int
    | Dollars Money.Money
    | Flag
    | Streak Int


{-| A unique string identifier for a marker. Stable across app versions — do
not rename an existing id once users can earn it.
-}
type alias MarkerId =
    String


{-| A single achievement definition.

Fields are alphabetized per the Elm style guide.

-}
type alias Marker =
    { blurb : String
    , family : Family
    , goal : Goal
    , id : MarkerId
    , name : String
    }


{-| The current state of a marker for a given `Inputs` snapshot.

  - `Earned` — the goal was reached.
  - `Locked` — not yet earned. `progress` is a 0–1 fraction of the way there;
    `label` is a human-readable description of progress (e.g. `"21 / 30 days"`).

-}
type MarkerState
    = Earned { marker : Marker }
    | Locked { label : String, marker : Marker, progress : Float }


{-| A single expense projected down to the fields the evaluation engine needs.

Callers should project from fully-resolved entries (`Entry.resolve` already
applied) so amendment and soft-delete semantics are handled before this
module is reached.

-}
type alias ExpenseFacts =
    { amount : Money.Money
    , category : Category.Category
    , createdAt : Time.Posix
    , tripId : String
    }


{-| A single trip projected down to the fields the evaluation engine needs.
-}
type alias TripFacts =
    { budget : Money.Money
    , id : String
    }


{-| The complete input snapshot for `evaluate`.

  - `expenses` — all resolved expenses across all trips.
  - `now` — the current time, used for streak calculations. Passed explicitly so
    the function stays pure and testable.
  - `trips` — all trips, used for per-trip predicates and budget checks.
  - `zone` — the time zone used to bucket expenses into calendar days for streak
    computation. In v1 callers always pass `Time.utc`; the parameter exists so
    switching to the user's local zone is a one-line change.

-}
type alias Inputs =
    { expenses : List ExpenseFacts
    , now : Time.Posix
    , trips : List TripFacts
    , zone : Time.Zone
    }



-- CATALOG


{-| The complete list of achievement markers, in stable display order.
-}
catalog : List Marker
catalog =
    [ markerTrailhead
    , markerMileMarker1
    , markerMileMarker100
    , markerSeasonedTraveler
    , markerWellBlazedTrail
    , markerSwitchbacks
    , markerCairnBuilder
    , markerFillErUp
    , markerPremiumUnleaded
    , markerBigRig
    , markerBudgetWhatBudget
    , markerSouvenirTax
    ]


{-| Returns `True` for markers that are meaningful in a per-trip context — i.e.
markers whose earning condition depends on data from a single trip.

Returns `False` for career/account-wide markers that fire on every trip once
earned (e.g. `trailhead`, `mile-marker-1`) or that count across all trips
(`mile-marker-100`, `seasoned-traveler`). Those markers do not belong in the
per-trip Ledger strip and should be filtered out before display.

-}
isTripScoped : Marker -> Bool
isTripScoped marker =
    case marker.id of
        "trailhead" ->
            False

        "mile-marker-1" ->
            False

        "mile-marker-100" ->
            False

        "seasoned-traveler" ->
            False

        _ ->
            True


markerTrailhead : Marker
markerTrailhead =
    { blurb = "Log your first expense."
    , family = TrailDiscipline
    , goal = Flag
    , id = "trailhead"
    , name = "Trailhead"
    }


markerMileMarker1 : Marker
markerMileMarker1 =
    { blurb = "Start your first trip."
    , family = MileMarkers
    , goal = Count 1
    , id = "mile-marker-1"
    , name = "Mile Marker 1"
    }


markerMileMarker100 : Marker
markerMileMarker100 =
    { blurb = "Log 100 expenses."
    , family = MileMarkers
    , goal = Count 100
    , id = "mile-marker-100"
    , name = "Mile Marker 100"
    }


markerSeasonedTraveler : Marker
markerSeasonedTraveler =
    { blurb = "Complete 10 trips."
    , family = MileMarkers
    , goal = Count 10
    , id = "seasoned-traveler"
    , name = "Seasoned Traveler"
    }


markerWellBlazedTrail : Marker
markerWellBlazedTrail =
    { blurb = "Log expenses 7 days in a row."
    , family = TrailDiscipline
    , goal = Streak 7
    , id = "well-blazed-trail"
    , name = "Well-Blazed Trail"
    }


markerSwitchbacks : Marker
markerSwitchbacks =
    { blurb = "Log expenses 30 days in a row."
    , family = TrailDiscipline
    , goal = Streak 30
    , id = "switchbacks"
    , name = "Switchbacks"
    }


markerCairnBuilder : Marker
markerCairnBuilder =
    { blurb = "Use 5 different expense categories on a single trip."
    , family = TrailDiscipline
    , goal = Count 5
    , id = "cairn-builder"
    , name = "Cairn Builder"
    }


markerFillErUp : Marker
markerFillErUp =
    { blurb = "Spend $1,000 on fuel across all trips."
    , family = Odometer
    , goal = Dollars (Money.fromCents 100000)
    , id = "fill-er-up"
    , name = "Fill 'er Up"
    }


markerPremiumUnleaded : Marker
markerPremiumUnleaded =
    { blurb = "Spend $500 on fuel in a single trip."
    , family = Odometer
    , goal = Dollars (Money.fromCents 50000)
    , id = "premium-unleaded"
    , name = "Premium Unleaded"
    }


markerBigRig : Marker
markerBigRig =
    { blurb = "Spend $5,000 on a single trip."
    , family = Odometer
    , goal = Dollars (Money.fromCents 500000)
    , id = "big-rig"
    , name = "Big Rig"
    }


markerBudgetWhatBudget : Marker
markerBudgetWhatBudget =
    { blurb = "Exceed your trip budget."
    , family = CautionSigns
    , goal = Flag
    , id = "budget-what-budget"
    , name = "Budget? What Budget?"
    }


{-| Earned when the user logs a single Misc-category expense of $250 or more.
-}
markerSouvenirTax : Marker
markerSouvenirTax =
    { blurb = "Drop $250 on a single Misc splurge."
    , family = CautionSigns
    , goal = Dollars (Money.fromCents 25000)
    , id = "souvenir-tax"
    , name = "Souvenir Tax"
    }



-- EVALUATE


{-| Evaluate the current state of every marker in the `catalog` against the
provided `Inputs` snapshot.

Returns one `MarkerState` per `Marker` in `catalog` order. `Locked` states
carry a `progress` (0–1) and a human-readable `label` so the UI can render a
progress bar without any additional computation.

-}
evaluate : Inputs -> List MarkerState
evaluate inputs =
    List.map (evaluateMarker inputs) catalog


evaluateMarker : Inputs -> Marker -> MarkerState
evaluateMarker inputs marker =
    case marker.id of
        "trailhead" ->
            -- Flag: any expense exists
            if not (List.isEmpty inputs.expenses) then
                Earned { marker = marker }

            else
                Locked
                    { label = "0 / 1 expense"
                    , marker = marker
                    , progress = 0
                    }

        "mile-marker-1" ->
            -- Count 1: at least 1 trip
            let
                have : Int
                have =
                    List.length inputs.trips
            in
            evaluateCount have marker

        "mile-marker-100" ->
            -- Count 100: at least 100 expenses
            let
                have : Int
                have =
                    List.length inputs.expenses
            in
            evaluateCount have marker

        "seasoned-traveler" ->
            -- Count 10: at least 10 trips
            let
                have : Int
                have =
                    List.length inputs.trips
            in
            evaluateCount have marker

        "well-blazed-trail" ->
            -- Streak 7: longest consecutive-day streak >= 7
            let
                have : Int
                have =
                    longestStreak inputs.zone (List.map .createdAt inputs.expenses)
            in
            evaluateStreak have marker

        "switchbacks" ->
            -- Streak 30: longest consecutive-day streak >= 30
            let
                have : Int
                have =
                    longestStreak inputs.zone (List.map .createdAt inputs.expenses)
            in
            evaluateStreak have marker

        "cairn-builder" ->
            -- Count 5: >= 5 distinct categories on a single trip
            let
                have : Int
                have =
                    inputs.trips
                        |> List.map
                            (\trip ->
                                inputs.expenses
                                    |> List.filter (\e -> e.tripId == trip.id)
                                    |> List.map .category
                                    |> distinctCount
                            )
                        |> List.maximum
                        |> Maybe.withDefault 0
            in
            evaluateCount have marker

        "fill-er-up" ->
            -- Dollars $1000: total fuel across all trips
            let
                have : Money.Money
                have =
                    sumWhere (\e -> e.category == Category.Fuel) inputs.expenses
            in
            evaluateDollars have "$1,000" marker

        "premium-unleaded" ->
            -- Dollars $500: fuel on a single trip
            let
                have : Money.Money
                have =
                    inputs.trips
                        |> List.map
                            (\trip ->
                                sumWhere
                                    (\e -> e.tripId == trip.id && e.category == Category.Fuel)
                                    inputs.expenses
                            )
                        |> List.foldl maxMoney Money.zero
            in
            evaluateDollars have "$500" marker

        "big-rig" ->
            -- Dollars $5000: total on a single trip
            let
                have : Money.Money
                have =
                    inputs.trips
                        |> List.map
                            (\trip ->
                                sumWhere (\e -> e.tripId == trip.id) inputs.expenses
                            )
                        |> List.foldl maxMoney Money.zero
            in
            evaluateDollars have "$5,000" marker

        "budget-what-budget" ->
            -- Flag: any trip over budget (skip zero-budget trips)
            let
                overBudget : Bool
                overBudget =
                    inputs.trips
                        |> List.any
                            (\trip ->
                                not (Money.isZero trip.budget)
                                    && (let
                                            tripTotal : Money.Money
                                            tripTotal =
                                                sumWhere (\e -> e.tripId == trip.id) inputs.expenses
                                        in
                                        Money.toCents tripTotal > Money.toCents trip.budget
                                       )
                            )
            in
            if overBudget then
                Earned { marker = marker }

            else
                Locked
                    { label = "No trip over budget yet"
                    , marker = marker
                    , progress = 0
                    }

        "souvenir-tax" ->
            -- Dollars $250: max single Misc expense >= goal
            let
                have : Money.Money
                have =
                    maxAmountWhere (\e -> e.category == Category.Misc) inputs.expenses
            in
            evaluateDollars have "$250" marker

        _ ->
            -- Unreachable with a well-formed catalog; treated as a locked Flag.
            Locked
                { label = "Unknown marker"
                , marker = marker
                , progress = 0
                }


{-| Evaluate a `Count` marker: `have` is the current count; the goal threshold
is read from the marker's `Goal` payload.
-}
evaluateCount : Int -> Marker -> MarkerState
evaluateCount have marker =
    case marker.goal of
        Count goal ->
            if have >= goal then
                Earned { marker = marker }

            else
                Locked
                    { label = String.fromInt have ++ " / " ++ String.fromInt goal
                    , marker = marker
                    , progress = min 1 (toFloat have / toFloat goal)
                    }

        _ ->
            -- Marker goal/id mismatch — locked with zero progress
            Locked { label = "0 / ?", marker = marker, progress = 0 }


{-| Evaluate a `Streak` marker: `have` is the longest streak in days; the goal
is read from the marker's `Goal` payload.
-}
evaluateStreak : Int -> Marker -> MarkerState
evaluateStreak have marker =
    case marker.goal of
        Streak goal ->
            if have >= goal then
                Earned { marker = marker }

            else
                Locked
                    { label = String.fromInt have ++ " / " ++ String.fromInt goal ++ " days"
                    , marker = marker
                    , progress = min 1 (toFloat have / toFloat goal)
                    }

        _ ->
            Locked { label = "0 / ? days", marker = marker, progress = 0 }


{-| Evaluate a `Dollars` marker: `have` is the current amount; the goal is read
from the marker's `Goal` payload. `goalLabel` is the human-readable threshold
(e.g. `"$1,000"`) for the locked label.
-}
evaluateDollars : Money.Money -> String -> Marker -> MarkerState
evaluateDollars have goalLabel marker =
    case marker.goal of
        Dollars goal ->
            if Money.toCents have >= Money.toCents goal then
                Earned { marker = marker }

            else
                Locked
                    { label = Money.format have ++ " / " ++ goalLabel
                    , marker = marker
                    , progress = min 1 (toFloat (Money.toCents have) / toFloat (Money.toCents goal))
                    }

        _ ->
            Locked { label = Money.format have ++ " / ?", marker = marker, progress = 0 }


maxMoney : Money.Money -> Money.Money -> Money.Money
maxMoney a b =
    if Money.toCents a > Money.toCents b then
        a

    else
        b



-- HELPERS


{-| Convert a `Time.Posix` to a calendar day key as an integer
`year * 10000 + month * 100 + day`, in the given zone. Used to bucket expenses
into days for streak calculation.

The epoch (1970-01-01 UTC) produces `19700101`; the next day produces `19700102`.

-}
dayKey : Time.Zone -> Time.Posix -> Int
dayKey zone posix =
    let
        year : Int
        year =
            Time.toYear zone posix

        month : Int
        month =
            monthToInt (Time.toMonth zone posix)

        day : Int
        day =
            Time.toDay zone posix
    in
    year * 10000 + month * 100 + day


monthToInt : Time.Month -> Int
monthToInt month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12


{-| Compute the longest run of consecutive integers in a sorted, deduplicated
list of day keys. Used internally by `longestStreak`.

A "consecutive" run means each element equals the previous + 1.

    longestRun [ 1, 2, 3, 5, 6 ]
    --> 3

    longestRun []
    --> 0

    longestRun [ 5 ]
    --> 1

-}
longestRun : List Int -> Int
longestRun keys =
    case keys of
        [] ->
            0

        first :: rest ->
            longestRunHelp rest first 1 1


longestRunHelp : List Int -> Int -> Int -> Int -> Int
longestRunHelp remaining prev current best =
    case remaining of
        [] ->
            max current best

        next :: rest ->
            if next == prev + 1 then
                longestRunHelp rest next (current + 1) (max best (current + 1))

            else
                longestRunHelp rest next 1 (max best 1)


{-| Compute the longest streak of consecutive calendar days (in the given zone)
covered by the provided list of `Time.Posix` timestamps. Each day need only
have one expense to count. Returns 0 for an empty list.
-}
longestStreak : Time.Zone -> List Time.Posix -> Int
longestStreak zone posixes =
    posixes
        |> List.map (dayKey zone)
        |> List.sort
        |> deduplicate
        |> longestRun


deduplicate : List Int -> List Int
deduplicate xs =
    List.foldr
        (\x acc ->
            case acc of
                head :: _ ->
                    if x == head then
                        acc

                    else
                        x :: acc

                [] ->
                    [ x ]
        )
        []
        xs


{-| Sum the `amount` field for all expenses that satisfy the given predicate.
Returns `Money.zero` for an empty list or when no expenses match.
-}
sumWhere : (ExpenseFacts -> Bool) -> List ExpenseFacts -> Money.Money
sumWhere pred expenses =
    expenses
        |> List.filter pred
        |> List.map .amount
        |> Money.sum


{-| Return the largest single `amount` among all expenses that satisfy the
given predicate. Returns `Money.zero` when no expenses match.

Unlike `sumWhere`, this does not accumulate — it finds the single maximum
value. Used to evaluate "max single expense" markers such as Souvenir Tax.

-}
maxAmountWhere : (ExpenseFacts -> Bool) -> List ExpenseFacts -> Money.Money
maxAmountWhere pred expenses =
    expenses
        |> List.filter pred
        |> List.map .amount
        |> List.foldl maxMoney Money.zero


{-| Count the number of distinct values in a list.

    distinctCount [ 1, 2, 2, 3 ]
    --> 3

    distinctCount []
    --> 0

    distinctCount [ "a", "b", "a" ]
    --> 2

-}
distinctCount : List a -> Int
distinctCount xs =
    xs
        |> List.foldl
            (\x acc ->
                if List.member x acc then
                    acc

                else
                    x :: acc
            )
            []
        |> List.length
