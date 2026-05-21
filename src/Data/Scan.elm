module Data.Scan exposing (OcrData, ScanItem, ScanStatus(..))

{-| Receipt-scan queue: one `ScanItem` per receipt the user has dropped
into the Scan tab, plus the OCR result the Anthropic API hands back.

The queue is a `Dict String ScanItem` keyed by the item's local id
(`"scan-<n>"`). Each item moves through `ScanQueued → ScanProcessing →
ScanReady → ScanSubmitted` as files are read, OCR completes, the user
reviews the result on the Add page, and the resulting expense is saved.

Why optional fields on `OcrData`: Anthropic returns "best effort" JSON
and any field may be missing or unreadable. The Add page fills them in
from `OcrData` and falls back to defaults for whatever's missing, so
making them required would force fake placeholder values into the
domain.

-}

import Data.Category exposing (Category)
import Data.Location exposing (LocationState)
import Data.PaymentMethod exposing (PaymentMethod)


{-| Lifecycle stage of one queued receipt.

  - `ScanQueued` — file picked, not yet read into a data URL.
  - `ScanProcessing` — OCR request in flight to Anthropic.
  - `ScanReady` — OCR returned (with or without data); user can review.
  - `ScanSubmitted` — review confirmed and the expense was saved; the
    card stays visible (greyed out) until "Clear submitted" is tapped.

-}
type ScanStatus
    = ScanProcessing
    | ScanQueued
    | ScanReady
    | ScanSubmitted


{-| Best-effort fields parsed from a receipt photo by the Anthropic OCR
prompt (see `Main.ocrSystemPrompt`).

Every field is optional because the model may fail to read any subset of
them — for example a faded thermal receipt can produce a clear amount
but unreadable date. The Add-page review step is the user's chance to
correct anything missing or wrong.

-}
type alias OcrData =
    { amount : Maybe Float
    , category : Maybe Category
    , date : Maybe String
    , longNote : Maybe String
    , merchant : Maybe String
    , note : Maybe String
    , paymentMethod : Maybe PaymentMethod
    }


{-| One receipt in the scan queue.

  - `id` — local-only key (`"scan-<n>"`), never reaches PouchDB.
  - `imageUrl` — base64 data URL of the picked image, used as both the
    preview src and the OCR upload.
  - `exifDebug` — raw EXIF dump shown in the "debug info" disclosure
    when EXIF parsing finds no GPS. Useful for diagnosing why a photo
    we'd expect to have coordinates didn't.
  - `locationState` — independent of OCR; populated via the EXIF-GPS
    extraction port.
  - `ocrData` — `Nothing` until OCR returns; `Just` even if the model
    extracted nothing (so we know it ran).
  - `status` — the lifecycle stage above.

-}
type alias ScanItem =
    { exifDebug : String
    , id : String
    , imageUrl : String
    , locationState : LocationState
    , ocrData : Maybe OcrData
    , status : ScanStatus
    }
