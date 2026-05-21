module Pages.Stats exposing (viewTab)

import Chart as C
import Chart.Attributes as CA
import Data.Category as Category
import Data.Entry as Entry
import Data.TripId as TripId
import Data.Trips as Trips exposing (TripsState(..))
import Dict
import Helpers exposing (formatAmount, isoToDayCount)
import Html exposing (Html)
import Html.Attributes
import Routing
import Set
import Svg
import Svg.Attributes
import Types exposing (AuthState, Msg)
import UI.Card
import UI.Rule
import UI.Theme


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    let
        entries =
            entriesForCurrentTrip as_
    in
    { actions = []
    , body = viewBody as_ entries
    , hero = viewHero as_ entries
    }



-- Resolved entries for the route's trip, or [] if not loaded yet.


entriesForCurrentTrip : AuthState -> List Entry.EffectiveEntry
entriesForCurrentTrip as_ =
    case Routing.routeTripId as_.route of
        Just tripId ->
            if Set.member (TripId.toString tripId) as_.tripLoaded then
                Entry.resolve
                    (as_.expenses |> Dict.get (TripId.toString tripId) |> Maybe.withDefault Dict.empty |> Dict.values)
                    (Dict.values as_.amendments)
                    (Dict.values as_.voids)
                    tripId

            else
                []

        Nothing ->
            []


viewHero : AuthState -> List Entry.EffectiveEntry -> Html Msg
viewHero model entries =
    let
        total =
            List.sum (List.map .amount entries)

        numDays =
            List.length (Entry.uniqueDates entries)

        numEntries =
            List.length entries

        avgPerDay =
            if numDays > 0 then
                total / toFloat numDays

            else
                0

        avgPerEntry =
            if numEntries > 0 then
                total / toFloat numEntries

            else
                0

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
            if daysIn > 0 then
                String.fromInt daysIn

            else
                "—"

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
            if List.isEmpty values then
                [ 0 ]

            else
                values

        maxVal =
            Maybe.withDefault 1 (List.maximum safeValues)

        safeMax =
            if maxVal <= 0 then
                1

            else
                maxVal

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


