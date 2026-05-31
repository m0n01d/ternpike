module Data.Stats exposing
    ( FuelPrim
    , StatsMode(..)
    , binEntries
    , buildMonthlyBins
    , buildWeeklyBins
    , cumulativePoints
    , formatDateShort
    , formatDollars
    , formatIso
    , formatMonthYear
    , formatPricePerGallonAxis
    , fuelSummary
    , last7DaysValues
    , monthAbbr
    , parseYearMonth
    , pricePerGallonSeries
    , spanDays
    , tripDaysIn
    )

{-| Pure data helpers for the Stats page: time-binning, day-span arithmetic,
date and currency formatting, and the loading-vs-ready discriminator.

Everything here takes primitive inputs (ISO date strings, cent counts,
records) rather than the richer `Data.Entry.EffectiveEntry` /
`Data.DateField.DateField` / `Data.Money.Money` types used elsewhere in
the app. That's deliberate: it lets `elm-verify-examples` cover the math
with literal `-->` assertions instead of fixture boilerplate.

`Pages.Stats` is the only caller and is responsible for mapping
`EffectiveEntry → { date = DateField.toIso e.date, amountCents = Money.toCents e.amount }`
at the boundary. Sums happen in `Int` cents so the chart numbers don't
inherit IEEE-754 drift; the `Float`-typed `DailyDay.total` is computed
only at the very end (the elm-charts API requires Float).

The naive day-count helpers this module replaced (`isoToNaiveDayCount`,
`dayCountToIso`) collapsed Feb 29 and Mar 1 onto the same count, which
broke weekly-bin layout in leap years. `buildWeeklyBins` now uses
`Date.add Date.Days` + `Date.diff Date.Days` from `justinmimbs/date`
end-to-end and is exercised under both leap-year and year-boundary spans
in the examples below.

-}

import Data.Entry exposing (EffectiveEntry)
import Data.Money as Money
import Data.StatsGranularity exposing (Granularity(..))
import Data.StatsHover exposing (CumulativePoint, DailyDay, PricePoint)
import Date
import Set



-- LOADING DISCRIMINATOR


{-| Loading-vs-ready discriminator for the Stats page.

The Stats page renders aggregates (totals, daily burn, top categories,
charts) over the resolved entries for one trip. Those entries come from
folding `Data.Entry.resolve` over the cached expenses, amendments, and
voids — but the cache is empty until that trip's `GetTripExpenses`
round-trip completes.

`Pages.Stats.statsMode` looks up the current route's trip in
`AuthState.tripLoaded`; if it's not there yet, the page renders skeleton
placeholders, otherwise the resolved aggregates (or an empty-state
mascot if the loaded trip has no entries).

-}
type StatsMode
    = StatsLoading
    | StatsReady (List EffectiveEntry)



-- DAY-SPAN ARITHMETIC


{-| Inclusive day count between the first and last unique date that has
spend. Returns `0` when the list is empty.

    spanDays []
    --> 0

    spanDays [ { date = "2024-05-21", amountCents = 1230 } ]
    --> 1

    spanDays
        [ { date = "2024-05-21", amountCents = 1230 }
        , { date = "2024-05-25", amountCents = 700 }
        ]
    --> 5

    -- Spans crossing Feb 29 in a leap year are counted correctly:
    spanDays
        [ { date = "2024-02-28", amountCents = 100 }
        , { date = "2024-03-01", amountCents = 100 }
        ]
    --> 3

    -- Multiple entries on the same day collapse to one unique date:
    spanDays
        [ { date = "2024-05-21", amountCents = 500 }
        , { date = "2024-05-21", amountCents = 700 }
        ]
    --> 1

-}
spanDays : List { a | date : String } -> Int
spanDays entries =
    let
        sorted =
            uniqueAscending (List.map .date entries)
    in
    case ( List.head sorted, List.head (List.reverse sorted) ) of
        ( Just firstIso, Just lastIso ) ->
            case ( Date.fromIsoString firstIso, Date.fromIsoString lastIso ) of
                ( Ok first, Ok last ) ->
                    Date.diff Date.Days first last + 1

                _ ->
                    0

        _ ->
            0


