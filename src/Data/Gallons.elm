module Data.Gallons exposing
    ( Gallons
    , decoder
    , encoder
    , format
    , fromString
    , toInputString
    )

{-| A fuel volume, in **thousandths of a gallon**.

Fuel pumps meter to three decimals (e.g. `12.345 gal`), so volume is
stored as an opaque `Int` of milligallons: `12.345 gal == 12345`. The
opaque constructor keeps a volume from being confused with a price or a
dollar amount.

Build one with `fromString` or `decoder`; consume it with `format`,
`toInputString`, or `encoder`. Wire format is a JSON `Float` gallons
(`12.345`); trailing zeros are trimmed on display (`12.3`, not `12.300`).

-}

import Json.Decode
import Json.Encode


{-| Opaque fuel volume in thousandths of a gallon. Always non-negative.
-}
type Gallons
    = Gallons Int


{-| Parse a user-typed gallons string (e.g. `"12.345"` or `"  12.3 "`)
into `Gallons`. Returns `Nothing` for empty or non-numeric input.
Rounds to the nearest thousandth.
-}
fromString : String -> Maybe Gallons
fromString raw =
    let
        trimmed : String
        trimmed =
            String.trim raw
    in
    if trimmed == "" then
        Nothing

    else
        Maybe.map (\g -> Gallons (round (g * 1000))) (String.toFloat trimmed)


{-| Render for display, trailing zeros trimmed: `"12.3"`, `"12.345"`,
`"12"`. The " gal" unit suffix is the caller's to add.
-}
format : Gallons -> String
format =
    toInputString


{-| Render as a bare number string for an `<input value=...>`, trailing
zeros trimmed: `"12.3"`, `"12.345"`, `"12"`.
-}
toInputString : Gallons -> String
toInputString (Gallons thousandths) =
    let
        whole : Int
        whole =
            thousandths // 1000

        fracStr : String
        fracStr =
            trimTrailingZeros (String.padLeft 3 '0' (String.fromInt (remainderBy 1000 thousandths)))
    in
    if fracStr == "" then
        String.fromInt whole

    else
        String.fromInt whole ++ "." ++ fracStr


trimTrailingZeros : String -> String
trimTrailingZeros s =
    if String.endsWith "0" s then
        trimTrailingZeros (String.dropRight 1 s)

    else
        s


{-| Decode the wire `Float` gallons shape into thousandths.
-}
decoder : Json.Decode.Decoder Gallons
decoder =
    Json.Decode.map (\g -> Gallons (round (g * 1000))) Json.Decode.float


{-| Encode as a JSON `Float` gallons for PouchDB / CouchDB.
-}
encoder : Gallons -> Json.Encode.Value
encoder (Gallons thousandths) =
    Json.Encode.float (toFloat thousandths / 1000)
