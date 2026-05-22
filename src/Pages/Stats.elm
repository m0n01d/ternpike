module Pages.Stats exposing (viewTab)

import Chart as C
import Chart.Attributes as CA
import Chart.Events as CE
import Chart.Item as CI
import Data.Category as Category
import Data.DateField as DateField exposing (DateField)
import Data.Entry as Entry
import Data.Money as Money exposing (Money)
import Data.Stats exposing (StatsMode(..))
import Data.StatsGranularity as StatsGranularity exposing (Granularity(..))
import Data.StatsHover exposing (CumulativePoint, DailyDay)
import Data.TripId as TripId
import Data.Trips as Trips exposing (TripsState(..))
import Dict
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
import UI.Mascot
import UI.Rule
import UI.Skeleton
import UI.Theme


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    let
        mode =
            statsMode as_
    in
    { actions = []
    , body = viewBody as_ mode
    , hero = viewHero as_ mode
    }



-- StatsLoading until the current trip's bulk fetch has completed; then
-- StatsReady with the resolved entries derived from the cache.


statsMode : AuthState -> StatsMode
statsMode as_ =
    case Routing.routeTripId as_.route of
        Just tripId ->
            if Set.member (TripId.toString tripId) as_.tripLoaded then
                StatsReady
                    (Entry.resolve
                        (as_.expenses |> Dict.get (TripId.toString tripId) |> Maybe.withDefault Dict.empty |> Dict.values)
                        (Dict.values as_.amendments)
                        (Dict.values as_.voids)
                        tripId
                    )

            else
                StatsLoading

        Nothing ->
            StatsLoading


viewHero : AuthState -> StatsMode -> Html Msg
viewHero model mode =
    case mode of
        StatsLoading ->
            viewSkeletonHero

        StatsReady entries ->
            viewHeroReady model entries


viewSkeletonHero : Html Msg
viewSkeletonHero =
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "TOTAL SPENT" ]
        , UI.Skeleton.text "h-12 w-40"
        , UI.Skeleton.text "h-3 w-32 mt-2"
        , UI.Rule.dashedRule
        , Html.div [ Html.Attributes.class "flex gap-6" ]
            [ skeletonStatBlock
            , skeletonStatBlock
            ]
        ]


skeletonStatBlock : Html Msg
skeletonStatBlock =
    Html.div [ Html.Attributes.class "flex-1" ]
        [ UI.Skeleton.text "h-3 w-16 mb-2"
        , UI.Skeleton.text "h-5 w-20"
        ]


viewHeroReady : AuthState -> List Entry.EffectiveEntry -> Html Msg
viewHeroReady model entries =
    let
        total =
            Money.sum (List.map .amount entries)

        numDays =
            List.length (Entry.uniqueDates entries)

        numEntries =
            List.length entries

        totalCents =
            Money.toCents total

        avgPerDay =
            if numDays > 0 then
                Money.fromCents (totalCents // numDays)

            else
                Money.zero

        avgPerEntry =
            if numEntries > 0 then
                Money.fromCents (totalCents // numEntries)

            else
                Money.zero

        activeTrip =
            case ( Routing.routeTripId model.route, model.trips ) of
                ( Just tripId, TripsLoaded trips ) ->
                    Trips.findTrip tripId trips

                _ ->
                    Nothing

        tripStart =
            activeTrip
                |> Maybe.map .startDate

        budget =
            activeTrip
                |> Maybe.map .budget
                |> Maybe.withDefault Money.zero

        daysIn =
            tripDaysIn tripStart model.today

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
                    [ Html.text (Money.format total) ]
                , Html.div [ Html.Attributes.class "mt-2 text-xs font-mono tracking-wide text-muted" ]
                    [ Html.text (String.fromInt numEntries ++ " ENTRIES · DAY " ++ dayOfTripStr) ]
                ]
            , sparkline last7
            ]
        , if not (Money.isZero budget) then
            UI.BudgetBar.viewLine { budget = budget, spent = total }

          else
            UI.Rule.dashedRule
        , Html.div [ Html.Attributes.class "flex gap-6" ]
            [ statBlock "DAILY BURN" (Money.format avgPerDay)
            , statBlock "AVG / ENTRY" (Money.format avgPerEntry)
            ]
        ]


