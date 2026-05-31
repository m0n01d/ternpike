module Pages.Milepost exposing (viewTab)

{-| "The Milepost" — the account-wide achievement collection screen (#409).

Renders `AuthState.milepostStates` (the evaluated catalog stashed by
`Main.reconcileMileposts`) grouped by `Data.Milepost.Family`, each marker shown
via the shared `UI.Milepost.markerChip`. A progress bar at the top tracks the
earned / total fraction. A brand-new user (everything locked) gets a welcoming
empty-state prompt rather than a wall of greyed-out cards.

The page's container carries `Verify.Contract.verifyAttrs "MilepostScreen"` from
the same `Verify.Specs.MilepostScreen.surfaceFor` projection the verification
invariants read, so the DOM probe at `/verify/MilepostScreen/<fixture>` checks
exactly what renders.

@docs viewTab

-}

import Data.Milepost as Milepost
import Html exposing (Html)
import Html.Attributes
import Types exposing (AuthState, Msg)
import UI.Milepost
import UI.Rule
import Verify.Contract
import Verify.Specs.MilepostScreen


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    let
        states : List Milepost.MarkerState
        states =
            as_.milepostStates

        earned : Int
        earned =
            List.length (List.filter isEarned states)

        total : Int
        total =
            List.length states
    in
    { actions = []
    , body =
        Html.div
            (Verify.Contract.verifyAttrs "MilepostScreen" (Verify.Specs.MilepostScreen.surfaceFor states))
            [ if earned == 0 then
                viewEmptyState

              else
                Html.div []
                    (List.filterMap (viewFamilySection states) familiesInOrder)
            ]
    , hero = viewHero earned total
    }


{-| The progress hero — Playfair lede + an earned/total bar.
-}
viewHero : Int -> Int -> Html Msg
viewHero earned total =
    let
        pct : Int
        pct =
            if total == 0 then
                0

            else
                clamp 0 100 (round (toFloat earned / toFloat total * 100))
    in
    Html.div []
        [ Html.p [ Html.Attributes.class "text-sm text-muted font-body" ]
            [ Html.text "Markers you reach along the way — one for every habit, mile, and dollar logged." ]
        , Html.div [ Html.Attributes.class "mt-3" ]
            [ Html.div [ Html.Attributes.class "h-2 w-full rounded-full bg-tan/40 overflow-hidden" ]
                [ Html.div
                    -- dynamic percentage width; cannot be a static Tailwind class.
                    [ Html.Attributes.class "h-full rounded-full bg-rust"
                    , Html.Attributes.style "width" (String.fromInt pct ++ "%")
                    ]
                    []
                ]
            , Html.p [ Html.Attributes.class "mt-1.5 text-xs font-mono text-muted" ]
                [ Html.text (String.fromInt earned ++ " of " ++ String.fromInt total ++ " reached") ]
            ]
        ]


{-| The all-locked welcome. Shown when the user hasn't earned a single marker.
-}
viewEmptyState : Html Msg
viewEmptyState =
    Html.div [ Html.Attributes.class "py-10 text-center" ]
        [ Html.p [ Html.Attributes.class "font-display text-xl font-bold text-forest" ]
            [ Html.text "No markers yet" ]
        , Html.p [ Html.Attributes.class "mt-2 text-sm text-muted max-w-xs mx-auto" ]
            [ Html.text "Start logging expenses to reach your first marker. The trail fills in as you go." ]
        ]


{-| One section per family — a kicker heading plus that family's chips. Returns
`Nothing` for families with no markers (keeps `filterMap` honest as the catalog
grows).
-}
viewFamilySection : List Milepost.MarkerState -> Milepost.Family -> Maybe (Html Msg)
viewFamilySection states family =
    let
        inFamily : List Milepost.MarkerState
        inFamily =
            List.filter (\st -> stateFamily st == family) states
    in
    if List.isEmpty inFamily then
        Nothing

    else
        Just
            (Html.section [ Html.Attributes.class "mb-6" ]
                [ UI.Rule.kicker (familyLabel family)
                , Html.div [ Html.Attributes.class "flex flex-col gap-3" ]
                    (List.map UI.Milepost.markerChip inFamily)
                ]
            )


familiesInOrder : List Milepost.Family
familiesInOrder =
    [ Milepost.TrailDiscipline
    , Milepost.MileMarkers
    , Milepost.Odometer
    , Milepost.CautionSigns
    ]


familyLabel : Milepost.Family -> String
familyLabel family =
    case family of
        Milepost.CautionSigns ->
            "CAUTION SIGNS"

        Milepost.MileMarkers ->
            "MILE MARKERS"

        Milepost.Odometer ->
            "ODOMETER"

        Milepost.TrailDiscipline ->
            "TRAIL DISCIPLINE"


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
