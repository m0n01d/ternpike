module UI.MoneyView exposing (amount, heroTotal, wholeDollars)

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
import Data.Entry as Entry
import Data.ExchangeRate as ExchangeRate exposing (RateTable)
import Data.Money as Money exposing (Money)
import Html exposing (Html)
import Html.Attributes
import UI.DateView


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


{-| The trip's hero total — the single entry point the Ledger and Stats heroes
use for the big spend figure. Picks the right layout for the trip's currency
shape:

  - **Single currency** (the common case): one big native number, byte-identical
    to before. If it's a _foreign_ single currency with a rate available, a
    small `≈ $… USD · est.` line sits below it.
  - **Multi-currency, rate available**: the converted home-currency estimate as
    the big headline (`≈ $420 USD`, clearly marked an estimate), with the exact
    native amounts stacked beneath under an "actually spent" label — the source
    of truth, never hidden.
  - **Multi-currency, no rate** (offline, or an un-rated currency): the native
    amounts stacked as the headline (they can't collapse to one number).

This owns its own font sizing (the call sites no longer wrap it in a
`text-5xl` container). Ternpike never converts on the data path — the estimate
headline is derived, presentation-only, and `≈`/`est.`-marked so it can't be
mistaken for what was actually spent.

-}
heroTotal : RateTable -> List Entry.EffectiveEntry -> Html msg
heroTotal rates entries =
    let
        subtotals : List ( Currency, Money )
        subtotals =
            Entry.totalsByCurrency entries

        est : { missing : List Currency, total : Money }
        est =
            Entry.estimatedHomeTotal (ExchangeRate.estimate rates) entries

        estimateShown : Bool
        estimateShown =
            not (ExchangeRate.isEmpty rates)
                && (Money.toCents est.total > 0)
                && List.any (\e -> e.currency /= Currency.usd) entries
    in
    case subtotals of
        [] ->
            bigAmount Currency.usd Money.zero

        [ ( currency, m ) ] ->
            Html.div []
                (bigAmount currency m
                    :: (if estimateShown then
                            [ estimateLine est rates ]

                        else
                            []
                       )
                )

        many ->
            if estimateShown then
                Html.div []
                    [ estimateHeadline est
                    , estimateCaption rates
                    , breakdown many
                    ]

            else
                stackedNative many


bigAmount : Currency -> Money -> Html msg
bigAmount currency m =
    Html.div
        [ Html.Attributes.class "font-display text-5xl font-black text-forest tracking-tight leading-none" ]
        [ amount currency m ]


stackedNative : List ( Currency, Money ) -> Html msg
stackedNative pairs =
    Html.div
        [ Html.Attributes.class "font-display text-4xl font-black text-forest tracking-tight leading-tight" ]
        (List.map (\( currency, m ) -> Html.div [] [ amount currency m ]) pairs)


estimateHeadline : { missing : List Currency, total : Money } -> Html msg
estimateHeadline est =
    -- text-4xl (vs the single-currency text-5xl) keeps `≈ $11,147.00` on one
    -- line at mobile width even for large totals, and matches the stacked-native
    -- size so the estimate reads as a peer of the native headline, not louder.
    Html.div
        [ Html.Attributes.class "font-display text-4xl font-black text-forest tracking-tight leading-none" ]
        [ Html.span [ Html.Attributes.attribute "aria-hidden" "true" ] [ Html.text "≈ " ]
        , amount Currency.usd est.total
        , if List.isEmpty est.missing then
            Html.text ""

          else
            -- "+" means "at least" (some currency had no rate); decorative, so
            -- hidden from the reader rather than spoken "plus".
            Html.span [ Html.Attributes.attribute "aria-hidden" "true" ] [ Html.text "+" ]
        ]


estimateCaption : RateTable -> Html msg
estimateCaption rates =
    Html.div
        [ Html.Attributes.class "mt-1 text-[11px] font-mono tracking-wide text-muted" ]
        (Html.text "est."
            :: (case ExchangeRate.asOf rates of
                    Just date ->
                        [ Html.text " · as of ", UI.DateView.monthDay date ]

                    Nothing ->
                        []
               )
        )


breakdown : List ( Currency, Money ) -> Html msg
breakdown pairs =
    Html.div
        [ Html.Attributes.class "mt-3 pt-2 border-t border-tan/50" ]
        (Html.div
            [ Html.Attributes.class "text-[9px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "Actually spent" ]
            :: List.map breakdownRow pairs
        )


breakdownRow : ( Currency, Money ) -> Html msg
breakdownRow ( currency, m ) =
    Html.div
        [ Html.Attributes.class "flex items-baseline justify-between py-0.5" ]
        [ Html.span
            [ Html.Attributes.class "text-[11px] font-mono uppercase tracking-wider text-muted" ]
            [ Html.text (Currency.code currency) ]
        , Html.div
            [ Html.Attributes.class "font-display text-xl font-bold text-forest" ]
            [ amount currency m ]
        ]


{-| The small `≈ $… USD · est.` line used under a single foreign-currency
total (the multi-currency case promotes the estimate to a headline instead —
see `heroTotal`).
-}
estimateLine : { missing : List Currency, total : Money } -> RateTable -> Html msg
estimateLine est rates =
    Html.div [ Html.Attributes.class "mt-1 text-sm font-mono text-moss" ]
        [ Html.span [ Html.Attributes.attribute "aria-hidden" "true" ] [ Html.text "≈ " ]
        , amount Currency.usd est.total
        , if List.isEmpty est.missing then
            Html.text ""

          else
            Html.span [ Html.Attributes.attribute "aria-hidden" "true" ] [ Html.text "+" ]
        , Html.span [ Html.Attributes.class "text-muted" ]
            (Html.text " · est."
                :: (case ExchangeRate.asOf rates of
                        Just date ->
                            [ Html.text " · as of ", UI.DateView.monthDay date ]

                        Nothing ->
                            []
                   )
            )
        ]


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
