module Data.Notifications exposing
    ( NotificationPrefs
    , NotificationToggle(..)
    , PanelState(..)
    , Permission(..)
    , StandaloneState(..)
    , decodePrefs
    , defaultPrefs
    , encodePrefs
    , panelState
    , permissionFromString
    )

{-| Typed foundation for the PWA iOS notifications track.

This module is intentionally inert at runtime: no ports, no effects, no
HTTP. It exposes only the types + codecs that the rest of the track
(JS handlers, server routes, Settings UI, e2e tests) needs to import.
Wiring the actual behavior lands in downstream issues; landing the
types first lets those issues proceed in parallel without redoing
decoder work.

The data model:

  - `Permission` mirrors the four states the browser's Notification API
    can be in (`"granted"`, `"denied"`, `"default"`) plus an
    `Unsupported` bucket for engines that don't ship the API at all
    (older Safari, some embedded WebViews). Stored on `AuthState` and
    refreshed by the JS port whenever `Notification.permission`
    changes.
  - `StandaloneState` records whether the app is running inside the
    iOS "Add to Home Screen" PWA shell vs. an in-browser tab. iOS only
    allows the Notifications API in standalone mode, so a chunk of the
    Settings UI gates on this. Hydrated at boot from
    `window.navigator.standalone` / `display-mode: standalone` media
    query.
  - `NotificationPrefs` is the user's opt-in matrix — which categories
    of notification they've enabled. Today there's just the one
    (`weeklyScanReminder`); the record is designed to grow as more
    notification kinds land. Persisted to PouchDB (per the storage-tier
    rules: user preferences, syncs across devices, not secret).
  - `NotificationToggle` (the discriminator for which pref a Toggle
    Msg is flipping; today the only variant is `WeeklyScanReminder`
    but the type exists so adding more prefs is a one-line `Msg`
    change rather than a constructor explosion) lands here alongside
    the port-wiring issue that first imports it. The push-subscription
    triple (endpoint, auth, p256dh) lives entirely on the JS side —
    it's constructed by `pushManager.subscribe()` and POSTed straight
    to the server without round-tripping through Elm, so it has no
    type on this side.

Wire formats:

  - `Permission` is not encoded directly here — the JS side reports it
    via the `NotificationStateChanged` port as a raw string and
    `permissionFromString` parses it.
  - `NotificationPrefs` decodes via `decodePrefs` (the persisted
    PouchDB doc) and encodes via `encodePrefs` (sent both to the JS
    `savePushPrefs` port for server-side persistence and, eventually,
    to the per-device server endpoint for cron-driven scheduling).

-}

import Json.Decode
import Json.Encode



-- PERMISSION


{-| The browser's Notification API permission state.

`Default` is the pre-prompt state — the user has neither granted nor
denied. `Granted` and `Denied` are the two terminal states; only a
fresh permission prompt can move out of `Denied` (and Safari requires
the user to manually flip it in Settings). `Unsupported` is for engines
that don't ship the API at all — fall back to a "not available" UI.

-}
type Permission
    = Default
    | Denied
    | Granted
    | Unsupported


{-| Parse the browser's permission string into a `Permission`.

The mapping matches the [Notification API spec][spec] (`"granted"`,
`"denied"`, `"default"`); anything else — including the empty string
the JS shim emits when `Notification` is `undefined` — collapses to
`Unsupported`.

[spec]: https://developer.mozilla.org/en-US/docs/Web/API/Notification/permission

    permissionFromString "granted"
    --> Granted

    permissionFromString "denied"
    --> Denied

    permissionFromString "default"
    --> Default

    permissionFromString "unsupported"
    --> Unsupported

    permissionFromString ""
    --> Unsupported

    permissionFromString "anything-else"
    --> Unsupported

-}
permissionFromString : String -> Permission
permissionFromString raw =
    case raw of
        "granted" ->
            Granted

        "denied" ->
            Denied

        "default" ->
            Default

        _ ->
            Unsupported



-- STANDALONE


{-| Whether the app is running as an installed PWA (`Standalone`) or
inside a normal browser tab (`InBrowser`).

iOS only exposes the Notifications API to standalone PWAs, so the
Settings UI's "Enable notifications" affordance is gated on this. On
other platforms the distinction is informational — the API works
either way.

-}
type StandaloneState
    = InBrowser
    | Standalone



