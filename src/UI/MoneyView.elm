module UI.MoneyView exposing (amount, wholeDollars)

{-| Elm-side wrappers around the `<tp-amount>` web component.

`<tp-amount>` is defined in `src/elements/tp-amount.js`. It uses
`Intl.NumberFormat` to render a `Money` amount with the correct thousands
separator and decimal placement for the active locale, and carries the a11y
contract that makes screen readers announce "twelve dollars and thirty-four
cents" instead of "dollar sign one two point three four". See the docstring
at the top of `src/elements/tp-amount.js` for the full contract.

Both helpers in this module emit `<tp-amount value="..." currency="USD">`
nodes. The locale defaults to the closest ancestor `lang` attribute,
falling back to `document.documentElement.lang` or `"en-US"`. When a
per-user locale picker ships (#23) the element will pick it up
automatically — no per-call-site plumbing needed.

This module is the only place in the codebase that should construct
`<tp-amount>` nodes — keep new currency-rendering sites going through here
so the a11y attributes never drift.

-}

import Data.Money as Money exposing (Money)
import Html exposing (Html)
import Html.Attributes


{-| Render a `Money` value with two decimals (the default for USD).

Use this in body copy, ledger rows, totals — anywhere you want the full
`$1,234.56` shape. Replaces `Html.text (Money.format m)`.

-}
amount : Money -> Html msg
amount m =
    Html.node "tp-amount"
        [ Html.Attributes.attribute "value" (Money.toDollarString m)
        , Html.Attributes.attribute "currency" "USD"
        ]
        []


{-| Render a `Money` value with no fractional digits (i.e. dollars only).

The hero `UI.BudgetBar` chips use this — the small "spent / budget" labels
sit on a tight baseline and a `.56` tail would break the line height.
Replaces the deleted `UI.BudgetBar.formatWholeDollars`.

-}
wholeDollars : Money -> Html msg
wholeDollars m =
    Html.node "tp-amount"
        [ Html.Attributes.attribute "value" (Money.toDollarString m)
        , Html.Attributes.attribute "currency" "USD"
        , Html.Attributes.attribute "maximumfractiondigits" "0"
        ]
        []
