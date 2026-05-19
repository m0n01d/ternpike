module Data.TripIdTest exposing (suite)

import Data.TripId as TripId
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "TripId"
        [ test "roundtrip preserves value including :: delimiters and timestamp colons" <|
            \_ ->
                "trip::2024-01-15T10:30:00.000Z::17000000"
                    |> TripId.fromString
                    |> TripId.toString
                    |> Expect.equal "trip::2024-01-15T10:30:00.000Z::17000000"
        , test "equality by value" <|
            \_ ->
                Expect.equal (TripId.fromString "trip::X") (TripId.fromString "trip::X")
        , test "inequality" <|
            \_ ->
                Expect.notEqual (TripId.fromString "trip::A") (TripId.fromString "trip::B")
        ]
