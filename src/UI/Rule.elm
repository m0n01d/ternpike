module UI.Rule exposing (dashedRule, kicker)

import Html exposing (Html)
import Html.Attributes


dashedRule : Html msg
dashedRule =
    Html.hr
        [ Html.Attributes.class "border-0 border-t border-dashed border-tan/70 my-4" ]
        []


kicker : String -> Html msg
kicker label =
    Html.div
        [ Html.Attributes.class "text-xs font-mono uppercase tracking-widest text-moss mb-2" ]
        [ Html.text label ]
