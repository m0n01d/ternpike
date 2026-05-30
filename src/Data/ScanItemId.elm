module Data.ScanItemId exposing (ScanItemId, fromString, toString)

{-| Opaque wrapper around a scan-queue item id.

The string follows a fixed, durable format:

    scan::<millis>::<seq>

where `<millis>` is the capture timestamp and `<seq>` is a monotonic
per-session counter (`AuthState.scanSeq`). The counter — rather than a
per-batch index — is what keeps two captures in the same millisecond
from colliding. A multi-receipt split reuses its parent's id as the
middle segment so children stay grouped:

    scan::<parentId>::<i>

Unlike the previous `scan-<n>` scheme, this id is **persisted** to the
durable scan queue (IndexedDB, see `Data.Scan.scanItemEncoder`) so a
captured-but-not-yet-filed receipt survives a reload. It is still
local-only — it never reaches PouchDB / CouchDB — and is matched against
`AuthState.activeScanItemId` to decide which UI affordances to show.
Wrapping it in an opaque type stops the compiler from letting you mix
`ScanItemId` with any other `String`.

-}


type ScanItemId
    = ScanItemId String


fromString : String -> ScanItemId
fromString =
    ScanItemId


toString : ScanItemId -> String
toString (ScanItemId s) =
    s
