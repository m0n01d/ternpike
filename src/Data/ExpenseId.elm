module Data.ExpenseId exposing (ExpenseId, decode, encode, fromString, toString)

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
