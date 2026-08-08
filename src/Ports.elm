port module Ports exposing
    ( applySwUpdate, canInstall, clearAllStorage, clearStorage, deleteScanItem, downloadFile
    , extractExifGps, gotExifResult, gotGpsCoords
    , loadScanQueue, nativeShare, nativeShareResult, networkStatus, notificationState
    , ocrImagePrepared, pouchIn, pouchOut, prepareOcrImage, pushSubscribeResult
    , requestGeolocation, saveScanItem, savePushPrefs, saveStorage, scanItemSaved
    , scanProxyIn, scanProxyOut, scanQueueLoaded, startSync, stopSync, storageStatus
    , subscribePush, swUpdateReady, trackFunnel, triggerInstallPrompt
    , unsubscribePush, verifyResults
    )

{-| Every JavaScript interop port for the app, extracted from `Main.elm`
so feature modules (e.g. `Page.Scan`) can call the ports they need
without depending on `Main`. The set is unchanged from when these lived
in `Main`; only their home moved (#368).

@docs applySwUpdate, canInstall, clearAllStorage, clearStorage, deleteScanItem, downloadFile
@docs extractExifGps, gotExifResult, gotGpsCoords
@docs loadScanQueue, nativeShare, nativeShareResult, networkStatus, notificationState
@docs ocrImagePrepared, pouchIn, pouchOut, prepareOcrImage, pushSubscribeResult
@docs requestGeolocation, saveScanItem, savePushPrefs, saveStorage, scanItemSaved
@docs scanProxyIn, scanProxyOut, scanQueueLoaded, startSync, stopSync, storageStatus
@docs subscribePush, swUpdateReady, trackFunnel, triggerInstallPrompt
@docs unsubscribePush, verifyResults

-}

import Json.Decode
import Json.Encode


port saveStorage : { key : String, value : String } -> Cmd msg


port clearStorage : () -> Cmd msg


port clearAllStorage : () -> Cmd msg


port pouchOut : Json.Decode.Value -> Cmd msg


port pouchIn : (Json.Decode.Value -> msg) -> Sub msg


port startSync : Json.Decode.Value -> Cmd msg


port stopSync : () -> Cmd msg


port requestGeolocation : () -> Cmd msg


port extractExifGps : { id : String, dataUrl : String } -> Cmd msg


port prepareOcrImage : { dataUrl : String, id : String, maxBytes : Int } -> Cmd msg


port ocrImagePrepared : ({ dataUrl : String, error : String, finalBytes : Int, id : String, originalBytes : Int } -> msg) -> Sub msg


port gotGpsCoords : ({ lat : Float, lon : Float, denied : Bool } -> msg) -> Sub msg


port gotExifResult : ({ id : String, lat : Float, lon : Float, hasGps : Bool, debug : String } -> msg) -> Sub msg


port networkStatus : (Bool -> msg) -> Sub msg


port triggerInstallPrompt : () -> Cmd msg


port canInstall : (Bool -> msg) -> Sub msg


port scanProxyOut : { backendUrl : String, body : Json.Encode.Value, itemId : String } -> Cmd msg


port scanProxyIn : ({ body : String, itemId : String, ok : Bool, status : Int } -> msg) -> Sub msg


port savePushPrefs : Json.Decode.Value -> Cmd msg


port subscribePush : { prefs : Json.Decode.Value, vapidPublicKey : String } -> Cmd msg


port unsubscribePush : () -> Cmd msg


port notificationState : ({ permission : String, prefs : Json.Decode.Value, standalone : Bool, subscribed : Bool } -> msg) -> Sub msg


port pushSubscribeResult : ({ error : String, ok : Bool } -> msg) -> Sub msg


port downloadFile : { content : String, filename : String, mimeType : String } -> Cmd msg


port nativeShare : { mode : String, text : String, title : String, url : String } -> Cmd msg


port nativeShareResult : ({ ok : Bool, reason : String } -> msg) -> Sub msg


{-| Fire-and-forget funnel analytics beacon (#340). Payload is
`{ stage, flockId }` — see `Analytics.elm` for the stage allowlist.
The JS handler POSTs to `/invite/track` (no auth, no PII).
-}
port trackFunnel : { flockId : String, stage : String } -> Cmd msg


{-| Push the full verification matrix to JS so the `/verify` routes can expose
`window.__verify`. Fired only when booting into a `RouteVerify` URL. See
`Verify.Registry` and the Verify track plan.
-}
port verifyResults : Json.Encode.Value -> Cmd msg



-- DURABLE SCAN QUEUE (#371)
--
-- The offline scan queue is persisted to an IndexedDB object store
-- (`scanQueue`) keyed by scan id. `loadScanQueue` asks JS to `getAll` the
-- store and hand it back via `scanQueueLoaded`; `saveScanItem` persists one
-- normalized item, acked through `scanItemSaved` (so a `QuotaExceededError`
-- surfaces as `persistError` instead of being silently swallowed).
-- `deleteScanItem` removes one item by id from the durable store — its
-- first Elm callers (the change-feed-confirmed submit clear + `ClearDoneItems`)
-- land in #374; the JS handler has been wired since #371 (see `src/main.js`).
-- `storageStatus` carries the boot probe + best-effort
-- `navigator.storage.persist()` result.


{-| Ask JS to `getAll` the durable `scanQueue` store and reply via
[`scanQueueLoaded`](#scanQueueLoaded). Fired from `init`'s authed branch and
the in-SPA re-login arms (`VerifyCodeResult` / `MagicVerifyResult`).
-}
port loadScanQueue : () -> Cmd msg


{-| The hydrated queue as a JSON array of `scanItemEncoder`-shaped docs.
Decoded item-by-item through `Data.Scan.scanItemDecoder` (bad docs are
quarantined), then normalized by `Data.Scan.reconcileHydratedQueue`.
-}
port scanQueueLoaded : (Json.Decode.Value -> msg) -> Sub msg


{-| Persist one `scanItemEncoder`-shaped doc to the durable `scanQueue`
store. Acked through [`scanItemSaved`](#scanItemSaved).
-}
port saveScanItem : Json.Decode.Value -> Cmd msg


{-| Remove one item (by its durable `scan::<millis>::<seq>` id) from the
durable `scanQueue` store. Fire-and-forget — the JS handler swallows a
failed `delete` (a `delete` on an absent key is a no-op, which is exactly
the idempotency the change-feed echo relies on). First callers land in
#374: the change-feed-confirmed submit clear and `ClearDoneItems`.
-}
port deleteScanItem : String -> Cmd msg


{-| Save-ack for [`saveScanItem`](#saveScanItem). `ok` is `False` (with a
non-empty `error`) when the underlying `put` threw — e.g.
`QuotaExceededError`. Elm flips `persistError` on the matching item so the
capture UI never promises durability it didn't get.
-}
port scanItemSaved : ({ error : String, id : String, ok : Bool } -> msg) -> Sub msg


{-| Device storage availability, persistence, and installed-PWA mode.
`available` is `False` when the boot probe of the `scanQueue` store failed
(Private Browsing / Lockdown Mode); `persisted` reflects
`navigator.storage.persisted()` / `persist()` (best-effort, resolves `False`
when the UA declines); `installed` is `True` when the app is running in
standalone (installed-PWA) mode — `navigator.standalone === true` or
`matchMedia('(display-mode: standalone)').matches`; `isIos` is `True` when the
UA is iOS/iPadOS — used to gate the manual Add-to-Home-Screen nudge since iOS
never fires `beforeinstallprompt` (#377).
-}
port storageStatus : ({ available : Bool, installed : Bool, isIos : Bool, persisted : Bool } -> msg) -> Sub msg



-- SERVICE-WORKER UPDATE TOAST (#477)


{-| Ask JS to activate the waiting service worker: it posts `SKIP_WAITING` and
reloads once the new worker takes control (`controllerchange`).

Fired by the update bar's **Reload** button. The handler is defensive by
design — if there is no waiting worker it reloads immediately, and it arms a
~4s timeout that force-reloads when `controllerchange` never arrives. A
waiting worker that never activates is a real WebKit behavior
([199110](https://bugs.webkit.org/show_bug.cgi?id=199110), open iOS 12.3 →
16), and the fetch handler is network-first, so an unconditional reload is
always correct. Reload can therefore never be a no-op.

-}
port applySwUpdate : () -> Cmd msg


{-| `True` when JS is holding a service worker that is installed and waiting
to take over; `False` retracts it (the worker went `redundant`, so a failed
activation can't leave a permanent bar on screen).

`Bool` rather than a one-shot signal, matching every other state-carrying Sub
port (`canInstall`, `networkStatus`, `storageStatus`). JS holds the waiting
worker and re-emits on every resume tick: `Main.updateAuth` is only reached
from `AuthModel`, so a notification that lands while the login screen is
mounted is dropped, and without the re-emit a logged-out user would never see
the toast for the rest of the session.

-}
port swUpdateReady : (Bool -> msg) -> Sub msg
