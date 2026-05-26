module Pages.Settings exposing (viewPanel, viewTab)

import Data.AnthropicKey as AnthropicKey
import Data.Auth exposing (AppConfig)
import Data.ColorScheme exposing (ColorScheme(..))
import Data.Notifications as Notifications
import Data.Tier as Tier
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Pages.Settings.SharedTrips
import Types exposing (AuthState, Msg(..))
import UI.Button
import UI.Card
import UI.Layout
import UI.Rule


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = []
    , body =
        Html.div []
            [ viewAppearanceSection as_.colorScheme
            , viewBody as_.config (Just as_) (Just as_.showDayIntensity) as_.showInstallPrompt as_.version
            , Pages.Settings.SharedTrips.view as_
            ]
    , hero = viewHero
    }


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
                version
            ]
        ]


viewHero : Html Msg
viewHero =
    Html.div [ Html.Attributes.class "text-sm text-muted" ]
        [ Html.text "Local-first preferences. Nothing here leaves the device." ]


viewBody : AppConfig -> Maybe AuthState -> Maybe Bool -> Bool -> String -> Html Msg
viewBody cfg maybeAuthState maybeDayIntensity showInstallPrompt version =
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
        , case maybeAuthState of
            Just as_ ->
                viewNotificationsSection as_

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
                    , Html.Attributes.value (cfg.anthropicKey |> Maybe.map AnthropicKey.toHeader |> Maybe.withDefault "")
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


viewAppearanceSection : ColorScheme -> Html Msg
viewAppearanceSection current =
    let
        schemeBtn scheme label =
            Html.button
                [ Html.Attributes.type_ "button"
                , Html.Events.onClick (SetColorScheme scheme)
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


viewNotificationsSection : AuthState -> Html Msg
viewNotificationsSection as_ =
    Html.div []
        [ UI.Rule.kicker "NOTIFICATIONS"
        , UI.Card.subCard (viewNotificationsBody as_)
        ]


viewNotificationsBody : AuthState -> List (Html Msg)
viewNotificationsBody as_ =
    if as_.notificationPermission == Notifications.Unsupported then
        [ Html.p [ Html.Attributes.class "text-xs text-muted" ]
            [ Html.text "Notifications aren't available in this browser. On iPhone or iPad, install Ternpike to your home screen first — tap the Share button in Safari, then choose Add to Home Screen." ]
        ]

    else if not (Tier.isPaid as_.tier) then
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

    else if as_.standalone == Notifications.InBrowser then
        [ Html.p [ Html.Attributes.class "text-xs text-muted" ]
            [ Html.text "Install Ternpike to your home screen to enable notifications. Tap the Share button in Safari, then choose Add to Home Screen." ]
        ]

    else if as_.notificationPermission == Notifications.Denied then
        [ Html.p [ Html.Attributes.class "text-xs text-muted" ]
            [ Html.text "Notifications are blocked. Re-enable them in iOS Settings → Notifications → Ternpike." ]
        ]

    else if as_.notificationPermission == Notifications.Granted && as_.pushSubscribed then
        [ viewToggleRow
            { helper = "Get notified if your data hasn't backed up in 3 days. Recommended — this is a data protection alert, not an engagement nudge."
            , label = "Sync stalled alert"
            , msg = ToggleNotificationPref Notifications.SyncStalled
            , value = as_.notificationPrefs.syncStalled
            }
        , viewToggleRow
            { helper = "Every Friday at 5pm UTC, we'll nudge you to scan this week's receipts."
            , label = "Weekly receipt reminder"
            , msg = ToggleNotificationPref Notifications.WeeklyScanReminder
            , value = as_.notificationPrefs.weeklyScanReminder
            }
        ]

    else
        [ Html.p [ Html.Attributes.class "text-xs text-muted mb-3" ]
            [ Html.text "Weekly Friday reminder to scan receipts. You can turn it off anytime." ]
        , UI.Button.primary { label = "Enable notifications", onClick = RequestPushPermission }
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
