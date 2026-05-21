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
    , body = viewBody as_.config (Just as_.showDayIntensity) as_.showInstallPrompt as_.version
    , hero = viewHero as_.config
    }


viewPanel : AppConfig -> Bool -> String -> Html Msg
viewPanel cfg isSignedIn version =
    Html.div [ Html.Attributes.class "px-5 py-6" ]
        [ viewHero cfg
        , Html.div [ Html.Attributes.class "mt-4" ]
            [ viewBody cfg
                (if isSignedIn then
                    Just True

                 else
                    Nothing
                )
                False
                version
            ]
        ]


viewHero : AppConfig -> Html Msg
viewHero _ =
    Html.div [ Html.Attributes.class "text-sm text-muted" ]
        [ Html.text "Local-first preferences. Nothing here leaves the device." ]


viewBody : AppConfig -> Maybe Bool -> Bool -> String -> Html Msg
viewBody cfg maybeDayIntensity showInstallPrompt version =
    let
        isSignedIn =
            maybeDayIntensity /= Nothing
    in
    Html.div []
        [ case maybeDayIntensity of
            Just dayIntensity ->
                viewDisplaySection dayIntensity

            Nothing ->
                Html.text ""
        , if showInstallPrompt then
            viewInstallSection

          else
            Html.text ""
        , UI.Rule.kicker "CONNECTION"
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


viewDisplaySection : Bool -> Html Msg
viewDisplaySection dayIntensity =
    Html.div []
        [ UI.Rule.kicker "DISPLAY"
        , UI.Card.subCard
            [ viewToggleRow
                { helper = "Tint the rule between DAY and date by how this day's total compares to the trip's median spend."
                , label = "Day spending intensity"
                , msg = ToggleDayIntensity
                , value = dayIntensity
                }
            ]
        ]


viewInstallSection : Html Msg
viewInstallSection =
    Html.div []
        [ UI.Rule.kicker "INSTALL"
        , UI.Card.subCard
            [ Html.p [ Html.Attributes.class "text-xs text-muted mb-3" ]
                [ Html.text "Add Ternpike to your home screen for an app-like, full-screen experience." ]
            , UI.Button.secondary { label = "Install app", onClick = TriggerInstallPrompt }
            ]
        ]


viewToggleRow : { helper : String, label : String, msg : Msg, value : Bool } -> Html Msg
viewToggleRow { helper, label, msg, value } =
    Html.div [ Html.Attributes.class "flex items-start justify-between gap-4" ]
        [ Html.div [ Html.Attributes.class "flex-1 min-w-0" ]
            [ Html.div [ Html.Attributes.class "text-sm text-ink" ] [ Html.text label ]
            , Html.p [ Html.Attributes.class "text-xs text-muted mt-1" ] [ Html.text helper ]
            ]
        , Html.button
            [ Html.Attributes.type_ "button"
            , Html.Events.onClick msg
            , Html.Attributes.attribute "role" "switch"
            , Html.Attributes.attribute "aria-checked"
                (if value then
                    "true"

                 else
                    "false"
                )
            , Html.Attributes.attribute "aria-label" label
            , Html.Attributes.classList
                [ ( "relative shrink-0 w-11 h-6 rounded-full cursor-pointer transition-colors border", True )
                , ( "bg-moss border-moss", value )
                , ( "bg-cream-deep border-tan", not value )
                ]
            ]
            [ Html.span
                [ Html.Attributes.classList
                    [ ( "absolute top-0.5 w-5 h-5 rounded-full bg-parchment shadow-sm transition-all", True )
                    , ( "left-[22px]", value )
                    , ( "left-0.5", not value )
                    ]
                ]
                []
            ]
        ]
