module UI.Card exposing (subCard)

import Html exposing (Html)
import Html.Attributes


subCard : List (Html msg) -> Html msg
subCard children =
    Html.div
        [ Html.Attributes.class "bg-cream rounded-card p-4 mb-4" ]
        children
