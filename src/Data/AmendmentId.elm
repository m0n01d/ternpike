module Data.AmendmentId exposing (AmendmentId, decode, encode, fromString, toString)

{-| Opaque wrapper around a PouchDB amendment `_id`.

The string follows a fixed format that doubles as the document key in PouchDB:

    amend::<expenseId>::<iso>::<nonce>

Wrapping it in an opaque type stops the compiler from letting you mix
`AmendmentId` with `ExpenseId` (or with any other `String`). Use `toString`
only when you need the raw key for a `Dict` lookup or for matching against
the embedded expense ID in `Data/Entry.elm:applyAmendment`.

-}

import Json.Decode
import Json.Encode


type AmendmentId
    = AmendmentId String


decode : Json.Decode.Decoder AmendmentId
decode =
    Json.Decode.map AmendmentId Json.Decode.string


encode : AmendmentId -> Json.Encode.Value
encode (AmendmentId s) =
    Json.Encode.string s


fromString : String -> AmendmentId
fromString =
    AmendmentId


toString : AmendmentId -> String
toString (AmendmentId s) =
    s
