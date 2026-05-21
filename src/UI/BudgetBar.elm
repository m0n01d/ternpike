module UI.BudgetBar exposing (view, viewSubtle)

{-| Shared budget progress bar used by the Trips and Ledger heroes.

Two variants, same color logic (rust fill, danger when over budget):

  - `view` — Trips-style: a labelled bar inside the hero with spent on the
    left and budget on the right, sitting under a dashed rule.
  - `viewSubtle` — Ledger-style: a thin un-labelled bar absolute-positioned
    against the bottom edge of the hero card. The hero card in
    `UI.Layout.page` is already `relative overflow-hidden`, so the bar
    follows the card's rounded corners and never affects the hero's text
    layout.

Render nothing for `budget <= 0` upstream; this module assumes a positive
budget.

-}

import Html exposing (Html)
import Html.Attributes
import UI.Rule


view : { spent : Float, budget : Float } -> Html msg
view { spent, budget } =
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
                    [ Html.text ("$" ++ String.fromInt (round spent)) ]
                , Html.span [ Html.Attributes.class labelClass ]
                    [ Html.text "spent" ]
                ]
            , Html.div [ Html.Attributes.class "flex items-baseline gap-1.5" ]
                [ Html.span [ Html.Attributes.class "text-sm font-semibold text-forest" ]
                    [ Html.text ("$" ++ String.fromInt (round budget)) ]
                , Html.span [ Html.Attributes.class labelClass ]
                    [ Html.text "budget" ]
                ]
            ]
        ]


viewSubtle : { spent : Float, budget : Float } -> Html msg
viewSubtle { spent, budget } =
    track (state spent budget)
        "absolute bottom-0 left-0 right-0 h-1 bg-cream-deep"



-- INTERNAL


type alias BarState =
    { isOver : Bool
    , pctInt : Int
    }


state : Float -> Float -> BarState
state spent budget =
    let
        pct =
            Basics.min 1.0 (spent / budget)
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
