module UI.Card exposing
    ( heroCard
    , ruledCard
    , subCard
    )

import Html exposing (Html)
import Html.Attributes


heroCard : { actions : List (Html msg), body : Html msg, kicker : String, title : String } -> Html msg
heroCard { actions, body, kicker, title } =
    Html.div
        [ Html.Attributes.class "relative bg-cream bg-topo rounded-card shadow-card p-5 mb-5 overflow-hidden" ]
        [ Html.div
            [ Html.Attributes.class "flex items-start justify-between gap-3 mb-3" ]
            [ Html.div [ Html.Attributes.class "flex flex-col" ]
                [ Html.span
                    [ Html.Attributes.class "font-mono text-xs uppercase tracking-widest text-moss mb-1" ]
                    [ Html.text kicker ]
                , Html.h2
                    [ Html.Attributes.class "font-display text-3xl font-black text-forest leading-tight" ]
                    [ Html.text title ]
                ]
            , Html.div [ Html.Attributes.class "flex items-center gap-2 shrink-0" ] actions
            ]
        , Html.div [ Html.Attributes.class "relative" ] [ body ]
        ]


ruledCard : List (Html msg) -> Html msg
ruledCard children =
    Html.div
        [ Html.Attributes.class "rounded-card p-4 mb-4 border-t border-b border-dashed border-tan/70" ]
        children


subCard : List (Html msg) -> Html msg
subCard children =
    Html.div
        [ Html.Attributes.class "bg-cream rounded-card p-4 mb-4" ]
        children
