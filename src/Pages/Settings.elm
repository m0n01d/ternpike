module Pages.Settings exposing (viewPanel, viewTab)

import Html exposing (Html)
import Html.Attributes
import Html.Events
import Types exposing (..)
import UI.Layout


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = []
    , body = viewBody as_.config True as_.version
    , hero = viewHero as_.config
    }


viewPanel : AppConfig -> Bool -> String -> Html Msg
viewPanel cfg isSignedIn version =
    Html.div [ Html.Attributes.class "px-5 py-6" ]
        [ viewHero cfg
        , Html.div [ Html.Attributes.class "mt-4" ]
            [ viewBody cfg isSignedIn version ]
        ]


viewHero : AppConfig -> Html Msg
viewHero cfg =
    UI.Layout.formField "ANTHROPIC API KEY"
        (Html.input
            [ Html.Attributes.type_ "password"
            , Html.Attributes.value cfg.anthropicKey
            , Html.Events.onInput ApiKeyChanged
            , Html.Attributes.placeholder "sk-ant-..."
            , UI.Layout.textInputStyle
            ]
            []
        )


viewBody : AppConfig -> Bool -> String -> Html Msg
viewBody _ isSignedIn version =
    Html.div []
        [ if isSignedIn then
            Html.button
                [ Html.Events.onClick SignOutClicked
                , Html.Attributes.class "w-full bg-transparent border border-rust text-rust rounded-lg py-3.5 text-[15px] cursor-pointer"
                ]
                [ Html.text "SIGN OUT" ]

          else
            Html.text ""
        , Html.div [ Html.Attributes.class "mt-2" ]
            [ Html.button
                [ Html.Events.onClick ResetSettingsClicked
                , Html.Attributes.class "w-full bg-transparent border border-tan text-muted rounded-lg py-3.5 text-sm cursor-pointer"
                ]
                [ Html.text "Reset all settings" ]
            ]
        , if version /= "" then
            Html.p [ Html.Attributes.class "text-muted text-[11px] text-center mt-6 font-mono" ]
                [ Html.text version ]

          else
            Html.text ""
        ]