{-| Inclusive day count from the trip's start date to "today". Both args
are ISO `YYYY-MM-DD` strings. Returns `0` when `tripStart` is `Nothing`,
when either string is malformed, or when `tripStart` is the legacy epoch
sentinel (`"1970-01-01"`) which `Data.DateField.decoder` produces for
documents whose `startDate` was never set.

    tripDaysIn (Just "2024-05-21") "2024-05-21"
    --> 1

    tripDaysIn (Just "2024-05-21") "2024-05-24"
    --> 4

    tripDaysIn Nothing "2024-05-21"
    --> 0

    tripDaysIn (Just "1970-01-01") "2024-05-21"
    --> 0

    -- Leap-year crossing is counted correctly:
    tripDaysIn (Just "2024-02-28") "2024-03-01"
    --> 3

    -- Malformed input falls back to 0 rather than throwing:
    tripDaysIn (Just "garbage") "2024-05-21"
    --> 0

-}
tripDaysIn : Maybe String -> String -> Int
tripDaysIn tripStart today =
    case tripStart of
        Just startIso ->
            if startIso == "1970-01-01" then
                0

            else
                case ( Date.fromIsoString startIso, Date.fromIsoString today ) of
                    ( Ok start, Ok now ) ->
                        Date.diff Date.Days start now + 1

                    _ ->
                        0

        Nothing ->
            0



-- HERO SPARKLINE INPUT


{-| The per-day total (in dollars, for the chart) for the last 7 unique
days with spend, in chronological order. Drives the hero sparkline.

Sums happen in `Int` cents and divide by `100.0` once at the very end
so totals like `0.10 + 0.20` come out as exactly `0.30` rather than
`0.30000000000000004`.

    last7DaysValues []
    --> []

    last7DaysValues [ { date = "2024-05-21", amountCents = 1230 } ]
    --> [ 12.30 ]

    -- Older days returned in chronological order, capped at the most recent 7:
    last7DaysValues
        [ { date = "2024-05-21", amountCents = 100 }
        , { date = "2024-05-22", amountCents = 200 }
        , { date = "2024-05-23", amountCents = 300 }
        ]
    --> [ 1.0, 2.0, 3.0 ]

    -- Multiple entries on the same day sum together:
    last7DaysValues
        [ { date = "2024-05-21", amountCents = 100 }
        , { date = "2024-05-21", amountCents = 200 }
        , { date = "2024-05-22", amountCents = 400 }
        ]
    --> [ 3.0, 4.0 ]

    -- Cent-precision arithmetic: 0.10 + 0.20 == 0.30 exactly:
    last7DaysValues
        [ { date = "2024-05-21", amountCents = 10 }
        , { date = "2024-05-21", amountCents = 20 }
        ]
    --> [ 0.30 ]

-}
last7DaysValues : List { a | date : String, amountCents : Int } -> List Float
last7DaysValues entries =
    let
        dates =
            entries
                |> List.map .date
                |> uniqueAscending
                |> List.reverse
                |> List.take 7
                |> List.reverse

        totalForDate d =
            entries
                |> List.filter (\e -> e.date == d)
                |> List.map .amountCents
                |> List.sum
                |> centsToDollars
    in
    List.map totalForDate dates



-- CUMULATIVE CHART


{-| Build the points for the cumulative-spend chart, one per unique date
that has spend, in ascending chronological order. For each date, `y` is
the running total (in dollars) of every entry on-or-before that date,
and `x` is the 1-indexed position so the chart axis reads linearly even
when the days with spend aren't evenly spaced (gaps collapse).

Sums happen in `Int` cents and divide by `100.0` at the boundary so the
curve doesn't inherit float drift. Multiple entries on the same date
collapse to a single point with all of that day's spend folded in.

    cumulativePoints []
    --> []

    cumulativePoints [ { date = "2024-05-21", amountCents = 1230 } ]
    --> [ { date = "2024-05-21", x = 1, y = 12.30 } ]

    cumulativePoints [ { date = "2024-05-21", amountCents = 100 }, { date = "2024-05-22", amountCents = 200 }, { date = "2024-05-23", amountCents = 300 } ]
    --> [ { date = "2024-05-21", x = 1, y = 1.0 }, { date = "2024-05-22", x = 2, y = 3.0 }, { date = "2024-05-23", x = 3, y = 6.0 } ]

    -- Out-of-order input still produces ascending points:
    cumulativePoints [ { date = "2024-05-23", amountCents = 300 }, { date = "2024-05-21", amountCents = 100 }, { date = "2024-05-22", amountCents = 200 } ]
    --> [ { date = "2024-05-21", x = 1, y = 1.0 }, { date = "2024-05-22", x = 2, y = 3.0 }, { date = "2024-05-23", x = 3, y = 6.0 } ]

    -- Multiple entries on the same date collapse to one point:
    cumulativePoints [ { date = "2024-05-21", amountCents = 500 }, { date = "2024-05-21", amountCents = 700 }, { date = "2024-05-22", amountCents = 300 } ]
    --> [ { date = "2024-05-21", x = 1, y = 12.0 }, { date = "2024-05-22", x = 2, y = 15.0 } ]

    -- Cent-precision: 0.10 + 0.20 == 0.30 exactly:
    cumulativePoints [ { date = "2024-05-21", amountCents = 10 }, { date = "2024-05-22", amountCents = 20 } ]
    --> [ { date = "2024-05-21", x = 1, y = 0.10 }, { date = "2024-05-22", x = 2, y = 0.30 } ]

-}
cumulativePoints :
    List { a | date : String, amountCents : Int }
    -> List CumulativePoint
