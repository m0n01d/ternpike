module Pages.Ledger exposing (viewLedgerTab)

import Data.Category as Category
import Data.Entry as Entry
import Helpers exposing (effectiveEntryToExpense, encodeWaypoints, formatAmount, formatDateDisplay)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Keyed as Keyed
import Json.Decode
import Types exposing (..)
import UI.Layout exposing (sectionHead)


viewLedgerTab : AuthState -> Html Msg
viewLedgerTab model =
    let
        entriesView =
            case model.expensesState of
                Loading ->
                    viewSkeleton

                NotAsked ->
                    viewSkeleton

                Loaded [] ->
                    Html.p [ Html.Attributes.class "text-muted text-center py-8" ]
                        [ Html.text "No expenses yet. Add your first one!" ]

                Loaded entries ->
                    Keyed.node "div"
                        []
                        (Entry.uniqueDates entries
                            |> List.map
                                (\date ->
                                    let
                                        dayEntries =
                                            List.filter (\e -> e.date == date) entries
                                    in
                                    ( date
                                    , Html.div [ Html.Attributes.class "mb-6" ]
                                        [ Html.div
                                            [ Html.Attributes.class "text-[11px] tracking-widest text-muted mb-2 pb-1.5 border-b border-tan flex justify-between items-center" ]
                                            [ Html.text (String.toUpper (formatDateDisplay date))
                                            , Html.span [ Html.Attributes.class "font-mono text-rust tracking-normal" ]
                                                [ Html.text (formatAmount (List.sum (List.map .amount dayEntries))) ]
                                            ]
                                        , Keyed.node "div" [] (List.map (\e -> ( e.id, viewEntryRow e )) dayEntries)
                                        ]
                                    )
                                )
                        )
    in
    Html.div [ Html.Attributes.class "p-5" ]
        [ Html.div [ Html.Attributes.class "flex items-center justify-between mb-5" ]
            [ Html.h2 [ sectionHead ] [ Html.text "LEDGER" ]
            , Html.div [ Html.Attributes.class "flex gap-2" ]
                [ Html.button
                    [ Html.Events.onClick ToggleLedgerMap
                    , Html.Attributes.class
                        ("px-3 py-1.5 rounded border text-sm cursor-pointer "
                            ++ (if model.showLedgerMap then
                                    "border-forest-light bg-cream text-forest"
                                 else
                                    "border-tan bg-transparent text-muted"
                               )
                        )
                    ]
                    [ Html.text "🗺 map" ]
                , Html.button
                    [ Html.Events.onClick RefreshClicked
                    , Html.Attributes.class "px-3 py-1.5 rounded border border-tan bg-transparent text-muted text-sm cursor-pointer"
                    ]
                    [ Html.text "↻ refresh" ]
                ]
            ]
        , case model.expensesState of
            Loaded entries ->
                viewLedgerSummary entries

            _ ->
                Html.text ""
        , case model.expensesState of
            Loaded entries ->
                viewLedgerMap model entries

            _ ->
                Html.text ""
        , entriesView
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


viewLedgerSummary : List Entry.EffectiveEntry -> Html Msg
viewLedgerSummary entries =
    let
        total =
            List.sum (List.map .amount entries)

        catRow =
            Category.all
                |> List.filterMap
                    (\cat ->
                        let
                            t =
                                entries
                                    |> List.filter (\e -> e.category == cat)
                                    |> List.map .amount
                                    |> List.sum
                        in
                        if t > 0 then
                            Just ( cat, t )
                        else
                            Nothing
                    )
    in
    Html.div [ Html.Attributes.class "bg-cream rounded-xl px-4 py-3.5 mb-5" ]
        [ Html.div [ Html.Attributes.class "font-mono text-[22px] text-rust mb-3" ]
            [ Html.text (formatAmount total) ]
        , Html.div [ Html.Attributes.class "flex flex-wrap gap-2.5" ]
            (List.map
                (\( cat, t ) ->
                    Html.div [ Html.Attributes.class "flex items-center gap-1" ]
                        [ Html.span [ Html.Attributes.class "text-[15px]" ] [ Html.text (Category.icon cat) ]
                        , Html.span [ Html.Attributes.class "font-mono text-[13px] text-muted" ]
                            [ Html.text (formatAmount t) ]
                        ]
                )
                catRow
            )
        ]


viewEntryRow : Entry.EffectiveEntry -> Html Msg
viewEntryRow entry =
    Html.div
        [ Html.Events.onClick (EditEntry (effectiveEntryToExpense entry))
        , Html.Attributes.class "bg-cream rounded-lg px-4 py-3.5 mb-2 flex items-center gap-3 cursor-pointer"
        ]
        [ Html.div
            [ Html.Attributes.class "w-2.5 h-2.5 rounded-full shrink-0"
            -- dynamic category color cannot be expressed as a Tailwind class
            , Html.Attributes.style "background" (Category.color entry.category)
            ]
            []
        , Html.span [ Html.Attributes.class "text-xl shrink-0 leading-none" ] [ Html.text (Category.icon entry.category) ]
        , Html.div [ Html.Attributes.class "flex-1 min-w-0" ]
            [ Html.div [ Html.Attributes.class "text-[15px] text-ink truncate" ]
                [ Html.text
                    (if entry.note /= "" then
                        entry.note

                     else if entry.merchant /= "" then
                        entry.merchant

                     else
                        Category.label entry.category
                    )
                ]
            , if entry.merchant /= "" && entry.note /= "" then
                Html.div [ Html.Attributes.class "text-xs text-moss" ] [ Html.text entry.merchant ]

              else
                Html.text ""
            , if entry.longNote /= "" then
                Html.div [ Html.Attributes.class "text-xs text-moss mt-0.5 leading-snug line-clamp-2" ] [ Html.text entry.longNote ]

              else
                Html.text ""
            ]
        , Html.span [ Html.Attributes.class "font-mono text-[17px] text-ink shrink-0" ]
            [ Html.text (formatAmount entry.amount) ]
        , case entry.lat of
            Just _ ->
                Html.span
                    [ Html.Attributes.class "text-sm text-moss shrink-0"
                    , Html.Attributes.title "Has GPS coordinates"
                    ]
                    [ Html.text "📍" ]

            Nothing ->
                Html.text ""
        , Html.button
            [ Html.Events.stopPropagationOn "click" (Json.Decode.succeed ( VoidEntry (effectiveEntryToExpense entry), True ))
            , Html.Attributes.class "bg-transparent border-none text-rust text-lg cursor-pointer px-2 py-1 shrink-0 min-w-[44px] min-h-[44px] flex items-center justify-center"
            ]
            [ Html.text "✕" ]
        ]


viewSkeleton : Html Msg
viewSkeleton =
    Html.div []
        (List.repeat 5
            (Html.div
                [ Html.Attributes.class "bg-cream rounded-lg py-[18px] px-4 mb-2 flex gap-3" ]
                [ Html.div [ Html.Attributes.class "w-2.5 h-2.5 rounded-full bg-tan mt-1" ] []
                , Html.div [ Html.Attributes.class "flex-1 h-4 bg-tan rounded" ] []
                , Html.div [ Html.Attributes.class "w-14 h-4 bg-tan rounded" ] []
                ]
            )
        )
