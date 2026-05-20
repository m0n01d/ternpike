module Pages.Stats exposing (viewTab)

import Chart as C
import Chart.Attributes as CA
import Data.Category as Category
import Data.Entry as Entry
import Helpers exposing (formatAmount, isoToDayCount)
import Html exposing (Html)
import Html.Attributes
import Data.Trips as Trips
import Svg
import Svg.Attributes
import Types exposing (..)
import UI.Card
import UI.Rule
import UI.Theme


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = []
    , body = viewBody as_
    , hero = viewHero as_
    }


viewHero : AuthState -> Html Msg
viewHero model =
    let
        entries =
            case model.expensesState of
                ExpensesReady es -> es
                _                -> []

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

        tripStart =
            case model.trips of
                TripsLoaded trips ->
                    (Trips.selectedTrip trips).startDate

                _ ->
                    ""

        daysIn =
            if tripStart /= "" && model.today /= "" then
                isoToDayCount model.today - isoToDayCount tripStart + 1
            else
                0

        dayOfTripStr =
            if daysIn > 0 then String.fromInt daysIn else "—"

        last7 =
            last7DaysValues entries
    in
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "TOTAL SPENT" ]
        , Html.div [ Html.Attributes.class "flex items-end justify-between gap-4" ]
            [ Html.div []
                [ Html.div [ Html.Attributes.class "font-display text-5xl font-black text-forest tracking-tight leading-none" ]
                    [ Html.text (formatAmount total) ]
                , Html.div [ Html.Attributes.class "mt-2 text-xs font-mono tracking-wide text-muted" ]
                    [ Html.text (String.fromInt numEntries ++ " ENTRIES · DAY " ++ dayOfTripStr) ]
                ]
            , sparkline last7
            ]
        , UI.Rule.dashedRule
        , Html.div [ Html.Attributes.class "flex gap-6" ]
            [ statBlock "DAILY BURN" (formatAmount avgPerDay)
            , statBlock "AVG / ENTRY" (formatAmount avgPerEntry)
            ]
        ]


statBlock : String -> String -> Html Msg
statBlock label_ value =
    Html.div [ Html.Attributes.class "flex-1" ]
        [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss" ]
            [ Html.text label_ ]
        , Html.div [ Html.Attributes.class "font-display text-xl font-bold text-forest mt-0.5" ]
            [ Html.text value ]
        ]


last7DaysValues : List Entry.EffectiveEntry -> List Float
last7DaysValues entries =
    let
        dates =
            Entry.uniqueDates entries
                |> List.sort
                |> List.reverse
                |> List.take 7
                |> List.reverse

        totalForDate d =
            entries
                |> List.filter (\e -> e.date == d)
                |> List.map .amount
                |> List.sum
    in
    List.map totalForDate dates


sparkline : List Float -> Svg.Svg msg
sparkline values =
    let
        safeValues =
            if List.isEmpty values then [ 0 ] else values

        maxVal =
            Maybe.withDefault 1 (List.maximum safeValues)

        safeMax =
            if maxVal <= 0 then 1 else maxVal

        barCount =
            List.length safeValues

        barWidth =
            100 / toFloat barCount

        bars =
            List.indexedMap
                (\i v ->
                    let
                        height_ =
                            (v / safeMax) * 30
                    in
                    Svg.rect
                        [ Svg.Attributes.x (String.fromFloat (toFloat i * barWidth))
                        , Svg.Attributes.y (String.fromFloat (30 - height_))
                        , Svg.Attributes.width (String.fromFloat (barWidth * 0.75))
                        , Svg.Attributes.height (String.fromFloat height_)
                        , Svg.Attributes.fill "#b85c38"
                        , Svg.Attributes.rx "1"
                        ]
                        []
                )
                safeValues
    in
    Svg.svg
        [ Svg.Attributes.viewBox "0 0 100 30"
        , Svg.Attributes.class "w-24 h-10"
        ]
        bars


viewBody : AuthState -> Html Msg
viewBody model =
    let
        entries =
            case model.expensesState of
                ExpensesReady es -> es
                _                -> []

        total =
            List.sum (List.map .amount entries)

        numDays =
            List.length (Entry.uniqueDates entries)

        numEntries =
            List.length entries

        avgPerDay =
            if numDays > 0 then total / toFloat numDays else 0

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
            case model.trips of
                TripsLoaded trips ->
                    (Trips.selectedTrip trips).startDate

                _ ->
                    ""

        daysIn =
            if tripStart /= "" && model.today /= "" then
                isoToDayCount model.today - isoToDayCount tripStart + 1
            else
                0
    in
    Html.div []
        [ UI.Rule.kicker "AT A GLANCE"
        , UI.Card.subCard
            [ Html.div [ Html.Attributes.class "grid grid-cols-2 gap-3" ]
                [ statCard "MEDIAN" (formatAmount median)
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
            ]
        , if List.isEmpty entries then
            Html.text ""

          else
            Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker "TOP CATEGORIES"
                , UI.Card.subCard
                    [ viewCategoryChart entries ]
                ]
        , if numDays > 1 then
            Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker "DAILY SPENDING"
                , UI.Card.subCard
                    [ viewDailyChart entries ]
                ]

          else
            Html.text ""
        , if numDays > 1 then
            Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker "CUMULATIVE SPEND"
                , UI.Card.subCard
                    [ viewCumulativeChart entries ]
                ]

          else
            Html.text ""
        , if List.isEmpty top5 then
            Html.text ""

          else
            Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker "TOP 5 LARGEST"
                , UI.Card.subCard
                    [ Html.div []
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
        ]


statCard : String -> String -> Html Msg
statCard label_ value =
    Html.div []
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
