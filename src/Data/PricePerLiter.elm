module Data.PricePerLiter exposing
    ( PricePerLiter
    , decoder
    , encoder
    , format
    , fromString
    , toInputString
    )

{-| The unit price of fuel per liter, in **mills** (thousandths of a dollar).

The metric sibling of `Data.PricePerGallon`. Canadian pump prices carry a
third decimal just like US ones (e.g. `$1.659/L`), and `Data.Money` (`Int`
cents) would round that away, so the per-liter price gets its own opaque type
stored as mills: `$1.659 == 1659` mills.

The constructor is opaque so a price-per-liter can never be confused with a
`Money` (cents) or a bare `Float`. Build one with `fromString` or `decoder`;
consume it with `format`, `toInputString`, or `encoder`.

Wire format on PouchDB / CouchDB is a JSON `Float` dollars (`1.659`). Unlike
`Data.PricePerGallon.format`, `format` here emits a bare number with no `$`,
since the amount can be Canadian dollars — the caller pairs it with the
expense's currency (see `Data.Currency`) and the `/L` unit.

-}

import Json.Decode
import Json.Encode


{-| Opaque unit price in mills (thousandths of a dollar). Always
non-negative for a real fuel price.
-}
type PricePerLiter
    = PricePerLiter Int


{-| Parse a user-typed price string (e.g. `"1.659"` or `"$1.65"`) into a
`PricePerLiter`. Returns `Nothing` for empty or non-numeric input. A
leading `$` and surrounding whitespace are tolerated; the value is
rounded to the nearest mill.
-}
fromString : String -> Maybe PricePerLiter
fromString raw =
    let
        trimmed : String
        trimmed =
            String.trim raw

        stripped : String
        stripped =
            if String.startsWith "$" trimmed then
                String.dropLeft 1 trimmed

            else
                trimmed
    in
    if stripped == "" then
        Nothing

    else
        Maybe.map (\dollars -> PricePerLiter (round (dollars * 1000)))
            (String.toFloat stripped)


{-| Render as a bare number string for display, two decimals minimum and a
third only when significant: `"1.659"`, `"1.65"`. No currency symbol — the
caller adds the currency and the `/L` suffix.
-}
format : PricePerLiter -> String
format =
    toInputString


{-| Render as a bare number string for an `<input value=...>`: `"1.659"`,
`"1.65"`. Two decimals minimum, a third only when significant. No `$`.
-}
toInputString : PricePerLiter -> String
toInputString (PricePerLiter mills) =
    let
        dollars : Int
        dollars =
            mills // 1000

        frac : Int
        frac =
            remainderBy 1000 mills

        thirdDigit : Int
        thirdDigit =
            remainderBy 10 frac
    in
    if thirdDigit == 0 then
        String.fromInt dollars ++ "." ++ String.padLeft 2 '0' (String.fromInt (frac // 10))

    else
        String.fromInt dollars ++ "." ++ String.padLeft 3 '0' (String.fromInt frac)


{-| Decode the wire `Float` dollars shape into mills, rounding to the
nearest mill so floats like `1.6590000001` come out as exactly 1659.
-}
decoder : Json.Decode.Decoder PricePerLiter
decoder =
    Json.Decode.map (\dollars -> PricePerLiter (round (dollars * 1000))) Json.Decode.float


{-| Encode as a JSON `Float` dollars for PouchDB / CouchDB.
-}
encoder : PricePerLiter -> Json.Encode.Value
encoder (PricePerLiter mills) =
    Json.Encode.float (toFloat mills / 1000)
