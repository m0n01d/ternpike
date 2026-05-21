module Pages.Settings exposing (viewPanel, viewTab)

import Data.Auth exposing (AppConfig)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Types exposing (AuthState, Msg(..))
import UI.Button
import UI.Card
import UI.Layout
import UI.Rule


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
viewHero _ =
    Html.div [ Html.Attributes.class "text-sm text-muted" ]
        [ Html.text "Local-first preferences. Nothing here leaves the device." ]


viewBody : AppConfig -> Bool -> String -> Html Msg
viewBody cfg isSignedIn version =
    Html.div []
        [ UI.Rule.kicker "CONNECTION"
        , UI.Card.subCard
            [ UI.Layout.formField "Anthropic API key"
                (Html.input
                    [ Html.Attributes.type_ "password"
                    , Html.Attributes.value cfg.anthropicKey
                    , Html.Events.onInput ApiKeyChanged
                    , Html.Attributes.placeholder "sk-ant-..."
                    , UI.Layout.textInputStyle
                    ]
                    []
                )
            , Html.p [ Html.Attributes.class "text-xs text-muted mt-2" ]
                [ Html.text "Used to read receipts locally. Never sent to Ternpike servers." ]
            ]
        , UI.Rule.kicker "SESSION"
        , UI.Card.subCard
            [ Html.div [ Html.Attributes.class "flex flex-col gap-3" ]
                ((if isSignedIn then
                    [ UI.Button.secondary { label = "Sign out", onClick = SignOutClicked } ]

                  else
                    []
                 )
                    ++ [ UI.Button.ghost { label = "Reset local data", onClick = ResetSettingsClicked } ]
                )
            ]
        , if version /= "" then
            Html.div [ Html.Attributes.class "mt-6 text-center text-[10px] font-mono uppercase tracking-widest text-muted" ]
                [ Html.text ("VERSION " ++ version) ]

          else
            Html.text ""
        ]