cumulativePoints entries =
    let
        sortedIsos =
            uniqueAscending (List.map .date entries)
    in
    List.indexedMap
        (\i iso ->
            { date = iso
            , x = toFloat (i + 1)
            , y = totalBetween "" iso entries
            }
        )
        sortedIsos



-- TIME-BINNING


{-| Aggregate primitive entries into time-bins for a resolved granularity.

  - `Daily` — one bin per unique date that has spend (matches the historical
    behavior; empty days inside the span are intentionally NOT padded).

  - `Weekly` — one bin per 7-day window starting from the first date with
    spend. Empty weeks inside the span are included as zero-total bars so
    the time axis reads linearly.

  - `Monthly` — one bin per calendar month between the first and last
    spend-month, inclusive. Empty months inside the span are included
    as zero-total bars.

    import Data.StatsGranularity exposing (Granularity(..))

    binEntries Daily []
    --> []

    binEntries Weekly []
    --> []

    binEntries Monthly []
    --> []

    binEntries Daily [ { date = "2024-05-21", amountCents = 1230 } ]
    --> [ { date = "2024-05-21", endDate = "2024-05-21", total = 12.30 } ]

    binEntries Daily [ { date = "2024-05-21", amountCents = 500 }, { date = "2024-05-21", amountCents = 700 }, { date = "2024-05-23", amountCents = 300 } ]
    --> [ { date = "2024-05-21", endDate = "2024-05-21", total = 12.0 }, { date = "2024-05-23", endDate = "2024-05-23", total = 3.0 } ]

-}
binEntries : Granularity -> List { a | date : String, amountCents : Int } -> List DailyDay
binEntries resolved entries =
    let
        sortedIsos =
            uniqueAscending (List.map .date entries)
    in
    case resolved of
        Daily ->
            sortedIsos
                |> List.map
                    (\iso ->
                        { date = iso
                        , endDate = iso
                        , total = totalBetween iso iso entries
                        }
                    )

        Weekly ->
            case ( List.head sortedIsos, List.head (List.reverse sortedIsos) ) of
                ( Just firstIso, Just lastIso ) ->
                    buildWeeklyBins firstIso lastIso entries

                _ ->
                    []

        Monthly ->
            case ( List.head sortedIsos, List.head (List.reverse sortedIsos) ) of
                ( Just firstIso, Just lastIso ) ->
                    buildMonthlyBins firstIso lastIso entries

                _ ->
                    []


{-| Build the weekly bins between two ISO dates (inclusive of both). The
last bin is clamped to `lastIso` rather than running past it, so a 10-day
span produces a 7-day bin followed by a 3-day bin.

Uses real calendar arithmetic via `Date.add Date.Days` so spans crossing
Feb 29 in a leap year — or year boundaries — get the correct labels and
day counts.

    buildWeeklyBins "2024-05-21" "2024-05-21" []
    --> [ { date = "2024-05-21", endDate = "2024-05-21", total = 0 } ]

    buildWeeklyBins "2024-05-21" "2024-05-28" []
    --> [ { date = "2024-05-21", endDate = "2024-05-27", total = 0 }, { date = "2024-05-28", endDate = "2024-05-28", total = 0 } ]

    buildWeeklyBins "2024-02-25" "2024-03-09" []
    --> [ { date = "2024-02-25", endDate = "2024-03-02", total = 0 }, { date = "2024-03-03", endDate = "2024-03-09", total = 0 } ]

    buildWeeklyBins "2023-12-30" "2024-01-05" []
    --> [ { date = "2023-12-30", endDate = "2024-01-05", total = 0 } ]

    buildWeeklyBins "2024-05-21" "2024-05-28" [ { date = "2024-05-22", amountCents = 500 }, { date = "2024-05-28", amountCents = 700 } ]
    --> [ { date = "2024-05-21", endDate = "2024-05-27", total = 5.0 }, { date = "2024-05-28", endDate = "2024-05-28", total = 7.0 } ]

    buildWeeklyBins "garbage" "2024-05-21" []
    --> []

-}
buildWeeklyBins :
    String
    -> String
    -> List { a | date : String, amountCents : Int }
    -> List DailyDay
