module Data.Scan exposing (OcrData, ScanItem, ScanStatus(..), ocrDataDecoder, ocrDataListDecoder)

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

import Data.Category as Category exposing (Category)
import Data.DateField as DateField exposing (DateField)
import Data.Location exposing (LocationState)
import Data.Money as Money exposing (Money)
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod)
import Data.ScanItemId exposing (ScanItemId)
import Json.Decode
import Json.Decode.Pipeline as Pipeline


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
    { address : Maybe String
    , amount : Maybe Money
    , category : Maybe Category
    , date : Maybe DateField
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
  - `ocrError` — human-readable reason the most recent OCR attempt
    failed (HTTP error, refusal, unparseable JSON, etc.). `Nothing`
    while OCR is in flight or after a successful read; surfaced on the
    Scan card so the user can tell why an item is in fill-manually
    mode instead of guessing.
  - `status` — the lifecycle stage above.

-}
type alias ScanItem =
    { exifDebug : String
    , id : ScanItemId
    , imageUrl : String
    , locationState : LocationState
    , ocrData : Maybe OcrData
    , ocrError : Maybe String
    , status : ScanStatus
    }


{-| Decode one OCR JSON object into an `OcrData`. Every field is
optional — Anthropic's "best effort" parser may omit any of them, and a
missing field falls through to `Nothing` rather than failing the whole
parse. `address` was added in #150 so receipts batch-scanned at home
can be geocoded to where they were actually issued (paid tier) or
manually pinned (free tier).
-}
ocrDataDecoder : Json.Decode.Decoder OcrData
ocrDataDecoder =
    Json.Decode.succeed OcrData
        |> Pipeline.optional "address" (Json.Decode.map Just Json.Decode.string) Nothing
        |> Pipeline.optional "amount" (Json.Decode.map Just Money.decoder) Nothing
        |> Pipeline.optional "category" (Json.Decode.map Just (Json.Decode.map Category.fromString Json.Decode.string)) Nothing
        |> Pipeline.optional "date" (Json.Decode.map Just DateField.decoder) Nothing
        |> Pipeline.optional "longNote" (Json.Decode.map Just Json.Decode.string) Nothing
        |> Pipeline.optional "merchant" (Json.Decode.map Just Json.Decode.string) Nothing
        |> Pipeline.optional "note" (Json.Decode.map Just Json.Decode.string) Nothing
        |> Pipeline.optional "paymentMethod"
            (Json.Decode.nullable
                (Json.Decode.string
                    |> Json.Decode.andThen
                        (\s ->
                            case PaymentMethod.fromString s of
                                Just pm ->
                                    Json.Decode.succeed pm

                                Nothing ->
                                    Json.Decode.fail ("Unknown paymentMethod: " ++ s)
                        )
                )
            )
            Nothing


{-| Decode either a single OCR object or a JSON array of them into a
list. The Anthropic prompt asks for an array, but legacy single-object
responses still parse for backward compatibility.
-}
ocrDataListDecoder : Json.Decode.Decoder (List OcrData)
ocrDataListDecoder =
    Json.Decode.oneOf
        [ Json.Decode.list ocrDataDecoder
        , Json.Decode.map List.singleton ocrDataDecoder
        ]
