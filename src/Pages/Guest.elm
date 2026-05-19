module Pages.Guest exposing (viewGuest)

import Html exposing (Html)
import Html.Attributes
import Html.Events
import Types exposing (..)
import Pages.Settings
import UI.Mascot


viewGuest : GuestState -> Html Msg
viewGuest gs =
    Html.div
        [ Html.Attributes.class "flex flex-col items-center justify-center min-h-screen px-6 py-8 text-center" ]
        [ UI.Mascot.ternSvg "animate-soar mb-6 w-36"
        , Html.h1
            [ Html.Attributes.class "text-4xl font-black font-display tracking-tight mb-2 text-forest" ]
            [ Html.text "Tern"
            , Html.span [ Html.Attributes.class "text-rust" ] [ Html.text "pike" ]
            ]
        , Html.p [ Html.Attributes.class "text-muted mb-8 text-base" ]
            [ Html.text "Road log for the long way north" ]
        , case gs.authError of
            Just err ->
                Html.div
                    [ Html.Attributes.class "w-full max-w-xs mb-4 px-4 py-3 rounded-lg bg-rust-tint border border-rust text-rust text-sm text-left" ]
                    [ Html.text err ]

            Nothing ->
                case gs.session.reason of
                    SessionExpired ->
                        Html.div
                            [ Html.Attributes.class "w-full max-w-xs mb-4 px-4 py-3 rounded-lg bg-rust-tint border border-rust text-rust text-sm text-left" ]
                            [ Html.text "Session expired — sign in to continue." ]

                    _ ->
                        Html.text ""
        , case gs.session.reason of
            AwaitingCode _ ->
                Html.form
                    [ Html.Events.onSubmit SubmitCode
                    , Html.Attributes.class "w-full max-w-xs"
                    ]
                    [ Html.p [ Html.Attributes.class "text-muted text-sm mb-4" ]
                        [ Html.text ("A code was sent to " ++ gs.emailInput ++ ". Enter it below.") ]
                    , Html.input
                        [ Html.Attributes.type_ "text"
                        , Html.Attributes.value gs.codeInput
                        , Html.Events.onInput CodeInputChanged
                        , Html.Attributes.placeholder "123456"
                        , Html.Attributes.class "w-full mb-3"
                        ]
                        []
                    , Html.button
                        [ Html.Attributes.type_ "submit"
                        , Html.Attributes.class "w-full bg-rust text-parchment border-none rounded-lg py-4 text-base font-bold cursor-pointer min-h-[52px] tracking-widest"
                        ]
                        [ Html.text "VERIFY CODE" ]
                    ]

            _ ->
                Html.form
                    [ Html.Events.onSubmit SubmitEmail
                    , Html.Attributes.class "w-full max-w-xs"
                    ]
                    [ Html.input
                        [ Html.Attributes.type_ "text"
                        , Html.Attributes.value gs.emailInput
                        , Html.Events.onInput EmailInputChanged
                        , Html.Attributes.placeholder "your@email.com"
                        , Html.Attributes.class "w-full mb-3"
                        ]
                        []
                    , Html.button
                        [ Html.Attributes.type_ "submit"
                        , Html.Attributes.class "w-full bg-rust text-parchment border-none rounded-lg py-4 text-base font-bold cursor-pointer min-h-[52px] tracking-widest"
                        ]
                        [ Html.text "CONTINUE" ]
                    ]
        , Html.div [ Html.Attributes.class "mt-12 w-full" ]
            [ Html.button
                [ Html.Events.onClick ToggleGuestSettings
                , Html.Attributes.class "bg-transparent border border-tan text-muted rounded-md px-5 py-2.5 text-sm cursor-pointer"
                ]
                [ Html.text "⚙ Settings" ]
            , if gs.showSettings then
                Pages.Settings.viewPanel gs.session.config False gs.version

              else
                Html.text ""
            ]
        ]
