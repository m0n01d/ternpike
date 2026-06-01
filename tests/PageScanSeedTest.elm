module PageScanSeedTest exposing (suite)

{-| #452 coverage for the international gas-pump scan path: `Page.Scan.seedPending`
must seed the form's `currency` from the OCR result and route the volume +
unit price into the form's two shared raw fuel fields regardless of unit
system, so a metric (foreign) pump fills the form as liters and a US pump as
gallons.

The headline invariant is the round-trip `seedPending >> PendingEntry.parseEntry`:
because `currency` drives `parseEntry`'s gallons-vs-liters choice
(`Data.Currency.usesGallons`), a peso pump scan must parse back to a
`FuelDetail` with `liters` set and `gallons = Nothing`, and a US pump scan the
mirror. This is the end-to-end guard that a foreign pump never files gallons.

-}

import Data.Category
import Data.Currency as Currency
import Data.DateField as DateField exposing (DateField)
import Data.FuelDetail exposing (FuelDetail)
import Data.Gallons as Gallons
import Data.Liters as Liters
import Data.Money as Money
import Data.PendingEntry as PendingEntry
import Data.PricePerGallon as PricePerGallon
import Data.PricePerLiter as PricePerLiter
import Data.Scan as Scan exposing (ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Expect
import Page.Scan
import Test exposing (Test, describe, test)
import Time


seedDate : DateField
seedDate =
    DateField.today Time.utc (Time.millisToPosix 0)


{-| A ready scan item whose only interesting field is its OCR result.
-}
itemWithOcr : Scan.OcrData -> ScanItem
itemWithOcr ocr =
    { draft = Nothing
    , exif = Scan.ExifMissing
    , exifDebug = ""
    , expectedExpenseId = Nothing
    , geocode = Scan.GeocodeNotAttempted
    , id = ScanItemId.fromString "scan::0::0"
    , imageUrl = "data:image/jpeg;base64,xxx"
    , lastError = Nothing
    , ocrData = Just ocr
    , ocrError = Nothing
    , persistError = False
    , retryCount = 0
    , schemaVersion = Scan.currentSchemaVersion
    , status = ScanReady
    }


usPumpOcr : Scan.OcrData
usPumpOcr =
    { address = Nothing
    , amount = Just (Money.fromCents 5298)
    , category = Just Data.Category.Fuel
    , currency = Just (Currency.fromLabel "usd")
    , date = Nothing
    , fuelDetail =
        Just
            { gallons = Gallons.fromString "12.345"
            , grade = Nothing
            , liters = Nothing
            , pricePerGallon = PricePerGallon.fromString "4.299"
            , pricePerLiter = Nothing
            }
    , longNote = Nothing
    , merchant = Nothing
    , note = Nothing
    , paymentMethod = Nothing
    }


metricPumpOcr : Scan.OcrData
metricPumpOcr =
    { address = Nothing
    , amount = Just (Money.fromCents 89650)
    , category = Just Data.Category.Fuel
    , currency = Just (Currency.fromLabel "mxn")
    , date = Nothing
    , fuelDetail =
        Just
            { gallons = Nothing
            , grade = Nothing
            , liters = Liters.fromString "38.21"
            , pricePerGallon = Nothing
            , pricePerLiter = PricePerLiter.fromString "23.459"
            }
    , longNote = Nothing
    , merchant = Nothing
    , note = Nothing
    , paymentMethod = Nothing
    }


fuelUnitPair : Maybe FuelDetail -> ( Bool, Bool )
fuelUnitPair detail =
    ( detail |> Maybe.andThen .gallons |> (/=) Nothing
    , detail |> Maybe.andThen .liters |> (/=) Nothing
    )


suite : Test
suite =
    describe "Page.Scan.seedPending — international fuel"
        [ test "seeds currency from the OCR result (USD)" <|
            \_ ->
                Page.Scan.seedPending seedDate (itemWithOcr usPumpOcr)
                    |> .currency
                    |> Currency.code
                    |> Expect.equal "USD"
        , test "seeds currency from the OCR result (MXN)" <|
            \_ ->
                Page.Scan.seedPending seedDate (itemWithOcr metricPumpOcr)
                    |> .currency
                    |> Currency.code
                    |> Expect.equal "MXN"
        , test "an OCR result with no currency falls back to USD" <|
            \_ ->
                Page.Scan.seedPending seedDate (itemWithOcr { metricPumpOcr | currency = Nothing })
                    |> .currency
                    |> Currency.code
                    |> Expect.equal "USD"
        , test "the shared fuel field is populated for a metric pump (from liters)" <|
            \_ ->
                Page.Scan.seedPending seedDate (itemWithOcr metricPumpOcr)
                    |> (\pe -> ( pe.fuelGallons /= "", pe.fuelPricePerGallon /= "" ))
                    |> Expect.equal ( True, True )
        , test "round-trip: a US pump scan parses back as GALLONS (not liters)" <|
            \_ ->
                Page.Scan.seedPending seedDate (itemWithOcr usPumpOcr)
                    |> PendingEntry.parseEntry
                    |> Result.map (.fuelDetail >> fuelUnitPair)
                    |> Expect.equal (Ok ( True, False ))
        , test "round-trip: a metric pump scan parses back as LITERS (not gallons)" <|
            \_ ->
                Page.Scan.seedPending seedDate (itemWithOcr metricPumpOcr)
                    |> PendingEntry.parseEntry
                    |> Result.map (.fuelDetail >> fuelUnitPair)
                    |> Expect.equal (Ok ( False, True ))
        ]
