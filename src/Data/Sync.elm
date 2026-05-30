module Data.Sync exposing (NetworkState(..), SyncState(..), becameOnline, isOffline)

{-| PouchDB → CouchDB live-sync health.

The single source of truth lives in JavaScript (`src/pouch.js` owns the
sync handle); this enum is what the JS side reports back through the
`SyncStateMsg` inbound message. The header badge in `UI.Layout`
translates these states into the small dot/warn indicator.

The `AuthExpired` state is special: when sync reports it, the auth
token has been rejected and we drop straight to `GuestModel
SessionExpired` (handled in `Main.updateAuth`'s `AuthExpiredMsg` arm).

-}


{-| Sync states reported by the PouchDB→CouchDB replicator.

  - `NotEnabled` — sync hasn't been started (initial state before
    `startSync`).
  - `Syncing` — replication is actively transferring documents.
  - `Synced` — replication is idle and caught up; the moment we first
    see this we fire `GetAllTrips` (race-free entry point for the
    initial fetch — see `Main.init` docstring).
  - `SyncError` — transient error; replication retries on its own.
  - `AuthExpired` — the auth token was rejected; not recoverable
    without re-login.

-}
type SyncState
    = AuthExpired
    | NotEnabled
    | SyncError
    | Synced
    | Syncing


{-| The browser's connectivity, as a tri-state.

`navigator.onLine` is a `Bool`, but the value only arrives _after_ boot
(via the `networkStatus` port). The window between boot and that first
report is a real third state: we don't yet know whether we're online.
Modelling it as `Unknown` — rather than defaulting `networkOffline` to
`False` — lets the capture path treat "unknown" as offline-safe and
defer OCR, so the boot window can't fire a doomed network call (#372).

  - `Offline` — the browser reports no connection.
  - `Online` — the browser reports a connection.
  - `Unknown` — no `networkStatus` report has landed yet (boot window).

-}
type NetworkState
    = Offline
    | Online
    | Unknown


{-| Whether to treat the connection as offline. `Unknown` collapses to
`True` (offline-safe): the capture path defers, the banner shows, until
the first real `networkStatus` report proves we're `Online`.

    isOffline Online
    --> False

    isOffline Offline
    --> True

    isOffline Unknown
    --> True

-}
isOffline : NetworkState -> Bool
isOffline state =
    case state of
        Offline ->
            True

        Online ->
            False

        Unknown ->
            True


{-| True on the connectivity EDGE into online: the previous tri-state was
treated as offline (`Offline` or the boot-window `Unknown`) and the fresh
`navigator.onLine` report is `True`. This is the trigger for re-running
deferred OCR in-session (#400) — a `navigator.onLine` flip the live
PouchDB sync may not observe as a fresh `Synced` edge, so the
connectivity port drives the retry directly.

Returns `False` for a redundant online report (already `Online`), so a
duplicate `networkStatus True` can't double-dispatch.

    becameOnline Offline True
    --> True

    becameOnline Unknown True
    --> True

    becameOnline Online True
    --> False

    becameOnline Offline False
    --> False

-}
becameOnline : NetworkState -> Bool -> Bool
becameOnline previous isOnline =
    isOnline && isOffline previous
