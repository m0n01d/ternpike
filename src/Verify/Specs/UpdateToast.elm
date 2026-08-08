module Verify.Specs.UpdateToast exposing (Input, honest, surface, inputForFixture, results)

{-| Verification unit for the "New version available" update bar (#477).

Covers every branch of `UI.Layout.viewUpdateToast` plus the one interaction it
has with the ordinary toast: the two are both `fixed` bottom-anchored bars, and
if they ever share an offset the persistent update bar hides every ordinary
toast ("Link copied", share errors, ~10 `toastFor` sites) for the rest of the
session. Both the view and this surface read the slot decision from
`Data.SwUpdate.isShowing`, so neither can re-derive it independently.

`corrupt = True` models exactly that regression — the ordinary toast failing to
shift up while the update bar is on screen.

@docs Input, honest, surface, inputForFixture, results

-}

import Data.SwUpdate as SwUpdate
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


{-| The slice this unit observes: the update lifecycle state plus whether an
ordinary toast is also on screen. `corrupt = True` pins the ordinary toast to
the update bar's slot — only the probe sets it.
-}
type alias Input =
    { corrupt : Bool
    , swUpdate : SwUpdate.UpdateState
    , toastPresent : Bool
    }


{-| An honest input (never corrupt) — the projection the view + DOM tier feed.
-}
honest : { swUpdate : SwUpdate.UpdateState, toastPresent : Bool } -> Input
honest fields =
    { corrupt = False
    , swUpdate = fields.swUpdate
    , toastPresent = fields.toastPresent
    }


{-| Derive the update bar's observable surface.

`Html.Extra.nothing` emits no element, so absence is encoded as a surface
_value_ (`reload = "absent"`) on an always-rendered wrapper rather than by
omitting the host element — otherwise `/verify/UpdateToast/hidden` would never
resolve its selector and the DOM tier would hang to timeout instead of failing.

-}
surface : Input -> Contract.Surface
surface input =
    let
        barSlot : String
        barSlot =
            if SwUpdate.isShowing input.swUpdate then
                "lower"

            else
                "absent"

        toastSlot : String
        toastSlot =
            if not input.toastPresent then
                "absent"

            else if input.corrupt then
                -- A regression: the ordinary toast never shifts up, so the
                -- persistent update bar buries it.
                "lower"

            else if SwUpdate.isShowing input.swUpdate then
                "upper"

            else
                "lower"
    in
    [ ( "reload", reloadFor input.swUpdate )
    , ( "bar-slot", barSlot )
    , ( "toast-slot", toastSlot )
    ]


{-| Map a fixture name to its input. Single source of truth for the fixtures
_and_ the DOM-tier seeding in `Main.applyUnitSeed`.
-}
inputForFixture : String -> Input
inputForFixture name =
    case name of
        "waiting" ->
            honest { swUpdate = SwUpdate.UpdateWaiting, toastPresent = False }

        "applying" ->
            honest { swUpdate = SwUpdate.Applying, toastPresent = False }

        "toast-both" ->
            honest { swUpdate = SwUpdate.UpdateWaiting, toastPresent = True }

        "probe-shared-slot" ->
            { corrupt = True, swUpdate = SwUpdate.UpdateWaiting, toastPresent = True }

        _ ->
            -- "hidden" and any unknown fixture: nothing to install.
            honest { swUpdate = SwUpdate.NoUpdate, toastPresent = False }


{-| The pure-tier results for this unit, collected by `Verify.Registry`.
-}
results : List Core.RunResult
results =
    Runner.runUnit spec


spec : Spec.UnitSpec Input
spec =
    { fixtures =
        List.map
            (\name -> { input = inputForFixture name, name = name, probe = String.startsWith "probe" name })
            fixtureNames
    , invariants =
        [ { name = "Reload is offered exactly when an update is waiting", check = reloadWhenWaiting }
        , { name = "Reload is busy exactly while applying", check = busyWhenApplying }
        , { name = "the update bar and the ordinary toast never share a slot", check = slotsAreDistinct }
        ]
    , name = "UpdateToast"
    , surface = surface
    }


fixtureNames : List String
fixtureNames =
    [ "hidden", "waiting", "applying", "toast-both", "probe-shared-slot" ]



-- INVARIANTS


reloadWhenWaiting : Input -> Contract.Surface -> Maybe String
reloadWhenWaiting input observed =
    let
        offered : Bool
        offered =
            value "reload" observed == Just "ready"
    in
    if offered == (input.swUpdate == SwUpdate.UpdateWaiting) then
        Nothing

    else if offered then
        Just "a tappable Reload rendered with no worker waiting"

    else
        Just "a waiting worker did not offer Reload"


busyWhenApplying : Input -> Contract.Surface -> Maybe String
busyWhenApplying input observed =
    let
        busy : Bool
        busy =
            value "reload" observed == Just "busy"
    in
    if busy == (input.swUpdate == SwUpdate.Applying) then
        Nothing

    else if busy then
        Just "Reload rendered busy while no update was being applied"

    else
        Just "an in-flight update left Reload live and re-tappable"


slotsAreDistinct : Input -> Contract.Surface -> Maybe String
slotsAreDistinct _ observed =
    case ( value "bar-slot" observed, value "toast-slot" observed ) of
        ( Just bar, Just toast ) ->
            if bar == "absent" || toast == "absent" || bar /= toast then
                Nothing

            else
                Just ("both bars occupy the " ++ bar ++ " slot — the ordinary toast is buried")

        _ ->
            Just "the surface did not report both slots"



-- SURFACE HELPERS


reloadFor : SwUpdate.UpdateState -> String
reloadFor state =
    case state of
        SwUpdate.Applying ->
            "busy"

        SwUpdate.NoUpdate ->
            "absent"

        SwUpdate.UpdateWaiting ->
            "ready"


value : String -> Contract.Surface -> Maybe String
value key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
