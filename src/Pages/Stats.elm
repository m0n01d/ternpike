module Pages.Stats exposing (viewTab)

import Chart as C
import Chart.Attributes as CA
import Chart.Events as CE
import Chart.Item as CI
import Data.Category as Category
import Data.Entry as Entry
import Data.StatsGranularity as StatsGranularity exposing (Granularity(..))
import Data.StatsHover exposing (CumulativePoint, DailyDay)
import Data.TripId as TripId
import Data.Trips as Trips exposing (TripsState(..))
import Dict
import Helpers exposing (formatAmount, isoToDayCount)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Routing
import Set
import Svg
import Svg.Attributes
import Types exposing (AuthState, Msg(..))
import UI.BudgetBar
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

        activeTrip =
            case ( Routing.routeTripId model.route, model.trips ) of
                ( Just tripId, TripsLoaded trips ) ->
                    Trips.findTrip tripId trips

                _ ->
                    Nothing

        tripStart =
            activeTrip
                |> Maybe.map .startDate
                |> Maybe.withDefault ""

        budget =
            activeTrip
                |> Maybe.map .budget
                |> Maybe.withDefault 0

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
        , if budget > 0 then
            UI.BudgetBar.viewLine { spent = total, budget = budget }

          else
            UI.Rule.dashedRule
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
            let
                resolved =
                    Maybe.withDefault (StatsGranularity.fromSpan (spanDays entries))
                        model.statsGranularity
            in
            Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker (StatsGranularity.kicker resolved)
                , UI.Card.subCard
                    [ viewDailyChart resolved model.statsHover.dailyBars entries ]
                ]

          else
            Html.text ""
        , if numDays > 1 then
            Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker "CUMULATIVE SPEND"
                , UI.Card.subCard
                    [ viewCumulativeChart model.statsHover.cumulativePoints entries ]
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


viewDailyChart : Granularity -> List (CI.One DailyDay CI.Bar) -> List Entry.EffectiveEntry -> Html Msg
viewDailyChart resolved hovered entries =
    let
        sortedDates =
            Entry.uniqueDates entries |> List.reverse

        firstDate =
            List.head sortedDates |> Maybe.withDefault ""

        lastDate =
            sortedDates |> List.reverse |> List.head |> Maybe.withDefault ""

        days : List DailyDay
        days =
            binEntries resolved entries

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
        [ granularitySelector resolved
        , Html.div [ Html.Attributes.class "flex items-center justify-between mb-2" ]
            [ Html.div [ Html.Attributes.class "text-[11px] font-mono text-muted" ]
                [ Html.text rangeLabel ]
            , scrubHint
            ]
        , C.chart
            [ CA.height 160
            , CA.margin { top = 8, bottom = 8, left = 44, right = 8 }
            , CE.onMouseMove HoverDailyBars (CE.getNearest CI.bars)
            , CE.onMouseLeave (HoverDailyBars [])
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
            , C.each hovered <|
                \_ item ->
                    [ C.tooltip item
                        [ CA.onTopOrBottom, CA.background "#fffaf2", CA.border UI.Theme.colorTan ]
                        []
                        (dailyTooltipContent resolved (CI.getData item))
                    ]
            ]
        ]


granularitySelector : Granularity -> Html Msg
granularitySelector resolved =
    Html.div [ Html.Attributes.class "flex flex-wrap gap-1 mb-2" ]
        (List.map (granularityChip resolved) StatsGranularity.all)


granularityChip : Granularity -> Granularity -> Html Msg
granularityChip resolved chip =
    let
        isActive =
            chip == resolved

        baseClass =
            "text-[11px] font-mono px-2.5 py-1 rounded-full border transition-colors"

        toneClass =
            if isActive then
                " bg-rust text-cream border-rust"

            else
                " bg-transparent text-muted border-tan/60 hover:border-muted"
    in
    Html.button
        [ Html.Attributes.class (baseClass ++ toneClass)
        , Html.Attributes.type_ "button"
        , Html.Events.onClick (SetStatsGranularity chip)
        ]
        [ Html.text (StatsGranularity.label chip) ]


