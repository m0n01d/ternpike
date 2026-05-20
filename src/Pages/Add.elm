module Pages.Add exposing (viewTab)

import Data.Category as Category exposing (Category(..))
import Dict
import Helpers exposing (formatCoord)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Types exposing (..)
import UI.Button
import UI.Card
import UI.Layout
import UI.Rule


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = viewActions as_
    , body = viewBody as_
    , hero = viewHero as_
    }


viewActions : AuthState -> List (Html Msg)
viewActions model =
    if model.activeScanItemId /= Nothing then
        [ UI.Button.ghost { label = "← queue", onClick = BackToQueue } ]

    else if model.editingEntry /= Nothing then
        [ UI.Button.ghost { label = "← cancel", onClick = CancelEdit } ]

    else
        []


viewHero : AuthState -> Html Msg
viewHero model =
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "AMOUNT" ]
        , Html.div [ Html.Attributes.class "flex items-baseline gap-2" ]
            [ Html.span
                [ Html.Attributes.class "font-display text-5xl font-black text-forest leading-none" ]
                [ Html.text "$" ]
            , Html.input
                [ Html.Attributes.type_ "number"
                , Html.Attributes.attribute "inputmode" "decimal"
                , Html.Attributes.value model.pendingEntry.amount
                , Html.Events.onInput AmountChanged
                , Html.Attributes.placeholder "0.00"
                , Html.Attributes.class "w-full bg-transparent border-0 outline-none font-display text-5xl font-black text-forest tabular-nums tracking-tight leading-none"
                ]
                []
            ]
        ]
