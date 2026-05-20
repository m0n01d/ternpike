module Pages.Guest exposing (viewGuest)

import Html exposing (Html)
import Html.Attributes
import Html.Events
import Pages.Settings
import Types exposing (..)
import UI.Button
import UI.Card
import UI.Icons
import UI.Mascot
import UI.Rule


viewGuest : GuestState -> Html Msg
viewGuest gs =
    Html.div
        [ Html.Attributes.class "min-h-screen flex flex-col items-center justify-center px-6 bg-[image:var(--bg-topo-atlas)] bg-no-repeat bg-[size:2400px_2000px] bg-[position:-960px_-540px] transition-[background-position] duration-700 ease-out" ]
        [ Html.div [ Html.Attributes.class "text-center max-w-sm w-full mb-8" ]
            [ UI.Mascot.ternSvg "w-32 mx-auto animate-soar"
            , Html.h1
                [ Html.Attributes.class "font-display text-5xl font-black tracking-tight mt-4 text-forest" ]
                [ Html.text "Tern"
                , Html.span [ Html.Attributes.class "text-rust" ] [ Html.text "pike" ]
                ]
            , Html.p
                [ Html.Attributes.class "font-mono text-[11px] uppercase tracking-widest text-moss mt-3" ]
                [ Html.text "ROAD LOG FOR THE LONG WAY NORTH" ]
            ]
        , UI.Rule.dashedRule
        , Html.div [ Html.Attributes.class "max-w-sm w-full" ]
            [ viewFormCard gs ]
        , viewErrorChip gs
        , Html.div [ Html.Attributes.class "mt-6 text-center" ]
            [ UI.Button.ghost { label = "Settings", onClick = ToggleGuestSettings }
            , if gs.showSettings then
                Pages.Settings.viewPanel gs.session.config False gs.version

              else
                Html.text ""
            ]
        ]


viewFormCard : GuestState -> Html Msg
viewFormCard gs =
    case gs.session.reason of
        AwaitingCode _ ->
            UI.Card.subCard
                [ Html.form
                    [ Html.Events.onSubmit SubmitCode
                    , Html.Attributes.class "w-full"
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
                    , UI.Button.primary { label = "Verify code", onClick = SubmitCode }
                    ]
                ]

        _ ->
            UI.Card.subCard
                [ Html.form
                    [ Html.Events.onSubmit SubmitEmail
                    , Html.Attributes.class "w-full"
                    ]
                    [ Html.input
                        [ Html.Attributes.type_ "text"
                        , Html.Attributes.value gs.emailInput
                        , Html.Events.onInput EmailInputChanged
                        , Html.Attributes.placeholder "your@email.com"
                        , Html.Attributes.class "w-full mb-3"
                        ]
                        []
                    , UI.Button.primary { label = "Continue", onClick = SubmitEmail }
                    ]
                ]


viewErrorChip : GuestState -> Html Msg
viewErrorChip gs =
    let
        chip msg =
            Html.div
                [ Html.Attributes.class "mt-4 inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-rust-tint border border-rust/40 text-rust text-xs font-mono uppercase tracking-wide" ]
                [ UI.Icons.close "w-3 h-3", Html.text msg ]
    in
    case gs.authError of
        Just err ->
            chip err

        Nothing ->
            case gs.session.reason of
                SessionExpired ->
                    chip "Session expired — sign in to continue."

                _ ->
                    Html.text ""
