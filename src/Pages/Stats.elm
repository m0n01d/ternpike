module Pages.Stats exposing (viewTab)

import Chart as C
import Chart.Attributes as CA
import Chart.Events as CE
import Chart.Item as CI
import Data.Category as Category
import Data.Currency exposing (Currency)
import Data.DateField as DateField
import Data.Entry as Entry
import Data.Gallons
import Data.Money as Money exposing (Money)
import Data.PricePerGallon
import Data.Stats as Stats exposing (StatsMode(..))
import Data.StatsGranularity as StatsGranularity exposing (Granularity(..))
import Data.StatsHover exposing (CumulativePoint, DailyDay, PricePoint)
import Data.TripId as TripId
import Data.Trips as Trips exposing (TripsState(..))
import Dict
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Extra
import List.Extra
import Maybe.Extra
import Routing
import Set
import Svg
import Svg.Attributes
import Types exposing (AuthMsg_(..), AuthState, Msg(..))
import UI.BudgetBar
import UI.Card
import UI.Mascot
import UI.MoneyView
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


toPrimEntries : List Entry.EffectiveEntry -> List { date : String, amountCents : Int }
toPrimEntries entries =
    List.map (\e -> { date = DateField.toIso e.date, amountCents = Money.toCents e.amount }) entries


toFuelPrims : List Entry.EffectiveEntry -> List Stats.FuelPrim
toFuelPrims entries =
    entries
        |> List.filterMap
            (\e ->
                case e.fuelDetail of
                    Just fd ->
                        Just
                            { date = DateField.toIso e.date
                            , gallons = Maybe.map Data.Gallons.toFloat fd.gallons
                            , pricePerGallon = Maybe.map Data.PricePerGallon.toDollars fd.pricePerGallon
                            }

                    Nothing ->
                        Nothing
            )


viewHero : AuthState -> StatsMode -> Html Msg
viewHero model mode =
    case mode of
        StatsLoading ->
            viewSkeletonHero

        StatsReady entries ->
            viewHeroReady model entries


viewSkeletonHero : Html Msg
viewSkeletonHero =
    UI.Mascot.loading


viewHeroReady : AuthState -> List Entry.EffectiveEntry -> Html Msg
viewHeroReady model entries =
    let
        primEntries =
            toPrimEntries entries

        displayCurrency =
            Entry.primaryCurrency entries

        -- Derived scalars (total, burn, averages) are reported in a single
        -- currency, so they're computed over only the trip's primary-currency
        -- entries — never a meaningless CAD+USD cent sum. The hero TOTAL SPENT
        -- above shows the exact per-currency split. For an all-USD trip
        -- `primaryEntries == entries`, so nothing changes.
        primaryEntries =
            List.filter (\e -> e.currency == displayCurrency) entries

        isUsdOnly =
            List.all (\e -> e.currency == Data.Currency.USD) entries

        total =
            Money.sum (List.map .amount primaryEntries)

        numEntries =
            List.length entries

        totalCents =
            Money.toCents total

        primaryDayCount =
            List.length (Entry.uniqueDates primaryEntries)

        primaryEntryCount =
            List.length primaryEntries

        avgPerDay =
            if primaryDayCount > 0 then
                Money.fromCents (totalCents // primaryDayCount)

            else
                Money.zero

        avgPerEntry =
            if primaryEntryCount > 0 then
                Money.fromCents (totalCents // primaryEntryCount)

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
                |> Maybe.map (.startDate >> DateField.toIso)

        budget =
            activeTrip
                |> Maybe.map .budget
                |> Maybe.withDefault Money.zero

        daysIn =
            Stats.tripDaysIn tripStart (DateField.toIso model.today)

        dayOfTripStr =
            if daysIn > 0 then
                String.fromInt daysIn

            else
                "—"

        last7 =
            Stats.last7DaysValues primEntries
    in
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "TOTAL SPENT" ]
        , Html.div [ Html.Attributes.class "flex items-end justify-between gap-4" ]
            [ Html.div []
                [ Html.div [ Html.Attributes.class "font-display text-5xl font-black text-forest tracking-tight leading-none" ]
                    [ UI.MoneyView.totals (Entry.totalsByCurrency entries) ]
                , Html.div [ Html.Attributes.class "mt-2 text-xs font-mono tracking-wide text-muted" ]
                    [ Html.text (String.fromInt numEntries ++ " ENTRIES · DAY " ++ dayOfTripStr) ]
                ]
            , sparkline last7
            ]
        , if isUsdOnly && not (Money.isZero budget) then
            -- The budget is a USD figure; only compare it against spend when
            -- every entry is USD. A trip with any CAD spend hides the bar
            -- rather than show a cross-currency comparison.
            UI.BudgetBar.viewLine { budget = budget, spent = total }

          else
            UI.Rule.dashedRule
        , Html.div [ Html.Attributes.class "flex gap-6" ]
            [ statBlock "DAILY BURN" (UI.MoneyView.amount displayCurrency avgPerDay)
            , statBlock "AVG / ENTRY" (UI.MoneyView.amount displayCurrency avgPerEntry)
            ]
        ]


