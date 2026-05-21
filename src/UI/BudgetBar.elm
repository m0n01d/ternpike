module UI.BudgetBar exposing (view, viewMerged)

{-| Shared budget progress bar used by both the Trips and Ledger heroes.

The two view functions render the same track, fill, and color logic so the
"is this over budget?" treatment stays in lockstep across pages. They
differ only in what sits under the bar:

  - `view` — Trips-style: spent on the left, budget on the right
  - `viewMerged` — Ledger-style: `<pct>% of $<budget>` on the left, caller-
    supplied trailing content (e.g. entry/day counts) on the right

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
        , track st
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


viewMerged : { budget : Float, spent : Float, trailing : Html msg } -> Html msg
viewMerged { budget, spent, trailing } =
    let
        st =
            state spent budget

        percentText =
            if st.isOver then
                "100%+ of $" ++ String.fromInt (round budget)

            else
                String.fromInt st.pctInt ++ "% of $" ++ String.fromInt (round budget)

        percentClass =
            if st.isOver then
                "text-[10px] font-mono uppercase tracking-widest text-danger"

            else
                labelClass
    in
    Html.div []
        [ UI.Rule.dashedRule
        , track st
        , Html.div [ Html.Attributes.class "mt-2 flex justify-between items-baseline gap-3" ]
            [ Html.span [ Html.Attributes.class percentClass ]
                [ Html.text percentText ]
            , trailing
            ]
        ]



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


track : BarState -> Html msg
track st =
    let
        barColor =
            if st.isOver then
                "h-full bg-danger transition-all duration-500"

            else
                "h-full bg-rust transition-all duration-500"
    in
    Html.div [ Html.Attributes.class "h-2 bg-cream-deep rounded-full overflow-hidden" ]
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
