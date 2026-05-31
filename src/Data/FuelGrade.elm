module Data.FuelGrade exposing
    ( FuelGrade(..)
    , decoder
    , display
    , encoder
    , fromString
    )

{-| The grade (octane tier) of a fuel purchase.

The four common pump grades are modelled as constructors so the Add-form
picker can offer them as buttons and the compiler keeps display
exhaustive. Anything a receipt prints that doesn't map to one of those —
`E85`, `Off-road`, an octane number — is preserved verbatim in
`Other String` rather than discarded, so an unusual grade still
round-trips through the wire.

`label` is the lowercase wire serialization; `display` is the
title-cased UI form; `fromString` is lenient and always succeeds.

-}

import Json.Decode
import Json.Encode


{-| A fuel grade. `Other` carries the receipt's own text for anything
outside the four common pump grades.
-}
type FuelGrade
    = Diesel
    | Midgrade
    | Other String
    | Premium
    | Regular


{-| Parse a grade string, lenient and always succeeding. Common aliases
(`reg`, `plus`, `super`, …) map to the canonical grade; anything else is
kept verbatim as `Other` (preserving the receipt's original casing).
-}
fromString : String -> FuelGrade
fromString raw =
    let
        trimmed : String
        trimmed =
            String.trim raw
    in
    case String.toLower trimmed of
        "regular" ->
            Regular

        "reg" ->
            Regular

        "unleaded" ->
            Regular

        "midgrade" ->
            Midgrade

        "mid" ->
            Midgrade

        "plus" ->
            Midgrade

        "premium" ->
            Premium

        "prem" ->
            Premium

        "super" ->
            Premium

        "diesel" ->
            Diesel

        _ ->
            Other trimmed


{-| The lowercase wire label. `Other` keeps its original text so it
round-trips through `fromString`.
-}
label : FuelGrade -> String
label grade =
    case grade of
        Diesel ->
            "diesel"

        Midgrade ->
            "midgrade"

        Other s ->
            s

        Premium ->
            "premium"

        Regular ->
            "regular"


{-| The title-cased display form for the UI.
-}
display : FuelGrade -> String
display grade =
    case grade of
        Diesel ->
            "Diesel"

        Midgrade ->
            "Midgrade"

        Other s ->
            s

        Premium ->
            "Premium"

        Regular ->
            "Regular"


{-| Decode a JSON string into a `FuelGrade` (lenient — every string is a
valid grade).
-}
decoder : Json.Decode.Decoder FuelGrade
decoder =
    Json.Decode.map fromString Json.Decode.string


{-| Encode as the wire `label` string.
-}
encoder : FuelGrade -> Json.Encode.Value
encoder grade =
    Json.Encode.string (label grade)