buildWeeklyBins firstIso lastIso entries =
    case ( Date.fromIsoString firstIso, Date.fromIsoString lastIso ) of
        ( Ok first, Ok last ) ->
            let
                spanCount =
                    Date.diff Date.Days first last

                weekCount =
                    spanCount // 7 + 1
            in
            List.range 0 (weekCount - 1)
                |> List.map
                    (\i ->
                        let
                            startDate =
                                Date.add Date.Days (i * 7) first

                            endCandidate =
                                Date.add Date.Days 6 startDate

                            endDate_ =
                                if Date.compare endCandidate last == GT then
                                    last

                                else
                                    endCandidate

                            startIso_ =
                                Date.toIsoString startDate

                            endIso_ =
                                Date.toIsoString endDate_
                        in
                        { date = startIso_
                        , endDate = endIso_
                        , total = totalBetween startIso_ endIso_ entries
                        }
                    )

        _ ->
            []


{-| Build the monthly bins between two ISO dates (inclusive of both
months). Each bin spans from day 1 to day 31 of its calendar month — the
day-31 upper bound is intentional: dates compare lexicographically as
strings and `"YYYY-MM-31"` is always ≥ any real date in that month. The
monthly tooltip header renders via [`formatMonthYear`](#formatMonthYear)
so the synthetic `endDate` is never shown to the user.

    buildMonthlyBins "2024-05-21" "2024-05-31" []
    --> [ { date = "2024-05-01", endDate = "2024-05-31", total = 0 } ]

    buildMonthlyBins "2024-05-21" "2024-07-04" []
    --> [ { date = "2024-05-01", endDate = "2024-05-31", total = 0 }, { date = "2024-06-01", endDate = "2024-06-31", total = 0 }, { date = "2024-07-01", endDate = "2024-07-31", total = 0 } ]

    buildMonthlyBins "2023-11-01" "2024-02-01" []
    --> [ { date = "2023-11-01", endDate = "2023-11-31", total = 0 }, { date = "2023-12-01", endDate = "2023-12-31", total = 0 }, { date = "2024-01-01", endDate = "2024-01-31", total = 0 }, { date = "2024-02-01", endDate = "2024-02-31", total = 0 } ]

    buildMonthlyBins "2024-05-21" "2024-06-15" [ { date = "2024-05-21", amountCents = 500 }, { date = "2024-05-25", amountCents = 700 }, { date = "2024-06-15", amountCents = 300 } ]
    --> [ { date = "2024-05-01", endDate = "2024-05-31", total = 12.0 }, { date = "2024-06-01", endDate = "2024-06-31", total = 3.0 } ]

-}
buildMonthlyBins :
    String
    -> String
    -> List { a | date : String, amountCents : Int }
    -> List DailyDay
buildMonthlyBins firstIso lastIso entries =
    let
        ( fy, fm ) =
            parseYearMonth firstIso

        ( ly, lm ) =
            parseYearMonth lastIso

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

                    endIso =
                        formatIso year month 31
                in
                { date = startIso
                , endDate = endIso
                , total = totalBetween startIso endIso entries
                }
            )



-- DATE PARSING + FORMATTING


{-| Parse the year and month from an ISO date or year-month string.
Returns `( 0, 1 )` on malformed input — same silent-default pattern the
rest of the helpers use; downstream callers treat the result as an empty
bin range rather than crashing.

    parseYearMonth "2024-05-21"
    --> ( 2024, 5 )

    parseYearMonth "2024-05"
    --> ( 2024, 5 )

    parseYearMonth "2024-12-31"
    --> ( 2024, 12 )

    parseYearMonth ""
    --> ( 0, 1 )

    parseYearMonth "garbage"
    --> ( 0, 1 )

-}
parseYearMonth : String -> ( Int, Int )
parseYearMonth iso =
    case String.split "-" iso of
        y :: m :: _ ->
            ( Maybe.withDefault 0 (String.toInt y)
            , Maybe.withDefault 1 (String.toInt m)
            )

        _ ->
            ( 0, 1 )


