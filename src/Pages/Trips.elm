module Pages.Trips exposing (viewTab)

import Data.Entry as Entry
import Data.Navigation exposing (Tab(..))
import Data.Trip exposing (Trip, TripField(..), TripForm)
import Data.TripId as TripId
import Data.Trips as Trips exposing (TripsState(..))
import Dict
import Helpers
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Routing
import Set
import Types exposing (AuthState, Msg(..))
import UI.BudgetBar
import UI.Button
import UI.Icons
import UI.Layout
import UI.Skeleton


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = viewActions as_
    , body = viewBody as_
    , hero = viewHero as_
    }


viewActions : AuthState -> List (Html Msg)
viewActions as_ =
    case as_.trips of
        TripsLoaded trips ->
            let
                activeTrip =
                    Trips.selectedTrip trips

                canDelete =
                    not (List.isEmpty (Trips.otherTrips trips))
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

        _ ->
            []


viewHero : AuthState -> Html Msg
viewHero as_ =
    case as_.trips of
        TripsLoading _ _ ->
            Html.div [ Html.Attributes.class "py-2" ]
                [ UI.Skeleton.row ]

        TripsFailed err ->
            Html.div [ Html.Attributes.class "py-2 text-rust text-sm" ]
                [ Html.text ("Couldn't load trips: " ++ err) ]

        NoTripsYet ->
            Html.div [ Html.Attributes.class "py-2" ]
                [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
                    [ Html.text "WELCOME" ]
                , Html.div [ Html.Attributes.class "font-display text-3xl font-black text-forest tracking-tight leading-tight" ]
                    [ Html.text "Start your first trip" ]
                , Html.p [ Html.Attributes.class "mt-2 text-sm text-muted" ]
                    [ Html.text "Create a trip below to start tracking expenses." ]
                ]

        TripsLoaded trips ->
            let
                activeTrip =
                    Trips.selectedTrip trips

                entries =
                    if Set.member (TripId.toString activeTrip.id) as_.tripLoaded then
                        Entry.resolve
                            (as_.expenses |> Dict.get (TripId.toString activeTrip.id) |> Maybe.withDefault Dict.empty |> Dict.values)
                            (Dict.values as_.amendments)
                            (Dict.values as_.voids)
                            activeTrip.id

                    else
                        []
            in
            viewTripHero activeTrip entries


viewTripHero : Trip -> List Entry.EffectiveEntry -> Html Msg
viewTripHero activeTrip entries =
    let
        totalSpent =
            List.sum (List.map .amount entries)

        hasStart =
            activeTrip.startDate /= ""

        hasEnd =
            activeTrip.endDate /= ""

        dateLine =
            if hasStart && hasEnd then
                Helpers.formatDateDisplay activeTrip.startDate
                    ++ " — "
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
                    Html.text (" · " ++ String.fromInt totalDays ++ " DAYS")

                  else
                    Html.text ""
                ]

          else
            Html.text ""
        , if activeTrip.budget > 0 then
            UI.BudgetBar.view { spent = totalSpent, budget = activeTrip.budget }

          else
            Html.text ""
        ]


viewBody : AuthState -> Html Msg
viewBody as_ =
    let
        others =
            case as_.trips of
                TripsLoaded trips ->
                    Trips.otherTrips trips

                _ ->
                    []
    in
    Html.div []
        [ if not (List.isEmpty others) then
            Html.div [ Html.Attributes.class "mb-5" ]
                (List.map (viewOtherTripRow as_.basePath) others)

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


viewOtherTripRow : String -> Trip -> Html Msg
viewOtherTripRow basePath trip =
    Html.a
        [ Html.Attributes.href (Routing.tabToPath basePath trip.id LedgerTab)
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
                [ Html.Events.onClick CloseTripForm
                , Html.Attributes.class "flex-1 bg-transparent text-muted border border-tan rounded-lg py-3 text-[15px] cursor-pointer"
                ]
                [ Html.text "Cancel" ]
            ]
        ]
