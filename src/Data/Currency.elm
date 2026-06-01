module Data.Currency exposing
    ( Currency
    , code
    , common
    , decoder
    , encoder
    , fromCode
    , fromCodeOr
    , fromLabel
    , symbol
    , usd
    , usesGallons
    )

{-| The currency an expense was paid in, as an **ISO 4217 code**.

Ternpike records amounts in their **native** currency and never converts
between them. `Data.Money` stays currency-agnostic (raw `Int` cents — every
currency Ternpike supports has 100-cent minor units), so the currency lives
here as a separate per-expense field rather than inside `Money`.

The type is **open**: it wraps a validated three-letter ISO 4217 code rather
than a closed enum, so a North American overlander crossing into Mexico
(`MXN`) or down the Pan-American (`GTQ`, `CRC`, …) just works — `Intl`
renders any code, and there is no per-currency business logic that would need
exhaustive matching. `common` is the curated set offered in the picker; the
decoder accepts **any** plausible code so a doc synced from a newer client
that knows a currency we don't list still round-trips.

Wire format is the lowercase code (`"usd"`, `"cad"`, `"mxn"`). `fromCode` /
the `decoder` default any missing or unparseable value to `usd`, so the
pre-existing expense docs that carry no `"currency"` field — and any legacy
`"usd"` / `"cad"` strings from #447 — decode unchanged.

Minor-unit note: the `Int`-cents model assumes a 2-decimal currency, which
holds for every USD/CAD/MXN/Central-American currency. Zero- or three-decimal
currencies (e.g. JPY) are intentionally out of scope.

-}

import Json.Decode
import Json.Encode


{-| A currency, identified by its uppercase ISO 4217 code. Opaque so a code
string can't be confused with arbitrary text and is always validated.
-}
type Currency
    = Currency String


{-| The home/default currency, US dollars. Used as the fallback for legacy
docs and unparseable codes.
-}
usd : Currency
usd =
    Currency "USD"


{-| The curated set of currencies offered in the Add-form picker — the ones a
North American overlander actually crosses. The decoder still accepts codes
outside this list; `common` only bounds the UI.
-}
common : List Currency
common =
    List.map Currency
        [ "USD", "CAD", "MXN", "GTQ", "BZD", "HNL", "NIO", "CRC", "PAB" ]


{-| The uppercase ISO 4217 code, for the `<tp-amount currency="...">`
attribute that `Intl.NumberFormat` reads.

    Maybe.map code (fromCode "mxn")
    --> Just "MXN"

-}
code : Currency -> String
code (Currency c) =
    c


{-| Parse a string into a `Currency`, accepting any plausible three-letter
ISO 4217 code (case-insensitive, trimmed). Returns `Nothing` for anything
that isn't three letters.

    Maybe.map code (fromCode "cad")
    --> Just "CAD"

    Maybe.map code (fromCode "  MxN ")
    --> Just "MXN"

    fromCode "dollars"
    --> Nothing

    fromCode ""
    --> Nothing

-}
fromCode : String -> Maybe Currency
fromCode raw =
    let
        c : String
        c =
            String.toUpper (String.trim raw)
    in
    if String.length c == 3 && String.all Char.isAlpha c then
        Just (Currency c)

    else
        Nothing


{-| Parse a code, falling back to the given default when it isn't a valid
three-letter code.

    code (fromCodeOr usd "cad")
    --> "CAD"

    code (fromCodeOr usd "nonsense")
    --> "USD"

-}
fromCodeOr : Currency -> String -> Currency
fromCodeOr fallback raw =
    Maybe.withDefault fallback (fromCode raw)


{-| Parse a wire label (or any code) into a `Currency`, defaulting to `usd`.
The convenience form of `fromCodeOr usd` used by the decoder, the picker's
`onInput`, and tests.

    code (fromLabel "cad")
    --> "CAD"

    code (fromLabel "")
    --> "USD"

-}
fromLabel : String -> Currency
fromLabel =
    fromCodeOr usd


{-| A short display symbol for the amount-input adornment on the Add form
(the editable hero isn't a `<tp-amount>`, so it can't lean on `Intl`).
Known `common` currencies get their conventional glyph; anything else falls
back to its code.

    symbol usd
    --> "$"

    symbol (fromLabel "cad")
    --> "CA$"

    symbol (fromLabel "mxn")
    --> "MX$"

-}
symbol : Currency -> String
symbol currency =
    case code currency of
        "USD" ->
            "$"

        "CAD" ->
            "CA$"

        "MXN" ->
            "MX$"

        "GTQ" ->
            "Q"

        "BZD" ->
            "BZ$"

        "HNL" ->
            "L"

        "NIO" ->
            "C$"

        "CRC" ->
            "₡"

        "PAB" ->
            "B/."

        other ->
            other


{-| Whether fuel for this currency is metered in **gallons** rather than
liters. The United States is the only country that sells fuel by the gallon;
everyone else (Canada, Mexico, all of Central America) is metric. The fuel
unit is a property of where you are, not of the currency per se — but the
currency is a faithful proxy for it across the Americas.

    usesGallons usd
    --> True

    usesGallons (fromLabel "cad")
    --> False

    usesGallons (fromLabel "mxn")
    --> False

-}
usesGallons : Currency -> Bool
usesGallons currency =
    code currency == "USD"


{-| Decode a code into a `Currency`, tolerating missing/unparseable values by
falling back to `usd` (see the module doc).
-}
decoder : Json.Decode.Decoder Currency
decoder =
    Json.Decode.oneOf
        [ Json.Decode.map fromLabel Json.Decode.string
        , Json.Decode.succeed usd
        ]


{-| Encode as the lowercase wire code (`"usd"`, `"cad"`, `"mxn"`).
-}
encoder : Currency -> Json.Encode.Value
encoder currency =
    Json.Encode.string (String.toLower (code currency))