{-| Build an ISO `YYYY-MM-DD` string from year/month/day, padding month
and day to two digits. Used to synthesize month-boundary dates in
[`buildMonthlyBins`](#buildMonthlyBins).

    formatIso 2024 5 21
    --> "2024-05-21"

    formatIso 2024 1 1
    --> "2024-01-01"

    formatIso 2024 12 31
    --> "2024-12-31"

-}
formatIso : Int -> Int -> Int -> String
formatIso y m d =
    String.fromInt y
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt m)
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt d)


{-| Convert a two-digit month string to its three-letter abbreviation.
Unknown inputs pass through unchanged.

    monthAbbr "01"
    --> "Jan"

    monthAbbr "05"
    --> "May"

    monthAbbr "12"
    --> "Dec"

    monthAbbr "13"
    --> "13"

-}
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


{-| Render an ISO date as `"MMM d"`, dropping the year. Used for chart
axis labels where the year is implied by surrounding context. Malformed
input passes through unchanged.

    formatDateShort "2024-05-21"
    --> "May 21"

    formatDateShort "2024-01-01"
    --> "Jan 1"

    formatDateShort "2024-12-09"
    --> "Dec 9"

    formatDateShort "garbage"
    --> "garbage"

-}
formatDateShort : String -> String
formatDateShort iso =
    case String.split "-" iso of
        [ _, m, d ] ->
            monthAbbr m ++ " " ++ String.fromInt (Maybe.withDefault 0 (String.toInt d))

        _ ->
            iso


{-| Render an ISO date or year-month string as `"MMM YYYY"`. Used for
the monthly-bin tooltip header. Despite the previous name
`formatMonthLong`, this returns the three-letter abbreviation — not the
full month name — because that's what `Money.format` and friends use
elsewhere on the page.

    formatMonthYear "2024-05-21"
    --> "May 2024"

    formatMonthYear "2024-05"
    --> "May 2024"

    formatMonthYear "2024-12"
    --> "Dec 2024"

    formatMonthYear "garbage"
    --> "garbage"

-}
formatMonthYear : String -> String
formatMonthYear iso =
    case String.split "-" iso of
        y :: m :: _ ->
            monthAbbr m ++ " " ++ y

        _ ->
            iso


{-| Format a chart-axis `Float` (already in dollars) as `"$X.YY"`. Mirrors
`Money.format` but takes the `Float`-flavoured `total` / `y` fields that
the elm-charts API requires. Rounds to the nearest cent.

PINNED-RELAX: the exact decimal/separator style follows `Money.format` and will
evolve with #38 for DOM-facing contexts. The leading `'$'` is a stable invariant.

Canonical example:

    formatDollars 12.34
    --> "$12.34"

Round-trip: the result always starts with `'$'`:

    String.startsWith "$" (formatDollars 1234.56)
    --> True

-}
formatDollars : Float -> String
formatDollars dollars =
    Money.format (Money.fromCents (round (dollars * 100)))


{-| Format a `Float` price-per-gallon (already in dollars) with three
decimal places and a leading `$`. Used for chart axis ticks and tooltips
where the 9/10-cent digit is significant.

    formatPricePerGallonAxis 4.299
    --> "$4.299"

    formatPricePerGallonAxis 3.5
    --> "$3.500"

    formatPricePerGallonAxis 5.0
    --> "$5.000"

-}
formatPricePerGallonAxis : Float -> String
formatPricePerGallonAxis dollars =
    let
        millis : Int
        millis =
            round (dollars * 1000)

        whole : Int
        whole =
            millis // 1000

        frac : Int
        frac =
            abs (remainderBy 1000 millis)
    in
    "$" ++ String.fromInt whole ++ "." ++ String.padLeft 3 '0' (String.fromInt frac)



-- FUEL CHART


{-| Primitive input record for the fuel chart functions. One record per
fuel-up entry; `gallons` and `pricePerGallon` are `Maybe` because either
field may be absent from a given fuel-up.

`Pages.Stats.toFuelPrims` produces these from `EffectiveEntry` values;
the functions below consume them so they stay example-able.

-}
type alias FuelPrim =
    { date : String
    , gallons : Maybe Float
    , pricePerGallon : Maybe Float
    }


