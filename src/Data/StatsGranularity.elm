module Data.StatsGranularity exposing (Granularity(..), all, default, kicker, label, resolve)

{-| The user-facing time-binning choice for the Daily Spending chart.

The chart picks a bin size — daily, weekly, or monthly — so that long trips
don't collapse into a smear of hair-thin bars. `Auto` is the default and
chooses based on trip length; `Daily`/`Weekly`/`Monthly` are explicit
overrides surfaced by a chip selector on the Stats tab.

Lives on `AuthState.statsGranularity`. In-memory only — resets on sign-out
or refresh. No persistence.

@docs Granularity, all, default, kicker, label, resolve

-}


type Granularity
    = Auto
    | Daily
    | Monthly
    | Weekly


{-| Display order for the chip selector.
-}
all : List Granularity
all =
    [ Auto, Daily, Weekly, Monthly ]


{-| Initial state — let the chart decide based on trip length.
-}
default : Granularity
default =
    Auto


{-| Human-readable label for chip text and kicker derivations.

    label Auto --> "Auto"

    label Daily --> "Daily"

    label Weekly --> "Weekly"

    label Monthly --> "Monthly"

-}
label : Granularity -> String
label g =
    case g of
        Auto ->
            "Auto"

        Daily ->
            "Daily"

        Monthly ->
            "Monthly"

        Weekly ->
            "Weekly"


{-| The kicker text shown above the chart for a resolved (never `Auto`)
granularity.

    kicker Daily --> "DAILY SPENDING"

    kicker Weekly --> "WEEKLY SPENDING"

    kicker Monthly --> "MONTHLY SPENDING"

`Auto` falls back to the daily kicker — `resolve` will have replaced it
with a concrete granularity before this is called, but the case is
exhaustive to keep the compiler happy.

-}
kicker : Granularity -> String
kicker g =
    case g of
        Auto ->
            "DAILY SPENDING"

        Daily ->
            "DAILY SPENDING"

        Monthly ->
            "MONTHLY SPENDING"

        Weekly ->
            "WEEKLY SPENDING"


{-| Resolve `Auto` to a concrete granularity based on the inclusive span
in days between the trip's first and last day with spend.

  - ≤ 35 days → daily (a month-long trip still reads as ~30 narrow bars).
  - ≤ 210 days → weekly (≈30 weekly bars for a 7-month trip).
  - otherwise → monthly.

Explicit choices pass through unchanged.

    resolve Auto 22 --> Daily

    resolve Auto 100 --> Weekly

    resolve Auto 400 --> Monthly

    resolve Weekly 22 --> Weekly

-}
resolve : Granularity -> Int -> Granularity
resolve g spanDays =
    case g of
        Auto ->
            if spanDays <= 35 then
                Daily

            else if spanDays <= 210 then
                Weekly

            else
                Monthly

        _ ->
            g
