module Data.Liters exposing
    ( Liters
    , decoder
    , encoder
    , format
    , fromString
    , toInputString
    )

{-| A fuel volume, in **thousandths of a liter**.

The metric sibling of `Data.Gallons` — Canadian pumps meter in liters to
three decimals (e.g. `45.200 L`), so volume is stored as an opaque `Int` of
milliliters: `45.2 L == 45200`. The opaque constructor keeps a volume from
being confused with a price or a dollar amount.

Build one with `fromString` or `decoder`; consume it with `format`,
`toInputString`, or `encoder`. Wire format is a JSON `Float` liters
(`45.2`); trailing zeros are trimmed on display (`45.2`, not `45.200`).

-}

import Json.Decode
import Json.Encode


{-| Opaque fuel volume in thousandths of a liter. Always non-negative.
-}
type Liters
    = Liters Int


{-| Parse a user-typed liters string (e.g. `"45.2"` or `"  45.20 "`)
into `Liters`. Returns `Nothing` for empty or non-numeric input.
Rounds to the nearest thousandth.
-}
fromString : String -> Maybe Liters
fromString raw =
    let
        trimmed : String
        trimmed =
            String.trim raw
    in
    if trimmed == "" then
        Nothing

    else
        Maybe.map (\l -> Liters (round (l * 1000))) (String.toFloat trimmed)


{-| Render for display, trailing zeros trimmed: `"45.2"`, `"45.205"`,
`"45"`. The " L" unit suffix is the caller's to add.
-}
format : Liters -> String
format =
    toInputString


{-| Render as a bare number string for an `<input value=...>`, trailing
zeros trimmed: `"45.2"`, `"45.205"`, `"45"`.
-}
toInputString : Liters -> String
toInputString (Liters thousandths) =
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


{-| Decode the wire `Float` liters shape into thousandths.
-}
decoder : Json.Decode.Decoder Liters
decoder =
    Json.Decode.map (\l -> Liters (round (l * 1000))) Json.Decode.float


{-| Encode as a JSON `Float` liters for PouchDB / CouchDB.
-}
encoder : Liters -> Json.Encode.Value
encoder (Liters thousandths) =
    Json.Encode.float (Basics.toFloat thousandths / 1000)
