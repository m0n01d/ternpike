module Pages.Guest exposing (viewGuest)

import Data.Guest exposing (GuestReason(..))
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Pages.Settings
import RemoteData exposing (RemoteData)
import Types exposing (GuestMsg_(..), GuestState, Msg(..))
import UI.Button
import UI.Card
import UI.Icons
import UI.Mascot
import UI.Rule


viewGuest : GuestState -> Html Msg
viewGuest gs =
    Html.div
        [ Html.Attributes.class "min-h-dvh flex flex-col items-center justify-center px-6 bg-[image:var(--bg-topo-atlas)] bg-no-repeat bg-[size:2400px_2000px] bg-[position:-960px_-540px] transition-[background-position] duration-700 ease-out" ]
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
        , viewJoinHint gs
        , Html.div [ Html.Attributes.class "max-w-sm w-full" ]
            [ viewFormCard gs ]
        , viewErrorChip gs
        , Html.div [ Html.Attributes.class "mt-6 text-center" ]
            [ UI.Button.ghost { label = "Settings", onClick = GuestMsg ToggleGuestSettings }
            , if gs.showSettings then
                Pages.Settings.viewPanel gs.session.config False gs.version

              else
                Html.text ""
            ]
        ]


viewJoinHint : GuestState -> Html Msg
viewJoinHint gs =
    case gs.pendingJoinToken of
        Just _ ->
            Html.div [ Html.Attributes.class "max-w-sm w-full mb-4" ]
                [ Html.p [ Html.Attributes.class "text-sm text-moss text-center" ]
                    [ Html.text "Sign in to accept your shared-trip invite." ]
                ]

        Nothing ->
            Html.text ""


viewFormCard : GuestState -> Html Msg
viewFormCard gs =
    case gs.session.reason of
        NotLoggedIn ->
            viewEmailForm gs.emailInput { busy = False, label = "Continue" }

        SessionExpired ->
            viewEmailForm gs.emailInput { busy = False, label = "Continue" }

        RequestingCode email ->
            viewEmailForm email { busy = True, label = "Sending…" }

        AwaitingCode email ->
            viewCodeForm email gs.codeInput gs.resendStatus { busy = False, label = "Verify code" }

        VerifyingCode email code ->
            viewCodeForm email code gs.resendStatus { busy = True, label = "Verifying…" }


viewEmailForm : String -> { busy : Bool, label : String } -> Html Msg
viewEmailForm value { busy, label } =
    let
        formAttrs =
            Html.Attributes.class "w-full"
                :: (if busy then
                        []

                    else
                        [ Html.Events.onSubmit (GuestMsg SubmitEmail) ]
                   )

        inputAttrs =
            [ Html.Attributes.type_ "text"
            , Html.Attributes.value value
            , Html.Attributes.placeholder "your@email.com"
            , Html.Attributes.class "w-full mb-3"
            , Html.Attributes.disabled busy
            ]
                ++ (if busy then
                        []

                    else
                        [ Html.Events.onInput (GuestMsg << EmailInputChanged) ]
                   )
    in
    UI.Card.subCard
        [ Html.form formAttrs
            [ Html.input inputAttrs []
            , if busy then
                UI.Button.primaryBusy { label = label }

              else
                UI.Button.primary { label = label, onClick = GuestMsg SubmitEmail }
            ]
        ]


viewCodeForm : String -> String -> RemoteData e () -> { busy : Bool, label : String } -> Html Msg
viewCodeForm email code resendStatus { busy, label } =
    let
        formAttrs =
            Html.Attributes.class "w-full"
                :: (if busy then
                        []

                    else
                        [ Html.Events.onSubmit (GuestMsg SubmitCode) ]
                   )

        inputAttrs =
            [ Html.Attributes.type_ "text"
            , Html.Attributes.value code
            , Html.Attributes.placeholder "123456"
            , Html.Attributes.class "w-full mb-3"
            , Html.Attributes.disabled busy
            ]
                ++ (if busy then
                        []

                    else
                        [ Html.Events.onInput (GuestMsg << CodeInputChanged) ]
                   )
    in
    UI.Card.subCard
        [ Html.form formAttrs
            [ Html.p [ Html.Attributes.class "text-muted text-sm mb-4" ]
                [ Html.text ("A code was sent to " ++ email ++ ". Enter it below.") ]
            , Html.input inputAttrs []
            , if busy then
                UI.Button.primaryBusy { label = label }

              else
                UI.Button.primary { label = label, onClick = GuestMsg SubmitCode }
            , viewResendRow resendStatus busy
            ]
        ]


viewResendRow : RemoteData e () -> Bool -> Html Msg
viewResendRow resendStatus verifyBusy =
    let
        disabledButton label =
            Html.button
                [ Html.Attributes.type_ "button"
                , Html.Attributes.disabled True
                , Html.Attributes.class "bg-transparent border border-tan/60 text-moss/60 font-mono uppercase tracking-widest text-xs px-4 py-2 rounded-lg cursor-not-allowed"
                ]
                [ Html.text label ]

        idleButton =
            if verifyBusy then
                disabledButton "Resend code"

            else
                UI.Button.ghost { label = "Resend code", onClick = GuestMsg ResendCode }

        successNotice =
            Html.p
                [ Html.Attributes.class "text-moss text-xs font-mono uppercase tracking-wide mt-3" ]
                [ Html.text "New code sent — check your email." ]

        ( button, notice ) =
            case resendStatus of
                RemoteData.NotAsked ->
                    ( idleButton, Html.text "" )

                RemoteData.Loading ->
                    ( disabledButton "Sending…", Html.text "" )

                RemoteData.Failure _ ->
                    ( idleButton, Html.text "" )

                RemoteData.Success _ ->
                    ( idleButton, successNotice )
    in
    Html.div [ Html.Attributes.class "mt-4 flex flex-col items-start" ]
        [ button, notice ]


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
            case ( gs.session.reason, gs.resendStatus ) of
                ( _, RemoteData.Failure _ ) ->
                    chip "Could not resend code. Try again."

                ( SessionExpired, _ ) ->
                    chip "Session expired — sign in to continue."

                _ ->
                    Html.text ""