scrubHint : Html msg
scrubHint =
    Html.button
        [ Html.Attributes.class "group relative inline-flex items-center justify-center w-5 h-5 rounded-full border border-tan/60 text-[10px] font-mono text-muted hover:text-moss hover:border-muted focus:outline-none focus:text-moss focus:border-muted"
        , Html.Attributes.type_ "button"
        , Html.Attributes.attribute "aria-label" "How to read this chart"
        ]
        [ Html.text "i"
        , Html.span
            [ Html.Attributes.class "hidden group-hover:block group-focus:block absolute z-10 right-0 top-full mt-1 px-2 py-1 whitespace-nowrap rounded border border-tan bg-[#fffaf2] text-[11px] font-mono text-moss shadow-sm pointer-events-none"
            ]
            [ Html.text "swipe across the chart to inspect" ]
        ]


dailyTooltipContent : Granularity -> DailyDay -> List (Html Never)
dailyTooltipContent resolved d =
    let
        header =
            if d.date == d.endDate then
                formatDateShort d.date

            else if resolved == Monthly then
                formatMonthLong d.date

            else
                formatDateShort d.date ++ " – " ++ formatDateShort d.endDate
    in
    [ Html.div [ Html.Attributes.class "font-mono text-[11px] text-moss" ]
        [ Html.text header ]
    , Html.div [ Html.Attributes.class "font-mono text-sm text-rust" ]
        [ Html.text (formatAmount d.total) ]
    ]


{-| Inclusive day count between first and last unique date with spend.
Returns 0 when there are no entries.
-}
spanDays : List Entry.EffectiveEntry -> Int
spanDays entries =
    let
        sorted =
            Entry.uniqueDates entries |> List.reverse
    in
    case ( List.head sorted, sorted |> List.reverse |> List.head ) of
        ( Just first, Just last ) ->
            isoToDayCount last - isoToDayCount first + 1

        _ ->
            0


{-| Aggregate expenses into the bins for a resolved granularity. Empty
weeks/months inside the trip span are included as zero-height bars so the
time axis reads linearly. Daily mode preserves the historical
"only days with spend" behaviour to avoid surprise.
-}
binEntries : Granularity -> List Entry.EffectiveEntry -> List DailyDay
binEntries resolved entries =
    let
        sortedDates =
            Entry.uniqueDates entries |> List.reverse

        firstDate =
            List.head sortedDates |> Maybe.withDefault ""

        lastDate =
            sortedDates |> List.reverse |> List.head |> Maybe.withDefault ""

        totalBetween : String -> String -> Float
        totalBetween startIso endIso =
            entries
                |> List.filter (\e -> e.date >= startIso && e.date <= endIso)
                |> List.map .amount
                |> List.sum
    in
    case resolved of
        Daily ->
            sortedDates
                |> List.map
                    (\date ->
                        { date = date
                        , endDate = date
                        , total = totalBetween date date
                        }
                    )

        Weekly ->
            if firstDate == "" then
                []

            else
                buildWeeklyBins firstDate lastDate totalBetween

        Monthly ->
            if firstDate == "" then
                []

            else
                buildMonthlyBins firstDate lastDate totalBetween


buildWeeklyBins : String -> String -> (String -> String -> Float) -> List DailyDay
buildWeeklyBins firstDate lastDate totalBetween =
    let
        firstCount =
            isoToDayCount firstDate

        lastCount =
            isoToDayCount lastDate

        weekCount =
            (lastCount - firstCount) // 7 + 1
    in
    List.range 0 (weekCount - 1)
        |> List.map
            (\i ->
                let
                    startCount =
                        firstCount + i * 7

                    endCount =
                        min lastCount (startCount + 6)

                    startIso =
                        dayCountToIso startCount

                    endIso =
                        dayCountToIso endCount
                in
                { date = startIso
                , endDate = endIso
                , total = totalBetween startIso endIso
                }
            )


