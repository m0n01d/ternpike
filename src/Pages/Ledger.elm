module Pages.Ledger exposing (viewTab)

import Data.Category as Category
import Data.Entry as Entry
import Data.ExpenseId as ExpenseId
import Data.Ledger exposing (LedgerMode(..))
import Data.TripId as TripId
import Data.Trips
import Dict
import Helpers exposing (effectiveEntryToExpense, encodeWaypoints, formatAmount, formatDateDisplay)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Keyed as Keyed
import Json.Decode
import Routing
import Set
import Types exposing (AuthState, Msg(..))
import UI.BudgetBar
import UI.Button
import UI.Icons
import UI.Mascot
import UI.Skeleton


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    let
        mode =
            ledgerMode as_
    in
    { actions = viewActions as_
    , body = viewBody as_ mode
    , hero = viewHero (activeBudget as_) mode
    }


activeBudget : AuthState -> Float
activeBudget as_ =
    case ( Routing.routeTripId as_.route, as_.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded trips ) ->
            Data.Trips.findTrip tripId trips
                |> Maybe.map .budget
                |> Maybe.withDefault 0

        _ ->
            0



-- LedgerLoading until the current trip's bulk fetch has completed; then
-- LedgerReady with the resolved entries derived from the cache.


ledgerMode : AuthState -> LedgerMode
ledgerMode as_ =
    case Routing.routeTripId as_.route of
        Just tripId ->
            if Set.member (TripId.toString tripId) as_.tripLoaded then
                LedgerReady
                    (Entry.resolve
                        (as_.expenses |> Dict.get (TripId.toString tripId) |> Maybe.withDefault Dict.empty |> Dict.values)
                        (Dict.values as_.amendments)
                        (Dict.values as_.voids)
                        tripId
                    )

            else
                LedgerLoading

        Nothing ->
            LedgerLoading


viewActions : AuthState -> List (Html Msg)
viewActions model =
    [ UI.Button.iconButton
        { icon = UI.Icons.map "w-4 h-4"
        , onClick = ToggleLedgerMap
        , title =
            if model.showLedgerMap then
                "Hide map"

            else
                "Show map"
        }
    , UI.Button.iconButton
        { icon = UI.Icons.chevronRight "w-4 h-4"
        , onClick = RefreshClicked
        , title = "Refresh"
        }
    ]


viewHero : Float -> LedgerMode -> Html Msg
viewHero budget mode =
    case mode of
        LedgerReady entries ->
            viewLedgerHero budget entries

        LedgerLoading ->
            Html.div [ Html.Attributes.class "font-mono text-[22px] text-muted" ]
                [ Html.text "—" ]


viewLedgerHero : Float -> List Entry.EffectiveEntry -> Html Msg
viewLedgerHero budget entries =
    let
        total =
            List.sum (List.map .amount entries)

        entryCount =
            List.length entries

        dayCount =
            List.length (Entry.uniqueDates entries)

        kickerText =
            if dayCount > 0 then
                String.fromInt entryCount
                    ++ " ENTRIES · "
                    ++ String.fromInt dayCount
                    ++ (if dayCount == 1 then
                            " DAY"

                        else
                            " DAYS"
                       )

            else
                String.fromInt entryCount ++ " ENTRIES"
    in
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div
            [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "RUNNING TOTAL" ]
        , Html.div
            [ Html.Attributes.class "font-display text-5xl font-black text-forest tracking-tight leading-none" ]
            [ Html.text (formatAmount total) ]
        , Html.div
            [ Html.Attributes.class "mt-2 text-xs text-muted font-mono tracking-wide" ]
            [ Html.text kickerText ]
        , if budget > 0 then
            UI.BudgetBar.viewSubtle { spent = total, budget = budget }

          else
            Html.text ""
        ]


viewBody : AuthState -> LedgerMode -> Html Msg
viewBody model mode =
    case mode of
        LedgerLoading ->
            viewSkeleton

        LedgerReady [] ->
            viewEmptyState

        LedgerReady entries ->
            Html.div []
                [ viewLedgerMap model entries
                , viewEntries model.basePath entries
                ]


viewEntries : String -> List Entry.EffectiveEntry -> Html Msg
viewEntries basePath entries =
    let
        dates =
            Entry.uniqueDates entries

        indexedDates =
            List.indexedMap
                (\i d -> ( d, List.length dates - i ))
                dates

        groupBlock ( date, dayN ) =
            let
                dayEntries =
                    List.filter (\e -> e.date == date) entries
            in
            ( date
            , Html.div [ Html.Attributes.class "mt-6 mb-4" ]
                [ viewDayKicker dayN date
                , Keyed.node "div"
                    [ Html.Attributes.class "animate-stagger-row" ]
                    (List.map
                        (\e -> ( ExpenseId.toString e.id, viewEntryRow basePath e ))
                        dayEntries
                    )
                ]
            )
    in
    Keyed.node "div" [] (List.map groupBlock indexedDates)


