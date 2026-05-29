module Verify.Specs.JoinSharedTrip exposing (Input, honest, surface, requestForFixture, results)

{-| Client-render verification unit for the `/sharedtrips/join` confirmation
page (#352). Covers the branches `Pages.JoinSharedTrip.viewAuthBody` derives
from `joinSharedTripRequest`: the ready confirmation, the in-flight "Joining…"
state, and the error chip (whose text reuses `Http.SharedTripApi.joinErrorMessage`,
already unit-tested). Together with the server-side join coverage (#353), this
brings `join-sharedtrip.spec.ts` to parity for deletion.

Scope: the request-driven states. The wrong-recipient render (a client decode of
the invite token) is left to a follow-up; the server-side 403 is covered by
`sec/invite-jwt.spec.js:103`.

@docs Input, honest, surface, requestForFixture, results

-}

import Http
import Http.SharedTripApi
import RemoteData exposing (RemoteData)
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


{-| The slice this unit observes. `corrupt = True` (probe only) claims an error
on a non-error state so an invariant has a real regression to catch.
-}
type alias Input =
    { corrupt : Bool
    , request : RemoteData Http.Error Http.SharedTripApi.JoinSharedTripResponse
    }


{-| An honest input (never corrupt) — the projection the view feeds.
-}
honest : RemoteData Http.Error Http.SharedTripApi.JoinSharedTripResponse -> Input
honest request =
    { corrupt = False, request = request }


{-| Derive the join page's observable surface. Reuses
`Http.SharedTripApi.joinErrorMessage` for the error chip so the surface can't
drift from the view.
-}
surface : Input -> Contract.Surface
surface input =
    let
        accept : String
        accept =
            case input.request of
                RemoteData.Loading ->
                    "busy"

                _ ->
                    "shown"

        error : String
        error =
            if input.corrupt then
                "corrupted"

            else
                case input.request of
                    RemoteData.Failure err ->
                        Http.SharedTripApi.joinErrorMessage err

                    _ ->
                        "none"
    in
    [ ( "accept", accept ), ( "error", error ) ]


{-| Map a fixture name to its join-request state. Single source of truth for the
fixtures and the DOM-tier seeding in `Main.applyUnitSeed`.
-}
requestForFixture : String -> RemoteData Http.Error Http.SharedTripApi.JoinSharedTripResponse
requestForFixture name =
    case name of
        "loading" ->
            RemoteData.Loading

        "expired" ->
            RemoteData.Failure (Http.BadStatus 410)

        "already-member" ->
            RemoteData.Failure (Http.BadStatus 409)

        _ ->
            -- "ready" and the probe both start from NotAsked.
            RemoteData.NotAsked


{-| The pure-tier results for this unit, collected by `Verify.Registry`.
-}
results : List Core.RunResult
results =
    Runner.runUnit spec


spec : Spec.UnitSpec Input
spec =
    { fixtures =
        [ { input = honest (requestForFixture "ready"), name = "ready", probe = False }
        , { input = honest (requestForFixture "loading"), name = "loading", probe = False }
        , { input = honest (requestForFixture "expired"), name = "expired", probe = False }
        , { input = honest (requestForFixture "already-member"), name = "already-member", probe = False }
        , { input = { corrupt = True, request = RemoteData.NotAsked }, name = "probe-ready-claims-error", probe = True }
        ]
    , invariants =
        [ { name = "in-flight shows a busy accept button", check = loadingBusy }
        , { name = "ready state shows no error", check = readyNoError }
        , { name = "failure surfaces the mapped error message", check = failureMapped }
        ]
    , name = "JoinSharedTrip"
    , surface = surface
    }



-- INVARIANTS


loadingBusy : Input -> Contract.Surface -> Maybe String
loadingBusy input observed =
    if input.request /= RemoteData.Loading then
        Nothing

    else if value "accept" observed == Just "busy" then
        Nothing

    else
        Just "in-flight join did not show a busy accept button"


readyNoError : Input -> Contract.Surface -> Maybe String
readyNoError input observed =
    if input.request /= RemoteData.NotAsked then
        Nothing

    else if value "error" observed == Just "none" then
        Nothing

    else
        Just "ready state surfaced an error"


failureMapped : Input -> Contract.Surface -> Maybe String
failureMapped input observed =
    case input.request of
        RemoteData.Failure err ->
            if value "error" observed == Just (Http.SharedTripApi.joinErrorMessage err) then
                Nothing

            else
                Just "failure did not surface the mapped error message"

        _ ->
            Nothing


value : String -> Contract.Surface -> Maybe String
value key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
