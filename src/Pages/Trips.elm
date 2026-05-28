module Pages.Trips exposing (viewTab)

import Data.DateField as DateField
import Data.Entry as Entry
import Data.Money as Money
import Data.Navigation exposing (Tab(..))
import Data.SharedTrip exposing (SharedTrip)
import Data.SharedTrips
import Data.Tier as Tier
import Data.Trip exposing (Trip)
import Data.TripId as TripId
import Data.Trips as Trips exposing (TripsState(..))
import Dict
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Extra
import Routing
import Set
import Types exposing (AuthMsg_(..), AuthState, Msg(..))
import UI.Avatar
import UI.BudgetBar
import UI.Button
import UI.DateView
import UI.Icons
import UI.Mascot
import UI.SharedTripBadge


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
                , onClick = AuthMsg (OpenEditTripForm activeTrip)
                , title = "Edit trip"
                }
                :: (if canDelete then
                        [ UI.Button.iconButton
                            { icon = UI.Icons.trash "w-4 h-4"
                            , onClick = AuthMsg (ConfirmDeleteTrip activeTrip)
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
            UI.Mascot.loading

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
flockForTrip : AuthState -> Trip -> Maybe SharedTrip
flockForTrip as_ trip =
    trip.flockId
        |> Maybe.andThen (\fid -> Data.SharedTrips.get fid as_.sharedTrips)


viewTripHero : Maybe SharedTrip -> Trip -> List Entry.EffectiveEntry -> Html Msg
viewTripHero maybeFlock activeTrip entries =
    let
        totalSpent =
            Money.sum (List.map .amount entries)

        hasStart =
            not (isEpochDate activeTrip.startDate)

        hasEnd =
            not (isEpochDate activeTrip.endDate)

        dateLineNodes : List (Html Msg)
        dateLineNodes =
            if hasStart && hasEnd then
                [ UI.DateView.short activeTrip.startDate
                , Html.text " — "
                , UI.DateView.short activeTrip.endDate
                ]

            else if hasStart then
                [ UI.DateView.short activeTrip.startDate ]

            else
                []

        totalDays =
            if hasStart && hasEnd then
                Basics.max 1 (DateField.diffDays activeTrip.startDate activeTrip.endDate + 1)

            else
                0
    in
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div [ Html.Attributes.class "mb-1 flex items-center gap-2" ]
            [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss" ]
                [ Html.text "ACTIVE TRIP" ]
            , Html.Extra.viewMaybe UI.SharedTripBadge.view maybeFlock
            ]
        , Html.div [ Html.Attributes.class "font-display text-4xl font-black text-forest tracking-tight leading-tight" ]
            [ Html.text activeTrip.name ]
        , Html.Extra.viewIf (activeTrip.description /= "") <|
            Html.p [ Html.Attributes.class "mt-2 text-sm text-muted" ]
                [ Html.text activeTrip.description ]
        , Html.div [ Html.Attributes.class "mt-2 flex items-center gap-3 text-xs font-mono tracking-wide text-muted" ]
            [ Html.Extra.viewIf (not (List.isEmpty dateLineNodes)) <|
                Html.span [ Html.Attributes.class "flex items-center gap-2" ]
                    (dateLineNodes
                        ++ (if totalDays > 0 then
                                [ Html.text ("· " ++ String.fromInt totalDays ++ " DAYS") ]

                            else
                                []
                           )
                    )
            , Html.Extra.viewMaybe
                (\flock -> UI.Avatar.viewStack (Data.SharedTrip.members flock))
                maybeFlock
            ]
        , Html.Extra.viewIf (not (Money.isZero activeTrip.budget)) <|
            UI.BudgetBar.view
                { budget = activeTrip.budget
                , spent = totalSpent
                }
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

        atLimit =
            case as_.trips of
                TripsLoaded trips ->
                    atTripLimit as_.tier trips

                _ ->
                    False
    in
    Html.div []
        [ Html.Extra.viewIf (not (List.isEmpty others)) <|
            Html.div [ Html.Attributes.class "mb-5" ]
                (List.map (viewOtherTripRow as_) others)
        , if atLimit then
            viewTripLimitUpgradePrompt

          else
            viewNewTripButton
        ]


viewNewTripButton : Html Msg
viewNewTripButton =
    Html.button
        [ Html.Events.onClick (AuthMsg OpenNewTripForm)
        , Html.Attributes.class "w-full bg-transparent border border-dashed border-tan rounded-xl py-3.5 text-muted text-[15px] cursor-pointer flex items-center justify-center gap-2 hover:border-moss hover:text-forest"
        ]
        [ UI.Icons.plus "w-4 h-4"
        , Html.text "New trip"
        ]


atTripLimit : Tier.Tier -> Trips.Trips -> Bool
atTripLimit tier trips =
    not (Tier.isPaid tier) && List.length (Trips.allTrips trips) >= 3


viewTripLimitUpgradePrompt : Html Msg
viewTripLimitUpgradePrompt =
    Html.div [ Html.Attributes.class "mt-3 bg-rust-tint border border-rust/30 rounded-lg px-3 py-2.5" ]
        [ Html.p [ Html.Attributes.class "text-[13px] text-rust-deep" ]
            [ Html.text "Free accounts are limited to 3 trips. "
            , Html.a
                [ Html.Attributes.href "/settings#billing"
                , Html.Attributes.class "underline font-semibold"
                ]
                [ Html.text "Upgrade to Osprey →" ]
            ]
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
            [ Html.Extra.viewMaybe
                (\flock ->
                    Html.div [ Html.Attributes.class "mb-1" ]
                        [ UI.SharedTripBadge.view flock ]
                )
                maybeFlock
            , Html.p [ Html.Attributes.class "text-[15px] font-semibold mb-0.5 truncate" ]
                [ Html.text trip.name ]
            , Html.div [ Html.Attributes.class "flex items-center gap-2" ]
                [ Html.Extra.viewIf (not (isEpochDate trip.startDate)) <|
                    Html.p [ Html.Attributes.class "text-[11px] text-moss font-mono" ]
                        [ UI.DateView.short trip.startDate ]
                , Html.Extra.viewMaybe
                    (\flock -> UI.Avatar.viewStack (Data.SharedTrip.members flock))
                    maybeFlock
                ]
            ]
        , Html.span [ Html.Attributes.class "text-muted shrink-0 ml-2" ]
            [ UI.Icons.chevronRight "w-4 h-4" ]
        ]


{-| True when a `DateField` is the epoch sentinel (`1970-01-01`).
After R2, trip dates that were stored as the legacy `""` empty-string
sentinel parse to the epoch (via `DateField.decoder`'s built-in fallback,
or via `Main.parseFormDate` for newly-submitted forms). The view code
treats the epoch as "no date set" — same as the pre-R2 `/= ""` check.
-}
isEpochDate : DateField.DateField -> Bool
isEpochDate d =
    DateField.toIso d == "1970-01-01"
