module Pages.Ledger exposing (viewTab)

import Data.Category as Category
import Data.Entry as Entry
import Data.ExpenseId as ExpenseId
import Helpers exposing (effectiveEntryToExpense, encodeWaypoints, formatAmount, formatDateDisplay)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Keyed as Keyed
import Json.Decode
import Types exposing (..)
import UI.Button
import UI.Icons
import UI.Mascot
import UI.Skeleton


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = viewActions as_
    , body = viewBody as_
    , hero = viewHero as_
    }


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


viewHero : AuthState -> Html Msg
viewHero model =
    case model.expensesState of
        Loaded entries ->
            viewLedgerHero entries

        _ ->
            Html.div [ Html.Attributes.class "font-mono text-[22px] text-muted" ]
                [ Html.text "—" ]


viewLedgerHero : List Entry.EffectiveEntry -> Html Msg
viewLedgerHero entries =
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
        ]


viewBody : AuthState -> Html Msg
viewBody model =
    let
        entriesView =
            case model.expensesState of
                Loading ->
                    viewSkeleton

                NotAsked ->
                    viewSkeleton

                Loaded [] ->
                    viewEmptyState

                Loaded entries ->
                    viewEntries entries
    in
    Html.div []
        [ case model.expensesState of
            Loaded entries ->
                viewLedgerMap model entries

            _ ->
                Html.text ""
        , entriesView
        ]


viewEntries : List Entry.EffectiveEntry -> Html Msg
viewEntries entries =
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
                        (\e -> ( ExpenseId.toString e.id, viewEntryRow e ))
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


viewEntryRow : Entry.EffectiveEntry -> Html Msg
viewEntryRow entry =
    let
        primaryLabel =
            if entry.merchant /= "" then
                entry.merchant

            else if entry.note /= "" then
                entry.note

            else
                Category.label entry.category
    in
    Html.button
        [ Html.Events.onClick (EditEntry (effectiveEntryToExpense entry))
        , Html.Attributes.class "w-full text-left py-3 border-b border-dashed border-tan/70 flex items-baseline gap-3 bg-transparent border-l-0 border-r-0 border-t-0 cursor-pointer"
        ]
        [ Html.div [ Html.Attributes.class "flex-1 min-w-0" ]
            [ Html.div [ Html.Attributes.class "text-sm text-ink font-body truncate" ]
                [ Html.text primaryLabel ]
            , Html.div [ Html.Attributes.class "mt-0.5 flex items-center gap-2" ]
                [ Html.span
                    [ Html.Attributes.class "inline-block text-[10px] font-mono uppercase tracking-wider text-moss bg-cream-deep px-2 py-0.5 rounded" ]
                    [ Html.text (Category.label entry.category) ]
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
            [ Html.Events.stopPropagationOn "click" (Json.Decode.succeed ( VoidEntry (effectiveEntryToExpense entry), True ))
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
