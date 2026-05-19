module Pages.Trips exposing (viewTripsTab)

import Data.Trip exposing (TripField(..), TripForm)
import Helpers exposing (formatAmount)
import Html exposing (Html)
import Html.Attributes
import Html.Events
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
    Html.div [ Html.Attributes.class "p-5" ]
        [ Html.h2 [ sectionHead ] [ Html.text "TRIPS" ]
        , Html.div [ Html.Attributes.class "bg-cream border border-tan rounded-xl p-4 mb-5" ]
            [ Html.div [ Html.Attributes.class "flex justify-between items-start" ]
                [ Html.div []
                    [ Html.p [ Html.Attributes.class "text-lg font-bold text-rust font-display mb-1" ]
                        [ Html.text activeTrip.name ]
                    , if activeTrip.description /= "" then
                        Html.p [ Html.Attributes.class "text-sm text-muted mb-2" ]
                            [ Html.text activeTrip.description ]
                      else
                        Html.text ""
                    , if activeTrip.startDate /= "" then
                        Html.p [ Html.Attributes.class "text-xs text-moss" ]
                            [ Html.text (activeTrip.startDate ++ (if activeTrip.endDate /= "" then " → " ++ activeTrip.endDate else "")) ]
                      else
                        Html.text ""
                    ]
                , Html.div [ Html.Attributes.class "flex gap-2" ]
                    [ Html.button
                        [ Html.Events.onClick (OpenEditTripForm activeTrip)
                        , Html.Attributes.class "bg-transparent border border-tan text-muted rounded-md px-2.5 py-1.5 text-xs cursor-pointer"
                        ]
                        [ Html.text "Edit" ]
                    , if List.length (Zipper.toList as_.trips) > 1 then
                        Html.button
                            [ Html.Events.onClick (ConfirmDeleteTrip activeTrip)
                            , Html.Attributes.class "bg-transparent border border-rust/50 text-rust rounded-md px-2.5 py-1.5 text-xs cursor-pointer"
                            ]
                            [ Html.text "Delete" ]
                      else
                        Html.text ""
                    ]
                ]
            , if activeTrip.budget > 0 then
                let
                    pct =
                        Basics.min 1.0 (totalSpent / activeTrip.budget)
                in
                Html.div [ Html.Attributes.class "mt-3" ]
                    [ Html.div [ Html.Attributes.class "flex justify-between text-xs text-muted mb-1" ]
                        [ Html.text ("$" ++ String.fromInt (round totalSpent) ++ " spent")
                        , Html.text ("Budget: $" ++ String.fromInt (round activeTrip.budget))
                        ]
                    , Html.div [ Html.Attributes.class "bg-tan rounded h-1.5" ]
                        [ Html.div
                            [ Html.Attributes.class ("rounded h-1.5 " ++ (if pct >= 1.0 then "bg-[#a83020]" else "bg-rust"))
                            -- dynamic percentage; cannot express as a Tailwind class
                            , Html.Attributes.style "width" (String.fromFloat (pct * 100) ++ "%")
                            ]
                            []
                        ]
                    ]
              else
                Html.text ""
            ]
        , if not (List.isEmpty otherTrips) then
            Html.div [ Html.Attributes.class "mb-5" ]
                (List.map
                    (\trip ->
                        Html.button
                            [ Html.Events.onClick (SelectTrip trip.id)
                            , Html.Attributes.class "w-full bg-cream border border-tan rounded-xl px-4 py-3.5 mb-2 flex justify-between items-center cursor-pointer text-ink"
                            ]
                            [ Html.div [ Html.Attributes.class "text-left" ]
                                [ Html.p [ Html.Attributes.class "text-[15px] font-semibold mb-0.5" ] [ Html.text trip.name ]
                                , if trip.startDate /= "" then
                                    Html.p [ Html.Attributes.class "text-[11px] text-moss" ] [ Html.text trip.startDate ]
                                  else
                                    Html.text ""
                                ]
                            , Html.span [ Html.Attributes.class "text-muted text-base" ] [ Html.text "›" ]
                            ]
                    )
                    otherTrips
                )
          else
            Html.text ""
        , case as_.tripForm of
            Nothing ->
                Html.button
                    [ Html.Events.onClick OpenNewTripForm
                    , Html.Attributes.class "w-full bg-transparent border border-dashed border-tan rounded-xl py-3.5 text-muted text-[15px] cursor-pointer"
                    ]
                    [ Html.text "+ New Trip" ]

            Just form ->
                viewTripForm form
        ]


viewTripForm : TripForm -> Html Msg
viewTripForm form =
    Html.div [ Html.Attributes.class "bg-cream border border-tan rounded-xl p-4" ]
        [ Html.p [ Html.Attributes.class "text-[15px] font-bold text-rust font-display mb-4" ]
            [ Html.text (if form.editing == Nothing then "New Trip" else "Edit Trip") ]
        , if not (List.isEmpty form.errors) then
            Html.div [ Html.Attributes.class "bg-[#fdf0ea] border border-rust rounded-lg p-2.5 mb-3" ]
                (List.map (\e -> Html.p [ Html.Attributes.class "text-sm text-rust" ] [ Html.text e ]) form.errors)
          else
            Html.text ""
        , formField "TRIP NAME"
            (Html.input [ Html.Attributes.type_ "text", Html.Attributes.value form.name, Html.Events.onInput (TripFieldChanged TripName), Html.Attributes.placeholder "Alaska 2026", textInputStyle ] [])
        , formField "DESCRIPTION"
            (Html.input [ Html.Attributes.type_ "text", Html.Attributes.value form.description, Html.Events.onInput (TripFieldChanged TripDescription), Html.Attributes.placeholder "Optional", textInputStyle ] [])
        , formField "START DATE"
            (Html.input [ Html.Attributes.type_ "date", Html.Attributes.value form.startDate, Html.Events.onInput (TripFieldChanged TripStartDate), textInputStyle ] [])
        , formField "END DATE"
            (Html.input [ Html.Attributes.type_ "date", Html.Attributes.value form.endDate, Html.Events.onInput (TripFieldChanged TripEndDate), textInputStyle ] [])
        , formField "BUDGET ($)"
            (Html.input [ Html.Attributes.type_ "number", Html.Attributes.value form.budget, Html.Events.onInput (TripFieldChanged TripBudget), Html.Attributes.placeholder "0 = no budget", textInputStyle ] [])
        , formField "COVER PHOTO URL"
            (Html.input [ Html.Attributes.type_ "url", Html.Attributes.value form.coverPhotoUrl, Html.Events.onInput (TripFieldChanged TripCoverPhoto), Html.Attributes.placeholder "https://...", textInputStyle ] [])
        , Html.div [ Html.Attributes.class "flex gap-2.5 mt-4" ]
            [ Html.button
                [ Html.Events.onClick SaveTripForm
                , Html.Attributes.class "flex-1 bg-rust text-parchment border-none rounded-lg py-3 text-[15px] font-bold cursor-pointer"
                ]
                [ Html.text "Save" ]
            , Html.button
                [ Html.Events.onClick (TabChanged TripsTab)
                , Html.Attributes.class "flex-1 bg-transparent text-muted border border-tan rounded-lg py-3 text-[15px] cursor-pointer"
                ]
                [ Html.text "Cancel" ]
            ]
        ]
