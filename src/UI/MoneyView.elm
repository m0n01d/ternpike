module UI.MoneyView exposing (amount, totals, wholeDollars)

{-| Elm-side wrappers around the `<tp-amount>` web component.

`<tp-amount>` is defined in `src/elements/tp-amount.js`. It uses
`Intl.NumberFormat` to render a `Money` amount with the correct thousands
separator and decimal placement for the active locale, and carries the a11y
contract that makes screen readers announce "twelve dollars and thirty-four
cents" instead of "dollar sign one two point three four". See the docstring
at the top of `src/elements/tp-amount.js` for the full contract.

Both helpers in this module emit `<tp-amount value="..." currency="...">`
nodes, where the currency is the expense's own `Data.Currency` (rendered as
its ISO 4217 code) — `Intl.NumberFormat` turns `CAD` into `CA$` and `USD`
into `$`. The locale defaults to the closest ancestor `lang` attribute,
falling back to `document.documentElement.lang` or `"en-US"`. When a
per-user locale picker ships (#23) the element will pick it up
automatically — no per-call-site plumbing needed.

This module is the only place in the codebase that should construct
`<tp-amount>` nodes — keep new currency-rendering sites going through here
so the a11y attributes never drift.

-}

import Data.Currency as Currency exposing (Currency)
import Data.Money as Money exposing (Money)
import Html exposing (Html)
import Html.Attributes


{-| Render a `Money` value in the given currency with two decimals.

Use this in body copy, ledger rows, totals — anywhere you want the full
`$1,234.56` (or `CA$1,234.56`) shape. Replaces `Html.text (Money.format m)`.

-}
amount : Currency -> Money -> Html msg
amount currency m =
    Html.node "tp-amount"
        [ Html.Attributes.attribute "value" (Money.toDollarString m)
        , Html.Attributes.attribute "currency" (Currency.code currency)
        ]
        []


{-| Render a list of per-currency subtotals (from
`Data.Entry.totalsByCurrency`) as one inline group, each amount in its own
currency, separated by a middot.

Ternpike never converts between currencies, so a mixed US/Canada trip total
can't collapse to one number — this shows `$1,200 · CA$340`. A single-currency
trip yields a one-element list and renders exactly like a bare
`amount` call, so existing all-USD trips are visually unchanged. The amounts
inherit the surrounding font size (the Ledger/Stats heroes are large-text
containers).

-}
totals : List ( Currency, Money ) -> Html msg
totals pairs =
    Html.span []
        (pairs
            |> List.map (\( currency, m ) -> amount currency m)
            |> List.intersperse
                (Html.span
                    [ Html.Attributes.class "px-2 text-muted" ]
                    [ Html.text "·" ]
                )
        )


{-| Render a `Money` value in the given currency with no fractional digits
(i.e. dollars only).

The hero `UI.BudgetBar` chips use this — the small "spent / budget" labels
sit on a tight baseline and a `.56` tail would break the line height.
Replaces the deleted `UI.BudgetBar.formatWholeDollars`.

-}
wholeDollars : Currency -> Money -> Html msg
wholeDollars currency m =
    Html.node "tp-amount"
        [ Html.Attributes.attribute "value" (Money.toDollarString m)
        , Html.Attributes.attribute "currency" (Currency.code currency)
        , Html.Attributes.attribute "maximumfractiondigits" "0"
        ]
        []
