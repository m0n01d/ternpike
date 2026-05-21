module Data.Sync exposing (SyncState(..))

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
