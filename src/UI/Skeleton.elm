module UI.Skeleton exposing (card, row, text)

import Html exposing (Html)
import Html.Attributes


card : Html msg
card =
    Html.div
        [ Html.Attributes.class "animate-pulse-soft bg-tan/60 rounded w-full h-24 mb-3" ]
        []


row : Html msg
row =
    Html.div
        [ Html.Attributes.class "animate-pulse-soft bg-tan/60 rounded w-full h-12 mb-2 px-4" ]
        []


text : String -> Html msg
text widthClass =
    Html.div
        [ Html.Attributes.class ("animate-pulse-soft bg-tan/60 rounded h-3 " ++ widthClass) ]
        []
