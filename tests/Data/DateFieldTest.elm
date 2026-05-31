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
import Time


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
        , describe "today"
            [ test "derives the calendar date from a posix in UTC" <|
                \_ ->
                    DateField.today Time.utc (Time.millisToPosix 0)
                        |> DateField.toIso
                        |> Expect.equal "1970-01-01"
            , test "same instant buckets to an earlier local day in a western zone" <|
                -- The westward-traveler invariant: an instant that is the
                -- evening of May 21 at UTC-8 has already rolled over to May 22
                -- in UTC. `today` must follow the supplied zone, so a local
                -- (western) zone keeps it on May 21 — the day the user is
                -- actually living. 1716354000000 == 2024-05-22T05:00:00Z ==
                -- 9 PM May 21 at UTC-8.
                \_ ->
                    let
                        instant : Time.Posix
                        instant =
                            Time.millisToPosix 1716354000000

                        westernZone : Time.Zone
                        westernZone =
                            Time.customZone -480 []
                    in
                    ( DateField.today Time.utc instant |> DateField.toIso
                    , DateField.today westernZone instant |> DateField.toIso
                    )
                        |> Expect.equal ( "2024-05-22", "2024-05-21" )
            ]
        ]
