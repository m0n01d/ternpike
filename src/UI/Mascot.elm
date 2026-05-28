module UI.Mascot exposing (loading, ternSvg)

import Html exposing (Html)
import Html.Attributes
import Svg
import Svg.Attributes
import Types exposing (Msg)
import UI.Theme


ternSvg : String -> Html Msg
ternSvg className =
    Svg.svg
        [ Svg.Attributes.width "120"
        , Svg.Attributes.height "80"
        , Svg.Attributes.viewBox "0 0 120 80"
        , Svg.Attributes.fill "none"
        , Svg.Attributes.class className
        ]
        [ Svg.path
            [ Svg.Attributes.d "M60 40 C40 26, 8 20, 0 29 C16 28, 38 34, 60 44Z"
            , Svg.Attributes.fill UI.Theme.colorForest
            ]
            []
        , Svg.path
            [ Svg.Attributes.d "M60 40 C80 26, 112 20, 120 29 C104 28, 82 34, 60 44Z"
            , Svg.Attributes.fill UI.Theme.colorForestMid
            ]
            []
        , Svg.ellipse
            [ Svg.Attributes.cx "60"
            , Svg.Attributes.cy "43"
            , Svg.Attributes.rx "20"
            , Svg.Attributes.ry "7"
            , Svg.Attributes.fill UI.Theme.colorForest
            ]
            []
        , Svg.g
            [ Svg.Attributes.transform "rotate(-12 42 43)" ]
            [ Svg.path
                [ Svg.Attributes.d "M42 43 L18 38"
                , Svg.Attributes.stroke UI.Theme.colorForest
                , Svg.Attributes.strokeWidth "2.5"
                , Svg.Attributes.strokeLinecap "round"
                ]
                []
            , Svg.path
                [ Svg.Attributes.d "M42 43 L18 48"
                , Svg.Attributes.stroke UI.Theme.colorForest
                , Svg.Attributes.strokeWidth "2"
                , Svg.Attributes.strokeLinecap "round"
                ]
                []
            ]
        , Svg.ellipse
            [ Svg.Attributes.cx "76"
            , Svg.Attributes.cy "40"
            , Svg.Attributes.rx "9"
            , Svg.Attributes.ry "7"
            , Svg.Attributes.fill UI.Theme.colorInk
            ]
            []
        , Svg.path
            [ Svg.Attributes.d "M84 40 L96 38.5 L84 42Z"
            , Svg.Attributes.fill UI.Theme.colorRust
            ]
            []
        , Svg.circle
            [ Svg.Attributes.cx "79"
            , Svg.Attributes.cy "38.5"
            , Svg.Attributes.r "1.8"
            , Svg.Attributes.fill UI.Theme.colorTan
            ]
            []
        , Svg.circle
            [ Svg.Attributes.cx "79.5"
            , Svg.Attributes.cy "38.5"
            , Svg.Attributes.r "0.8"
            , Svg.Attributes.fill UI.Theme.colorInk
            ]
            []
        ]


{-| The tern mascot playing the soar animation, for use as a loading indicator.
-}
loading : Html Msg
loading =
    Html.div
        [ Html.Attributes.class "flex flex-col items-center justify-center gap-3 py-8" ]
        [ ternSvg "w-16 h-auto animate-soar"
        , Html.span
            [ Html.Attributes.class "text-xs font-mono tracking-widest text-muted uppercase" ]
            [ Html.text "Loading…" ]
        ]
