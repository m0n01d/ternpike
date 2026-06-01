module Data.Currency exposing
    ( Currency(..)
    , all
    , code
    , decoder
    , encoder
    , fromLabel
    , toLabel
    )

{-| The currency an expense was paid in.

Ternpike records amounts in their **native** currency and never converts
between them — a fuel-up in Canada is stored and shown in Canadian dollars, a
US purchase in US dollars. `Data.Money` stays currency-agnostic (raw `Int`
cents, and CAD also has 100-cent subunits), so the currency lives here as a
separate per-expense field rather than inside `Money`.

Only the two currencies a road trip to Alaska actually crosses are modelled.
Adding more later is a matter of extending the constructor list and the
`toLabel` / `fromLabel` / `code` mappings.

Wire format is the lowercase label (`"usd"` / `"cad"`). `fromLabel` and the
`decoder` default any unknown or missing value to `USD`, so the millions of
pre-existing expense docs that carry no `"currency"` field decode as US
dollars.

-}

import Json.Decode
import Json.Encode


{-| A currency. Constructors are alphabetized per the repo style guide.
-}
type Currency
    = CAD
    | USD


{-| Every currency, for the Add-form picker.
-}
all : List Currency
all =
    [ USD, CAD ]


{-| The lowercase wire label.

    toLabel CAD
    --> "cad"

    toLabel USD
    --> "usd"

-}
toLabel : Currency -> String
toLabel currency =
    case currency of
        CAD ->
            "cad"

        USD ->
            "usd"


{-| Parse a wire label back into a `Currency`, defaulting unknown or legacy
values to `USD`.

    fromLabel "cad"
    --> CAD

    fromLabel "CAD"
    --> CAD

    fromLabel ""
    --> USD

    fromLabel "eur"
    --> USD

-}
fromLabel : String -> Currency
fromLabel raw =
    case String.toLower (String.trim raw) of
        "cad" ->
            CAD

        _ ->
            USD


{-| The ISO 4217 code, for the `<tp-amount currency="...">` attribute that
`Intl.NumberFormat` reads (renders `CA$` for CAD, `$` for USD).

    code CAD
    --> "CAD"

    code USD
    --> "USD"

-}
code : Currency -> String
code currency =
    case currency of
        CAD ->
            "CAD"

        USD ->
            "USD"


{-| Decode the wire label into a `Currency`, tolerating missing/unknown values
by falling back to `USD` (see the module doc).
-}
decoder : Json.Decode.Decoder Currency
decoder =
    Json.Decode.oneOf
        [ Json.Decode.map fromLabel Json.Decode.string
        , Json.Decode.succeed USD
        ]


{-| Encode as the lowercase wire label.
-}
encoder : Currency -> Json.Encode.Value
encoder currency =
    Json.Encode.string (toLabel currency)