-- PANEL STATE


{-| Which branch the Settings → Notifications panel renders. The single source
of truth for that decision, shared by the view (`Pages.Settings`) and the
verification surface (`Verify.Specs.NotificationsPaywall`), so the two can't
drift.

  - `PanelUnsupported` — the browser has no Notification API.
  - `PanelUpgradeRequired` — free tier; show the upgrade prompt + disabled button.
  - `PanelNotConfigured` — this build ships no VAPID public key, so no
    subscription can ever be created here; say so instead of offering a button.
  - `PanelNeedsInstall` — paid but running in a browser tab, not the installed PWA.
  - `PanelBlocked` — permission denied; show re-enable instructions.
  - `PanelSubscribed` — granted and subscribed; show the per-pref toggle rows.
  - `PanelCanEnable` — paid, standalone, not yet subscribed; show the Enable button.

-}
type PanelState
    = PanelBlocked
    | PanelCanEnable
    | PanelNeedsInstall
    | PanelNotConfigured
    | PanelSubscribed
    | PanelUnsupported
    | PanelUpgradeRequired


{-| Decide which notifications-panel branch applies. Mirrors the precedence in
`Pages.Settings.viewNotificationsBody` exactly.

`configured` is "this build has a VAPID public key" (`AppConfig.vapidPublicKey`
is non-empty). Without one, `pushManager.subscribe` cannot be called at all.

    panelState { configured = True, isPaid = False, permission = Granted, standalone = Standalone, subscribed = False }
    --> PanelUpgradeRequired

    panelState { configured = True, isPaid = True, permission = Granted, standalone = Standalone, subscribed = True }
    --> PanelSubscribed

    panelState { configured = True, isPaid = True, permission = Default, standalone = InBrowser, subscribed = False }
    --> PanelNeedsInstall

    panelState { configured = True, isPaid = True, permission = Denied, standalone = Standalone, subscribed = False }
    --> PanelBlocked

    panelState { configured = True, isPaid = True, permission = Default, standalone = Standalone, subscribed = False }
    --> PanelCanEnable

    panelState { configured = True, isPaid = True, permission = Unsupported, standalone = Standalone, subscribed = True }
    --> PanelUnsupported

    panelState { configured = False, isPaid = True, permission = Default, standalone = Standalone, subscribed = False }
    --> PanelNotConfigured

An unconfigured build still defers to the browser and the tier:

    panelState { configured = False, isPaid = True, permission = Unsupported, standalone = Standalone, subscribed = False }
    --> PanelUnsupported

    panelState { configured = False, isPaid = False, permission = Default, standalone = Standalone, subscribed = False }
    --> PanelUpgradeRequired

-}
panelState :
    { a
        | configured : Bool
        , isPaid : Bool
        , permission : Permission
        , standalone : StandaloneState
        , subscribed : Bool
    }
    -> PanelState
panelState { configured, isPaid, permission, standalone, subscribed } =
    if permission == Unsupported then
        PanelUnsupported

    else if not isPaid then
        PanelUpgradeRequired

    else if not configured then
        -- Ranked third — behind the browser check and the tier check, ahead of
        -- everything below it. `PanelUnsupported` and `PanelUpgradeRequired`
        -- are facts about the user's browser and account that hold on every
        -- build, so they still win. But an unconfigured build cannot mint a
        -- subscription at all, which makes every state BELOW this one a dead
        -- end: `PanelNeedsInstall` would send the user through
        -- Add-to-Home-Screen for nothing, `PanelBlocked` would send them into
        -- iOS Settings for nothing, and `PanelCanEnable` would offer a button
        -- whose only possible outcome is the error this PR now surfaces.
        -- Telling them the environment can't do it is the honest answer.
        --
        -- The one branch it can mask is `PanelSubscribed`. That needs a live
        -- subscription minted by an earlier, configured deploy — and push
        -- subscriptions are per-origin, so an origin that has never shipped a
        -- key has none to mask. Acceptable.
        PanelNotConfigured

    else if standalone == InBrowser then
        PanelNeedsInstall

    else if permission == Denied then
        PanelBlocked

    else if permission == Granted && subscribed then
        PanelSubscribed

    else
        PanelCanEnable



