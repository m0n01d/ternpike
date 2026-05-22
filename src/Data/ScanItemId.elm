module Data.ScanItemId exposing (ScanItemId, decode, encode, fromString, toString)

{-| Opaque wrapper around a local-only scan item id.

The string follows a fixed format:

    scan-<n>

Unlike `ExpenseId` / `AmendmentId` / `TripId`, this value is **never
persisted** to PouchDB — it lives only in `AuthState` while a scan is in
flight and is matched against `AuthState.activeScanItemId` to decide which
UI affordances to show. Wrapping it in an opaque type stops the compiler
from letting you mix `ScanItemId` with any other `String`.

-}

import Json.Decode
import Json.Encode


type ScanItemId
    = ScanItemId String


decode : Json.Decode.Decoder ScanItemId
decode =
    Json.Decode.map ScanItemId Json.Decode.string


encode : ScanItemId -> Json.Encode.Value
encode (ScanItemId s) =
    Json.Encode.string s


fromString : String -> ScanItemId
fromString =
    ScanItemId


toString : ScanItemId -> String
toString (ScanItemId s) =
    s
