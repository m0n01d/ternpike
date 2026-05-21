module Data.ExpenseId exposing (ExpenseId, decode, encode, fromString, toString)

{-| Opaque wrapper around a PouchDB expense `_id`.

The string follows a fixed format that doubles as the document key in PouchDB:

    expense::<ISO-8601 timestamp>::<8-char nonce>

Wrapping it in an opaque type stops the compiler from letting you mix
`ExpenseId` with `TripId` (or with any other `String`). Use `toString` only
when you need the raw key for a `Dict` lookup or for embedding into an
amendment/void ID.
-}

import Json.Decode
import Json.Encode


type ExpenseId
    = ExpenseId String


decode : Json.Decode.Decoder ExpenseId
decode =
    Json.Decode.map ExpenseId Json.Decode.string


encode : ExpenseId -> Json.Encode.Value
encode (ExpenseId s) =
    Json.Encode.string s


fromString : String -> ExpenseId
fromString =
    ExpenseId


toString : ExpenseId -> String
toString (ExpenseId s) =
    s
