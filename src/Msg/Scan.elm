module Msg.Scan exposing (Msg(..))

{-| Messages exclusive to the Scan / OCR feature, carved out of the
top-level `AuthMsg_` in `Types.elm` (#368). `Types.AuthMsg_` now nests
these under a single `ScanMsg Msg.Scan.Msg` variant, and `Page.Scan.update`
handles them.

This module deliberately does NOT import `Types`: `Types` imports it (for
the nested variant), so importing back would form a compile-time cycle.
It carries only the data types its constructor payloads need.

@docs Msg

-}

import File exposing (File)
import Http
import Http.GeocodeApi
import Time


{-| Every Scan-page action. See `Page.Scan.update` for the handlers.

  - `FilesSelected` — user picked one or more files to scan. Fires a
    `Time.now` task so the durable id uses the real capture millis.
  - `FilesStamped` — the `Time.now` for a batch resolved; mint ids now.
  - `GotFileUrl` — a selected file finished reading into a data URL.
  - `OcrImagePrepared` — JS finished downscaling an image for OCR.
  - `GotOcrResult` — direct (BYO-key) Anthropic response landed.
  - `ScanProxyResult` — hosted-proxy scan response landed.
  - `GotExifCoords` — EXIF GPS extraction finished for an item.
  - `GotGeocodeResult` — `/geocode` of a receipt address resolved.
  - `ReviewScanItem` — open the Add form pre-filled from a scan item.
  - `BackToQueue` — return from the Add review form to the scan queue.
  - `ClearDoneItems` — drop submitted items from the queue.
  - `RetryDeferredScans` — connectivity returned (the proven `Synced`
    sync edge in `Main`): run OCR for as many `ScanDeferred` items as the
    tier concurrency cap allows. Idempotent — a redundant `Synced` edge
    with the in-flight set already at the cap dispatches nothing.

-}
type Msg
    = BackToQueue
    | ClearDoneItems
    | FilesSelected (List File)
    | FilesStamped Time.Posix (List File)
    | GotExifCoords String (Maybe Float) (Maybe Float) String
    | GotFileUrl String String
    | GotGeocodeResult String (Result Http.Error Http.GeocodeApi.GeocodeResponse)
    | GotOcrResult String (Result String String)
    | OcrImagePrepared { dataUrl : String, error : String, finalBytes : Int, id : String, originalBytes : Int }
    | RetryDeferredScans
    | ReviewScanItem String
    | ScanProxyResult { body : String, itemId : String, ok : Bool, status : Int }
