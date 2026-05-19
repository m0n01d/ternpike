module Pages.Stats exposing (viewStatsTab)

import Chart as C
import Chart.Attributes as CA
import Data.Category as Category
import Data.Entry as Entry
import Helpers exposing (formatAmount, isoToDayCount)
import Html exposing (Html)
import Html.Attributes
import List.NonEmpty.Zipper as Zipper
import Types exposing (..)
import UI.Layout exposing (sectionHead)
import UI.Theme


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
    Html.div [ Html.Attributes.class "p-5" ]
        [ Html.h2 [ sectionHead ] [ Html.text "STATS" ]
        , Html.div [ Html.Attributes.class "grid grid-cols-2 gap-3 mb-6" ]
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
            Html.text ""

          else
            Html.div [ Html.Attributes.class "bg-cream rounded-xl p-5 mb-4" ]
                [ Html.div [ Html.Attributes.class "text-xs tracking-widest text-moss mb-2" ] [ Html.text "BY CATEGORY" ]
                , viewCategoryChart entries
                ]
        , if numDays > 1 then
            Html.div [ Html.Attributes.class "bg-cream rounded-xl p-5 mb-4" ]
                [ Html.div [ Html.Attributes.class "text-xs tracking-widest text-moss mb-2" ] [ Html.text "DAILY SPENDING" ]
                , viewDailyChart entries
                ]

          else
            Html.text ""
        , if numDays > 1 then
            Html.div [ Html.Attributes.class "bg-cream rounded-xl p-5 mb-4" ]
                [ Html.div [ Html.Attributes.class "text-xs tracking-widest text-moss mb-2" ] [ Html.text "CUMULATIVE SPEND" ]
                , viewCumulativeChart entries
                ]

          else
            Html.text ""
        , if List.isEmpty top5 then
            Html.text ""

          else
            Html.div [ Html.Attributes.class "bg-cream rounded-xl p-5" ]
                [ Html.div [ Html.Attributes.class "text-xs tracking-widest text-moss mb-3" ] [ Html.text "TOP 5 LARGEST" ]
                , Html.div []
                    (List.indexedMap
                        (\i entry ->
                            Html.div
                                [ Html.Attributes.class
                                    ("flex items-center gap-3 py-2.5 "
                                        ++ (if i < List.length top5 - 1 then "border-b border-tan" else "")
                                    )
                                ]
                                [ Html.span [ Html.Attributes.class "text-moss font-mono w-5" ]
                                    [ Html.text (String.fromInt (i + 1) ++ ".") ]
                                , Html.span [ Html.Attributes.class "text-lg leading-none" ] [ Html.text (Category.icon entry.category) ]
                                , Html.div [ Html.Attributes.class "flex-1" ]
                                    [ Html.div [ Html.Attributes.class "text-sm text-ink" ] [ Html.text (if entry.note /= "" then entry.note else Category.label entry.category) ]
                                    , Html.div [ Html.Attributes.class "text-[11px] text-muted" ] [ Html.text entry.date ]
                                    ]
                                , Html.span [ Html.Attributes.class "font-mono text-rust text-base" ]
                                    [ Html.text (formatAmount entry.amount) ]
                                ]
                        )
                        top5
                    )
                ]
        ]


statCard : String -> String -> Html Msg
statCard label_ value =
    Html.div [ Html.Attributes.class "bg-cream rounded-xl p-4" ]
        [ Html.div [ Html.Attributes.class "text-[11px] tracking-widest text-moss mb-1.5" ]
            [ Html.text label_ ]
        , Html.div [ Html.Attributes.class "text-[22px] font-mono text-rust" ]
            [ Html.text value ]
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
        , C.binLabels .label [ CA.moveDown 16, CA.color UI.Theme.colorMuted, CA.fontSize 9 ]
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
            [ C.bar .total [ CA.color UI.Theme.colorRust ] ]
            days
        , C.binLabels .date [ CA.moveDown 16, CA.color UI.Theme.colorMuted, CA.fontSize 8 ]
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
            [ C.interpolated .y [ CA.color UI.Theme.colorRust, CA.width 2 ] [] ]
            points
        ]
