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
import Data.Currency as Currency
import Data.DateField as DateField
import Data.GeoPoint as GeoPoint
import Data.Liters as Liters
import Data.Location exposing (LocationSource(..), LocationState(..))
import Data.Money as Money
import Data.PaymentMethod as PaymentMethod
import Data.PricePerLiter as PricePerLiter
import Data.Scan as Scan exposing (ExifPhase(..), GeocodePhase(..), ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Dict
import Expect
import Json.Decode
import Set
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Data.Scan"
        [ ocrDataDecoderSuite
        , scanItemCodecSuite
        , reconcileSuite
        , effectiveLocationSuite
        , mergeOcrIntoDraftSuite
        , expectedExpenseSuite
        , mergeHydratedQueueSuite
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
        , test "parses a metric pump scan: currency MXN + liters/pricePerLiter, no gallons" <|
            \_ ->
                let
                    wire =
                        """
                        { "amount": 896.50
                        , "category": "fuel"
                        , "currency": "mxn"
                        , "liters": 38.21
                        , "pricePerLiter": 23.459
                        , "grade": "regular"
                        }
                        """
                in
                Json.Decode.decodeString Scan.ocrDataDecoder wire
                    |> Result.map
                        (\ocr ->
                            { currency = ocr.currency
                            , liters = Maybe.andThen .liters ocr.fuelDetail
                            , gallons = Maybe.andThen .gallons ocr.fuelDetail
                            , pricePerLiter = Maybe.andThen .pricePerLiter ocr.fuelDetail
                            }
                        )
                    |> Expect.equal
                        (Ok
                            { currency = Just (Currency.fromLabel "mxn")
                            , liters = Liters.fromString "38.21"
                            , gallons = Nothing
                            , pricePerLiter = PricePerLiter.fromString "23.459"
                            }
                        )
        , test "an unreadable currency collapses to Nothing (not a USD default)" <|
            \_ ->
                Json.Decode.decodeString Scan.ocrDataDecoder """{ "amount": 5.5, "currency": "dollars" }"""
                    |> Result.map .currency
                    |> Expect.equal (Ok Nothing)
        , test "currency + liters survive an encode/decode round-trip" <|
            \_ ->
                Scan.ocrDataEncoder metricOcr
                    |> Json.Decode.decodeValue Scan.ocrDataDecoder
                    |> Expect.equal (Ok metricOcr)
        ]


{-| A metric (Mexican pump) OCR result: pesos, liters, price-per-liter —
the foreign-pump shape that the gas-pump scan track (#452) added.
-}
metricOcr : Scan.OcrData
metricOcr =
    { address = Nothing
    , amount = Just (Money.fromCents 89650)
    , category = Just Category.Fuel
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
    , currency = Nothing
    , date = Just sampleDate
    , fuelDetail = Nothing
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


{-| Manual-pin precedence (#374): a user's offline manual pin (persisted
into `draft.locationState`) beats a geocode that only resolves on a late
reconnect — the user's pin is their final say. Pinned BOTH directly and
after a codec round-trip, so a reload can't surface the geocode over the
pin.
-}
effectiveLocationSuite : Test
effectiveLocationSuite =
    let
        pinnedDraft : Scan.DraftFields
        pinnedDraft =
            { sampleDraft | locationState = LocationGot anchorage ManualPin }

        pinnedOverGeocode : ScanItem
        pinnedOverGeocode =
            { baseItem
                | draft = Just pinnedDraft
                , geocode = GeocodeResolved paris
            }
    in
    describe "effectiveLocation manual-pin precedence"
        [ test "a draft manual pin beats a late geocode" <|
            \_ ->
                Scan.effectiveLocation pinnedOverGeocode
                    |> Expect.equal (LocationGot anchorage ManualPin)
        , test "the manual-pin precedence holds after a codec round-trip" <|
            \_ ->
                Scan.scanItemEncoder pinnedOverGeocode
                    |> Json.Decode.decodeValue Scan.scanItemDecoder
                    |> Result.map Scan.effectiveLocation
                    |> Expect.equal (Ok (LocationGot anchorage ManualPin))
        , test "a non-manual draft location (BrowserGeo) does NOT override geocode" <|
            \_ ->
                Scan.effectiveLocation
                    { baseItem
                        | draft = Just { pinnedDraft | locationState = LocationGot anchorage BrowserGeo }
                        , geocode = GeocodeResolved paris
                    }
                    |> Expect.equal (LocationGot paris Geocoded)
        ]


{-| Blanks-only merge (#374): a set draft field wins; an untouched
(`Nothing`) field falls through to OCR. Beyond the module doctests, this
pins the whole-record behavior over the real `sampleOcr` / `sampleDraft`
fixtures.
-}
mergeOcrIntoDraftSuite : Test
mergeOcrIntoDraftSuite =
    let
        emptyDraft : Scan.DraftFields
        emptyDraft =
            { address = Nothing
            , amount = Nothing
            , category = Nothing
            , date = Nothing
            , locationState = LocationIdle
            , longNote = Nothing
            , merchant = Nothing
            , note = Nothing
            , paymentMethod = Nothing
            }
    in
    describe "mergeOcrIntoDraft"
        [ test "an empty draft is the identity over OCR" <|
            \_ ->
                Scan.mergeOcrIntoDraft emptyDraft sampleOcr
                    |> Expect.equal sampleOcr
        , test "set draft fields win; untouched fields keep OCR" <|
            \_ ->
                let
                    merged =
                        Scan.mergeOcrIntoDraft sampleDraft sampleOcr
                in
                Expect.all
                    [ -- draft set these → draft wins
                      \_ -> Expect.equal (Just "456 Elm St") merged.address
                    , \_ -> Expect.equal (Just (Money.fromCents 1200)) merged.amount
                    , \_ -> Expect.equal (Just Category.Fuel) merged.category
                    , \_ -> Expect.equal (Just "Manual Merchant") merged.merchant
                    , \_ -> Expect.equal (Just PaymentMethod.Cash) merged.paymentMethod

                    -- draft left these untouched → OCR survives
                    , \_ -> Expect.equal sampleOcr.longNote merged.longNote
                    , \_ -> Expect.equal sampleOcr.note merged.note
                    ]
                    ()
        ]


{-| The change-feed echo match (#374): `idsWithExpectedExpense` returns
the queue keys to retire when an expense arrives, and returns `[]` for a
re-delivered echo — the idempotency that makes the change-feed delete a
no-op the second time.
-}
expectedExpenseSuite : Test
expectedExpenseSuite =
    let
        expenseId : String
        expenseId =
            "expense::2026-05-30T00:00:00.000Z::17162000"

        tagged : ScanItem
        tagged =
            { baseItem | status = ScanSubmitted, expectedExpenseId = Just expenseId }

        queue : Dict.Dict String ScanItem
        queue =
            Dict.fromList
                [ ( "scan::1::0", tagged )
                , ( "scan::2::0", { baseItem | expectedExpenseId = Nothing } )
                ]
    in
    describe "idsWithExpectedExpense"
        [ test "matches the item whose expectedExpenseId equals the arriving id" <|
            \_ ->
                Scan.idsWithExpectedExpense expenseId queue
                    |> Expect.equal [ "scan::1::0" ]
        , test "is a no-op (empty) once the matching item is gone — idempotent echo" <|
            \_ ->
                Scan.idsWithExpectedExpense expenseId (Dict.remove "scan::1::0" queue)
                    |> Expect.equal []
        , test "returns empty when no item expects the arriving id" <|
            \_ ->
                Scan.idsWithExpectedExpense "expense::other" queue
                    |> Expect.equal []
        ]


{-| Hydration-window tombstones (#374): a `loadScanQueue` that lands AFTER
a delete must not resurrect the deleted card.
-}
mergeHydratedQueueSuite : Test
mergeHydratedQueueSuite =
    let
        inMemory : Dict.Dict String ScanItem
        inMemory =
            Dict.singleton "scan::live::0" { baseItem | status = ScanReady }

        hydrated : Dict.Dict String ScanItem
        hydrated =
            Dict.fromList
                [ ( "scan::live::0", { baseItem | status = ScanProcessing } )
                , ( "scan::gone::0", { baseItem | status = ScanReady } )
                ]
    in
    describe "mergeHydratedQueue"
        [ test "a tombstoned id from the hydrated side is NOT resurrected" <|
            \_ ->
                Scan.mergeHydratedQueue (Set.fromList [ "scan::gone::0" ]) inMemory hydrated
                    |> Dict.keys
                    |> Expect.equal [ "scan::live::0" ]
        , test "the in-memory item wins a key collision over its stale hydrated form" <|
            \_ ->
                Scan.mergeHydratedQueue Set.empty inMemory hydrated
                    |> Dict.get "scan::live::0"
                    |> Maybe.map .status
                    |> Expect.equal (Just ScanReady)
        , test "a non-tombstoned hydrated-only item IS brought in" <|
            \_ ->
                Scan.mergeHydratedQueue Set.empty inMemory hydrated
                    |> Dict.member "scan::gone::0"
                    |> Expect.equal True
        ]
