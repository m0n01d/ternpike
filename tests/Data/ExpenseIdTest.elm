module Data.ExpenseIdTest exposing (suite)

import Data.ExpenseId as ExpenseId
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "ExpenseId"
        [ test "roundtrip preserves value including :: delimiters and timestamp colons" <|
            \_ ->
                "expense::2024-01-15T10:30:00.000Z::17000001"
                    |> ExpenseId.fromString
                    |> ExpenseId.toString
                    |> Expect.equal "expense::2024-01-15T10:30:00.000Z::17000001"
        , test "equality by value" <|
            \_ ->
                Expect.equal (ExpenseId.fromString "expense::X") (ExpenseId.fromString "expense::X")
        , test "inequality" <|
            \_ ->
                Expect.notEqual (ExpenseId.fromString "expense::A") (ExpenseId.fromString "expense::B")
        ]
