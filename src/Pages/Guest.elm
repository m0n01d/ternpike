module Pages.Guest exposing (viewGuest)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Types exposing (..)
import UI.Layout exposing (viewSettingsPanel)


viewGuest : GuestState -> Html Msg
viewGuest gs =
    div
        [ style "display" "flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "justify-content" "center"
        , style "min-height" "100vh"
        , style "padding" "32px 24px"
        , style "text-align" "center"
        ]
        [ div [ style "font-size" "48px", style "margin-bottom" "16px" ] [ text "🏔" ]
        , h1
            [ style "font-size" "32px"
            , style "font-weight" "700"
            , style "color" "#e8a020"
            , style "letter-spacing" "0.05em"
            , style "margin-bottom" "8px"
            ]
            [ text "ALASKA TRACKER" ]
        , p [ style "color" "#7a8a80", style "margin-bottom" "24px", style "font-size" "16px" ]
            [ text "Road log for the long way north" ]
        , case gs.authError of
            Just err ->
                div
                    [ class "w-full mb-4 px-4 py-3 rounded-lg bg-[#2a1510] border border-[#e85030] text-[#e8a020] text-sm text-left" ]
                    [ text err ]

            Nothing ->
                case gs.session.reason of
                    SessionExpired ->
                        div
                            [ class "w-full mb-4 px-4 py-3 rounded-lg bg-[#2a1510] border border-[#e85030] text-[#e8a020] text-sm text-left" ]
                            [ text "Session expired — sign in to continue." ]

                    _ ->
                        text ""
        , case gs.session.reason of
            AwaitingCode _ ->
                div [ style "width" "100%", style "max-width" "320px" ]
                    [ p [ style "color" "#7a8a80", style "font-size" "14px", style "margin-bottom" "16px" ]
                        [ text ("A code was sent to " ++ gs.emailInput ++ ". Enter it below.") ]
                    , input
                        [ type_ "text"
                        , value gs.codeInput
                        , onInput CodeInputChanged
                        , placeholder "123456"
                        , style "width" "100%"
                        , style "margin-bottom" "12px"
                        ]
                        []
                    , button
                        [ onClick SubmitCode
                        , style "width" "100%"
                        , style "background" "#e8a020"
                        , style "color" "#0d0f0e"
                        , style "border" "none"
                        , style "border-radius" "8px"
                        , style "padding" "16px"
                        , style "font-size" "16px"
                        , style "font-weight" "700"
                        , style "cursor" "pointer"
                        , style "min-height" "52px"
                        ]
                        [ text "VERIFY CODE" ]
                    ]

            _ ->
                div [ style "width" "100%", style "max-width" "320px" ]
                    [ input
                        [ type_ "text"
                        , value gs.emailInput
                        , onInput EmailInputChanged
                        , placeholder "your@email.com"
                        , style "width" "100%"
                        , style "margin-bottom" "12px"
                        ]
                        []
                    , button
                        [ onClick SubmitEmail
                        , style "width" "100%"
                        , style "background" "#e8a020"
                        , style "color" "#0d0f0e"
                        , style "border" "none"
                        , style "border-radius" "8px"
                        , style "padding" "16px"
                        , style "font-size" "16px"
                        , style "font-weight" "700"
                        , style "cursor" "pointer"
                        , style "min-height" "52px"
                        ]
                        [ text "CONTINUE" ]
                    ]
        , div [ style "margin-top" "48px", style "width" "100%" ]
            [ button
                [ onClick ToggleGuestSettings
                , style "background" "none"
                , style "border" "1px solid #3a4240"
                , style "color" "#7a8a80"
                , style "border-radius" "6px"
                , style "padding" "10px 20px"
                , style "font-size" "14px"
                , style "cursor" "pointer"
                ]
                [ text "⚙ Settings" ]
            , if gs.showSettings then
                viewSettingsPanel gs.session.config False gs.version

              else
                text ""
            ]
        ]
