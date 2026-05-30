module Data.ScanTest exposing (suite)

{-| `Data.Scan` decoders / encoders:

  - `ocrDataDecoder` parses an Anthropic OCR response with / without the
    address field (#150).
  - `scanItemEncoder` / `scanItemDecoder` round-trip a `ScanItem`
    losslessly across every status, both EXIF / geocode shapes (incl. a
    `GeoPoint`), and tolerate missing fields on the wire (#370).
  - `reconcileHydratedQueue` resets in-flight statuses to `ScanDeferred`
    while preserving `ScanReady` / `ScanSubmitted` (#370).

-}

import Data.Category as Category
import Data.DateField as DateField
import Data.GeoPoint as GeoPoint
import Data.Location exposing (LocationSource(..), LocationState(..))
import Data.Money as Money
import Data.PaymentMethod as PaymentMethod
import Data.Scan as Scan exposing (ExifPhase(..), GeocodePhase(..), ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Dict
import Expect
import Json.Decode
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Data.Scan"
        [ ocrDataDecoderSuite
        , scanItemCodecSuite
        , reconcileSuite
        ]


ocrDataDecoderSuite : Test
ocrDataDecoderSuite =
    describe "ocrDataDecoder"
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



-- ROUND-TRIP


{-| Encode a `ScanItem`, decode it back, and assert the decoded item
equals the original. The single source of every round-trip assertion.
-}
roundTrips : ScanItem -> Expect.Expectation
roundTrips item =
    Scan.scanItemEncoder item
        |> Json.Decode.decodeValue Scan.scanItemDecoder
        |> Expect.equal (Ok item)


sampleDate : DateField.DateField
sampleDate =
    DateField.today Time.utc (Time.millisToPosix 1716200000000)


baseItem : ScanItem
baseItem =
    { draft = Nothing
    , exif = ExifMissing
    , exifDebug = ""
    , expectedExpenseId = Nothing
    , geocode = GeocodeNotAttempted
    , id = ScanItemId.fromString "scan::1716200000000::3"
    , imageUrl = "data:image/jpeg;base64,xxx"
    , lastError = Nothing
    , ocrData = Nothing
    , ocrError = Nothing
    , persistError = False
    , retryCount = 0
    , schemaVersion = Scan.currentSchemaVersion
    , status = ScanReady
    }


sampleOcr : Scan.OcrData
sampleOcr =
    { address = Just "123 4th Ave, Anchorage AK"
    , amount = Just (Money.fromCents 1230)
    , category = Just Category.Food
    , date = Just sampleDate
    , longNote = Just "a long note about lunch"
    , merchant = Just "Cafe Halibut"
    , note = Just "lunch"
    , paymentMethod = Just PaymentMethod.Credit
    }


sampleDraft : Scan.DraftFields
sampleDraft =
    { address = Just "456 Elm St"
    , amount = Just "12."
    , category = Just Category.Fuel
    , date = Just sampleDate
    , locationState = LocationGot (GeoPoint.fromDegrees 61.2 -149.9) ManualPin
    , longNote = Nothing
    , merchant = Just "Manual Merchant"
    , note = Nothing
    , paymentMethod = Just PaymentMethod.Cash
    }


anchorage : GeoPoint.GeoPoint
anchorage =
    GeoPoint.fromDegrees 61.2181 -149.9003


paris : GeoPoint.GeoPoint
paris =
    GeoPoint.fromDegrees 48.8566 2.3522


scanItemCodecSuite : Test
scanItemCodecSuite =
    describe "scanItemEncoder / scanItemDecoder round-trip"
        [ test "ocrDataEncoder round-trips through ocrDataDecoder" <|
            \_ ->
                Scan.ocrDataEncoder sampleOcr
                    |> Json.Decode.decodeValue Scan.ocrDataDecoder
                    |> Expect.equal (Ok sampleOcr)
        , test "ScanDeferred" <|
            \_ -> roundTrips { baseItem | status = ScanDeferred }
        , test "ScanProcessing" <|
            \_ -> roundTrips { baseItem | status = ScanProcessing }
        , test "ScanQueued" <|
            \_ -> roundTrips { baseItem | status = ScanQueued }
        , test "ScanReady" <|
            \_ -> roundTrips { baseItem | status = ScanReady }
        , test "ScanSubmitted carrying an expectedExpenseId" <|
            \_ -> roundTrips { baseItem | status = ScanSubmitted, expectedExpenseId = Just "expense::2026-05-30::abc" }
        , test "fully-populated item (ocrData + draft + bookkeeping)" <|
            \_ ->
                roundTrips
                    { baseItem
                        | draft = Just sampleDraft
                        , exifDebug = "GPS: none"
                        , lastError = Just "persist failed once"
                        , ocrData = Just sampleOcr
                        , ocrError = Just "model refused first pass"
                        , persistError = True
                        , retryCount = 2
                        , status = ScanReady
                    }
        , test "ExifFound carries a GeoPoint through the round-trip" <|
            \_ -> roundTrips { baseItem | exif = ExifFound anchorage }
        , test "ExifChecking round-trips" <|
            \_ -> roundTrips { baseItem | exif = ExifChecking }
        , test "GeocodeResolved carries a GeoPoint through the round-trip" <|
            \_ -> roundTrips { baseItem | geocode = GeocodeResolved paris }
        , test "GeocodeRequested round-trips" <|
            \_ -> roundTrips { baseItem | geocode = GeocodeRequested }
        , test "GeocodeMissed round-trips" <|
            \_ -> roundTrips { baseItem | geocode = GeocodeMissed }
        , test "draft locationState (LocationGot ManualPin) survives the round-trip" <|
            \_ ->
                Scan.scanItemEncoder { baseItem | draft = Just sampleDraft }
                    |> Json.Decode.decodeValue Scan.scanItemDecoder
                    |> Result.map (.draft >> Maybe.map .locationState)
                    |> Expect.equal (Ok (Just (LocationGot (GeoPoint.fromDegrees 61.2 -149.9) ManualPin)))
        , test "EXIF + geocode precedence (geocode wins) is preserved post-roundtrip" <|
            \_ ->
                let
                    item =
                        { baseItem
                            | exif = ExifFound anchorage
                            , geocode = GeocodeResolved paris
                        }
                in
                Scan.scanItemEncoder item
                    |> Json.Decode.decodeValue Scan.scanItemDecoder
                    |> Result.map Scan.effectiveLocation
                    |> Expect.equal (Ok (LocationGot paris Geocoded))
        , test "missing status / draft / schemaVersion fields are tolerated" <|
            \_ ->
                let
                    wire =
                        """
                        { "id": "scan::1716200000000::3"
                        , "imageUrl": "data:image/jpeg;base64,xxx"
                        }
                        """
                in
                Json.Decode.decodeString Scan.scanItemDecoder wire
                    |> Result.map (\i -> ( i.status, i.draft, i.schemaVersion ))
                    |> Expect.equal (Ok ( ScanDeferred, Nothing, Scan.currentSchemaVersion ))
        ]


reconcileSuite : Test
reconcileSuite =
    let
        normalized : ScanStatus -> Maybe ScanStatus
        normalized status =
            Dict.singleton "k" { baseItem | status = status }
                |> Scan.reconcileHydratedQueue
                |> Dict.get "k"
                |> Maybe.map .status
    in
    describe "reconcileHydratedQueue"
        [ test "resets ScanProcessing to ScanDeferred" <|
            \_ -> Expect.equal (Just ScanDeferred) (normalized ScanProcessing)
        , test "resets ScanQueued to ScanDeferred" <|
            \_ -> Expect.equal (Just ScanDeferred) (normalized ScanQueued)
        , test "leaves ScanDeferred as ScanDeferred" <|
            \_ -> Expect.equal (Just ScanDeferred) (normalized ScanDeferred)
        , test "preserves ScanReady" <|
            \_ -> Expect.equal (Just ScanReady) (normalized ScanReady)
        , test "preserves ScanSubmitted" <|
            \_ -> Expect.equal (Just ScanSubmitted) (normalized ScanSubmitted)
        , test "preserves the non-status fields of a normalized item" <|
            \_ ->
                Dict.singleton "k" { baseItem | status = ScanProcessing, ocrData = Just sampleOcr }
                    |> Scan.reconcileHydratedQueue
                    |> Dict.get "k"
                    |> Maybe.map .ocrData
                    |> Expect.equal (Just (Just sampleOcr))
        ]
