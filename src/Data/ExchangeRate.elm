module Data.ExchangeRate exposing
    ( RateTable
    , asOf
    , empty
    , estimate
    , httpDecoder
    , isEmpty
    , rateFor
    )

{-| A table of exchange rates for the optional spend **estimate** (#448).

Ternpike records every amount in its native currency and never converts —
this table only powers a _derived, presentation-only_ estimate of a
multi-currency trip's total in the home currency (USD). It is never written
back onto an expense.

Rates are **home-per-foreign**: `rates["cad"] = 0.73` means 1 CAD ≈ 0.73 USD,
so a native amount is multiplied by its rate to estimate USD. The home
currency itself is implicitly `1.0` (see `rateFor`). Keys are lowercase ISO
codes matching `Data.Currency`'s wire form. The table is fetched from the
`/rates` Worker endpoint (free, mid-market daily reference rates) and cached
in the synced `Data.UserSettings` doc; `asOf` carries the rate date so the UI
can caption "est. · as of <date>".

-}

import Data.Currency as Currency exposing (Currency)
import Data.DateField as DateField exposing (DateField)
import Data.Money as Money exposing (Money)
import Dict exposing (Dict)
import Json.Decode


{-| Home-per-foreign rates keyed by lowercase ISO code, plus the date the
rates were published (for the "as of" caption).
-}
type alias RateTable =
    { asOf : Maybe DateField
    , rates : Dict String Float
    }


{-| The empty table — no rates known yet (estimate is hidden).
-}
empty : RateTable
empty =
    { asOf = Nothing, rates = Dict.empty }


{-| True when no rates are known, so callers can suppress the estimate.
-}
isEmpty : RateTable -> Bool
isEmpty table =
    Dict.isEmpty table.rates


{-| The publication date of the rates, for the "est. · as of <date>" caption.
-}
asOf : RateTable -> Maybe DateField
asOf table =
    table.asOf


{-| The factor to multiply a `currency` amount by to estimate home (USD). The
home currency is 1:1; other currencies come from the table; an unknown
currency is `Nothing` (so the caller reports a missing rate rather than
guessing).
-}
rateFor : RateTable -> Currency -> Maybe Float
rateFor table currency =
    if currency == Currency.usd then
        Just 1.0

    else
        Dict.get (String.toLower (Currency.code currency)) table.rates


{-| Estimate a native amount in the home currency, or `Nothing` when no rate
is known for that currency. Rounds to whole cents at the boundary.
-}
estimate : RateTable -> Currency -> Money -> Maybe Money
estimate table currency money =
    rateFor table currency
        |> Maybe.map
            (\factor ->
                Money.fromCents (round (toFloat (Money.toCents money) * factor))
            )


{-| Decode the `/rates` Worker response (`{ base, date, rates }`) into a
`RateTable`. Keys arrive lowercase; an absent/invalid `date` is tolerated.
-}
httpDecoder : Json.Decode.Decoder RateTable
httpDecoder =
    Json.Decode.map2 (\rates date -> { asOf = date, rates = rates })
        (Json.Decode.field "rates" (Json.Decode.dict Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field "date" DateField.decoder))
