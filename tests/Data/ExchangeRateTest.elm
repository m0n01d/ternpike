module Data.ExchangeRateTest exposing (suite)

import Data.Currency
import Data.ExchangeRate as ExchangeRate
import Data.Money as Money
import Dict
import Expect
import Json.Decode
import Test exposing (Test, describe, test)


table : ExchangeRate.RateTable
table =
    { asOf = Nothing
    , rates = Dict.fromList [ ( "cad", 0.73 ), ( "mxn", 0.058 ) ]
    }


suite : Test
suite =
    describe "Data.ExchangeRate"
        [ describe "rateFor"
            [ test "home currency (USD) is always 1.0" <|
                \_ ->
                    ExchangeRate.rateFor table Data.Currency.usd
                        |> Expect.equal (Just 1.0)
            , test "a currency in the table returns its rate" <|
                \_ ->
                    ExchangeRate.rateFor table (Data.Currency.fromLabel "cad")
                        |> Expect.equal (Just 0.73)
            , test "an unknown currency returns Nothing" <|
                \_ ->
                    ExchangeRate.rateFor table (Data.Currency.fromLabel "gtq")
                        |> Expect.equal Nothing
            , test "USD with an empty table is still 1.0" <|
                \_ ->
                    ExchangeRate.rateFor ExchangeRate.empty Data.Currency.usd
                        |> Expect.equal (Just 1.0)
            ]
        , describe "estimate"
            [ test "USD passes through 1:1" <|
                \_ ->
                    ExchangeRate.estimate table Data.Currency.usd (Money.fromCents 10000)
                        |> Maybe.map Money.toCents
                        |> Expect.equal (Just 10000)
            , test "CAD 100.00 @ 0.73 ≈ USD 73.00" <|
                \_ ->
                    ExchangeRate.estimate table (Data.Currency.fromLabel "cad") (Money.fromCents 10000)
                        |> Maybe.map Money.toCents
                        |> Expect.equal (Just 7300)
            , test "MXN 1000.00 @ 0.058 ≈ USD 58.00, rounded to cents" <|
                \_ ->
                    ExchangeRate.estimate table (Data.Currency.fromLabel "mxn") (Money.fromCents 100000)
                        |> Maybe.map Money.toCents
                        |> Expect.equal (Just 5800)
            , test "an unknown currency yields Nothing" <|
                \_ ->
                    ExchangeRate.estimate table (Data.Currency.fromLabel "gtq") (Money.fromCents 10000)
                        |> Expect.equal Nothing
            ]
        , describe "httpDecoder"
            [ test "decodes the /rates response into a lowercase-keyed table" <|
                \_ ->
                    """{"ok":true,"base":"usd","date":"2026-06-01","rates":{"cad":0.73,"mxn":0.058},"cached":false}"""
                        |> Json.Decode.decodeString ExchangeRate.httpDecoder
                        |> Result.map (\t -> ExchangeRate.rateFor t (Data.Currency.fromLabel "cad"))
                        |> Expect.equal (Ok (Just 0.73))
            , test "tolerates a missing date" <|
                \_ ->
                    """{"rates":{"cad":0.73}}"""
                        |> Json.Decode.decodeString ExchangeRate.httpDecoder
                        |> Result.map ExchangeRate.asOf
                        |> Expect.equal (Ok Nothing)
            ]
        ]
