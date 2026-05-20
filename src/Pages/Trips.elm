module Pages.Trips exposing (viewTab)

import Data.Trip exposing (Trip, TripField(..), TripForm)
import Helpers
import Html exposing (Html)
import Html.Attributes
import Html.Events
import List.NonEmpty.Zipper as Zipper
import Types exposing (AuthState, ExpensesState(..), Msg(..), Tab(..))
import UI.Button
import UI.Icons
import UI.Layout
import UI.Rule


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = viewActions as_
    , body = viewBody as_
    , hero = viewHero as_
    }


viewActions : AuthState -> List (Html Msg)
viewActions as_ =
    let
        activeTrip =
            Zipper.current as_.trips

        canDelete =
            List.length (Zipper.toList as_.trips) > 1
    in
    UI.Button.iconButton
        { icon = UI.Icons.pencil "w-4 h-4"
        , onClick = OpenEditTripForm activeTrip
        , title = "Edit trip"
        }
        :: (if canDelete then
                [ UI.Button.iconButton
                    { icon = UI.Icons.trash "w-4 h-4"
                    , onClick = ConfirmDeleteTrip activeTrip
                    , title = "Delete trip"
                    }
                ]

            else
                []
           )


viewHero : AuthState -> Html Msg
viewHero as_ =
    let
        activeTrip =
            Zipper.current as_.trips

        totalSpent =
            case as_.expensesState of
                Loaded entries ->
                    List.sum (List.map .amount entries)

                _ ->
                    0

        hasStart =
            activeTrip.startDate /= ""

        hasEnd =
            activeTrip.endDate /= ""

        dateLine =
            if hasStart && hasEnd then
                Helpers.formatDateDisplay activeTrip.startDate
                    ++ " \u{2014} "
                    ++ Helpers.formatDateDisplay activeTrip.endDate

            else if hasStart then
                Helpers.formatDateDisplay activeTrip.startDate

            else
                ""

        totalDays =
            if hasStart && hasEnd then
                Basics.max 1
                    (Helpers.isoToDayCount activeTrip.endDate
                        - Helpers.isoToDayCount activeTrip.startDate
                        + 1
                    )

            else
                0
    in
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "ACTIVE TRIP" ]
        , Html.div [ Html.Attributes.class "font-display text-4xl font-black text-forest tracking-tight leading-tight" ]
            [ Html.text activeTrip.name ]
        , if activeTrip.description /= "" then
            Html.p [ Html.Attributes.class "mt-2 text-sm text-muted" ]
                [ Html.text activeTrip.description ]

          else
            Html.text ""
        , if dateLine /= "" then
            Html.div [ Html.Attributes.class "mt-2 flex items-center gap-2 text-xs font-mono tracking-wide text-muted" ]
                [ Html.text dateLine
                , if totalDays > 0 then
                    Html.text (" \u{00B7} " ++ String.fromInt totalDays ++ " DAYS")

                  else
                    Html.text ""
                ]

          else
            Html.text ""
        , if activeTrip.budget > 0 then
            viewBudgetBar totalSpent activeTrip.budget

          else
            Html.text ""
        ]


viewBudgetBar : Float -> Float -> Html Msg
viewBudgetBar totalSpent budget =
    let
        pct =
            Basics.min 1.0 (totalSpent / budget)

        pctInt =
            round (pct * 100)

        barColor =
            if pct >= 1.0 then
                "h-full bg-danger transition-all duration-500"

            else
                "h-full bg-rust transition-all duration-500"
    in
    Html.div []
        [ UI.Rule.dashedRule
        , Html.div [ Html.Attributes.class "h-2 bg-cream-deep rounded-full overflow-hidden" ]
            [ Html.div
                [ Html.Attributes.class barColor

                -- dynamic percentage width; cannot be expressed as a static Tailwind class
                , Html.Attributes.style "width" (String.fromInt pctInt ++ "%")
                ]
                []
            ]
        , Html.div [ Html.Attributes.class "mt-2 flex justify-between text-xs font-mono text-moss" ]
            [ Html.text ("$" ++ String.fromInt (round totalSpent) ++ " spent")
            , Html.text ("$" ++ String.fromInt (round budget) ++ " budget")
            ]
        ]


