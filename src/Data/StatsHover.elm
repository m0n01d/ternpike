module Data.StatsHover exposing
    ( CumulativePoint, DailyDay, PricePoint
    , Hover, empty, setCumulative, setDaily, setPricePerGallon
    )

{-| Transient hover state for the Stats tab's three interactive charts.

Lives on `AuthState.statsHover`. Cleared whenever the pointer leaves a
chart; never persisted. Defined here (rather than inline in `Pages.Stats`)
because `Types.AuthState` references it — and `Types` cannot import
`Pages.Stats` without a circular import.


# Data record types

Each record type is the per-datum shape passed into `Chart.bars` /
`Chart.series`. The `Hover` field types wrap them as elm-charts
`Chart.Item.One` handles so that `Chart.tooltip` can render anchored
tooltips for them.

@docs CumulativePoint, DailyDay, PricePoint


# Hover state

@docs Hover, empty, setCumulative, setDaily, setPricePerGallon

-}

import Chart.Item as CI


{-| One bar in the Daily Spending chart.

`date` is the bin's start (ISO `YYYY-MM-DD`); `endDate` is the inclusive
last day in the bin. `endDate == date` means a single-day bin (`Daily`
granularity); otherwise the bin spans a week or a calendar month and the
tooltip renders the range.

-}
type alias DailyDay =
    { date : String
    , endDate : String
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


{-| One point on the Price-per-Gallon trend line: the underlying ISO date
plus the `(x, y)` chart coordinates (`x` is the 1-based fuel-up index,
`y` is the price in dollars).
-}
type alias PricePoint =
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
    , pricePerGallonPoints : List (CI.One PricePoint CI.Dot)
    }


{-| Initial state — nothing hovered.
-}
empty : Hover
empty =
    { cumulativePoints = []
    , dailyBars = []
    , pricePerGallonPoints = []
    }


setDaily : Hover -> List (CI.One DailyDay CI.Bar) -> Hover
setDaily hover items =
    { hover | dailyBars = items }


setCumulative : Hover -> List (CI.One CumulativePoint CI.Dot) -> Hover
setCumulative hover items =
    { hover | cumulativePoints = items }


setPricePerGallon : Hover -> List (CI.One PricePoint CI.Dot) -> Hover
setPricePerGallon hover items =
    { hover | pricePerGallonPoints = items }
