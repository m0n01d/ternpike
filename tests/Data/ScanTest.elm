module Data.ScanTest exposing (suite)

{-| Verify that `Data.Scan.ocrDataDecoder` parses an Anthropic OCR
response with the address field (#150) and tolerates one without it.
-}

import Data.Scan as Scan
import Expect
import Json.Decode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Data.Scan.ocrDataDecoder"
        [ test "parses an OCR response with address" <|
            \_ ->
                let
                    wire =
                        """
                        { "amount": 12.30
                        , "category": "food"
                        , "merchant": "Cafe Halibut"
                        , "address": "123 4th Ave, Anchorage AK"
                        , "date": "2024-05-21"
                        , "note": "lunch"
                        , "paymentMethod": "credit"
                        }
                        """
                in
                Json.Decode.decodeString Scan.ocrDataDecoder wire
                    |> Result.map .address
                    |> Expect.equal (Ok (Just "123 4th Ave, Anchorage AK"))
        , test "parses an OCR response without address" <|
            \_ ->
                let
                    wire =
                        """
                        { "amount": 5.50
                        , "category": "fuel"
                        , "merchant": "Gas Station"
                        , "date": "2024-05-21"
                        }
                        """
                in
                Json.Decode.decodeString Scan.ocrDataDecoder wire
                    |> Result.map .address
                    |> Expect.equal (Ok Nothing)
        , test "parses an OCR response with null address" <|
            \_ ->
                let
                    wire =
                        """
                        { "amount": 5.50
                        , "merchant": "Gas Station"
                        , "address": null
                        }
                        """
                in
                Json.Decode.decodeString Scan.ocrDataDecoder wire
                    |> Result.map .address
                    |> Expect.equal (Ok Nothing)
        , test "ocrDataListDecoder accepts a multi-receipt array" <|
            \_ ->
                let
                    wire =
                        """
                        [ { "amount": 5.50, "address": "111 Main St" }
                        , { "amount": 9.99, "address": "222 Park Ave" }
                        ]
                        """
                in
                Json.Decode.decodeString Scan.ocrDataListDecoder wire
                    |> Result.map (List.map .address)
                    |> Expect.equal (Ok [ Just "111 Main St", Just "222 Park Ave" ])
        ]