{-| Build the points for the price-per-gallon trend chart, one per
fuel-up that has a price, in ascending chronological order. `x` is
1-indexed (mirrors `cumulativePoints`); `y` is the price in dollars.

    pricePerGallonSeries []
    --> []

    pricePerGallonSeries [ { date = "2024-05-21", gallons = Just 12.3, pricePerGallon = Nothing } ]
    --> []

    pricePerGallonSeries [ { date = "2024-05-21", gallons = Just 12.3, pricePerGallon = Just 4.299 } ]
    --> [ { date = "2024-05-21", x = 1, y = 4.299 } ]

    pricePerGallonSeries
        [ { date = "2024-05-21", gallons = Just 10.0, pricePerGallon = Just 3.59 }
        , { date = "2024-05-24", gallons = Nothing, pricePerGallon = Just 4.19 }
        , { date = "2024-05-28", gallons = Just 15.0, pricePerGallon = Nothing }
        ]
    --> [ { date = "2024-05-21", x = 1, y = 3.59 }, { date = "2024-05-24", x = 2, y = 4.19 } ]

-}
pricePerGallonSeries : List FuelPrim -> List PricePoint
pricePerGallonSeries prims =
    prims
        |> List.filterMap
            (\p ->
                case p.pricePerGallon of
                    Just price ->
                        Just { date = p.date, price = price }

                    Nothing ->
                        Nothing
            )
        |> List.sortBy .date
        |> List.indexedMap
            (\i pt ->
                { date = pt.date
                , x = toFloat (i + 1)
                , y = pt.price
                }
            )


{-| Aggregate fuel stats across a list of fuel-up primitives.

  - `totalGallons` — sum of all `Just gallons` values (entries without a
    gallons reading contribute 0).
  - `avg` / `min` / `max` — over the `Just pricePerGallon` values only;
    `Nothing` when no fuel-up has a price.

Examples:

    fuelSummary []
    --> { avg = Nothing, max = Nothing, min = Nothing, totalGallons = 0 }

    fuelSummary [ { date = "2024-05-21", gallons = Just 10.0, pricePerGallon = Nothing } ]
    --> { avg = Nothing, max = Nothing, min = Nothing, totalGallons = 10.0 }

    fuelSummary [ { date = "2024-05-21", gallons = Just 10.0, pricePerGallon = Just 4.299 } ]
    --> { avg = Just 4.299, max = Just 4.299, min = Just 4.299, totalGallons = 10.0 }

    fuelSummary
        [ { date = "2024-05-21", gallons = Just 10.0, pricePerGallon = Just 3.59 }
        , { date = "2024-05-24", gallons = Just 12.0, pricePerGallon = Just 4.299 }
        , { date = "2024-05-28", gallons = Nothing,   pricePerGallon = Just 5.29 }
        ]
    --> { avg = Just 4.393, max = Just 5.29, min = Just 3.59, totalGallons = 22.0 }

-}
fuelSummary :
    List FuelPrim
    -> { avg : Maybe Float, max : Maybe Float, min : Maybe Float, totalGallons : Float }
fuelSummary prims =
    let
        totalGallons : Float
        totalGallons =
            prims
                |> List.filterMap .gallons
                |> List.sum

        prices : List Float
        prices =
            List.filterMap .pricePerGallon prims

        avg : Maybe Float
        avg =
            if List.isEmpty prices then
                Nothing

            else
                let
                    n : Int
                    n =
                        List.length prices

                    sumPrices : Float
                    sumPrices =
                        List.sum prices
                in
                Just (toFloat (round (sumPrices / toFloat n * 1000)) / 1000)
    in
    { avg = avg
    , max = List.maximum prices
    , min = List.minimum prices
    , totalGallons = totalGallons
    }



-- INTERNAL


uniqueAscending : List comparable -> List comparable
uniqueAscending xs =
    Set.toList (Set.fromList xs)


totalBetween :
    String
    -> String
    -> List { a | date : String, amountCents : Int }
    -> Float
totalBetween startIso endIso entries =
    entries
        |> List.filter (\e -> e.date >= startIso && e.date <= endIso)
        |> List.map .amountCents
        |> List.sum
        |> centsToDollars


centsToDollars : Int -> Float
centsToDollars cents =
    toFloat cents / 100
