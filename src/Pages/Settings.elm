module Pages.Settings exposing (PlanProps, viewPanel, viewPlanSection, viewTab)

import Data.AnthropicKey as AnthropicKey
import Data.Auth exposing (AppConfig)
import Data.ColorScheme exposing (ColorScheme(..))
import Data.Notifications as Notifications
import Data.SubscriptionStatus as SubscriptionStatus
import Data.Tier as Tier exposing (Tier(..))
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Extra
import Http
import Http.Billing
import Maybe.Extra
import Pages.Settings.SharedTrips
import RemoteData exposing (RemoteData)
import Types exposing (AuthMsg_(..), AuthState, Msg(..), SharedMsg_(..))
import UI.Button
import UI.Card
import UI.DateView
import UI.Layout
import UI.Rule
import Verify.Contract
import Verify.Specs.NotificationsPaywall


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = []
    , body =
        Html.div []
            [ Html.Extra.viewIf as_.postJoinPrompt (viewPostJoinCard as_)
            , viewAppearanceSection as_.colorScheme
            , viewBody as_.config (Just as_) (Just as_.showDayIntensity) as_.showInstallPrompt
            , Pages.Settings.SharedTrips.view as_
            , viewVersionFooter as_.version
            ]
    , hero = viewHero
    }


{-| One-time post-join retention card (#338). Surfaced on the
member-landing after a successful funnel join — never during the guest
preview. Reuses the existing PWA plumbing rather than rebuilding it:

  - **Standalone (installed PWA):** offer the crew-activity push opt-in
    via `EnableCrewPush` (defaults the `sharedTripActivity` pref on, fires
    `subscribePush`). iOS only exposes push to an installed PWA, so this
    branch is the only one that can ask for push.
  - **In-browser + `beforeinstallprompt` fired (`showInstallPrompt`):**
    offer the native Add-to-Home-Screen via `TriggerInstallPrompt`.
  - **In-browser + no `beforeinstallprompt` (iOS Safari):** show manual
    "Share → Add to Home Screen" guidance. Documented gap: an iOS user
    who never installs gets no push (push-only, no email fallback).

Every branch offers a dismiss (`DismissPostJoinPrompt`) so the card shows
exactly once.

-}
viewPostJoinCard : AuthState -> Html Msg
viewPostJoinCard as_ =
    let
        ( bodyChildren, actionChildren ) =
            if as_.standalone == Notifications.Standalone then
                ( [ Html.p [ Html.Attributes.class "text-base text-ink font-medium" ]
                        [ Html.text "You're in!" ]
                  , Html.p [ Html.Attributes.class "text-sm text-muted" ]
                        [ Html.text "Get notified when crew adds an expense?" ]
                  ]
                , [ UI.Button.primary { label = "Turn on alerts", onClick = AuthMsg EnableCrewPush }
                  , UI.Button.ghost { label = "Maybe later", onClick = AuthMsg DismissPostJoinPrompt }
                  ]
                )

            else if as_.showInstallPrompt then
                ( [ Html.p [ Html.Attributes.class "text-base text-ink font-medium" ]
                        [ Html.text "You're in!" ]
                  , Html.p [ Html.Attributes.class "text-sm text-muted" ]
                        [ Html.text "Add Ternpike to your home screen so crew alerts can reach you." ]
                  ]
                , [ UI.Button.primary { label = "Add", onClick = AuthMsg TriggerInstallPrompt }
                  , UI.Button.ghost { label = "Not now", onClick = AuthMsg DismissPostJoinPrompt }
                  ]
                )

            else
                ( [ Html.p [ Html.Attributes.class "text-base text-ink font-medium" ]
                        [ Html.text "Want crew alerts?" ]
                  , Html.p [ Html.Attributes.class "text-sm text-muted" ]
                        [ Html.text "Tap the Share button in Safari, then choose Add to Home Screen to get notified when crew adds an expense." ]
                  ]
                , [ UI.Button.secondary { label = "Got it", onClick = AuthMsg DismissPostJoinPrompt } ]
                )
    in
    Html.div [ Html.Attributes.class "mb-4" ]
        [ UI.Rule.kicker "WELCOME"
        , UI.Card.subCard
            [ Html.div [ Html.Attributes.class "flex flex-col gap-3" ]
                (bodyChildren
                    ++ [ Html.div [ Html.Attributes.class "flex gap-2 mt-1" ] actionChildren ]
                )
            ]
        ]


viewPanel : AppConfig -> Bool -> String -> Html Msg
viewPanel cfg isSignedIn version =
    Html.div [ Html.Attributes.class "px-5 py-6" ]
        [ viewHero
        , Html.div [ Html.Attributes.class "mt-4" ]
            [ viewBody cfg
                Nothing
                (if isSignedIn then
                    Just True

                 else
                    Nothing
                )
                False
            , viewVersionFooter version
            ]
        ]


viewHero : Html Msg
viewHero =
    Html.div [ Html.Attributes.class "text-sm text-muted" ]
        [ Html.text "Local-first preferences. Nothing here leaves the device." ]


viewBody : AppConfig -> Maybe AuthState -> Maybe Bool -> Bool -> Html Msg
viewBody cfg maybeAuthState maybeDayIntensity showInstallPrompt =
    let
        isSignedIn =
            maybeDayIntensity /= Nothing
    in
    Html.div []
        [ Html.Extra.viewMaybe (\as_ -> viewPlanSection (planPropsFromAuth as_)) maybeAuthState
        , Html.Extra.viewMaybe viewDisplaySection maybeDayIntensity
        , Html.Extra.viewMaybe viewNotificationsSection maybeAuthState
        , Html.Extra.viewIf isSignedIn viewShareSection
        , Html.Extra.viewIf showInstallPrompt viewInstallSection
        , UI.Rule.kicker "CONNECTION"
        , UI.Card.subCard
            (viewAnthropicKeySection cfg maybeAuthState)
        , Html.Extra.viewMaybe viewSyncSection maybeAuthState
        , UI.Rule.kicker "SESSION"
        , UI.Card.subCard
            [ Html.div [ Html.Attributes.class "flex flex-col gap-3" ]
                ((if isSignedIn then
                    [ UI.Button.secondary { label = "Sign out", onClick = AuthMsg SignOutClicked } ]

                  else
                    []
                 )
                    ++ [ UI.Button.ghost { label = "Reset local data", onClick = SharedMsg ResetSettingsClicked } ]
                )
            ]
        ]


viewSyncSection : AuthState -> Html Msg
viewSyncSection as_ =
    let
        valueChildren =
            case as_.lastSyncedAt of
                Just at ->
                    [ UI.DateView.dateOf at
                    , Html.text " at "
                    , UI.DateView.timeOf at
                    ]

                Nothing ->
                    [ Html.text "Not yet this session" ]
    in
    Html.div []
        [ UI.Rule.kicker "SYNC"
        , UI.Card.subCard
            [ Html.div [ Html.Attributes.class "flex items-center justify-between gap-4" ]
                [ Html.span [ Html.Attributes.class "text-sm text-ink" ] [ Html.text "Last synced" ]
                , Html.span [ Html.Attributes.class "text-sm text-muted" ] valueChildren
                ]
            ]
        ]


viewVersionFooter : String -> Html Msg
viewVersionFooter version =
    Html.Extra.viewIf (version /= "")
        (Html.div [ Html.Attributes.class "mt-6 text-center text-[10px] font-mono uppercase tracking-widest text-muted" ]
            [ Html.text ("VERSION " ++ version) ]
        )


viewAnthropicKeySection : AppConfig -> Maybe AuthState -> List (Html Msg)
viewAnthropicKeySection cfg maybeAuthState =
    let
        isPaid =
            Maybe.Extra.unwrap False (\as_ -> Tier.isPaid as_.tier) maybeAuthState

        keyIsSet =
            cfg.anthropicKey /= Nothing

        showInput =
            Maybe.Extra.unwrap False .showByoKeyInput maybeAuthState

        toggleOn =
            keyIsSet || showInput

        keyInput =
            [ UI.Layout.formField "Anthropic API key"
                (Html.input
                    [ Html.Attributes.type_ "password"
                    , Html.Attributes.value (cfg.anthropicKey |> Maybe.map AnthropicKey.toHeader |> Maybe.withDefault "")
                    , Html.Events.onInput (SharedMsg << ApiKeyChanged)
                    , Html.Attributes.placeholder "sk-ant-..."
                    , UI.Layout.textInputStyle
                    ]
                    []
                )
            , Html.p [ Html.Attributes.class "text-xs text-muted mt-2" ]
                [ Html.text "Used to read receipts locally. Never sent to Ternpike servers." ]
            ]
    in
    if isPaid then
        let
            toggleRow =
                viewToggleRow
                    { helper = "Leave off to use Ternpike's hosted key. Your key never reaches our servers when this is on."
                    , label = "Use my own Anthropic key"
                    , msg =
                        if toggleOn then
                            SharedMsg (ApiKeyChanged "")

                        else
                            SharedMsg ShowByoKeyInput
                    , value = toggleOn
                    }
        in
        if toggleOn then
            toggleRow :: keyInput

        else
            [ toggleRow ]

    else
        keyInput


viewAppearanceSection : ColorScheme -> Html Msg
viewAppearanceSection current =
    let
        schemeBtn scheme label =
            Html.button
                [ Html.Attributes.type_ "button"
                , Html.Events.onClick (SharedMsg (SetColorScheme scheme))
                , Html.Attributes.classList
                    [ ( "flex-1 py-2 rounded-lg text-xs font-mono uppercase tracking-widest cursor-pointer border transition-colors", True )
                    , ( "bg-forest text-parchment border-forest", current == scheme )
                    , ( "bg-cream-deep text-muted border-tan hover:border-moss hover:text-forest", current /= scheme )
                    ]
                ]
                [ Html.text label ]
    in
    Html.div []
        [ UI.Rule.kicker "APPEARANCE"
        , UI.Card.subCard
            [ Html.div [ Html.Attributes.class "flex gap-2" ]
                [ schemeBtn Light "Light"
                , schemeBtn Auto "Auto"
                , schemeBtn Dark "Dark"
                ]
            , Html.p [ Html.Attributes.class "text-xs text-muted mt-2" ]
                [ Html.text "Auto follows your system setting." ]
            ]
        ]


viewDisplaySection : Bool -> Html Msg
viewDisplaySection dayIntensity =
    Html.div []
        [ UI.Rule.kicker "DISPLAY"
        , UI.Card.subCard
            [ viewToggleRow
                { helper = "Tint the rule between DAY and date by how this day's total compares to the trip's median spend."
                , label = "Day spending intensity"
                , msg = AuthMsg ToggleDayIntensity
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
            , UI.Button.secondary { label = "Install app", onClick = AuthMsg TriggerInstallPrompt }
            ]
        ]


viewShareSection : Html Msg
viewShareSection =
    Html.div []
        [ UI.Rule.kicker "SHARE"
        , UI.Card.subCard
            [ Html.p [ Html.Attributes.class "text-xs text-muted mb-3" ]
                [ Html.text "A personal QR that friends can scan off your phone to install Ternpike." ]
            , UI.Button.secondary { label = "Share Ternpike", onClick = AuthMsg OpenShareModal }
            ]
        ]


{-| The key-free projection of `AuthState` that both the notifications panel
and its verification surface read. One helper so the two can't disagree about
what they're looking at.

`configured` is the build's VAPID public key being non-empty: without one,
`pushManager.subscribe` cannot be called, so no amount of tapping can produce
a subscription.

-}
notificationsInput :
    AuthState
    ->
        { configured : Bool
        , error : Maybe String
        , isPaid : Bool
        , permission : Notifications.Permission
        , standalone : Notifications.StandaloneState
        , subscribed : Bool
        }
notificationsInput as_ =
    { configured = as_.config.vapidPublicKey /= ""
    , error = as_.pushError
    , isPaid = Tier.isPaid as_.tier
    , permission = as_.notificationPermission
    , standalone = as_.standalone
    , subscribed = as_.pushSubscribed
    }


viewNotificationsSection : AuthState -> Html Msg
viewNotificationsSection as_ =
    Html.div
        (Verify.Contract.verifyAttrs "NotificationsPaywall"
            (Verify.Specs.NotificationsPaywall.surface
                (Verify.Specs.NotificationsPaywall.honest (notificationsInput as_))
            )
        )
        [ UI.Rule.kicker "NOTIFICATIONS"
        , UI.Card.subCard (viewNotificationsBody as_ ++ viewPushError as_.pushError)
        ]


{-| The reason the last subscribe attempt failed, rendered in the pane itself
rather than as a toast — the complaint this fixes is "I tapped Enable and
nothing appeared," so the feedback has to live where the button is and stay
there. Appended after the panel body so it sits directly below the button in
the `PanelCanEnable` branch, and still shows if the failure moved the panel to
`PanelBlocked` (a denied prompt does exactly that).
-}
viewPushError : Maybe String -> List (Html Msg)
viewPushError maybeReason =
    case maybeReason of
        Nothing ->
            []

        Just reason ->
            [ Html.p
                [ Html.Attributes.class "text-xs text-rust mt-3" ]
                [ Html.text ("Couldn't enable notifications: " ++ reason) ]
            ]


viewNotificationsBody : AuthState -> List (Html Msg)
viewNotificationsBody as_ =
    case Notifications.panelState (notificationsInput as_) of
        Notifications.PanelUnsupported ->
            [ Html.p [ Html.Attributes.class "text-xs text-muted" ]
                [ Html.text "Notifications aren't available in this browser. On iPhone or iPad, install Ternpike to your home screen first — tap the Share button in Safari, then choose Add to Home Screen." ]
            ]

        Notifications.PanelUpgradeRequired ->
            [ Html.div [ Html.Attributes.class "flex items-start justify-between gap-3" ]
                [ Html.p [ Html.Attributes.class "text-xs text-muted flex-1" ]
                    [ Html.text "Upgrade to Osprey to enable weekly scan reminders." ]
                , Html.button
                    [ Html.Attributes.type_ "button"
                    , Html.Attributes.disabled True
                    , Html.Attributes.class "shrink-0 px-3 py-1.5 text-sm font-medium rounded-lg bg-cream-deep text-muted border border-tan cursor-not-allowed"
                    ]
                    [ Html.text "Enable notifications" ]
                ]
            ]

        Notifications.PanelNotConfigured ->
            [ Html.p [ Html.Attributes.class "text-xs text-muted" ]
                [ Html.text "Push notifications aren't configured in this build of Ternpike, so there's nothing to turn on here. This is an environment setting, not something you can change from the app." ]
            ]

        Notifications.PanelNeedsInstall ->
            [ Html.p [ Html.Attributes.class "text-xs text-muted" ]
                [ Html.text "Install Ternpike to your home screen to enable notifications. Tap the Share button in Safari, then choose Add to Home Screen." ]
            ]

        Notifications.PanelBlocked ->
            [ Html.p [ Html.Attributes.class "text-xs text-muted" ]
                [ Html.text "Notifications are blocked. Re-enable them in iOS Settings → Notifications → Ternpike." ]
            ]

        Notifications.PanelSubscribed ->
            [ viewToggleRow
                { helper = "Get a push when you're removed from a shared trip or when billing ownership is transferred to you."
                , label = "Shared trip access change"
                , msg = AuthMsg (ToggleNotificationPref Notifications.SharedTripAccessChange)
                , value = as_.notificationPrefs.sharedTripAccessChange
                }
            , viewToggleRow
                { helper = "Get a push when a co-traveler adds, edits, or voids an expense on a shared trip."
                , label = "Shared trip activity"
                , msg = AuthMsg (ToggleNotificationPref Notifications.SharedTripActivity)
                , value = as_.notificationPrefs.sharedTripActivity
                }
            , viewToggleRow
                { helper = "Get a push when someone invites you to a shared trip. Tap to accept or decline in Settings."
                , label = "Shared trip invite"
                , msg = AuthMsg (ToggleNotificationPref Notifications.SharedTripInvite)
                , value = as_.notificationPrefs.sharedTripInvite
                }
            , viewToggleRow
                { helper = "Get notified if your data hasn't backed up in 3 days. Recommended — this is a data protection alert, not an engagement nudge."
                , label = "Sync stalled alert"
                , msg = AuthMsg (ToggleNotificationPref Notifications.SyncStalled)
                , value = as_.notificationPrefs.syncStalled
                }
            , viewToggleRow
                { helper = "Every Friday at 5pm UTC, we'll nudge you to scan this week's receipts."
                , label = "Weekly receipt reminder"
                , msg = AuthMsg (ToggleNotificationPref Notifications.WeeklyScanReminder)
                , value = as_.notificationPrefs.weeklyScanReminder
                }
            ]

        Notifications.PanelCanEnable ->
            [ Html.p [ Html.Attributes.class "text-xs text-muted mb-3" ]
                [ Html.text "Weekly Friday reminder to scan receipts. You can turn it off anytime." ]
            , UI.Button.primary { label = "Enable notifications", onClick = AuthMsg RequestPushPermission }
            ]


{-| Minimal record `viewPlanSection` actually reads from `AuthState`.

Extracted so the Plan section is testable without forging a complete
`AuthState` (which requires a `Browser.Navigation.Key`, unobtainable in
unit tests). Tests build a `PlanProps` literal directly; the production
caller uses `planPropsFromAuth as_` to project from the real model.

-}
type alias PlanProps =
    { billingCheckout : RemoteData Http.Billing.CheckoutFailure Http.Billing.CheckoutOk
    , billingPortal : RemoteData Http.Error ()
    , subscriptionStatus : Maybe SubscriptionStatus.SubscriptionStatus
    , tier : Tier
    , trailblazerNumber : Maybe Int
    , trailblazerStatus : RemoteData Http.Error Http.Billing.TrailblazerStatus
    }


{-| Project the Plan section's inputs out of the full `AuthState`. Used
at the production call site.
-}
planPropsFromAuth : AuthState -> PlanProps
planPropsFromAuth as_ =
    { billingCheckout = as_.billingCheckout
    , billingPortal = as_.billingPortal
    , subscriptionStatus = as_.subscriptionStatus
    , tier = as_.tier
    , trailblazerNumber = as_.trailblazerNumber
    , trailblazerStatus = as_.trailblazerStatus
    }


viewPlanSection : PlanProps -> Html Msg
viewPlanSection props =
    Html.div []
        [ UI.Rule.kicker "PLAN"
        , UI.Card.subCard (viewPlanBody props)
        ]


viewPlanBody : PlanProps -> List (Html Msg)
viewPlanBody props =
    let
        checkoutErrorChip =
            case props.billingCheckout of
                RemoteData.Failure Http.Billing.CheckoutSoldOut ->
                    [ Html.p
                        [ Html.Attributes.class "text-xs text-rust mt-3" ]
                        [ Html.text "Sorry, the last Trailblazer slot just sold out." ]
                    ]

                RemoteData.Failure Http.Billing.CheckoutAlreadyTrailblazer ->
                    [ Html.p
                        [ Html.Attributes.class "text-xs text-rust mt-3" ]
                        [ Html.text "You're already a Trailblazer." ]
                    ]

                RemoteData.Failure (Http.Billing.CheckoutError detail) ->
                    [ Html.p
                        [ Html.Attributes.class "text-xs text-rust mt-3" ]
                        [ Html.text ("Something went wrong starting checkout. Please try again. (" ++ detail ++ ")") ]
                    ]

                RemoteData.NotAsked ->
                    []

                RemoteData.Loading ->
                    []

                RemoteData.Success _ ->
                    []

        portalErrorChip =
            case props.billingPortal of
                RemoteData.Failure _ ->
                    [ Html.p
                        [ Html.Attributes.class "text-xs text-rust mt-3" ]
                        [ Html.text "Couldn't open the billing portal. Please try again." ]
                    ]

                RemoteData.NotAsked ->
                    []

                RemoteData.Loading ->
                    []

                RemoteData.Success _ ->
                    []
    in
    case props.tier of
        Tern ->
            viewPlanTern props ++ checkoutErrorChip

        Osprey ->
            viewPlanOsprey props ++ portalErrorChip

        Trailblazer ->
            viewPlanTrailblazer props ++ portalErrorChip


viewPlanTern : PlanProps -> List (Html Msg)
viewPlanTern props =
    let
        checkoutBusy =
            props.billingCheckout == RemoteData.Loading
    in
    [ Html.div [ Html.Attributes.class "text-sm text-ink font-medium mb-1" ]
        [ Html.text "Tern — Free" ]
    , Html.p [ Html.Attributes.class "text-xs text-muted mb-3" ]
        [ Html.text "Upgrade unlocks:" ]
    , Html.ul [ Html.Attributes.class "list-disc list-inside text-xs text-muted mb-4 space-y-1" ]
        [ Html.li [] [ Html.text "Hosted Anthropic OCR (no key setup)" ]
        , Html.li [] [ Html.text "Batch scanning" ]
        , Html.li [] [ Html.text "CSV export" ]
        ]
    , Html.div [ Html.Attributes.class "flex flex-col gap-3" ]
        [ viewCheckoutButton
            { busy = checkoutBusy
            , disabled = checkoutBusy
            , label = "Osprey — $2.99 / mo"
            , plan = "osprey_monthly"
            , style = StylePrimary
            }
        , viewCheckoutButton
            { busy = checkoutBusy
            , disabled = checkoutBusy
            , label = "Osprey yearly — $24 / yr (save $12)"
            , plan = "osprey_yearly"
            , style = StyleSecondary
            }
        , viewTrailblazerButton props
        ]
    ]


viewPlanOsprey : PlanProps -> List (Html Msg)
viewPlanOsprey props =
    let
        portalBusy =
            props.billingPortal == RemoteData.Loading
    in
    [ Html.div [ Html.Attributes.class "flex items-center gap-2 mb-3" ]
        [ Html.span [ Html.Attributes.class "text-sm text-ink font-medium" ]
            [ Html.text "Osprey" ]
        , viewSubscriptionChip props.subscriptionStatus
        ]
    , Html.div [ Html.Attributes.class "flex flex-col gap-3" ]
        [ viewPortalButton
            { busy = portalBusy
            , disabled = portalBusy
            , label = "Manage billing"
            }
        ]
    ]


viewPlanTrailblazer : PlanProps -> List (Html Msg)
viewPlanTrailblazer props =
    let
        heading =
            case props.trailblazerNumber of
                Just n ->
                    "Trailblazer #" ++ String.fromInt n ++ " (of 500)"

                Nothing ->
                    "Trailblazer (of 500)"

        portalBusy =
            props.billingPortal == RemoteData.Loading
    in
    [ Html.div [ Html.Attributes.class "text-sm text-ink font-medium mb-1" ]
        [ Html.text heading ]
    , Html.p [ Html.Attributes.class "text-xs text-muted mb-4" ]
        [ Html.text "Lifetime access. All 1.x updates included. Loyalty discount on v2." ]
    , Html.div [ Html.Attributes.class "flex flex-col gap-3" ]
        [ viewPortalButton
            { busy = portalBusy
            , disabled = portalBusy
            , label = "View receipts / update card"
            }
        ]
    ]


type ButtonStyle
    = StylePrimary
    | StyleSecondary


viewCheckoutButton :
    { busy : Bool
    , disabled : Bool
    , label : String
    , plan : String
    , style : ButtonStyle
    }
    -> Html Msg
viewCheckoutButton { busy, disabled, label, plan, style } =
    if busy then
        UI.Button.primaryBusy { label = label }

    else if disabled then
        Html.button
            [ Html.Attributes.type_ "button"
            , Html.Attributes.disabled True
            , Html.Attributes.class "bg-cream-deep text-muted border border-tan font-mono uppercase tracking-widest text-sm px-6 py-3 rounded-lg cursor-not-allowed"
            ]
            [ Html.text label ]

    else
        case style of
            StylePrimary ->
                UI.Button.primary
                    { label = label
                    , onClick = AuthMsg (BillingCheckoutClicked plan)
                    }

            StyleSecondary ->
                UI.Button.secondary
                    { label = label
                    , onClick = AuthMsg (BillingCheckoutClicked plan)
                    }


viewPortalButton : { busy : Bool, disabled : Bool, label : String } -> Html Msg
viewPortalButton { busy, disabled, label } =
    if busy then
        Html.button
            [ Html.Attributes.type_ "button"
            , Html.Attributes.disabled True
            , Html.Attributes.class "bg-cream-deep text-muted border border-tan font-mono uppercase tracking-widest text-sm px-6 py-3 rounded-lg cursor-not-allowed"
            ]
            [ Html.text "Opening…" ]

    else if disabled then
        Html.button
            [ Html.Attributes.type_ "button"
            , Html.Attributes.disabled True
            , Html.Attributes.class "bg-cream-deep text-muted border border-tan font-mono uppercase tracking-widest text-sm px-6 py-3 rounded-lg cursor-not-allowed"
            ]
            [ Html.text label ]

    else
        UI.Button.secondary
            { label = label
            , onClick = AuthMsg BillingPortalClicked
            }


viewTrailblazerButton : PlanProps -> Html Msg
viewTrailblazerButton props =
    let
        checkoutBusy =
            props.billingCheckout == RemoteData.Loading

        disabledButton label =
            Html.button
                [ Html.Attributes.type_ "button"
                , Html.Attributes.disabled True
                , Html.Attributes.class "bg-cream-deep text-muted border border-tan font-mono uppercase tracking-widest text-sm px-6 py-3 rounded-lg cursor-not-allowed"
                ]
                [ Html.text label ]
    in
    case props.trailblazerStatus of
        RemoteData.NotAsked ->
            disabledButton "Loading…"

        RemoteData.Loading ->
            disabledButton "Loading…"

        RemoteData.Failure _ ->
            disabledButton "Couldn't load remaining count"

        RemoteData.Success status ->
            if status.available == 0 then
                disabledButton "Trailblazer — Sold out"

            else
                viewCheckoutButton
                    { busy = checkoutBusy
                    , disabled = checkoutBusy
                    , label =
                        "Become a Trailblazer — $79 ("
                            ++ String.fromInt status.available
                            ++ " of "
                            ++ String.fromInt status.total
                            ++ " left)"
                    , plan = "trailblazer"
                    , style = StyleSecondary
                    }


viewSubscriptionChip : Maybe SubscriptionStatus.SubscriptionStatus -> Html Msg
viewSubscriptionChip maybeStatus =
    case maybeStatus of
        Just SubscriptionStatus.Active ->
            Html.Extra.nothing

        Just status ->
            Html.span
                [ Html.Attributes.classList
                    [ ( "text-xs font-mono uppercase tracking-widest px-2 py-0.5 rounded-full border", True )
                    , ( "bg-rust/10 text-rust border-rust/30", status == SubscriptionStatus.PastDue )
                    , ( "bg-cream-deep text-muted border-tan", status /= SubscriptionStatus.PastDue )
                    ]
                ]
                [ Html.text (SubscriptionStatus.label status) ]

        Nothing ->
            Html.Extra.nothing


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
