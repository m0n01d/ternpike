module Pages.Trips exposing (viewTab)

import Data.Entry as Entry
import Data.Flock exposing (Flock)
import Data.Flocks
import Data.Navigation exposing (Tab(..))
import Data.Trip as Trip exposing (Trip, TripField(..), TripForm, TripTarget)
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
import UI.Avatar
import UI.BudgetBar
import UI.Button
import UI.FlockBadge
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
            viewTripHero (flockForTrip as_ activeTrip) activeTrip entries


{-| The flock a trip belongs to, if any. `Nothing` for personal trips
or for flock trips whose meta hasn't synced yet (rare; the trip-card
falls back to the personal layout in that case).
-}
flockForTrip : AuthState -> Trip -> Maybe Flock
flockForTrip as_ trip =
    trip.flockId
        |> Maybe.andThen (\fid -> Data.Flocks.get fid as_.flocks)


viewTripHero : Maybe Flock -> Trip -> List Entry.EffectiveEntry -> Html Msg
viewTripHero maybeFlock activeTrip entries =
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
        [ Html.div [ Html.Attributes.class "mb-1 flex items-center gap-2" ]
            [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss" ]
                [ Html.text "ACTIVE TRIP" ]
            , case maybeFlock of
                Just flock ->
                    UI.FlockBadge.view flock

                Nothing ->
                    Html.text ""
            ]
        , Html.div [ Html.Attributes.class "font-display text-4xl font-black text-forest tracking-tight leading-tight" ]
            [ Html.text activeTrip.name ]
        , if activeTrip.description /= "" then
            Html.p [ Html.Attributes.class "mt-2 text-sm text-muted" ]
                [ Html.text activeTrip.description ]

          else
            Html.text ""
        , Html.div [ Html.Attributes.class "mt-2 flex items-center gap-3 text-xs font-mono tracking-wide text-muted" ]
            [ if dateLine /= "" then
                Html.span [ Html.Attributes.class "flex items-center gap-2" ]
                    [ Html.text dateLine
                    , if totalDays > 0 then
                        Html.text ("· " ++ String.fromInt totalDays ++ " DAYS")

                      else
                        Html.text ""
                    ]

              else
                Html.text ""
            , case maybeFlock of
                Just flock ->
                    UI.Avatar.viewStack (Data.Flock.members flock)

                Nothing ->
                    Html.text ""
            ]
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
                (List.map (viewOtherTripRow as_) others)

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
                viewTripForm as_ form
        ]


viewOtherTripRow : AuthState -> Trip -> Html Msg
viewOtherTripRow as_ trip =
    let
        maybeFlock =
            flockForTrip as_ trip
    in
    Html.a
        [ Html.Attributes.href (Routing.tabToPath as_.basePath trip.id LedgerTab)
        , Html.Attributes.class "w-full bg-cream border border-tan rounded-xl px-4 py-3.5 mb-2 flex justify-between items-center cursor-pointer text-ink hover:shadow-card-hover transition-shadow"
        ]
        [ Html.div [ Html.Attributes.class "text-left min-w-0 flex-1" ]
            [ case maybeFlock of
                Just flock ->
                    Html.div [ Html.Attributes.class "mb-1" ]
                        [ UI.FlockBadge.view flock ]

                Nothing ->
                    Html.text ""
            , Html.p [ Html.Attributes.class "text-[15px] font-semibold mb-0.5 truncate" ]
                [ Html.text trip.name ]
            , Html.div [ Html.Attributes.class "flex items-center gap-2" ]
                [ if trip.startDate /= "" then
                    Html.p [ Html.Attributes.class "text-[11px] text-moss font-mono" ]
                        [ Html.text (Helpers.formatDateDisplay trip.startDate) ]

                  else
                    Html.text ""
                , case maybeFlock of
                    Just flock ->
                        UI.Avatar.viewStack (Data.Flock.members flock)

                    Nothing ->
                        Html.text ""
                ]
            ]
        , Html.span [ Html.Attributes.class "text-muted shrink-0 ml-2" ]
            [ UI.Icons.chevronRight "w-4 h-4" ]
        ]


viewTripForm : AuthState -> TripForm -> Html Msg
viewTripForm as_ form =
    let
        ownedFlocks =
            Data.Flocks.ownedBy as_.currentUser as_.flocks

        isNew =
            form.editing == Nothing
    in
    Html.div [ Html.Attributes.class "bg-cream border border-tan rounded-xl p-4" ]
        [ Html.p [ Html.Attributes.class "text-[15px] font-bold text-rust font-display mb-4" ]
            [ Html.text
                (if isNew then
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
        , if isNew && not (List.isEmpty ownedFlocks) then
            viewTargetPicker form.target ownedFlocks

          else
            Html.text ""
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


{-| Segmented control that asks "where does this trip live?" — Personal
or one of the user-owned flocks. Only shown on the create path with
at least one owned flock; the spec is to collapse the single-option
case to the implicit Personal default so the user never sees a
segmented control with one tile.
-}
viewTargetPicker : TripTarget -> List Flock -> Html Msg
viewTargetPicker selected ownedFlocks =
    let
        personalTile =
            viewTargetTile
                { active = selected == Trip.Personal
                , label = "Personal"
                , sub = "JUST YOU"
                , onSelect = TripTargetSelected Trip.Personal
                }

        flockTiles =
            List.map
                (\flock ->
                    viewTargetTile
                        { active = selected == Trip.InFlock flock.id
                        , label = flock.name
                        , sub = flockTileSub flock
                        , onSelect = TripTargetSelected (Trip.InFlock flock.id)
                        }
                )
                ownedFlocks
    in
    UI.Layout.formField "WHERE DOES THIS TRIP LIVE?"
        (Html.div []
            [ Html.div [ Html.Attributes.class "flex gap-2 flex-wrap" ]
                (personalTile :: flockTiles)
            , Html.p [ Html.Attributes.class "mt-2 text-[11px] text-muted font-mono tracking-wide italic" ]
                [ Html.text "This can't be changed later." ]
            ]
        )


viewTargetTile :
    { active : Bool, label : String, onSelect : Msg, sub : String }
    -> Html Msg
viewTargetTile opts =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Events.onClick opts.onSelect
        , Html.Attributes.classList
            [ ( "flex-1 min-w-[120px] rounded-lg border px-3 py-2 text-left cursor-pointer", True )
            , ( "bg-rust-tint border-rust-deep text-rust-deep", opts.active )
            , ( "bg-parchment border-tan text-ink hover:border-moss", not opts.active )
            ]
        ]
        [ Html.div [ Html.Attributes.class "text-[13px] font-semibold leading-tight" ]
            [ Html.text opts.label ]
        , Html.div [ Html.Attributes.class "mt-1 text-[10px] font-mono uppercase tracking-widest text-moss" ]
            [ Html.text opts.sub ]
        ]


{-| The sub-label under a flock tile: "Owner + N more" reads cleaner
than a comma-joined initial list when the flock is large, and short
enough at small flocks to keep the segmented control single-line.
-}
flockTileSub : Flock -> String
flockTileSub flock =
    let
        count =
            List.length (Data.Flock.members flock)
    in
    if count <= 1 then
        "JUST OWNER"

    else
        "OWNER + " ++ String.fromInt (count - 1)