{-| Number of inclusive days from the trip's start date to "today".
`tripStart` is a `Maybe DateField` because the active trip is itself a
`Maybe Trip` (no selection yet). `todayIso` is still String because
`AuthState.today` moves to `DateField` in R5/R7 — until then this is
the boundary. Returns 0 when start is missing, today is unparseable,
or the trip's start is the legacy epoch sentinel ("no start date set").
-}
tripDaysIn : Maybe DateField -> String -> Int
tripDaysIn tripStart todayIso =
    case ( tripStart, DateField.fromIso todayIso ) of
        ( Just start, Just today ) ->
            if DateField.toIso start == "1970-01-01" then
                0

            else
                DateField.diffDays start today + 1

        _ ->
            0


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
                |> List.sortWith DateField.compare
                |> List.reverse
                |> List.take 7
                |> List.reverse

        totalForDate d =
            entries
                |> List.filter (\e -> DateField.compare e.date d == EQ)
                |> List.map .amount
                |> Money.sum
                |> Money.toCents
                |> toFloat
                |> (\c -> c / 100)
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


viewBody : AuthState -> StatsMode -> Html Msg
viewBody model mode =
    case mode of
        StatsLoading ->
            viewSkeletonBody

        StatsReady [] ->
            viewEmptyState

        StatsReady entries ->
            viewBodyReady model entries


viewSkeletonBody : Html Msg
viewSkeletonBody =
    Html.div []
        [ UI.Rule.kicker "AT A GLANCE"
        , UI.Card.subCard
            [ Html.div [ Html.Attributes.class "grid grid-cols-2 gap-3" ]
                (List.repeat 5 skeletonStatCard)
            ]
        ]


skeletonStatCard : Html Msg
skeletonStatCard =
    Html.div []
        [ UI.Skeleton.text "h-3 w-20 mb-2"
        , UI.Skeleton.text "h-6 w-24"
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


viewBodyReady : AuthState -> List Entry.EffectiveEntry -> Html Msg
viewBodyReady model entries =
    let
        numDays =
            List.length (Entry.uniqueDates entries)

        numEntries =
            List.length entries

        avgPerDayCents =
            if numDays > 0 then
                Money.toCents (Money.sum (List.map .amount entries)) // numDays

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
                |> List.sortBy (\e -> negate (Money.toCents e.amount))
                |> List.take 5

        tripStart =
            case model.trips of
                TripsLoaded trips ->
                    Just (Trips.selectedTrip trips).startDate

                _ ->
                    Nothing

        daysIn =
            tripDaysIn tripStart model.today
    in
    Html.div []
        [ UI.Rule.kicker "AT A GLANCE"
        , UI.Card.subCard
            [ Html.div [ Html.Attributes.class "grid grid-cols-2 gap-3" ]
                [ statCard "MEDIAN" (Money.format median)
                , statCard "TOP CATEGORY"
                    (topCat
                        |> Maybe.map (\c -> Category.icon c ++ " " ++ Category.label c)
                        |> Maybe.withDefault "—"
                    )
                , if numDays > 1 then
                    statCard "BIGGEST DAY"
                        (bigDay
                            |> Maybe.map (\( d, t ) -> String.slice 5 10 (DateField.toIso d) ++ "  " ++ Money.format t)
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
                    (if avgPerDayCents > 0 then
                        Money.format (Money.fromCents (avgPerDayCents * 30))

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
                                        , Html.div [ Html.Attributes.class "text-[11px] text-muted" ] [ Html.text (DateField.toIso entry.date) ]
                                        ]
                                    , Html.span [ Html.Attributes.class "font-mono text-rust text-base" ]
                                        [ Html.text (Money.format entry.amount) ]
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
                                |> Money.sum
                        }
                    )
                |> List.filter (\r -> Money.toCents r.total > 0)
                |> List.sortBy (\r -> negate (Money.toCents r.total))

        maxTotalCents =
            rows
                |> List.map (\r -> Money.toCents r.total)
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
                        , maxTotalCents = maxTotalCents
                        , row = r
                        }
                )
                rows
            )


categoryRow :
    { isLast : Bool
    , maxTotalCents : Int
    , row : { cat : Category.Category, total : Money }
    }
    -> Html Msg
