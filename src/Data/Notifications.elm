module Data.Notifications exposing
    ( NotificationPrefs
    , Permission(..)
    , StandaloneState(..)
    , decodePrefs
    , defaultPrefs
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
  - `NotificationToggle` (the discriminator for which pref a Toggle Msg
    is flipping) and `PushSubscription` (the trio of strings the
    browser hands back from `pushManager.subscribe`) are both deferred
    to the issue that first imports them — the Settings UI for
    `NotificationToggle`, the server-route for `PushSubscription`.
    Landing them here would trip `NoUnused.Exports` with no consumer;
    follow the `Data.Tier` precedent and add types as they're imported.

Wire formats:

  - `Permission` is not encoded directly here — the JS side reports it
    via the `NotificationStateChanged` port as a raw string and
    `permissionFromString` parses it.
  - `NotificationPrefs` decodes via `decodePrefs` (the persisted
    PouchDB doc). The encoder lands with the Settings issue that
    first writes back to PouchDB — landing it here would trip
    `NoUnused.Exports`.

-}

import Json.Decode



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



-- PREFS


{-| The user's notification opt-in matrix.

One field per notification kind. Today there's just
`weeklyScanReminder`; future kinds (trip-budget alerts, shared-trip
member-joined pings, etc.) add fields here. Always opt-in: a fresh
user starts with everything `False` (see `defaultPrefs`).

Persisted to PouchDB at `user:notificationPrefs`. Synced across the
user's devices like any other PouchDB doc.

-}
type alias NotificationPrefs =
    { weeklyScanReminder : Bool
    }


{-| The default prefs for a brand-new user.

Every pref starts `False` — notifications are strictly opt-in. The
Settings UI is responsible for flipping individual fields on as the
user enables them.

-}
defaultPrefs : NotificationPrefs
defaultPrefs =
    { weeklyScanReminder = False
    }



-- CODECS


{-| Decode `NotificationPrefs` from JSON.

Missing fields fall back to the `defaultPrefs` value for that field,
so older docs (written before a new pref was added) decode without
error.

-}
decodePrefs : Json.Decode.Decoder NotificationPrefs
decodePrefs =
    Json.Decode.map NotificationPrefs
        (Json.Decode.oneOf
            [ Json.Decode.field "weeklyScanReminder" Json.Decode.bool
            , Json.Decode.succeed defaultPrefs.weeklyScanReminder
            ]
        )
