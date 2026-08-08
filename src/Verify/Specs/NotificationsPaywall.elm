module Verify.Specs.NotificationsPaywall exposing (Input, honest, surface, inputForFixture, results)

{-| Verification unit for the Settings → Notifications panel (#347).

Covers every branch of `Pages.Settings.viewNotificationsBody`, which is driven
by the shared decision `Data.Notifications.panelState` — reused here so the
surface can't drift from the view. The input is a key-free projection of
`(configured, error, isPaid, permission, standalone, subscribed)` plus a
`corrupt` knob used only by the adversarial probe.

`configured` is `AuthState.pushConfigured` — "the API this deployment talks to
serves a non-empty VAPID public key", reported over the `notificationState`
port at boot. `error` is `AuthState.pushError`, the reason a subscribe attempt
failed. Both exist because "Enable notifications" could previously fail in
total silence — the JS handler reported a reason, `PushSubscribeReceived`
discarded it, and a deployment with no key still rendered a live button.

`configured` used to read the build-time `AppConfig.vapidPublicKey`. That is no
longer what decides whether push can work: the subscribe path fetches the key
from the API (#490), so the gate now follows suit.

This retires `e2e/specs/notifications-paywall.spec.ts`: every assertion there is
a deterministic function of this input, so it needs no backend.

@docs Input, honest, surface, inputForFixture, results

-}

import Data.Notifications as Notifications
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


{-| The slice this unit observes. `corrupt = True` flips the rendered control
state to model a regression — only the probe sets it.
-}
type alias Input =
    { configured : Bool
    , corrupt : Bool
    , error : Maybe String
    , isPaid : Bool
    , permission : Notifications.Permission
    , standalone : Notifications.StandaloneState
    , subscribed : Bool
    }


{-| An honest input (never corrupt) — the projection the view + DOM tier feed.
-}
honest :
    { configured : Bool
    , error : Maybe String
    , isPaid : Bool
    , permission : Notifications.Permission
    , standalone : Notifications.StandaloneState
    , subscribed : Bool
    }
    -> Input
honest fields =
    { configured = fields.configured
    , corrupt = False
    , error = fields.error
    , isPaid = fields.isPaid
    , permission = fields.permission
    , standalone = fields.standalone
    , subscribed = fields.subscribed
    }


{-| Derive the notifications panel's observable surface. Reuses
`Data.Notifications.panelState` for the branch decision — `Input` is a superset
of that function's extensible record, so it goes through whole rather than
being re-projected; `corrupt` flips the enable-button key to a wrong value so
the probe's invariant has a real regression to catch.
-}
surface : Input -> Contract.Surface
surface input =
    let
        state : Notifications.PanelState
        state =
            Notifications.panelState input

        button : String
        button =
            if input.corrupt then
                -- A regression: claim the button is enabled regardless of state.
                "enabled"

            else
                buttonFor state
    in
    [ ( "panel", panelKey state )
    , ( "enable-button", button )
    , ( "upgrade-copy", upgradeCopyFor state )
    , ( "error", Maybe.withDefault "none" input.error )
    ]


{-| Map a fixture name to its input. Single source of truth for the fixtures
_and_ the DOM-tier seeding in `Main.seedVerifyAuthState`.
-}
inputForFixture : String -> Input
inputForFixture name =
    case name of
        "needs-install" ->
            honest { configured = True, error = Nothing, isPaid = True, permission = Notifications.Default, standalone = Notifications.InBrowser, subscribed = False }

        "blocked" ->
            honest { configured = True, error = Nothing, isPaid = True, permission = Notifications.Denied, standalone = Notifications.Standalone, subscribed = False }

        "subscribed" ->
            honest { configured = True, error = Nothing, isPaid = True, permission = Notifications.Granted, standalone = Notifications.Standalone, subscribed = True }

        "can-enable" ->
            honest { configured = True, error = Nothing, isPaid = True, permission = Notifications.Default, standalone = Notifications.Standalone, subscribed = False }

        "unconfigured" ->
            -- Paid, installed, permission un-asked — and the API reports no
            -- VAPID key, so there is nothing an Enable button could do.
            honest { configured = False, error = Nothing, isPaid = True, permission = Notifications.Default, standalone = Notifications.Standalone, subscribed = False }

        "subscribe-error" ->
            -- A tap that came back `ok:false`. The pane must say why.
            honest { configured = True, error = Just subscribeErrorReason, isPaid = True, permission = Notifications.Default, standalone = Notifications.Standalone, subscribed = False }

        "unsupported" ->
            honest { configured = True, error = Nothing, isPaid = True, permission = Notifications.Unsupported, standalone = Notifications.Standalone, subscribed = True }

        "probe-free-enabled" ->
            { configured = True, corrupt = True, error = Nothing, isPaid = False, permission = Notifications.Granted, standalone = Notifications.Standalone, subscribed = False }

        _ ->
            -- "tern" and any unknown fixture: the free-tier upgrade branch.
            honest { configured = True, error = Nothing, isPaid = False, permission = Notifications.Granted, standalone = Notifications.Standalone, subscribed = False }


{-| The reason the `subscribe-error` fixture carries — a real
`pushManager.subscribe` rejection string. Named so the DOM tier and the pure
tier assert the same text.
-}
subscribeErrorReason : String
subscribeErrorReason =
    "Registration failed - push service error"


{-| The pure-tier results for this unit, collected by `Verify.Registry`.
-}
results : List Core.RunResult
results =
    Runner.runUnit spec


spec : Spec.UnitSpec Input
spec =
    { fixtures =
        List.map
            (\name -> { input = inputForFixture name, name = name, probe = String.startsWith "probe" name })
            fixtureNames
    , invariants =
        [ { name = "free tier shows upgrade + disabled button", check = freeShowsUpgrade }
        , { name = "unsupported hides the enable button", check = unsupportedHidesButton }
        , { name = "paid + standalone + not-subscribed can enable", check = canEnable }
        , { name = "a deployment with no server VAPID key offers no button", check = unconfiguredHidesButton }
        , { name = "a failed subscribe surfaces its reason", check = errorIsSurfaced }
        ]
    , name = "NotificationsPaywall"
    , surface = surface
    }


fixtureNames : List String
fixtureNames =
    [ "tern", "needs-install", "blocked", "subscribed", "can-enable", "unconfigured", "subscribe-error", "unsupported", "probe-free-enabled" ]



-- INVARIANTS


freeShowsUpgrade : Input -> Contract.Surface -> Maybe String
freeShowsUpgrade input observed =
    -- Only applies to free, supported browsers (Unsupported wins regardless of tier).
    if input.isPaid || input.permission == Notifications.Unsupported then
        Nothing

    else if value "enable-button" observed == Just "disabled" && value "upgrade-copy" observed == Just "osprey" then
        Nothing

    else
        Just "free tier did not show a disabled button + upgrade copy"


unsupportedHidesButton : Input -> Contract.Surface -> Maybe String
unsupportedHidesButton input observed =
    if input.permission /= Notifications.Unsupported then
        Nothing

    else if value "enable-button" observed == Just "absent" then
        Nothing

    else
        Just "unsupported browser still rendered an enable button"


canEnable : Input -> Contract.Surface -> Maybe String
canEnable input observed =
    if not (input.configured && input.isPaid && input.standalone == Notifications.Standalone && input.permission == Notifications.Default) then
        Nothing

    else if value "enable-button" observed == Just "enabled" then
        Nothing

    else
        Just "paid + standalone + default did not offer the enable button"


unconfiguredHidesButton : Input -> Contract.Surface -> Maybe String
unconfiguredHidesButton input observed =
    -- The browser check and the tier check outrank the server-config check, so
    -- this only bites once both of those have passed.
    if input.configured || not input.isPaid || input.permission == Notifications.Unsupported then
        Nothing

    else if value "panel" observed == Just "unconfigured" && value "enable-button" observed == Just "absent" then
        Nothing

    else
        Just "a deployment with no server VAPID key still offered the enable button"


errorIsSurfaced : Input -> Contract.Surface -> Maybe String
errorIsSurfaced input observed =
    case input.error of
        Nothing ->
            if value "error" observed == Just "none" then
                Nothing

            else
                Just "the panel reported an error with nothing to report"

        Just reason ->
            if value "error" observed == Just reason then
                Nothing

            else
                Just "a failed subscribe attempt did not surface its reason"



-- SURFACE HELPERS


panelKey : Notifications.PanelState -> String
panelKey state =
    case state of
        Notifications.PanelUnsupported ->
            "unsupported"

        Notifications.PanelUpgradeRequired ->
            "upgrade"

        Notifications.PanelNotConfigured ->
            "unconfigured"

        Notifications.PanelNeedsInstall ->
            "install"

        Notifications.PanelBlocked ->
            "blocked"

        Notifications.PanelSubscribed ->
            "toggles"

        Notifications.PanelCanEnable ->
            "enable"


buttonFor : Notifications.PanelState -> String
buttonFor state =
    case state of
        Notifications.PanelUpgradeRequired ->
            "disabled"

        Notifications.PanelCanEnable ->
            "enabled"

        Notifications.PanelNotConfigured ->
            "absent"

        Notifications.PanelUnsupported ->
            "absent"

        Notifications.PanelNeedsInstall ->
            "absent"

        Notifications.PanelBlocked ->
            "absent"

        Notifications.PanelSubscribed ->
            "absent"


upgradeCopyFor : Notifications.PanelState -> String
upgradeCopyFor state =
    case state of
        Notifications.PanelUpgradeRequired ->
            "osprey"

        Notifications.PanelNotConfigured ->
            "none"

        Notifications.PanelUnsupported ->
            "none"

        Notifications.PanelNeedsInstall ->
            "none"

        Notifications.PanelBlocked ->
            "none"

        Notifications.PanelSubscribed ->
            "none"

        Notifications.PanelCanEnable ->
            "none"


value : String -> Contract.Surface -> Maybe String
value key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