-- PREFS


{-| The user's notification opt-in matrix.

One field per notification kind. Fields are alphabetised. Future kinds
add fields here. The server's `DEFAULT_PREFS` mirrors this shape.

Persisted to PouchDB at `user:notificationPrefs`. Synced across the
user's devices like any other PouchDB doc.

-}
type alias NotificationPrefs =
    { sharedTripAccessChange : Bool
    , sharedTripActivity : Bool
    , sharedTripInvite : Bool
    , syncStalled : Bool
    , weeklyScanReminder : Bool
    }


{-| The default prefs for a brand-new user.

`sharedTripAccessChange` defaults `True` — access changes are informational
(the user lost access or gained billing responsibility); opt-in by default.
`sharedTripActivity` defaults `True` — co-traveler activity is the
headline notification for the shared-trip feature; opt-in by default.
`sharedTripInvite` defaults `True` — being invited to a shared trip is a
direct, actionable event; opt-in by default.
`syncStalled` defaults `True` — it is a data-protection alert, not an
engagement nudge. `weeklyScanReminder` defaults `False` — the user must
opt in explicitly.

-}
defaultPrefs : NotificationPrefs
defaultPrefs =
    { sharedTripAccessChange = True
    , sharedTripActivity = True
    , sharedTripInvite = True
    , syncStalled = True
    , weeklyScanReminder = False
    }


{-| Discriminator for which pref a `ToggleNotificationPref` Msg is
flipping.

Constructors are alphabetised. Future kinds add a constructor here and
a field on `NotificationPrefs` together; the `updateAuth` `case` on
this type then gets a new branch and the compiler enforces the wiring
end-to-end.

-}
type NotificationToggle
    = SharedTripAccessChange
    | SharedTripActivity
    | SharedTripInvite
    | SyncStalled
    | WeeklyScanReminder



-- CODECS


{-| Decode `NotificationPrefs` from JSON.

Missing fields fall back to the `defaultPrefs` value for that field,
so older docs (written before a new pref was added) decode without
error.

-}
decodePrefs : Json.Decode.Decoder NotificationPrefs
decodePrefs =
    Json.Decode.map5 NotificationPrefs
        (Json.Decode.oneOf
            [ Json.Decode.field "sharedTripAccessChange" Json.Decode.bool
            , Json.Decode.succeed defaultPrefs.sharedTripAccessChange
            ]
        )
        (Json.Decode.oneOf
            [ Json.Decode.field "sharedTripActivity" Json.Decode.bool
            , Json.Decode.succeed defaultPrefs.sharedTripActivity
            ]
        )
        (Json.Decode.oneOf
            [ Json.Decode.field "sharedTripInvite" Json.Decode.bool
            , Json.Decode.succeed defaultPrefs.sharedTripInvite
            ]
        )
        (Json.Decode.oneOf
            [ Json.Decode.field "syncStalled" Json.Decode.bool
            , Json.Decode.succeed defaultPrefs.syncStalled
            ]
        )
        (Json.Decode.oneOf
            [ Json.Decode.field "weeklyScanReminder" Json.Decode.bool
            , Json.Decode.succeed defaultPrefs.weeklyScanReminder
            ]
        )


{-| Encode `NotificationPrefs` as JSON.

Mirrors `decodePrefs` — one field per opt-in. Sent through the
`savePushPrefs` outbound port whenever the user flips a toggle in the
Settings UI; the JS handler PUTs it to the server's per-device
preferences endpoint so the cron-driven scheduler can read it without
loading the user's PouchDB.

-}
encodePrefs : NotificationPrefs -> Json.Encode.Value
encodePrefs prefs =
    Json.Encode.object
        [ ( "sharedTripAccessChange", Json.Encode.bool prefs.sharedTripAccessChange )
        , ( "sharedTripActivity", Json.Encode.bool prefs.sharedTripActivity )
        , ( "sharedTripInvite", Json.Encode.bool prefs.sharedTripInvite )
        , ( "syncStalled", Json.Encode.bool prefs.syncStalled )
        , ( "weeklyScanReminder", Json.Encode.bool prefs.weeklyScanReminder )
        ]