statBlock : String -> Html Msg -> Html Msg
statBlock label_ value =
    Html.div [ Html.Attributes.class "flex-1" ]
        [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss" ]
            [ Html.text label_ ]
        , Html.div [ Html.Attributes.class "font-display text-xl font-bold text-forest mt-0.5" ]
            [ value ]
        ]


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
        primEntries =
            toPrimEntries entries

        displayCurrency =
            Entry.primaryCurrency entries

        -- Single-currency scalars (median, daily burn, 30-day projection) are
        -- computed over only the primary-currency entries so the number matches
        -- its `displayCurrency` label — no CAD+USD cent sums. All-USD trips are
        -- unaffected (`primaryEntries == entries`).
        primaryEntries =
            List.filter (\e -> e.currency == displayCurrency) entries

        numDays =
            List.length (Entry.uniqueDates entries)

        numEntries =
            List.length entries

        primaryDayCount =
            List.length (Entry.uniqueDates primaryEntries)

        avgPerDayCents =
            if primaryDayCount > 0 then
                Money.toCents (Money.sum (List.map .amount primaryEntries)) // primaryDayCount

            else
                0

        median =
            Entry.medianAmount primaryEntries

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
                    Just (DateField.toIso (Trips.selectedTrip trips).startDate)

                _ ->
                    Nothing

        daysIn =
            Stats.tripDaysIn tripStart (DateField.toIso model.today)
    in
    Html.div []
        [ UI.Rule.kicker "AT A GLANCE"
        , UI.Card.subCard
            [ Html.div [ Html.Attributes.class "grid grid-cols-2 gap-3" ]
                [ statCard "MEDIAN" (UI.MoneyView.amount displayCurrency median)
                , statCard "TOP CATEGORY"
                    (Html.text
                        (topCat
                            |> Maybe.map (\c -> Category.icon c ++ " " ++ Category.label c)
                            |> Maybe.withDefault "—"
                        )
                    )
                , if numDays > 1 then
                    statCard "BIGGEST DAY"
                        (case bigDay of
                            Just ( d, t ) ->
                                Html.span []
                                    [ Html.text (String.slice 5 10 (DateField.toIso d) ++ "  ")

                                    -- Label the biggest day in that day's own
                                    -- currency, not the trip-wide one — a lone
                                    -- CAD day in a USD trip shouldn't read `$`.
                                    , UI.MoneyView.amount
                                        (Entry.primaryCurrency
                                            (List.filter (\e -> DateField.compare e.date d == EQ) entries)
                                        )
                                        t
                                    ]

                            Nothing ->
                                Html.text "—"
                        )

                  else
                    statCard "ENTRIES TODAY" (Html.text (String.fromInt numEntries))
                , statCard "DAYS INTO TRIP"
                    (Html.text
                        (if daysIn > 0 then
                            String.fromInt daysIn

                         else
                            "—"
                        )
                    )
                , statCard "PROJ / 30 DAYS"
                    (if avgPerDayCents > 0 then
                        UI.MoneyView.amount displayCurrency (Money.fromCents (avgPerDayCents * 30))

                     else
                        Html.text "—"
                    )
                ]
            ]
        , Html.Extra.viewIf (not (List.isEmpty entries))
            (Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker "TOP CATEGORIES"
                , UI.Card.subCard
                    [ viewCategoryList entries ]
                ]
            )
        , Html.Extra.viewIf (numDays > 1)
            (let
                resolved =
                    Maybe.withDefault (StatsGranularity.fromSpan (Stats.spanDays primEntries))
                        model.statsGranularity
             in
             Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker (StatsGranularity.kicker resolved)
                , UI.Card.subCard
                    [ viewDailyChart resolved model.statsHover.dailyBars primEntries ]
                ]
            )
        , Html.Extra.viewIf (numDays > 1)
            (Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker "CUMULATIVE SPEND"
                , UI.Card.subCard
                    [ viewCumulativeChart model.statsHover.cumulativePoints entries ]
                ]
            )
        , let
            fuelPrims =
                toFuelPrims entries

            summary =
                Stats.fuelSummary fuelPrims

            hasFuelData =
                not (List.isEmpty fuelPrims)

            hasFuelPrices =
                List.length (Stats.pricePerGallonSeries fuelPrims) >= 2
          in
          Html.Extra.viewIf hasFuelData
            (Html.div []
                [ UI.Rule.dashedRule
                , UI.Rule.kicker "FUEL"
                , UI.Card.subCard
                    [ viewFuelSummaryRow summary
                    , Html.Extra.viewIf hasFuelPrices
                        (viewPricePerGallonChart model.statsHover.pricePerGallonPoints fuelPrims)
                    ]
                ]
            )
        , Html.Extra.viewIf (not (List.isEmpty top5))
            (Html.div []
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
                                        [ UI.MoneyView.amount entry.currency entry.amount ]
                                    ]
                            )
                            top5
                        )
                    ]
                ]
            )
        ]


