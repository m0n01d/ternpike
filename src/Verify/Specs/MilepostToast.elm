module Verify.Specs.MilepostToast exposing (results)

{-| Verification unit for the milepost earn-toast queue (#410).

Exercises `UI.MilepostToast.next` — the pure head-of-queue decision that both
the plaque view and this surface share — over an empty queue, a single-marker
queue, and a many-marker queue, plus an adversarial probe.

The observable surface is "which marker (if any) is being celebrated, and how
many remain queued." Invariants pin the contract the view relies on: an empty
queue shows nothing, a non-empty queue celebrates exactly its head, and the
celebrated marker is the first one enqueued (FIFO order).

Pure-tier only (like `Verify.Specs.Milepost`): no DOM seeding, no `Main` wiring
— the decision is a function of the queue alone.

@docs results

-}

import Data.Milepost as Milepost
import UI.MilepostToast as MilepostToast
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


{-| The input slice for this unit: the earn-toast queue. `corrupt = True` makes
the surface lie (claim nothing is showing even when the queue is non-empty), so
the probe fixture trips the invariants.
-}
type alias Input =
    { corrupt : Bool
    , queue : List Milepost.Marker
    }


{-| The first N markers from the live catalog, used to build the fixtures.
Pulling from `catalog` keeps the fixtures honest against the real markers
without hard-coding ids.
-}
sampleMarkers : Int -> List Milepost.Marker
sampleMarkers n =
    List.take n Milepost.catalog


{-| Derive the toast's observable surface. Reuses `MilepostToast.next` for the
branch decision; `corrupt` blanks the showing-marker key so the probe has a real
regression to catch.
-}
surface : Input -> Contract.Surface
surface input =
    let
        showing : String
        showing =
            case MilepostToast.next input.queue of
                Just marker ->
                    if input.corrupt then
                        -- A regression: claim nothing is celebrating even though
                        -- the queue is non-empty.
                        "none"

                    else
                        marker.id

                Nothing ->
                    "none"
    in
    [ ( "showing", showing )
    , ( "queued", String.fromInt (List.length input.queue) )
    ]


results : List Core.RunResult
results =
    Runner.runUnit spec


spec : Spec.UnitSpec Input
spec =
    { fixtures =
        [ { input = { corrupt = False, queue = [] }, name = "empty", probe = False }
        , { input = { corrupt = False, queue = sampleMarkers 1 }, name = "one-queued", probe = False }
        , { input = { corrupt = False, queue = sampleMarkers 3 }, name = "many-queued", probe = False }
        , { input = { corrupt = True, queue = sampleMarkers 2 }, name = "probe-hidden-with-queue", probe = True }
        ]
    , invariants =
        [ { name = "empty queue celebrates nothing", check = emptyShowsNothing }
        , { name = "non-empty queue celebrates its head", check = nonEmptyShowsHead }
        ]
    , name = "MilepostToast"
    , surface = surface
    }



-- INVARIANTS


emptyShowsNothing : Input -> Contract.Surface -> Maybe String
emptyShowsNothing input observed =
    if not (List.isEmpty input.queue) then
        Nothing

    else if value "showing" observed == Just "none" then
        Nothing

    else
        Just "empty queue still celebrated a marker"


nonEmptyShowsHead : Input -> Contract.Surface -> Maybe String
nonEmptyShowsHead input observed =
    case List.head input.queue of
        Nothing ->
            Nothing

        Just head ->
            if value "showing" observed == Just head.id then
                Nothing

            else
                Just "non-empty queue did not celebrate its head marker"


value : String -> Contract.Surface -> Maybe String
value key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
