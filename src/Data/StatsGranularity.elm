module Data.StatsGranularity exposing (Granularity(..), all, fromSpan, kicker, label)

{-| The user-facing time-binning choice for the Daily Spending chart.

The chart picks a bin size — daily, weekly, or monthly — so that long trips
don't collapse into a smear of hair-thin bars. On first render of a trip,
`fromSpan` picks a sensible default based on trip length. After that, the
chip selector on the Stats tab lets the user switch between the three
explicit choices, and the pick sticks for the rest of the session.

Lives on `AuthState.statsGranularity : Maybe Granularity` — `Nothing`
means "use `fromSpan` for the current trip"; `Just g` means "the user
picked `g`." In-memory only; no persistence.

@docs Granularity, all, fromSpan, kicker, label

-}


type Granularity
    = Daily
    | Monthly
    | Weekly


{-| Display order for the chip selector.
-}
all : List Granularity
all =
    [ Daily, Weekly, Monthly ]


{-| Pick the default granularity for a trip given the inclusive span in
days between the first and last day with spend.

  - ≤ 35 days → daily (a month-long trip still reads as ~30 narrow bars).
  - ≤ 210 days → weekly (≈30 weekly bars for a 7-month trip).
  - otherwise → monthly.

```
fromSpan 22 --> Daily

fromSpan 100 --> Weekly

fromSpan 400 --> Monthly
```

-}
fromSpan : Int -> Granularity
fromSpan spanDays =
    if spanDays <= 35 then
        Daily

    else if spanDays <= 210 then
        Weekly

    else
        Monthly


{-| Human-readable label for the chip selector.

    label Daily --> "Daily"

    label Weekly --> "Weekly"

    label Monthly --> "Monthly"

-}
label : Granularity -> String
label g =
    case g of
        Daily ->
            "Daily"

        Monthly ->
            "Monthly"

        Weekly ->
            "Weekly"


{-| The kicker text shown above the chart for a resolved granularity.

    kicker Daily --> "DAILY SPENDING"

    kicker Weekly --> "WEEKLY SPENDING"

    kicker Monthly --> "MONTHLY SPENDING"

-}
kicker : Granularity -> String
kicker g =
    case g of
        Daily ->
            "DAILY SPENDING"

        Monthly ->
            "MONTHLY SPENDING"

        Weekly ->
            "WEEKLY SPENDING"