statCard : String -> Html Msg -> Html Msg
statCard label_ value =
    Html.div []
        [ Html.div [ Html.Attributes.class "text-[11px] tracking-widest text-moss mb-1.5" ]
            [ Html.text label_ ]
        , Html.div [ Html.Attributes.class "text-[22px] font-mono text-rust" ]
            [ value ]
        ]


viewCategoryList : List Entry.EffectiveEntry -> Html Msg
viewCategoryList entries =
    let
        displayCurrency =
            Entry.primaryCurrency entries

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
    Html.Extra.viewIf (not (List.isEmpty rows))
        (Html.div []
            (List.indexedMap
                (\i r ->
                    categoryRow
                        { currency = displayCurrency
                        , isLast = i == List.length rows - 1
                        , maxTotalCents = maxTotalCents
                        , row = r
                        }
                )
                rows
            )
        )


categoryRow :
    { currency : Currency
    , isLast : Bool
    , maxTotalCents : Int
    , row : { cat : Category.Category, total : Money }
    }
    -> Html Msg
categoryRow { currency, isLast, maxTotalCents, row } =
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
            [ UI.MoneyView.amount currency row.total ]
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


viewDailyChart : Granularity -> List (CI.One DailyDay CI.Bar) -> List { date : String, amountCents : Int } -> Html Msg
viewDailyChart resolved hovered primEntries =
    let
        sortedIsos =
            primEntries |> List.map .date |> Set.fromList |> Set.toList

        firstDate =
            List.head sortedIsos |> Maybe.withDefault ""

        lastDate =
            List.Extra.last sortedIsos |> Maybe.withDefault ""

        days : List DailyDay
        days =
            Stats.binEntries resolved primEntries

        rangeLabel =
            if firstDate == "" then
                ""

            else
                Stats.formatDateShort firstDate
                    ++ " – "
                    ++ Stats.formatDateShort lastDate
                    ++ " · "
                    ++ String.fromInt (List.length sortedIsos)
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
            , CE.onMouseMove (AuthMsg << HoverDailyBars) (CE.getNearest CI.bars)
            , CE.onMouseLeave (AuthMsg (HoverDailyBars []))
            ]
            [ C.grid [ CA.color UI.Theme.colorTan, CA.dashed [ 2, 3 ] ]
            , C.yLabels
                [ CA.amount 4
                , CA.format Stats.formatDollars
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
        , Html.Events.onClick (AuthMsg (SetStatsGranularity chip))
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
                Stats.formatDateShort d.date

            else if resolved == Monthly then
                Stats.formatMonthYear d.date

            else
                Stats.formatDateShort d.date ++ " – " ++ Stats.formatDateShort d.endDate
    in
    [ Html.div [ Html.Attributes.class "font-mono text-[11px] text-moss" ]
        [ Html.text header ]
    , Html.div [ Html.Attributes.class "font-mono text-sm text-rust" ]
        [ Html.text (Stats.formatDollars d.total) ]
    ]


viewCumulativeChart : List (CI.One CumulativePoint CI.Dot) -> List Entry.EffectiveEntry -> Html Msg
viewCumulativeChart hovered entries =
    let
        points : List CumulativePoint
        points =
            Stats.cumulativePoints (toPrimEntries entries)

        firstDate =
            Maybe.Extra.unwrap "" .date (List.head points)

        lastDate =
            List.Extra.last points |> Maybe.Extra.unwrap "" .date

        finalTotal =
            List.Extra.last points |> Maybe.Extra.unwrap 0 .y
    in
    Html.div []
        [ Html.div [ Html.Attributes.class "flex items-center justify-end mb-1" ]
            [ scrubHint ]
        , C.chart
            [ CA.height 180
            , CA.margin { top = 16, bottom = 24, left = 44, right = 12 }
            , CE.onMouseMove (AuthMsg << HoverCumulativePoints) (CE.getNearest CI.dots)
            , CE.onMouseLeave (AuthMsg (HoverCumulativePoints []))
            ]
            [ C.yLabels
                [ CA.amount 4
                , CA.format Stats.formatDollars
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
                [ Svg.text (Stats.formatDateShort firstDate) ]
            , C.labelAt .max
                .min
                [ CA.moveDown 16
                , CA.fontSize 10
                , CA.color UI.Theme.colorMuted
                , CA.alignRight
                ]
                [ Svg.text (Stats.formatDateShort lastDate) ]
            , C.labelAt .max
                (\_ -> finalTotal)
                [ CA.moveUp 8
                , CA.moveLeft 2
                , CA.fontSize 11
                , CA.color UI.Theme.colorRust
                , CA.alignRight
                ]
                [ Svg.text (Stats.formatDollars finalTotal) ]
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
        [ Html.text (Stats.formatDateShort p.date) ]
    , Html.div [ Html.Attributes.class "font-mono text-sm text-rust" ]
        [ Html.text (Stats.formatDollars p.y) ]
    ]


viewFuelSummaryRow :
    { avg : Maybe Float, max : Maybe Float, min : Maybe Float, totalGallons : Float }
    -> Html Msg
viewFuelSummaryRow summary =
    let
        formatGallons : Float -> String
        formatGallons g =
            let
                rounded : Float
                rounded =
                    toFloat (round (g * 10)) / 10

                str : String
                str =
                    String.fromFloat rounded
            in
            str ++ " gal total"

        formatPrice : Float -> String
        formatPrice p =
            Stats.formatPricePerGallonAxis p ++ "/gal"
    in
    Html.div [ Html.Attributes.class "mb-3" ]
        [ Html.div [ Html.Attributes.class "font-mono text-sm text-ink" ]
            [ Html.text (formatGallons summary.totalGallons)
            , case summary.avg of
                Just avg ->
                    Html.text (" · avg " ++ formatPrice avg)

                Nothing ->
                    Html.text ""
            ]
        , case ( summary.min, summary.max ) of
            ( Just lo, Just hi ) ->
                Html.div [ Html.Attributes.class "font-mono text-xs text-muted mt-0.5" ]
                    [ Html.text ("low " ++ formatPrice lo ++ " · high " ++ formatPrice hi) ]

            _ ->
                Html.text ""
        ]


viewPricePerGallonChart : List (CI.One PricePoint CI.Dot) -> List Stats.FuelPrim -> Html Msg
viewPricePerGallonChart hovered fuelPrims =
    let
        points : List PricePoint
        points =
            Stats.pricePerGallonSeries fuelPrims

        firstDate : String
        firstDate =
            Maybe.Extra.unwrap "" .date (List.head points)

        lastDate : String
        lastDate =
            List.Extra.last points |> Maybe.Extra.unwrap "" .date
    in
    Html.div []
        [ Html.div [ Html.Attributes.class "flex items-center justify-end mb-1" ]
            [ scrubHint ]
        , C.chart
            [ CA.height 180
            , CA.margin { top = 16, bottom = 24, left = 52, right = 12 }
            , CE.onMouseMove (AuthMsg << HoverPricePerGallonPoints) (CE.getNearest CI.dots)
            , CE.onMouseLeave (AuthMsg (HoverPricePerGallonPoints []))
            ]
            [ C.yLabels
                [ CA.amount 4
                , CA.format Stats.formatPricePerGallonAxis
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
                [ Svg.text (Stats.formatDateShort firstDate) ]
            , C.labelAt .max
                .min
                [ CA.moveDown 16
                , CA.fontSize 10
                , CA.color UI.Theme.colorMuted
                , CA.alignRight
                ]
                [ Svg.text (Stats.formatDateShort lastDate) ]
            , C.each hovered <|
                \_ item ->
                    [ C.tooltip item
                        [ CA.onTopOrBottom, CA.background "#fffaf2", CA.border UI.Theme.colorTan ]
                        []
                        (priceTooltipContent (CI.getData item))
                    ]
            ]
        ]


priceTooltipContent : PricePoint -> List (Html Never)
priceTooltipContent p =
    [ Html.div [ Html.Attributes.class "font-mono text-[11px] text-moss" ]
        [ Html.text (Stats.formatDateShort p.date) ]
    , Html.div [ Html.Attributes.class "font-mono text-sm text-rust" ]
        [ Html.text (Stats.formatPricePerGallonAxis p.y) ]
    ]
