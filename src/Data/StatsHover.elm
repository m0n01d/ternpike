module Data.StatsHover exposing
    ( CumulativePoint, DailyDay
    , Hover, empty, setCumulative, setDaily
    )

{-| Transient hover state for the Stats tab's two interactive charts.

Lives on `AuthState.statsHover`. Cleared whenever the pointer leaves a
chart; never persisted. Defined here (rather than inline in `Pages.Stats`)
because `Types.AuthState` references it — and `Types` cannot import
`Pages.Stats` without a circular import.


# Data record types

Each record type is the per-datum shape passed into `Chart.bars` /
`Chart.series`. The `Hover` field types wrap them as elm-charts
`Chart.Item.One` handles so that `Chart.tooltip` can render anchored
tooltips for them.

@docs CumulativePoint, DailyDay


# Hover state

@docs Hover, empty, setCumulative, setDaily

-}

import Chart.Item as CI


{-| One bar in the Daily Spending chart: a date string (ISO `YYYY-MM-DD`)
and the day's total spend.
-}
type alias DailyDay =
    { date : String
    , total : Float
    }


{-| One point on the Cumulative Spend line: the underlying ISO date plus
the `(x, y)` chart coordinates (`x` is the 1-based day index, `y` is the
running total).
-}
type alias CumulativePoint =
    { date : String
    , x : Float
    , y : Float
    }


{-| Which chart datapoint(s) the user is currently hovering / tapping.
Empty lists mean "not hovering this chart."
-}
type alias Hover =
    { cumulativePoints : List (CI.One CumulativePoint CI.Dot)
    , dailyBars : List (CI.One DailyDay CI.Bar)
    }


{-| Initial state — nothing hovered.
-}
empty : Hover
empty =
    { cumulativePoints = []
    , dailyBars = []
    }


setDaily : Hover -> List (CI.One DailyDay CI.Bar) -> Hover
setDaily hover items =
    { hover | dailyBars = items }


setCumulative : Hover -> List (CI.One CumulativePoint CI.Dot) -> Hover
setCumulative hover items =
    { hover | cumulativePoints = items }