buildMonthlyBins : String -> String -> (String -> String -> Float) -> List DailyDay
buildMonthlyBins firstDate lastDate totalBetween =
    let
        ( fy, fm ) =
            parseYearMonth firstDate

        ( ly, lm ) =
            parseYearMonth lastDate

        monthCount =
            (ly - fy) * 12 + (lm - fm) + 1
    in
    List.range 0 (monthCount - 1)
        |> List.map
            (\i ->
                let
                    yearOffset =
                        (fm - 1 + i) // 12

                    year =
                        fy + yearOffset

                    month =
                        modBy 12 (fm - 1 + i) + 1

                    startIso =
                        formatIso year month 1

                    -- "31" is fine as the upper-bound of a string filter:
                    -- all dates in this month compare ≤ "YYYY-MM-31", and
                    -- the tooltip header for monthly mode renders via
                    -- `formatMonthLong d.date` so the exact end day is
                    -- never shown to the user.
                    endIso =
                        formatIso year month 31
                in
                { date = startIso
                , endDate = endIso
                , total = totalBetween startIso endIso
                }
            )


parseYearMonth : String -> ( Int, Int )
parseYearMonth iso =
    case String.split "-" iso of
        y :: m :: _ ->
            ( String.toInt y |> Maybe.withDefault 0
            , String.toInt m |> Maybe.withDefault 1
            )

        _ ->
            ( 0, 1 )


formatIso : Int -> Int -> Int -> String
formatIso y m d =
    String.fromInt y
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt m)
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt d)


{-| Inverse of `Helpers.isoToDayCount`.

`isoToDayCount` uses a naive `y * 365 + monthOffset + d` calendar (no leap
years). We invert the same way: year is `(count - 1) // 365` and the
remainder picks the month/day off the same `monthOffsets` table. The
calendar is fictional but self-consistent — adding 7 to a day count and
piping back through `dayCountToIso` reliably advances the ISO string by
exactly seven entries, which is all the weekly-bin code needs.

    dayCountToIso (Helpers.isoToDayCount "2026-04-30")
    --> "2026-04-30"

    dayCountToIso (Helpers.isoToDayCount "2026-04-30" + 7)
    --> "2026-05-07"

-}
dayCountToIso : Int -> String
dayCountToIso count =
    let
        y =
            (count - 1) // 365

        remainder =
            count - y * 365

        ( m, d ) =
            findMonthDay 1 0 monthEnds remainder
    in
    formatIso y m d


monthEnds : List Int
monthEnds =
    [ 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365 ]


findMonthDay : Int -> Int -> List Int -> Int -> ( Int, Int )
findMonthDay m prevEnd ends remainder =
    case ends of
        end :: rest ->
            if remainder <= end then
                ( m, remainder - prevEnd )

            else
                findMonthDay (m + 1) end rest remainder

        [] ->
            -- Should not happen given valid `count`; fall back to Dec 31.
            ( 12, 31 )


formatMonthLong : String -> String
formatMonthLong iso =
    case String.split "-" iso of
        y :: m :: _ ->
            monthAbbr m ++ " " ++ y

        _ ->
            iso


viewCumulativeChart : List (CI.One CumulativePoint CI.Dot) -> List Entry.EffectiveEntry -> Html Msg
viewCumulativeChart hovered entries =
    let
        sorted =
            Entry.uniqueDates entries |> List.reverse

        points : List CumulativePoint
        points =
            List.indexedMap
                (\i date ->
                    { date = date
                    , x = toFloat (i + 1)
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
    Html.div []
        [ Html.div [ Html.Attributes.class "flex items-center justify-end mb-1" ]
            [ scrubHint ]
        , C.chart
            [ CA.height 180
            , CA.margin { top = 16, bottom = 24, left = 44, right = 12 }
            , CE.onMouseMove HoverCumulativePoints (CE.getNearest CI.dots)
            , CE.onMouseLeave (HoverCumulativePoints [])
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
            , C.each hovered <|
                \_ item ->
                    [ C.tooltip item
                        [ CA.onTopOrBottom, CA.background "#fffaf2", CA.border UI.Theme.colorTan ]
                        []
                        (cumulativeTooltipContent (CI.getData item))
                    ]
            ]
        ]


cumulativeTooltipContent : CumulativePoint -> List (Html Never)
cumulativeTooltipContent p =
    [ Html.div [ Html.Attributes.class "font-mono text-[11px] text-moss" ]
        [ Html.text (formatDateShort p.date) ]
    , Html.div [ Html.Attributes.class "font-mono text-sm text-rust" ]
        [ Html.text (formatAmount p.y) ]
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