categoryRow { isLast, maxTotalCents, row } =
    let
        pct =
            if maxTotalCents > 0 then
                100 * toFloat (Money.toCents row.total) / toFloat maxTotalCents

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
            [ Html.text (Money.format row.total) ]
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
            List.head sortedDates |> Maybe.map DateField.toIso |> Maybe.withDefault ""

        lastDate =
            sortedDates |> List.reverse |> List.head |> Maybe.map DateField.toIso |> Maybe.withDefault ""

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
                , CA.format formatDollars
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
        [ Html.text (formatDollars d.total) ]
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
            DateField.diffDays first last + 1

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
            List.head sortedDates

        lastDate =
            sortedDates |> List.reverse |> List.head

        totalBetweenIso : String -> String -> Float
        totalBetweenIso startIso endIso =
            entries
                |> List.filter
                    (\e ->
                        let
                            iso =
                                DateField.toIso e.date
                        in
                        iso >= startIso && iso <= endIso
                    )
                |> List.map .amount
                |> Money.sum
                |> Money.toCents
                |> toFloat
                |> (\c -> c / 100)
    in
    case resolved of
        Daily ->
            sortedDates
                |> List.map
                    (\date ->
                        let
                            iso =
                                DateField.toIso date
                        in
                        { date = iso
                        , endDate = iso
                        , total = totalBetweenIso iso iso
                        }
                    )

        Weekly ->
            case ( firstDate, lastDate ) of
                ( Just first, Just last ) ->
                    buildWeeklyBins first last totalBetweenIso

                _ ->
                    []

        Monthly ->
            case ( firstDate, lastDate ) of
                ( Just first, Just last ) ->
                    buildMonthlyBins (DateField.toIso first) (DateField.toIso last) totalBetweenIso

                _ ->
                    []


buildWeeklyBins : DateField -> DateField -> (String -> String -> Float) -> List DailyDay
buildWeeklyBins firstDate lastDate totalBetween =
    let
        firstIso =
            DateField.toIso firstDate

        firstCount =
            isoToNaiveDayCount firstIso

        lastCount =
            isoToNaiveDayCount (DateField.toIso lastDate)

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


{-| Naive day-count used by the weekly-bin code: `y * 365 + monthOffset + d`,
no leap years. Matches the now-deleted `Helpers.isoToDayCount` byte-for-byte
so the weekly-bin layout doesn't shift during the typed-primitives
migration. R5 may revisit this once `Trip.startDate` / `today` move to
`DateField` — at that point we can use `DateField.diffDays` end-to-end and
drop these naive helpers.
-}
isoToNaiveDayCount : String -> Int
isoToNaiveDayCount s =
    case List.filterMap String.toInt (String.split "-" s) of
        [ y, m, d ] ->
            let
                monthOffsets =
                    [ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 ]

                offset =
                    List.drop (m - 1) monthOffsets |> List.head |> Maybe.withDefault 0
            in
            y * 365 + offset + d

        _ ->
            0


{-| Inverse of `isoToNaiveDayCount`.

Year is `(count - 1) // 365` and the remainder picks the month/day off the
same `monthOffsets` table. The calendar is fictional but self-consistent —
adding 7 to a day count and piping back through `dayCountToIso` reliably
advances the ISO string by exactly seven entries, which is all the
weekly-bin code needs.

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
                    { date = DateField.toIso date
                    , x = toFloat (i + 1)
                    , y =
                        entries
                            |> List.filter (\e -> DateField.compare e.date date /= GT)
                            |> List.map .amount
                            |> Money.sum
                            |> Money.toCents
                            |> toFloat
                            |> (\c -> c / 100)
                    }
                )
                sorted

        firstDate =
            List.head sorted |> Maybe.map DateField.toIso |> Maybe.withDefault ""

        lastDate =
            sorted |> List.reverse |> List.head |> Maybe.map DateField.toIso |> Maybe.withDefault ""

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
                , CA.format formatDollars
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
                [ Svg.text (formatDollars finalTotal) ]
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
        [ Html.text (formatDollars p.y) ]
    ]


formatDateShort : String -> String
formatDateShort iso =
    case String.split "-" iso of
        [ _, m, d ] ->
            monthAbbr m ++ " " ++ (String.toInt d |> Maybe.withDefault 0 |> String.fromInt)

        _ ->
            iso


{-| Format a chart-axis Float (already in dollars) as `"$X.YY"`. Mirrors
`Money.format` but works on the `Float`-flavoured `total` / `y` fields
that the elm-charts API requires. R5 may flip the chart records to
`Money` and let us drop this.
-}
formatDollars : Float -> String
formatDollars dollars =
    let
        cents =
            round (dollars * 100)
    in
    Money.format (Money.fromCents cents)


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
