module Pages.Trips exposing (viewTripsTab)

import Data.Trip exposing (TripField(..), TripForm)
import Helpers exposing (formatAmount)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import List.NonEmpty.Zipper as Zipper
import Types exposing (..)
import UI.Layout exposing (formField, sectionHead, textInputStyle)


viewTripsTab : AuthState -> Html Msg
viewTripsTab as_ =
    let
        activeTrip =
            Zipper.current as_.trips

        allTrips =
            Zipper.toList as_.trips

        otherTrips =
            List.filter (\t -> t.id /= activeTrip.id) allTrips

        totalSpent =
            case as_.expensesState of
                Loaded entries -> List.sum (List.map .amount entries)
                _              -> 0
    in
    div [ style "padding" "20px" ]
        [ h2 [ sectionHead ] [ text "TRIPS" ]
        , div
            [ style "background" "#161918"
            , style "border" "1px solid #2a3230"
            , style "border-radius" "12px"
            , style "padding" "16px"
            , style "margin-bottom" "20px"
            ]
            [ div [ style "display" "flex", style "justify-content" "space-between", style "align-items" "flex-start" ]
                [ div []
                    [ p
                        [ style "font-size" "18px"
                        , style "font-weight" "700"
                        , style "color" "#e8a020"
                        , style "margin-bottom" "4px"
                        ]
                        [ text activeTrip.name ]
                    , if activeTrip.description /= "" then
                        p [ style "font-size" "13px", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                            [ text activeTrip.description ]
                      else
                        text ""
                    , if activeTrip.startDate /= "" then
                        p [ style "font-size" "12px", style "color" "#4a5a50" ]
                            [ text (activeTrip.startDate ++ (if activeTrip.endDate /= "" then " → " ++ activeTrip.endDate else "")) ]
                      else
                        text ""
                    ]
                , div [ style "display" "flex", style "gap" "8px" ]
                    [ button
                        [ onClick (OpenEditTripForm activeTrip)
                        , style "background" "none"
                        , style "border" "1px solid #2a3230"
                        , style "color" "#7a8a80"
                        , style "border-radius" "6px"
                        , style "padding" "6px 10px"
                        , style "font-size" "12px"
                        , style "cursor" "pointer"
                        ]
                        [ text "Edit" ]
                    , if List.length (Zipper.toList as_.trips) > 1 then
                        button
                            [ onClick (ConfirmDeleteTrip activeTrip)
                            , style "background" "none"
                            , style "border" "1px solid #5a2020"
                            , style "color" "#e05050"
                            , style "border-radius" "6px"
                            , style "padding" "6px 10px"
                            , style "font-size" "12px"
                            , style "cursor" "pointer"
                            ]
                            [ text "Delete" ]
                      else
                        text ""
                    ]
                ]
            , if activeTrip.budget > 0 then
                let
                    pct =
                        Basics.min 1.0 (totalSpent / activeTrip.budget)
                in
                div [ style "margin-top" "12px" ]
                    [ div [ style "display" "flex", style "justify-content" "space-between", style "font-size" "12px", style "color" "#7a8a80", style "margin-bottom" "4px" ]
                        [ text ("$" ++ String.fromInt (round totalSpent) ++ " spent")
                        , text ("Budget: $" ++ String.fromInt (round activeTrip.budget))
                        ]
                    , div [ style "background" "#2a3230", style "border-radius" "4px", style "height" "6px" ]
                        [ div
                            [ style "background" (if pct >= 1.0 then "#e85030" else "#e8a020")
                            , style "border-radius" "4px"
                            , style "height" "6px"
                            , style "width" (String.fromFloat (pct * 100) ++ "%")
                            ]
                            []
                        ]
                    ]
              else
                text ""
            ]
        , if not (List.isEmpty otherTrips) then
            div [ style "margin-bottom" "20px" ]
                (List.map
                    (\trip ->
                        button
                            [ onClick (SelectTrip trip.id)
                            , style "width" "100%"
                            , style "background" "#161918"
                            , style "border" "1px solid #2a3230"
                            , style "border-radius" "10px"
                            , style "padding" "14px 16px"
                            , style "margin-bottom" "8px"
                            , style "display" "flex"
                            , style "justify-content" "space-between"
                            , style "align-items" "center"
                            , style "cursor" "pointer"
                            , style "color" "#c8d0c8"
                            , style "font-family" "inherit"
                            ]
                            [ div [ style "text-align" "left" ]
                                [ p [ style "font-size" "15px", style "font-weight" "600", style "margin-bottom" "2px" ] [ text trip.name ]
                                , if trip.startDate /= "" then
                                    p [ style "font-size" "11px", style "color" "#4a5a50" ] [ text trip.startDate ]
                                  else
                                    text ""
                                ]
                            , span [ style "color" "#7a8a80", style "font-size" "16px" ] [ text "›" ]
                            ]
                    )
                    otherTrips
                )
          else
            text ""
        , case as_.tripForm of
            Nothing ->
                button
                    [ onClick OpenNewTripForm
                    , style "width" "100%"
                    , style "background" "none"
                    , style "border" "1px dashed #3a4240"
                    , style "border-radius" "10px"
                    , style "padding" "14px"
                    , style "color" "#7a8a80"
                    , style "font-size" "15px"
                    , style "cursor" "pointer"
                    , style "font-family" "inherit"
                    ]
                    [ text "+ New Trip" ]

            Just form ->
                viewTripForm form
        ]


viewTripForm : TripForm -> Html Msg
viewTripForm form =
    div
        [ style "background" "#161918"
        , style "border" "1px solid #2a3230"
        , style "border-radius" "12px"
        , style "padding" "16px"
        ]
        [ p [ style "font-size" "15px", style "font-weight" "700", style "color" "#e8a020", style "margin-bottom" "16px" ]
            [ text (if form.editing == Nothing then "New Trip" else "Edit Trip") ]
        , if not (List.isEmpty form.errors) then
            div [ style "background" "#2a1510", style "border" "1px solid #e85030", style "border-radius" "8px", style "padding" "10px", style "margin-bottom" "12px" ]
                (List.map (\e -> p [ style "font-size" "13px", style "color" "#e8a020" ] [ text e ]) form.errors)
          else
            text ""
        , formField "TRIP NAME"
            (input [ type_ "text", value form.name, onInput (TripFieldChanged TripName), placeholder "Alaska 2026", textInputStyle ] [])
        , formField "DESCRIPTION"
            (input [ type_ "text", value form.description, onInput (TripFieldChanged TripDescription), placeholder "Optional", textInputStyle ] [])
        , formField "START DATE"
            (input [ type_ "date", value form.startDate, onInput (TripFieldChanged TripStartDate), textInputStyle ] [])
        , formField "END DATE"
            (input [ type_ "date", value form.endDate, onInput (TripFieldChanged TripEndDate), textInputStyle ] [])
        , formField "BUDGET ($)"
            (input [ type_ "number", value form.budget, onInput (TripFieldChanged TripBudget), placeholder "0 = no budget", textInputStyle ] [])
        , formField "COVER PHOTO URL"
            (input [ type_ "url", value form.coverPhotoUrl, onInput (TripFieldChanged TripCoverPhoto), placeholder "https://...", textInputStyle ] [])
        , div [ style "display" "flex", style "gap" "10px", style "margin-top" "16px" ]
            [ button
                [ onClick SaveTripForm
                , style "flex" "1"
                , style "background" "#e8a020"
                , style "color" "#0d0f0e"
                , style "border" "none"
                , style "border-radius" "8px"
                , style "padding" "12px"
                , style "font-size" "15px"
                , style "font-weight" "700"
                , style "cursor" "pointer"
                ]
                [ text "Save" ]
            , button
                [ onClick (TabChanged TripsTab)
                , style "flex" "1"
                , style "background" "none"
                , style "color" "#7a8a80"
                , style "border" "1px solid #2a3230"
                , style "border-radius" "8px"
                , style "padding" "12px"
                , style "font-size" "15px"
                , style "cursor" "pointer"
                ]
                [ text "Cancel" ]
            ]
        ]