viewBody : AuthState -> Html Msg
viewBody as_ =
    let
        activeTrip =
            Zipper.current as_.trips

        allTrips =
            Zipper.toList as_.trips

        otherTrips =
            List.filter (\t -> t.id /= activeTrip.id) allTrips
    in
    Html.div []
        [ if not (List.isEmpty otherTrips) then
            Html.div [ Html.Attributes.class "mb-5" ]
                (List.map viewOtherTripRow otherTrips)

          else
            Html.text ""
        , case as_.tripForm of
            Nothing ->
                Html.button
                    [ Html.Events.onClick OpenNewTripForm
                    , Html.Attributes.class "w-full bg-transparent border border-dashed border-tan rounded-xl py-3.5 text-muted text-[15px] cursor-pointer flex items-center justify-center gap-2 hover:border-moss hover:text-forest"
                    ]
                    [ UI.Icons.plus "w-4 h-4"
                    , Html.text "New trip"
                    ]

            Just form ->
                viewTripForm form
        ]


viewOtherTripRow : Trip -> Html Msg
viewOtherTripRow trip =
    Html.button
        [ Html.Events.onClick (SelectTrip trip.id)
        , Html.Attributes.class "w-full bg-cream border border-tan rounded-xl px-4 py-3.5 mb-2 flex justify-between items-center cursor-pointer text-ink hover:shadow-card-hover transition-shadow"
        ]
        [ Html.div [ Html.Attributes.class "text-left" ]
            [ Html.p [ Html.Attributes.class "text-[15px] font-semibold mb-0.5" ]
                [ Html.text trip.name ]
            , if trip.startDate /= "" then
                Html.p [ Html.Attributes.class "text-[11px] text-moss font-mono" ]
                    [ Html.text (Helpers.formatDateDisplay trip.startDate) ]

              else
                Html.text ""
            ]
        , Html.span [ Html.Attributes.class "text-muted" ]
            [ UI.Icons.chevronRight "w-4 h-4" ]
        ]


viewTripForm : TripForm -> Html Msg
viewTripForm form =
    Html.div [ Html.Attributes.class "bg-cream border border-tan rounded-xl p-4" ]
        [ Html.p [ Html.Attributes.class "text-[15px] font-bold text-rust font-display mb-4" ]
            [ Html.text
                (if form.editing == Nothing then
                    "New Trip"

                 else
                    "Edit Trip"
                )
            ]
        , if not (List.isEmpty form.errors) then
            Html.div [ Html.Attributes.class "bg-rust-tint border border-rust rounded-lg p-2.5 mb-3" ]
                (List.map
                    (\e -> Html.p [ Html.Attributes.class "text-sm text-rust" ] [ Html.text e ])
                    form.errors
                )

          else
            Html.text ""
        , UI.Layout.formField "TRIP NAME"
            (Html.input
                [ Html.Attributes.type_ "text"
                , Html.Attributes.value form.name
                , Html.Events.onInput (TripFieldChanged TripName)
                , Html.Attributes.placeholder "Alaska 2026"
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "DESCRIPTION"
            (Html.input
                [ Html.Attributes.type_ "text"
                , Html.Attributes.value form.description
                , Html.Events.onInput (TripFieldChanged TripDescription)
                , Html.Attributes.placeholder "Optional"
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "START DATE"
            (Html.input
                [ Html.Attributes.type_ "date"
                , Html.Attributes.value form.startDate
                , Html.Events.onInput (TripFieldChanged TripStartDate)
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "END DATE"
            (Html.input
                [ Html.Attributes.type_ "date"
                , Html.Attributes.value form.endDate
                , Html.Events.onInput (TripFieldChanged TripEndDate)
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "BUDGET ($)"
            (Html.input
                [ Html.Attributes.type_ "number"
                , Html.Attributes.value form.budget
                , Html.Events.onInput (TripFieldChanged TripBudget)
                , Html.Attributes.placeholder "0 = no budget"
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "COVER PHOTO URL"
            (Html.input
                [ Html.Attributes.type_ "url"
                , Html.Attributes.value form.coverPhotoUrl
                , Html.Events.onInput (TripFieldChanged TripCoverPhoto)
                , Html.Attributes.placeholder "https://..."
                , UI.Layout.textInputStyle
                ]
                []
            )
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
