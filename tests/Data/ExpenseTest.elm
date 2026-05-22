module Data.ExpenseTest exposing (suite)

{-| Verify that `Data.Expense.decoder` still accepts the legacy wire shape
written by pre-#92 clients: `amount` as a JSON number, `date` as a
`"YYYY-MM-DD"` string, `createdAt` as `"YYYY-MM-DDTHH:MM:SSZ"`, and
`lat` / `lon` as sibling JSON numbers (rather than a single `geoPoint`).

Closes the "old PouchDB doc still decodes after this lands" verification
check from the #92 issue body.

-}

import Data.DateField as DateField
import Data.Expense as Expense
import Data.GeoPoint as GeoPoint
import Data.Money as Money
import Expect
import Json.Decode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Data.Expense.decoder"
        [ test "accepts a legacy doc with float amount and ISO date/createdAt" <|
            \_ ->
                let
                    wire =
                        """
                        { "_id": "expense::2024-05-21T14:30:45Z::abcd1234"
                        , "amount": 12.30
                        , "category": "food"
                        , "createdAt": "2024-05-21T14:30:45Z"
                        , "createdBy": "alice@example.com"
                        , "date": "2024-05-21"
                        , "lat": 64.2008
                        , "lon": -149.4937
                        , "merchant": "Cafe Halibut"
                        , "note": "lunch"
                        , "tripId": "trip::2024-05-21T14:30:45Z::zzzzzzzz"
                        , "type": "expense"
                        }
                        """
                in
                case Json.Decode.decodeString Expense.decoder wire of
                    Ok e ->
                        Expect.all
                            [ \expense -> Expect.equal 1230 (Money.toCents expense.amount)
                            , \expense -> Expect.equal "2024-05-21" (DateField.toIso expense.date)
                            , \expense ->
                                expense.geoPoint
                                    |> Maybe.map GeoPoint.latDegrees
                                    |> Expect.equal (Just 64.2008)
                            , \expense ->
                                expense.geoPoint
                                    |> Maybe.map GeoPoint.lonDegrees
                                    |> Expect.equal (Just -149.4937)
                            ]
                            e

                    Err err ->
                        Expect.fail (Json.Decode.errorToString err)
        , test "missing lat/lon decodes to Nothing geoPoint" <|
            \_ ->
                let
                    wire =
                        """
                        { "_id": "expense::2024-05-21T14:30:45Z::abcd1234"
                        , "amount": 9.99
                        , "category": "fuel"
                        , "createdAt": "2024-05-21T14:30:45Z"
                        , "date": "2024-05-21"
                        , "merchant": "Gas Station"
                        , "note": ""
                        , "tripId": "trip::2024-05-21T14:30:45Z::zzzzzzzz"
                        , "type": "expense"
                        }
                        """
                in
                Json.Decode.decodeString Expense.decoder wire
                    |> Result.map .geoPoint
                    |> Expect.equal (Ok Nothing)
        , test "roundtrips through encoder/decoder" <|
            \_ ->
                let
                    wire =
                        """
                        { "_id": "expense::2024-05-21T14:30:45Z::abcd1234"
                        , "amount": 42.50
                        , "category": "lodging"
                        , "createdAt": "2024-05-21T14:30:45Z"
                        , "createdBy": "bob@example.com"
                        , "date": "2024-05-21"
                        , "lat": 60.0
                        , "lon": -150.0
                        , "merchant": "Cabin"
                        , "note": "one night"
                        , "tripId": "trip::2024-05-21T14:30:45Z::zzzzzzzz"
                        , "type": "expense"
                        }
                        """

                    decoded =
                        Json.Decode.decodeString Expense.decoder wire

                    reencoded =
                        decoded
                            |> Result.map Expense.encoder
                            |> Result.map (Json.Decode.decodeValue Expense.decoder)
                in
                case ( decoded, reencoded ) of
                    ( Ok first, Ok (Ok second) ) ->
                        Expect.all
                            [ \_ -> Expect.equal (Money.toCents first.amount) (Money.toCents second.amount)
                            , \_ -> Expect.equal (DateField.toIso first.date) (DateField.toIso second.date)
                            , \_ ->
                                Expect.equal
                                    (first.geoPoint |> Maybe.map GeoPoint.latDegrees)
                                    (second.geoPoint |> Maybe.map GeoPoint.latDegrees)
                            ]
                            ()

                    _ ->
                        Expect.fail "expected both decode + reencode to succeed"
        ]
