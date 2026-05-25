module Data.MoneyTest exposing (suite)

{-| Pinned format assertions for `Data.Money.format`.

These are the canonical PINNED-KEEP tests for the #114 audit. The
PINNED-RELAX literals (exact decimal/separator style) will change when #38
(Intl.NumberFormat) lands; at that point the `format` helper will be used
only for non-HTML consumers (chart labels, map popups) and these tests will
be the single place to update.

See `src/Data/Money.elm` module doc for the full invariant listing.
-}

import Data.Money as Money
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Data.Money.format"
        [ test "always starts with '$'" <|
            \_ ->
                Money.format (Money.fromCents 1230)
                    |> String.left 1
                    |> Expect.equal "$"
        , test "zero amount starts with '$'" <|
            \_ ->
                Money.format (Money.fromCents 0)
                    |> String.left 1
                    |> Expect.equal "$"
        , test "canonical example: 1230 cents → '$12.30'" <|
            \_ ->
                Money.format (Money.fromCents 1230)
                    |> Expect.equal "$12.30"
        , test "no thousands separator for amounts over $1000 (current stable output)" <|
            \_ ->
                Money.format (Money.fromCents 123456)
                    |> Expect.equal "$1234.56"
        , test "round-trip: toCents after fromCents is identity" <|
            \_ ->
                Money.toCents (Money.fromCents 1230)
                    |> Expect.equal 1230
        ]
