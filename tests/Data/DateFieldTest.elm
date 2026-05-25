module Data.DateFieldTest exposing (suite)

{-| Pinned format assertions for `Data.DateField.formatDisplay` and `formatMonthDay`.

These are the canonical PINNED-KEEP tests for the #114 audit. The
PINNED-RELAX literals (locale shape `"MMM d, yyyy"`) will change when #38
(Intl.DateTimeFormat) lands; at that point the `formatDisplay` helper will be
used only for non-HTML consumers and these tests will be the single place to
update.

See `src/Data/DateField.elm` module doc for the full invariant listing.
-}

import Data.DateField as DateField
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Data.DateField"
        [ describe "formatDisplay"
            [ test "canonical example: 2024-05-21 → 'May 21, 2024'" <|
                \_ ->
                    DateField.fromIso "2024-05-21"
                        |> Maybe.map DateField.formatDisplay
                        |> Expect.equal (Just "May 21, 2024")
            , test "produces a non-empty string for any valid date" <|
                \_ ->
                    DateField.fromIso "2024-01-01"
                        |> Maybe.map (String.isEmpty << DateField.formatDisplay)
                        |> Expect.equal (Just False)
            , test "invalid ISO produces Nothing" <|
                \_ ->
                    DateField.fromIso "not-a-date"
                        |> Maybe.map DateField.formatDisplay
                        |> Expect.equal Nothing
            ]
        , describe "toIso / fromIso round-trip"
            [ test "round-trip through ISO is identity" <|
                \_ ->
                    DateField.fromIso "2024-05-21"
                        |> Maybe.map DateField.toIso
                        |> Expect.equal (Just "2024-05-21")
            ]
        ]
