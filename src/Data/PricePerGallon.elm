module Data.PricePerGallon exposing
    ( PricePerGallon
    , decoder
    , encoder
    , format
    , fromString
    , toDollars
    , toInputString
    , toMills
    )

{-| The unit price of fuel, in **mills** (thousandths of a dollar).

Gas is conventionally priced to a third decimal — the famous "9/10 of a
cent" (e.g. `$4.299/gal`). `Data.Money` is `Int` cents and would round
that to `$4.30`, losing the very digit a fuel-up is priced at, so
price-per-gallon gets its own opaque type stored as mills:
`$4.299 == 4299` mills.

The constructor is opaque so a price-per-gallon can never be confused
with a `Money` (cents) or a bare `Float`. Build one with `fromString` or
`decoder`; consume it with `format`, `toInputString`, or `encoder`.

Wire format on PouchDB / CouchDB is a JSON `Float` dollars (`4.299`),
matching how `Data.Money` stores dollars — `decoder` reads the float and
rounds to the nearest mill; `encoder` emits the float back.

-}

import Json.Decode
import Json.Encode


{-| Opaque unit price in mills (thousandths of a dollar). Always
non-negative for a real fuel price.
-}
type PricePerGallon
    = PricePerGallon Int


{-| Convert a `PricePerGallon` to a `Float` in dollars. Useful for
charting where elm-charts expects `Float` y-values.

    toDollars (PricePerGallon 4299)
    --> 4.299

-}
toDollars : PricePerGallon -> Float
toDollars (PricePerGallon mills) =
    Basics.toFloat mills / 1000


{-| Parse a user-typed dollar string (e.g. `"4.299"` or `"$4.50"`) into a
`PricePerGallon`. Returns `Nothing` for empty or non-numeric input. A
leading `$` and surrounding whitespace are tolerated; the value is
rounded to the nearest mill.
-}
fromString : String -> Maybe PricePerGallon
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
        Maybe.map (\dollars -> PricePerGallon (round (dollars * 1000)))
            (String.toFloat stripped)


{-| Render for display with a leading `$`, two decimals minimum and a
third only when it's significant: `$4.299`, `$4.50`, `$4.09`. The
"/gal" suffix is the caller's to add.
-}
format : PricePerGallon -> String
format price =
    "$" ++ toInputString price


{-| Render as a bare number string for an `<input value=...>`: `"4.299"`,
`"4.50"`. Two decimals minimum, a third only when significant. No `$`.
-}
toInputString : PricePerGallon -> String
toInputString (PricePerGallon mills) =
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


{-| The raw unit price in mills (thousandths of a dollar): `$4.299 == 4299`.
Used by the Milepost engine to compare a fuel price against a mill threshold.
-}
toMills : PricePerGallon -> Int
toMills (PricePerGallon mills) =
    mills


{-| Decode the legacy/wire `Float` dollars shape into mills, rounding to
the nearest mill so floats like `4.2990000001` come out as exactly 4299.
-}
decoder : Json.Decode.Decoder PricePerGallon
decoder =
    Json.Decode.map (\dollars -> PricePerGallon (round (dollars * 1000))) Json.Decode.float


{-| Encode as a JSON `Float` dollars for PouchDB / CouchDB.
-}
encoder : PricePerGallon -> Json.Encode.Value
encoder (PricePerGallon mills) =
    Json.Encode.float (toFloat mills / 1000)
