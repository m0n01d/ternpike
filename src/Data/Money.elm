module Data.Money exposing
    ( Money
    , absDiff
    , add
    , decoder
    , encoder
    , format
    , fromCents
    , fromDollarString
    , isZero
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

`format` replaces the old `Helpers.formatAmount` (deleted in #92) and matches
its byte-for-byte output.


## Stable invariants (PINNED-KEEP)

  - `format` always returns a `String` whose first character is `'$'`.
  - `format` never returns a value with a thousands separator (e.g. `$1234.56`
    not `$1,234.56`) — **until #38 lands**, at which point DOM-facing display
    moves to `<tp-amount>` / `Intl.NumberFormat` and `format` is used only for
    non-HTML contexts (chart labels, map popups). The no-separator behavior is
    the current STABLE output shape; it is tested in `tests/Data/MoneyTest.elm`.


## Open for evolution under #38

  - The exact decimal / separator style of `format` — `"$12.30"`, `"$1,234.56"`,
    etc. — is not pinned long-term. When #38 ships, DOM-facing output will be
    produced by `<tp-amount value="...">` using `Intl.NumberFormat`. The
    `format` function will remain alive for non-HTML consumers.
  - See `tests/Data/MoneyTest.elm` for the canonical pinned assertions.

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

PINNED-KEEP: the leading `'$'` is a stable invariant.
PINNED-RELAX: the exact decimal/separator style will follow #38 (Intl.NumberFormat).

Canonical example (see also `tests/Data/MoneyTest.elm`):

    format (fromCents 1230)
    --> "$12.30"

Round-trip: the formatted string always starts with `'$'`:

    String.startsWith "$" (format (fromCents 1230))
    --> True

    String.startsWith "$" (format (fromCents 0))
    --> True

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


{-| Absolute difference between two `Money` values, in cents.

Useful for duplicate-detection tolerances where you want to know "are
these within $1 of each other?" without caring which is larger.

    absDiff (fromCents 4520) (fromCents 4600)
    --> 80

    absDiff (fromCents 4600) (fromCents 4520)
    --> 80

    absDiff (fromCents 1000) (fromCents 1000)
    --> 0

-}
absDiff : Money -> Money -> Int
absDiff (Money a) (Money b) =
    abs (a - b)


{-| Add two `Money` values.

    toCents (add (fromCents 1230) (fromCents 70))
    --> 1300

-}
add : Money -> Money -> Money
add (Money a) (Money b) =
    Money (a + b)


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
