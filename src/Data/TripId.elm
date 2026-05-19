module Data.TripId exposing (TripId, decode, encode, fromString, toString)

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
