module UI.BudgetBar exposing (view, viewLine, viewSubtle)

{-| Shared budget progress bar used across hero cards.

Three variants, same color logic (rust fill, danger when over budget):

  - `view` — Trips-style: a labelled bar inside the hero with spent on the
    left and budget on the right, sitting under a dashed rule.
  - `viewSubtle` — Ledger-style: a thin un-labelled bar absolute-positioned
    against the bottom edge of the hero card. The hero card in
    `UI.Layout.page` is already `relative overflow-hidden`, so the bar
    follows the card's rounded corners and never affects the hero's text
    layout.
  - `viewLine` — Stats-style: a thin un-labelled bar sitting in flow as a
    divider, intended as a drop-in replacement for `UI.Rule.dashedRule`.

Render nothing for a zero budget upstream; this module assumes a positive
budget.

Spent + budget are `Data.Money.Money` (#93): the labels render via
`UI.MoneyView.wholeDollars`, which emits a `<tp-amount …
maximumfractiondigits="0">` web component with Intl.NumberFormat-driven
thousands separators and a screen-reader-friendly `aria-label`.

-}

import Data.Currency
import Data.Money as Money exposing (Money)
import Html exposing (Html)
import Html.Attributes
import UI.MoneyView
import UI.Rule


view : { budget : Money, spent : Money } -> Html msg
view { budget, spent } =
    let
        st =
            state spent budget

        spentAmountClass =
            if st.isOver then
                "text-sm font-semibold text-danger"

            else
                "text-sm font-semibold text-rust"
    in
    Html.div []
        [ UI.Rule.dashedRule
        , track st "h-2 bg-cream-deep rounded-full overflow-hidden"
        , Html.div [ Html.Attributes.class "mt-2 flex justify-between items-baseline gap-3" ]
            [ Html.div [ Html.Attributes.class "flex items-baseline gap-1.5" ]
                [ Html.span [ Html.Attributes.class spentAmountClass ]
                    [ UI.MoneyView.wholeDollars Data.Currency.usd spent ]
                , Html.span [ Html.Attributes.class labelClass ]
                    [ Html.text "spent" ]
                ]
            , Html.div [ Html.Attributes.class "flex items-baseline gap-1.5" ]
                [ Html.span [ Html.Attributes.class "text-sm font-semibold text-forest" ]
                    [ UI.MoneyView.wholeDollars Data.Currency.usd budget ]
                , Html.span [ Html.Attributes.class labelClass ]
                    [ Html.text "budget" ]
                ]
            ]
        ]


viewSubtle : { budget : Money, spent : Money } -> Html msg
viewSubtle { budget, spent } =
    track (state spent budget)
        "absolute bottom-0 left-0 right-0 h-1 bg-cream-deep"


viewLine : { budget : Money, spent : Money } -> Html msg
viewLine { budget, spent } =
    track (state spent budget)
        "h-1 bg-cream-deep rounded-full overflow-hidden my-4"



-- INTERNAL


type alias BarState =
    { isOver : Bool
    , pctInt : Int
    }


state : Money -> Money -> BarState
state spent budget =
    let
        budgetCents =
            Money.toCents budget

        spentCents =
            Money.toCents spent

        pct =
            if budgetCents <= 0 then
                1.0

            else
                Basics.min 1.0 (toFloat spentCents / toFloat budgetCents)
    in
    { isOver = pct >= 1.0
    , pctInt = round (pct * 100)
    }


track : BarState -> String -> Html msg
track st trackClass =
    let
        barColor =
            if st.isOver then
                "h-full bg-danger transition-all duration-500"

            else
                "h-full bg-rust transition-all duration-500"
    in
    Html.div [ Html.Attributes.class trackClass ]
        [ Html.div
            [ Html.Attributes.class barColor

            -- dynamic percentage width; cannot be expressed as a static Tailwind class
            , Html.Attributes.style "width" (String.fromInt st.pctInt ++ "%")
            ]
            []
        ]


labelClass : String
labelClass =
    "text-[10px] font-mono uppercase tracking-widest text-moss"
