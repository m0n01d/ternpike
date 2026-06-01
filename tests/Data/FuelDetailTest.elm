module Data.FuelDetailTest exposing (suite)

import Data.Category
import Data.Currency
import Data.FuelDetail as FuelDetail
import Data.FuelGrade as FuelGrade exposing (FuelGrade(..))
import Data.Gallons as Gallons
import Data.Location exposing (LocationState(..))
import Data.PendingEntry as PendingEntry
import Data.PricePerGallon as PricePerGallon
import Expect
import Json.Decode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Fuel detail capture"
        [ describe "PricePerGallon"
            [ test "preserves the 9/10 cent third decimal" <|
                \_ ->
                    PricePerGallon.fromString "4.299"
                        |> Maybe.map PricePerGallon.format
                        |> Expect.equal (Just "$4.299")
            , test "drops an insignificant third decimal" <|
                \_ ->
                    PricePerGallon.fromString "4.50"
                        |> Maybe.map PricePerGallon.format
                        |> Expect.equal (Just "$4.50")
            , test "tolerates a leading dollar sign" <|
                \_ ->
                    PricePerGallon.fromString "$3.199"
                        |> Maybe.map PricePerGallon.toInputString
                        |> Expect.equal (Just "3.199")
            , test "rejects empty input" <|
                \_ ->
                    PricePerGallon.fromString "   "
                        |> Expect.equal Nothing
            ]
        , describe "Gallons"
            [ test "trims trailing zeros" <|
                \_ ->
                    Gallons.fromString "12.300"
                        |> Maybe.map Gallons.format
                        |> Expect.equal (Just "12.3")
            , test "keeps a full three-decimal reading" <|
                \_ ->
                    Gallons.fromString "12.345"
                        |> Maybe.map Gallons.format
                        |> Expect.equal (Just "12.345")
            , test "renders a whole number without a decimal point" <|
                \_ ->
                    Gallons.fromString "10"
                        |> Maybe.map Gallons.format
                        |> Expect.equal (Just "10")
            ]
        , describe "FuelGrade"
            [ test "maps common aliases to canonical grades" <|
                \_ ->
                    [ FuelGrade.fromString "reg", FuelGrade.fromString "Premium", FuelGrade.fromString "plus" ]
                        |> Expect.equal [ Regular, Premium, Midgrade ]
            , test "keeps an unknown grade verbatim as Other" <|
                \_ ->
                    FuelGrade.fromString "E85"
                        |> Expect.equal (Other "E85")
            , test "round-trips a known grade through display/fromString" <|
                \_ ->
                    FuelGrade.fromString (FuelGrade.display Premium)
                        |> Expect.equal Premium
            , test "round-trips an Other grade through display/fromString" <|
                \_ ->
                    FuelGrade.fromString (FuelGrade.display (Other "E85"))
                        |> Expect.equal (Other "E85")
            ]
        , describe "FuelDetail wire round-trip"
            [ test "encodes then decodes back to the same detail" <|
                \_ ->
                    let
                        detail : FuelDetail.FuelDetail
                        detail =
                            { gallons = Gallons.fromString "12.345"
                            , grade = Just Regular
                            , liters = Nothing
                            , pricePerGallon = PricePerGallon.fromString "4.299"
                            , pricePerLiter = Nothing
                            }
                    in
                    FuelDetail.encoder detail
                        |> Json.Decode.decodeValue FuelDetail.decoder
                        |> Expect.equal (Ok detail)
            , test "an all-empty detail is isEmpty" <|
                \_ ->
                    FuelDetail.isEmpty { gallons = Nothing, grade = Nothing, liters = Nothing, pricePerGallon = Nothing, pricePerLiter = Nothing }
                        |> Expect.equal True
            ]
        , describe "parseEntry fuel gating"
            [ test "captures fuel detail when the category is Fuel" <|
                \_ ->
                    parse { base | category = Data.Category.Fuel, fuelPricePerGallon = "4.299", fuelGallons = "12.3", fuelGrade = "Regular" }
                        |> Result.map .fuelDetail
                        |> Expect.equal
                            (Ok
                                (Just
                                    { gallons = Gallons.fromString "12.3"
                                    , grade = Just Regular
                                    , liters = Nothing
                                    , pricePerGallon = PricePerGallon.fromString "4.299"
                                    , pricePerLiter = Nothing
                                    }
                                )
                            )
            , test "drops fuel detail when the category is not Fuel" <|
                \_ ->
                    parse { base | category = Data.Category.Food, fuelPricePerGallon = "4.299", fuelGallons = "12.3" }
                        |> Result.map .fuelDetail
                        |> Expect.equal (Ok Nothing)
            , test "leaves fuel detail Nothing when no fuel field is filled" <|
                \_ ->
                    parse { base | category = Data.Category.Fuel }
                        |> Result.map .fuelDetail
                        |> Expect.equal (Ok Nothing)
            ]
        ]


parse : PendingEntry.PendingEntry -> Result (List String) PendingEntry.ParsedEntry
parse =
    PendingEntry.parseEntry


base : PendingEntry.PendingEntry
base =
    { address = ""
    , amount = "20.00"
    , category = Data.Category.Fuel
    , currency = Data.Currency.usd
    , date = "2024-05-21"
    , fuelGallons = ""
    , fuelGrade = ""
    , fuelPricePerGallon = ""
    , locationState = LocationIdle
    , longNote = ""
    , merchant = ""
    , note = ""
    , paymentMethod = Nothing
    }