viewBody : AuthState -> List Entry.EffectiveEntry -> Html Msg
viewBody model entries =
    let
        total =
            List.sum (List.map .amount entries)

        numDays =
            List.length (Entry.uniqueDates entries)

        numEntries =
            List.length entries

        avgPerDay =
            if numDays > 0 then
                total / toFloat numDays

            else
                0

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
                    (if daysIn > 0 then
                        String.fromInt daysIn

                     else
                        "—"
                    )
                , statCard "PROJ / 30 DAYS"
                    (if avgPerDay > 0 then
                        formatAmount (avgPerDay * 30)

                     else
                        "—"
                    )
                ]
            ]
        , if List.isEmpty entries then
            Html.text ""

          else
            Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker "TOP CATEGORIES"
                , UI.Card.subCard
                    [ viewCategoryList entries ]
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
                                            ++ (if i < List.length top5 - 1 then
                                                    "border-b border-tan"

                                                else
                                                    ""
                                               )
                                        )
                                    ]
                                    [ Html.span [ Html.Attributes.class "text-moss font-mono w-5" ]
                                        [ Html.text (String.fromInt (i + 1) ++ ".") ]
                                    , Html.span [ Html.Attributes.class "text-lg leading-none" ] [ Html.text (Category.icon entry.category) ]
                                    , Html.div [ Html.Attributes.class "flex-1" ]
                                        [ Html.div [ Html.Attributes.class "text-sm text-ink" ]
                                            [ Html.text
                                                (if entry.note /= "" then
                                                    entry.note

                                                 else
                                                    Category.label entry.category
                                                )
                                            ]
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


viewCategoryList : List Entry.EffectiveEntry -> Html Msg
viewCategoryList entries =
    let
        rows =
            Category.all
                |> List.map
                    (\cat ->
                        { cat = cat
                        , total =
                            entries
                                |> List.filter (\e -> e.category == cat)
                                |> List.map .amount
                                |> List.sum
                        }
                    )
                |> List.filter (\r -> r.total > 0)
                |> List.sortBy (\r -> negate r.total)

        maxTotal =
            rows
                |> List.map .total
                |> List.maximum
                |> Maybe.withDefault 1
    in
    if List.isEmpty rows then
        Html.text ""

    else
        Html.div []
            (List.indexedMap
                (\i r ->
                    categoryRow
                        { isLast = i == List.length rows - 1
                        , maxTotal = maxTotal
                        , row = r
                        }
                )
                rows
            )


categoryRow :
    { isLast : Bool
    , maxTotal : Float
    , row : { cat : Category.Category, total : Float }
    }
    -> Html Msg
categoryRow { isLast, maxTotal, row } =
    let
        pct =
            if maxTotal > 0 then
                100 * row.total / maxTotal

            else
                0
    in
    Html.div
        [ Html.Attributes.class
            ("flex items-center gap-3 py-2 "
                ++ (if isLast then
                        ""

                    else
                        "border-b border-tan/60"
                   )
            )
        ]
        [ Html.span [ Html.Attributes.class "text-lg leading-none w-5 shrink-0" ]
            [ Html.text (Category.icon row.cat) ]
        , Html.span [ Html.Attributes.class "text-sm text-ink w-20 shrink-0" ]
            [ Html.text (Category.label row.cat) ]
        , Html.div [ Html.Attributes.class "flex-1 min-w-0" ]
            [ categoryBar (Category.color row.cat) pct ]
        , Html.span [ Html.Attributes.class "font-mono text-sm text-rust w-20 text-right shrink-0" ]
            [ Html.text (formatAmount row.total) ]
        ]


categoryBar : String -> Float -> Svg.Svg msg
categoryBar fill pct =
    Svg.svg
        [ Svg.Attributes.viewBox "0 0 100 8"
        , Svg.Attributes.preserveAspectRatio "none"
        , Svg.Attributes.class "block w-full h-2"
        ]
        [ Svg.rect
            [ Svg.Attributes.x "0"
            , Svg.Attributes.y "0"
            , Svg.Attributes.width "100"
            , Svg.Attributes.height "8"
            , Svg.Attributes.rx "1"
            , Svg.Attributes.fill "#e8e0c8"
            ]
            []
        , Svg.rect
            [ Svg.Attributes.x "0"
            , Svg.Attributes.y "0"
            , Svg.Attributes.width (String.fromFloat pct)
            , Svg.Attributes.height "8"
            , Svg.Attributes.rx "1"
            , Svg.Attributes.fill fill
            ]
            []
        ]


viewDailyChart : List Entry.EffectiveEntry -> Html Msg
viewDailyChart entries =
    let
        sortedDates =
            Entry.uniqueDates entries |> List.reverse

        days =
            sortedDates
                |> List.map
                    (\date ->
                        { date = date
                        , total =
                            entries
                                |> List.filter (\e -> e.date == date)
                                |> List.map .amount
                                |> List.sum
                        }
                    )

        firstDate =
            List.head sortedDates |> Maybe.withDefault ""

        lastDate =
            sortedDates |> List.reverse |> List.head |> Maybe.withDefault ""

        rangeLabel =
            if firstDate == "" then
                ""

            else
                formatDateShort firstDate
                    ++ " – "
                    ++ formatDateShort lastDate
                    ++ " · "
                    ++ String.fromInt (List.length sortedDates)
                    ++ " days"
    in
    Html.div []
        [ Html.div [ Html.Attributes.class "text-[11px] font-mono text-muted mb-2" ]
            [ Html.text rangeLabel ]
        , C.chart
            [ CA.height 160
            , CA.margin { top = 8, bottom = 8, left = 44, right = 8 }
            ]
            [ C.grid [ CA.color UI.Theme.colorTan, CA.dashed [ 2, 3 ] ]
            , C.yLabels
                [ CA.amount 4
                , CA.format (\v -> formatAmount v)
                , CA.fontSize 10
                , CA.color UI.Theme.colorMuted
                , CA.withGrid
                ]
            , C.bars []
                [ C.bar .total [ CA.color UI.Theme.colorRust ] ]
                days
            ]
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

        firstDate =
            List.head sorted |> Maybe.withDefault ""

        lastDate =
            sorted |> List.reverse |> List.head |> Maybe.withDefault ""

        finalTotal =
            points
                |> List.reverse
                |> List.head
                |> Maybe.map .y
                |> Maybe.withDefault 0
    in
    C.chart
        [ CA.height 180
        , CA.margin { top = 16, bottom = 24, left = 44, right = 12 }
        ]
        [ C.yLabels
            [ CA.amount 4
            , CA.format (\v -> formatAmount v)
            , CA.fontSize 10
            , CA.color UI.Theme.colorMuted
            , CA.withGrid
            ]
        , C.grid [ CA.color UI.Theme.colorTan, CA.dashed [ 2, 3 ] ]
        , C.series .x
            [ C.interpolated .y
                [ CA.color UI.Theme.colorRust
                , CA.width 2
                , CA.opacity 0.18
                ]
                []
            ]
            points
        , C.labelAt .min
            .min
            [ CA.moveDown 16
            , CA.fontSize 10
            , CA.color UI.Theme.colorMuted
            , CA.alignLeft
            ]
            [ Svg.text (formatDateShort firstDate) ]
        , C.labelAt .max
            .min
            [ CA.moveDown 16
            , CA.fontSize 10
            , CA.color UI.Theme.colorMuted
            , CA.alignRight
            ]
            [ Svg.text (formatDateShort lastDate) ]
        , C.labelAt .max
            (\_ -> finalTotal)
            [ CA.moveUp 8
            , CA.moveLeft 2
            , CA.fontSize 11
            , CA.color UI.Theme.colorRust
            , CA.alignRight
            ]
            [ Svg.text (formatAmount finalTotal) ]
        ]


formatDateShort : String -> String
formatDateShort iso =
    case String.split "-" iso of
        [ _, m, d ] ->
            monthAbbr m ++ " " ++ (String.toInt d |> Maybe.withDefault 0 |> String.fromInt)

        _ ->
            iso


monthAbbr : String -> String
monthAbbr m =
    case m of
        "01" ->
            "Jan"

        "02" ->
            "Feb"

        "03" ->
            "Mar"

        "04" ->
            "Apr"

        "05" ->
            "May"

        "06" ->
            "Jun"

        "07" ->
            "Jul"

        "08" ->
            "Aug"

        "09" ->
            "Sep"

        "10" ->
            "Oct"

        "11" ->
            "Nov"

        "12" ->
            "Dec"

        _ ->
            m
