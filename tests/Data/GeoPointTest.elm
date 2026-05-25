module Data.GeoPointTest exposing (suite)

{-| Pinned format assertions for `Data.GeoPoint.format`.

These are the canonical PINNED-KEEP tests for the #114 audit. The `"lat, lon"`
shape and 9-char truncation are stable structural invariants — they control
Ledger row alignment and are unrelated to locale. No #38 Intl changes apply
to this helper.

See `src/Data/GeoPoint.elm` module doc for the full invariant listing.
-}

import Data.GeoPoint as GeoPoint
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Data.GeoPoint.format"
        [ test "canonical example: (45, -90) → '45, -90'" <|
            \_ ->
                GeoPoint.format (GeoPoint.fromDegrees 45 -90)
                    |> Expect.equal "45, -90"
        , test "always contains ', ' separator" <|
            \_ ->
                GeoPoint.format (GeoPoint.fromDegrees 64.2008 -149.4937)
                    |> String.contains ", "
                    |> Expect.equal True
        , test "truncates each component to at most 9 characters" <|
            \_ ->
                let
                    result =
                        GeoPoint.format (GeoPoint.fromDegrees 64.200800001 -149.493700001)

                    parts =
                        String.split ", " result
                in
                case parts of
                    [ lat, lon ] ->
                        Expect.all
                            [ \_ -> String.length lat |> Expect.atMost 9
                            , \_ -> String.length lon |> Expect.atMost 9
                            ]
                            ()

                    _ ->
                        Expect.fail ("expected exactly one ', ' separator, got: " ++ result)
        ]
