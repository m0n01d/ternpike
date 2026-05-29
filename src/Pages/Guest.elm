module Pages.Guest exposing (viewGuest)

import Data.Guest exposing (GuestReason(..))
import Data.Navigation
import Html exposing (Html)
import Html.Attributes
import Html.Attributes.Extra
import Html.Events
import Html.Extra
import Pages.NestPreview
import Pages.Settings
import RemoteData exposing (RemoteData)
import Types exposing (GuestMsg_(..), GuestState, Msg(..))
import UI.Button
import UI.Card
import UI.Icons
import UI.Mascot
import UI.Rule


{-| Route-aware guest dispatch.

The unauthenticated tree is no longer single-purpose: the Nest invite
funnel (see `docs/nest-invite-funnel.md`) will render preview /
magic-link pages off `gs.route` while signed out. `viewGuest` is the
seam those pages slot into — it dispatches on `gs.route`, with every
route in the app today falling through to the existing login form via
`viewLogin`. The funnel's dedicated routes (`RouteNestPreview`,
`RouteMagicLink`) arrive in a follow-on issue (#329); each adds its own
branch here and renders its own page instead of the login fallback.

`gs.route` is kept current by the `UrlChanged` handler in `Main.elm`
(`updateShared`), mirroring how `AuthState.route` tracks navigation.

-}
viewGuest : GuestState -> Html Msg
viewGuest gs =
    case gs.route of
        Data.Navigation.RouteJoinSharedTrip _ ->
            -- The join-invite landing keeps the login form today (the
            -- token is parked in `gs.pendingJoinToken` and redeemed
            -- after sign-in); naming it as an explicit branch documents
            -- it as the first funnel-adjacent route and keeps this a
            -- genuine dispatch rather than a degenerate one-arm case.
            viewLogin gs

        Data.Navigation.RouteMagicLink token ->
            -- Passwordless magic-link landing. The dedicated view
            -- (`Pages.NestPreview` conversion wall) lands in #335;
            -- for now fall through to the login form so the auth flow
            -- remains functional while the funnel UI is in progress.
            -- `token` is bound here so #335 can reference it from
            -- this branch without a structural change.
            viewLogin { gs | pendingJoinToken = Just token }

        Data.Navigation.RouteNestPreview _ ->
            -- Nest invite preview (#335). The resolve fetch fires from
            -- `Main.elm` on entry into this route and lands the decoded
            -- teaser in `gs.nestPreview`; we render that `RemoteData`
            -- read-only. The guest-preview gate that decides whether the
            -- scan affordance is shown rides on the decoded teaser; its
            -- first consumer is the scan dropzone in #336.
            Pages.NestPreview.view gs.nestPreview

        _ ->
            viewLogin gs


viewLogin : GuestState -> Html Msg
viewLogin gs =
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
            , Html.Extra.viewIf gs.showSettings
                (Pages.Settings.viewPanel gs.session.config False gs.version)
            ]
        ]


viewJoinHint : GuestState -> Html Msg
viewJoinHint gs =
    Html.Extra.viewMaybe
        (\_ ->
            Html.div [ Html.Attributes.class "max-w-sm w-full mb-4" ]
                [ Html.p [ Html.Attributes.class "text-sm text-moss text-center" ]
                    [ Html.text "Sign in to accept your shared-trip invite." ]
                ]
        )
        gs.pendingJoinToken


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
            [ Html.Attributes.class "w-full"
            , Html.Attributes.Extra.attributeIf (not busy) (Html.Events.onSubmit (GuestMsg SubmitEmail))
            ]

        inputAttrs =
            [ Html.Attributes.type_ "text"
            , Html.Attributes.value value
            , Html.Attributes.placeholder "your@email.com"
            , Html.Attributes.class "w-full mb-3"
            , Html.Attributes.disabled busy
            , Html.Attributes.Extra.attributeIf (not busy) (Html.Events.onInput (GuestMsg << EmailInputChanged))
            ]
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
            [ Html.Attributes.class "w-full"
            , Html.Attributes.Extra.attributeIf (not busy) (Html.Events.onSubmit (GuestMsg SubmitCode))
            ]

        inputAttrs =
            [ Html.Attributes.type_ "text"
            , Html.Attributes.value code
            , Html.Attributes.placeholder "123456"
            , Html.Attributes.class "w-full mb-3"
            , Html.Attributes.disabled busy
            , Html.Attributes.Extra.attributeIf (not busy) (Html.Events.onInput (GuestMsg << CodeInputChanged))
            ]
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
                    ( idleButton, Html.Extra.nothing )

                RemoteData.Loading ->
                    ( disabledButton "Sending…", Html.Extra.nothing )

                RemoteData.Failure _ ->
                    ( idleButton, Html.Extra.nothing )

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
                    Html.Extra.nothing
