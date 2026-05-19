module Pages.Stats exposing (viewStatsTab)

import Chart as C
import Chart.Attributes as CA
import Data.Category as Category
import Data.Entry as Entry
import Helpers exposing (formatAmount, isoToDayCount)
import Html exposing (..)
import Html.Attributes exposing (..)
import List.NonEmpty.Zipper as Zipper
import Types exposing (..)
import UI.Layout exposing (sectionHead)


viewStatsTab : AuthState -> Html Msg
viewStatsTab model =
    let
        entries =
            case model.expensesState of
                Loaded es -> es
                _         -> []

        total =
            List.sum (List.map .amount entries)

        numDays =
            List.length (Entry.uniqueDates entries)

        numEntries =
            List.length entries

        avgPerDay =
            if numDays > 0 then total / toFloat numDays else 0

        avgPerEntry =
            if numEntries > 0 then total / toFloat numEntries else 0

        median =
            Entry.medianAmount entries

        topCat =
            Entry.topCategory entries

        bigDay =
            Entry.biggestDay entries

        top5 =
            entries
                |> List.sortBy (\e -> negate e.amount)
                |> List.take 5

        tripStart =
            (Zipper.current model.trips).startDate

        daysIn =
            if tripStart /= "" && model.today /= "" then
                isoToDayCount model.today - isoToDayCount tripStart + 1
            else
                0
    in
    div [ style "padding" "20px" ]
        [ h2 [ sectionHead ] [ text "STATS" ]
        , div
            [ style "display" "grid"
            , style "grid-template-columns" "1fr 1fr"
            , style "gap" "12px"
            , style "margin-bottom" "24px"
            ]
            [ statCard "TOTAL SPENT" (formatAmount total)
            , statCard "ENTRIES" (String.fromInt numEntries)
            , statCard "DAYS ON ROAD" (String.fromInt numDays)
            , statCard "AVG / DAY" (formatAmount avgPerDay)
            , statCard "AVG / ENTRY" (formatAmount avgPerEntry)
            , statCard "MEDIAN" (formatAmount median)
            , statCard "TOP CATEGORY"
                (topCat
                    |> Maybe.map (\c -> Category.icon c ++ " " ++ Category.label c)
                    |> Maybe.withDefault "—"
                )
            , if numDays > 1 then
                statCard "BIGGEST DAY"
                    (bigDay
                        |> Maybe.map (\( d, t ) -> String.slice 5 10 d ++ "  " ++ formatAmount t)
                        |> Maybe.withDefault "—"
                    )
              else
                statCard "ENTRIES TODAY" (String.fromInt numEntries)
            , statCard "DAYS INTO TRIP"
                (if daysIn > 0 then String.fromInt daysIn else "—")
            , statCard "PROJ / 30 DAYS"
                (if avgPerDay > 0 then formatAmount (avgPerDay * 30) else "—")
            ]
        , if List.isEmpty entries then
            text ""

          else
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                , style "margin-bottom" "16px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                    [ text "BY CATEGORY" ]
                , viewCategoryChart entries
                ]
        , if numDays > 1 then
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                , style "margin-bottom" "16px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                    [ text "DAILY SPENDING" ]
                , viewDailyChart entries
                ]

          else
            text ""
        , if numDays > 1 then
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                , style "margin-bottom" "16px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                    [ text "CUMULATIVE SPEND" ]
                , viewCumulativeChart entries
                ]

          else
            text ""
        , if List.isEmpty top5 then
            text ""

          else
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "12px" ]
                    [ text "TOP 5 LARGEST" ]
                , div []
                    (List.indexedMap
                        (\i entry ->
                            div
                                [ style "display" "flex"
                                , style "align-items" "center"
                                , style "gap" "12px"
                                , style "padding" "10px 0"
                                , style "border-bottom" (if i < List.length top5 - 1 then "1px solid #2a3230" else "none")
                                ]
                                [ span [ style "color" "#4a5a50", style "font-family" "monospace", style "width" "20px" ]
                                    [ text (String.fromInt (i + 1) ++ ".") ]
                                , span [ style "font-size" "18px" ] [ text (Category.icon entry.category) ]
                                , div [ style "flex" "1" ]
                                    [ div [ style "font-size" "14px" ] [ text (if entry.note /= "" then entry.note else Category.label entry.category) ]
                                    , div [ style "font-size" "11px", style "color" "#7a8a80" ] [ text entry.date ]
                                    ]
                                , span [ style "font-family" "monospace", style "color" "#e8a020", style "font-size" "16px" ]
                                    [ text (formatAmount entry.amount) ]
                                ]
                        )
                        top5
                    )
                ]
        ]


statCard : String -> String -> Html Msg
statCard label_ value =
    div
        [ style "background" "#161918"
        , style "border-radius" "10px"
        , style "padding" "16px"
        ]
        [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "6px" ]
            [ text label_ ]
        , div [ style "font-size" "22px", style "font-family" "monospace", style "color" "#e8a020" ]
            [ text value ]
        ]


viewCategoryChart : List Entry.EffectiveEntry -> Html Msg
viewCategoryChart entries =
    let
        rows =
            Category.all
                |> List.map
                    (\cat ->
                        { color = Category.color cat
                        , label = Category.label cat
                        , total =
                            entries
                                |> List.filter (\e -> e.category == cat)
                                |> List.map .amount
                                |> List.sum
                        }
                    )
    in
    C.chart
        [ CA.height 140
        , CA.margin { top = 10, bottom = 28, left = 0, right = 0 }
        ]
        [ C.bars []
            [ C.bar .total []
                |> C.variation (\_ d -> [ CA.color d.color ])
            ]
            rows
        , C.binLabels .label [ CA.moveDown 16, CA.color "#7a8a80", CA.fontSize 9 ]
        ]


viewDailyChart : List Entry.EffectiveEntry -> Html Msg
viewDailyChart entries =
    let
        days =
            Entry.uniqueDates entries
                |> List.reverse
                |> List.map
                    (\date ->
                        { date = String.slice 5 10 date
                        , total =
                            entries
                                |> List.filter (\e -> e.date == date)
                                |> List.map .amount
                                |> List.sum
                        }
                    )
    in
    C.chart
        [ CA.height 140
        , CA.margin { top = 10, bottom = 28, left = 0, right = 0 }
        ]
        [ C.bars []
            [ C.bar .total [ CA.color "#e8a020" ] ]
            days
        , C.binLabels .date [ CA.moveDown 16, CA.color "#7a8a80", CA.fontSize 8 ]
        ]


viewCumulativeChart : List Entry.EffectiveEntry -> Html Msg
viewCumulativeChart entries =
    let
        sorted =
            Entry.uniqueDates entries |> List.reverse

        points =
            List.indexedMap
                (\i date ->
                    { x = toFloat (i + 1)
                    , y =
                        entries
                            |> List.filter (\e -> e.date <= date)
                            |> List.map .amount
                            |> List.sum
                    }
                )
                sorted
    in
    C.chart
        [ CA.height 160
        , CA.margin { top = 10, bottom = 10, left = 0, right = 0 }
        ]
        [ C.series .x
            [ C.interpolated .y [ CA.color "#4090e0", CA.width 2 ] [] ]
            points
        ]
