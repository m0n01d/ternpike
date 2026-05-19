module Pages.Ledger exposing (viewLedgerTab)

import Data.Category as Category
import Data.Entry as Entry
import Helpers exposing (effectiveEntryToExpense, encodeWaypoints, formatAmount, formatDateDisplay)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Json.Decode as D
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
                    p [ style "color" "#7a8a80", style "text-align" "center", style "padding" "32px 0" ]
                        [ text "No expenses yet. Add your first one!" ]

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
                                    , div [ style "margin-bottom" "24px" ]
                                        [ div
                                            [ style "font-size" "11px"
                                            , style "letter-spacing" "0.1em"
                                            , style "color" "#7a8a80"
                                            , style "margin-bottom" "8px"
                                            , style "padding-bottom" "6px"
                                            , style "border-bottom" "1px solid #2a3230"
                                            , style "display" "flex"
                                            , style "justify-content" "space-between"
                                            , style "align-items" "center"
                                            ]
                                            [ text (String.toUpper (formatDateDisplay date))
                                            , span
                                                [ style "font-family" "monospace"
                                                , style "color" "#e8a020"
                                                , style "letter-spacing" "0"
                                                ]
                                                [ text (formatAmount (List.sum (List.map .amount dayEntries))) ]
                                            ]
                                        , Keyed.node "div" [] (List.map (\e -> ( e.id, viewEntryRow e )) dayEntries)
                                        ]
                                    )
                                )
                        )
    in
    div [ style "padding" "20px" ]
        [ div [ class "flex items-center justify-between mb-5" ]
            [ h2 [ sectionHead ] [ text "LEDGER" ]
            , div [ class "flex gap-2" ]
                [ button
                    [ onClick ToggleLedgerMap
                    , class
                        (if model.showLedgerMap then
                            "px-3 py-1.5 rounded border border-[#3a4240] bg-[#1e3a50] text-[#4090e0] text-sm cursor-pointer font-[inherit]"

                         else
                            "px-3 py-1.5 rounded border border-[#3a4240] bg-transparent text-[#7a8a80] text-sm cursor-pointer font-[inherit]"
                        )
                    ]
                    [ text "🗺 map" ]
                , button
                    [ onClick RefreshClicked
                    , class "px-3 py-1.5 rounded border border-[#3a4240] bg-transparent text-[#7a8a80] text-sm cursor-pointer font-[inherit]"
                    ]
                    [ text "↻ refresh" ]
                ]
            ]
        , case model.expensesState of
            Loaded entries ->
                viewLedgerSummary entries

            _ ->
                text ""
        , case model.expensesState of
            Loaded entries ->
                viewLedgerMap model entries

            _ ->
                text ""
        , entriesView
        ]


viewLedgerMap : AuthState -> List Entry.EffectiveEntry -> Html Msg
viewLedgerMap model entries =
    if model.showLedgerMap then
        Html.node "waypoint-map"
            [ attribute "points" (encodeWaypoints entries)
            , class "block w-full rounded-xl overflow-hidden mb-5"
            , style "height" "260px"
            ]
            []

    else
        text ""


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
    div
        [ style "background" "#161918"
        , style "border-radius" "10px"
        , style "padding" "14px 16px"
        , style "margin-bottom" "20px"
        ]
        [ div
            [ style "font-family" "monospace"
            , style "font-size" "22px"
            , style "color" "#e8a020"
            , style "margin-bottom" "12px"
            ]
            [ text (formatAmount total) ]
        , div
            [ style "display" "flex"
            , style "flex-wrap" "wrap"
            , style "gap" "10px"
            ]
            (List.map
                (\( cat, t ) ->
                    div
                        [ style "display" "flex"
                        , style "align-items" "center"
                        , style "gap" "4px"
                        ]
                        [ span [ style "font-size" "15px" ] [ text (Category.icon cat) ]
                        , span
                            [ style "font-family" "monospace"
                            , style "font-size" "13px"
                            , style "color" "#7a8a80"
                            ]
                            [ text (formatAmount t) ]
                        ]
                )
                catRow
            )
        ]


viewEntryRow : Entry.EffectiveEntry -> Html Msg
viewEntryRow entry =
    div
        [ onClick (EditEntry (effectiveEntryToExpense entry))
        , style "background" "#161918"
        , style "border-radius" "8px"
        , style "padding" "14px 16px"
        , style "margin-bottom" "8px"
        , style "display" "flex"
        , style "align-items" "center"
        , style "gap" "12px"
        , style "cursor" "pointer"
        ]
        [ div
            [ style "width" "10px"
            , style "height" "10px"
            , style "border-radius" "50%"
            , style "background" (Category.color entry.category)
            , style "flex-shrink" "0"
            ]
            []
        , span [ style "font-size" "20px", style "flex-shrink" "0" ] [ text (Category.icon entry.category) ]
        , div [ style "flex" "1", style "min-width" "0" ]
            [ div
                [ style "font-size" "15px"
                , style "color" "#c8d0c8"
                , style "white-space" "nowrap"
                , style "overflow" "hidden"
                , style "text-overflow" "ellipsis"
                ]
                [ text
                    (if entry.note /= "" then
                        entry.note

                     else if entry.merchant /= "" then
                        entry.merchant

                     else
                        Category.label entry.category
                    )
                ]
            , if entry.merchant /= "" && entry.note /= "" then
                div [ style "font-size" "12px", style "color" "#4a5a50" ] [ text entry.merchant ]

              else
                text ""
            , if entry.longNote /= "" then
                div [ class "text-xs text-[#4a5a50] mt-1 leading-snug line-clamp-2" ] [ text entry.longNote ]

              else
                text ""
            ]
        , span
            [ style "font-family" "monospace"
            , style "font-size" "17px"
            , style "color" "#c8d0c8"
            , style "flex-shrink" "0"
            ]
            [ text (formatAmount entry.amount) ]
        , case entry.lat of
            Just _ ->
                span
                    [ style "font-size" "14px"
                    , style "color" "#4090e0"
                    , style "flex-shrink" "0"
                    , title "Has GPS coordinates"
                    ]
                    [ text "📍" ]

            Nothing ->
                text ""
        , button
            [ Html.Events.stopPropagationOn "click" (D.succeed ( VoidEntry (effectiveEntryToExpense entry), True ))
            , style "background" "none"
            , style "border" "none"
            , style "color" "#e85030"
            , style "font-size" "18px"
            , style "cursor" "pointer"
            , style "padding" "4px 8px"
            , style "flex-shrink" "0"
            , style "min-width" "44px"
            , style "min-height" "44px"
            , style "display" "flex"
            , style "align-items" "center"
            , style "justify-content" "center"
            ]
            [ text "✕" ]
        ]


viewSkeleton : Html Msg
viewSkeleton =
    div []
        (List.repeat 5
            (div
                [ style "background" "#161918"
                , style "border-radius" "8px"
                , style "padding" "18px 16px"
                , style "margin-bottom" "8px"
                , style "display" "flex"
                , style "gap" "12px"
                ]
                [ div [ style "width" "10px", style "height" "10px", style "border-radius" "50%", style "background" "#2a3230" ] []
                , div [ style "flex" "1", style "height" "16px", style "background" "#2a3230", style "border-radius" "4px" ] []
                , div [ style "width" "60px", style "height" "16px", style "background" "#2a3230", style "border-radius" "4px" ] []
                ]
            )
        )
