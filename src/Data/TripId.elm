module Data.TripId exposing (TripId, decode, encode, fromString, toString)

{-| Opaque wrapper around a PouchDB trip `_id`.

Format mirrors `ExpenseId`:

    trip::<ISO-8601 timestamp>::<8-char nonce>

In `AuthState`, the outer key of `expenses : Dict String (Dict String Expense)`
is `TripId.toString` — looking up a trip's expenses is a single `Dict.get`.
-}

import Json.Decode
import Json.Encode


type TripId
    = TripId String


decode : Json.Decode.Decoder TripId
decode =
    Json.Decode.map TripId Json.Decode.string


encode : TripId -> Json.Encode.Value
encode (TripId s) =
    Json.Encode.string s


fromString : String -> TripId
fromString =
    TripId


toString : TripId -> String
toString (TripId s) =
    s