viewDayKicker : Int -> String -> Html Msg
viewDayKicker dayN date =
    Html.div [ Html.Attributes.class "sticky top-14 z-[9] bg-parchment border-t border-tan/40 -mx-5 px-5 py-3 flex items-center gap-3" ]
        [ Html.span
            [ Html.Attributes.class "text-xs font-mono uppercase tracking-widest text-rust" ]
            [ Html.text ("DAY " ++ String.fromInt dayN) ]
        , Html.span [ Html.Attributes.class "h-px flex-1 bg-tan" ] []
        , Html.span
            [ Html.Attributes.class "text-xs font-mono uppercase tracking-widest text-moss" ]
            [ Html.text (String.toUpper (formatDateDisplay date)) ]
        ]


viewLedgerMap : AuthState -> List Entry.EffectiveEntry -> Html Msg
viewLedgerMap model entries =
    if model.showLedgerMap then
        Html.node "waypoint-map"
            [ Html.Attributes.attribute "points" (encodeWaypoints entries)
            , Html.Attributes.class "block w-full rounded-xl overflow-hidden mb-5 h-[260px]"
            ]
            []

    else
        Html.text ""


viewEntryRow : String -> Entry.EffectiveEntry -> Html Msg
viewEntryRow basePath entry =
    let
        primaryLabel =
            if entry.merchant /= "" then
                entry.merchant

            else if entry.note /= "" then
                entry.note

            else
                Category.label entry.category
    in
    Html.a
        [ Html.Attributes.href (Routing.editEntryPath basePath entry.tripId entry.id)
        , Html.Attributes.class "w-full text-left py-3 border-b border-dashed border-tan/70 flex items-baseline gap-3 cursor-pointer text-ink"
        ]
        [ Html.div [ Html.Attributes.class "flex-1 min-w-0" ]
            [ Html.div [ Html.Attributes.class "text-sm text-ink font-body truncate" ]
                [ Html.text primaryLabel ]
            , Html.div [ Html.Attributes.class "mt-1.5 flex items-center gap-2" ]
                [ Html.span
                    [ Html.Attributes.class "inline-block text-[10px] font-mono uppercase tracking-wider text-moss bg-cream-deep px-2 py-0.5 rounded" ]
                    [ Html.text (Category.label entry.category) ]
                , Html.span
                    [ Html.Attributes.class "text-xs leading-none"
                    , Html.Attributes.attribute "aria-hidden" "true"
                    ]
                    [ Html.text (Category.icon entry.category) ]
                , case entry.lat of
                    Just _ ->
                        Html.span
                            [ Html.Attributes.class "text-moss"
                            , Html.Attributes.title "Has GPS coordinates"
                            ]
                            [ UI.Icons.pin "w-3 h-3" ]

                    Nothing ->
                        Html.text ""
                ]
            ]
        , Html.div
            [ Html.Attributes.class "font-mono text-base text-forest tabular-nums shrink-0" ]
            [ Html.text (formatAmount entry.amount) ]
        , Html.span
            [ Html.Events.custom "click"
                (Json.Decode.succeed
                    { message = VoidEntry (effectiveEntryToExpense entry)
                    , preventDefault = True
                    , stopPropagation = True
                    }
                )
            , Html.Attributes.class "text-rust shrink-0 min-w-[32px] min-h-[32px] flex items-center justify-center cursor-pointer"
            ]
            [ UI.Icons.close "w-4 h-4" ]
        ]


viewEmptyState : Html Msg
viewEmptyState =
    Html.div [ Html.Attributes.class "py-16 text-center" ]
        [ UI.Mascot.ternSvg "w-16 mx-auto opacity-40"
        , Html.p [ Html.Attributes.class "mt-4 font-display italic text-lg text-moss" ]
            [ Html.text "No entries yet." ]
        , Html.p [ Html.Attributes.class "mt-1 text-sm text-muted" ]
            [ Html.text "Snap a receipt to start the log." ]
        ]


viewSkeleton : Html Msg
viewSkeleton =
    Html.div [ Html.Attributes.class "space-y-2" ]
        [ UI.Skeleton.row
        , UI.Skeleton.row
        , UI.Skeleton.row
        , UI.Skeleton.row
        , UI.Skeleton.row
        ]
