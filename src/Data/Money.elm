module Data.Money exposing
    ( Money
    , add
    , decoder
    , difference
    , encoder
    , format
    , fromCents
    , fromDollarString
    , isZero
    , scale
    , sum
    , toCents
    , toDollarString
    , zero
    )

{-| A currency amount, USD only, stored as `Int` cents.

This is the foundation of the Money-type refactor (#89). `Float` for money
is a latent IEEE-754 drift bug — `Pages/Stats.elm` and `Pages/Trips.elm`
both sum hundreds of expense amounts and display the difference between
two such sums on hero totals. Int cents eliminates the drift and matches
Stripe's pricing model (relevant when #14 lands).

The constructor is opaque so callers can't accidentally add an amount to a
budget threshold or treat cents as dollars. Always use `fromCents`,
`fromDollarString`, `decoder`, or `zero` to build a `Money`; use `toCents`,
`toDollarString`, `encoder`, `format`, or `sum` to consume one.

Wire format on PouchDB / CouchDB is still `Float` dollars (`12.30`, not
`1230`) so older app versions can decode synced docs during rollout —
`decoder` accepts the legacy `Float` shape and rounds to nearest cent;
`encoder` emits `Float` dollars. The migration is purely in the type
layer; the on-disk shape is unchanged.

`format` replaces `Helpers.formatAmount` and matches its byte-for-byte
output. `Helpers.formatAmount` stays in place for this issue — R1 deletes
it once the record refactors land.

-}

import Json.Decode
import Json.Encode


{-| Opaque currency amount in cents. Always non-negative for expenses;
amendments and differences can be negative.
-}
type Money
    = Money Int



-- BUILD


{-| Build a `Money` from cents. The unchecked construction path; callers
that know they have cents (e.g. arithmetic results) can use this directly.

    toCents (fromCents 1230)
    --> 1230

    toCents (fromCents 0)
    --> 0

    toCents (fromCents -500)
    --> -500

-}
fromCents : Int -> Money
fromCents cents =
    Money cents


{-| Parse a user-typed dollar string into `Money`. Returns `Nothing` for
non-numeric or empty input. Whitespace is trimmed; a leading `$` is
tolerated. Rounds to the nearest cent.

    fromDollarString "12.30"
    --> Just (fromCents 1230)

    fromDollarString "  $5  "
    --> Just (fromCents 500)

    fromDollarString ""
    --> Nothing

    fromDollarString "abc"
    --> Nothing

-}
fromDollarString : String -> Maybe Money
fromDollarString raw =
    let
        trimmed =
            String.trim raw

        stripped =
            if String.startsWith "$" trimmed then
                String.dropLeft 1 trimmed

            else
                trimmed
    in
    if stripped == "" then
        Nothing

    else
        case String.toFloat stripped of
            Just dollars ->
                Just (Money (round (dollars * 100)))

            Nothing ->
                Nothing


{-| The additive identity. Useful as the seed for `List.foldl` and as the
default value for an unparsed form field.

    toCents zero
    --> 0

-}
zero : Money
zero =
    Money 0



-- INSPECT


{-| Extract the underlying cent count. The unchecked consumption path;
prefer `format`, `toDollarString`, or `encoder` when emitting to a user
or to the wire.

    toCents (fromCents 1230)
    --> 1230

-}
toCents : Money -> Int
toCents (Money cents) =
    cents


{-| True when the amount is exactly zero cents.

    isZero zero
    --> True

    isZero (fromCents 1)
    --> False

    isZero (fromCents -1)
    --> False

-}
isZero : Money -> Bool
isZero (Money cents) =
    cents == 0


{-| Render `Money` as a dollar string suitable for an `<input value=...>`
attribute. Always two decimals, no `$` prefix, negative sign in front.

    toDollarString (fromCents 1230)
    --> "12.30"

    toDollarString (fromCents 0)
    --> "0.00"

    toDollarString (fromCents 5)
    --> "0.05"

    toDollarString (fromCents -500)
    --> "-5.00"

-}
toDollarString : Money -> String
toDollarString (Money cents) =
    let
        sign =
            if cents < 0 then
                "-"

            else
                ""

        abs_ =
            abs cents

        dollarsPart =
            abs_ // 100

        centsPart =
            remainderBy 100 abs_
    in
    sign ++ String.fromInt dollarsPart ++ "." ++ String.padLeft 2 '0' (String.fromInt centsPart)


{-| Render `Money` for display. Matches `Helpers.formatAmount` byte-for-byte
so the migration is invisible to users and snapshot tests.

    format (fromCents 1230)
    --> "$12.30"

    format (fromCents 5)
    --> "$0.05"

    format (fromCents 0)
    --> "$0.00"

    format (fromCents 100)
    --> "$1.00"

-}
format : Money -> String
format (Money cents) =
    let
        dollars =
            cents // 100

        centsRem =
            remainderBy 100 (abs cents)
    in
    "$" ++ String.fromInt dollars ++ "." ++ String.padLeft 2 '0' (String.fromInt centsRem)



-- COMBINE


{-| Add two `Money` values.

    toCents (add (fromCents 1230) (fromCents 70))
    --> 1300

-}
add : Money -> Money -> Money
add (Money a) (Money b) =
    Money (a + b)


{-| Subtract the second `Money` from the first. Result can be negative
(e.g. when computing "budget remaining" for an over-budget trip).

    toCents (difference (fromCents 1000) (fromCents 300))
    --> 700

    toCents (difference (fromCents 300) (fromCents 1000))
    --> -700

-}
difference : Money -> Money -> Money
difference (Money a) (Money b) =
    Money (a - b)


{-| Multiply by a scalar. Used by the one Stats site that projects
"monthly spend ≈ avgPerDay \* 30". Rounds to nearest cent.

    toCents (scale (fromCents 100) 2.5)
    --> 250

    toCents (scale (fromCents 333) 3.0)
    --> 999

    toCents (scale zero 100.0)
    --> 0

-}
scale : Money -> Float -> Money
scale (Money cents) factor =
    Money (round (toFloat cents * factor))


{-| Sum a list of `Money`. The drop-in replacement for
`List.sum (List.map .amount entries)` on hero totals.

    toCents (sum [ fromCents 100, fromCents 200, fromCents 350 ])
    --> 650

    toCents (sum [])
    --> 0

-}
sum : List Money -> Money
sum amounts =
    Money (List.foldl (\(Money c) acc -> acc + c) 0 amounts)



-- JSON


{-| Decode the legacy `Float` dollars wire shape into `Money` cents. Used
by every record decoder (`Data.Expense`, `Data.Trip`, `Data.Amendment`,
`Data.Scan`) as the field decoder for `amount` / `budget`. Rounds to the
nearest cent so floats like `12.300000000000002` come out as exactly 1230.
-}
decoder : Json.Decode.Decoder Money
decoder =
    Json.Decode.map (\dollars -> Money (round (dollars * 100))) Json.Decode.float


{-| Encode `Money` as `Float` dollars for PouchDB / CouchDB. Preserves the
existing wire format so older app versions can still decode synced docs
during the rollout of the Money refactor.
-}
encoder : Money -> Json.Encode.Value
encoder (Money cents) =
    Json.Encode.float (toFloat cents / 100)
