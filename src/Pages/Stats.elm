module Pages.Stats exposing (viewTab)

import Chart as C
import Chart.Attributes as CA
import Data.Category as Category
import Data.Entry as Entry
import Helpers exposing (formatAmount, isoToDayCount)
import Html exposing (Html)
import Html.Attributes
import List.NonEmpty.Zipper as Zipper
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

        tripStart =
            (Zipper.current model.trips).startDate

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
