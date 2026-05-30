module PageScanMergeTest exposing (suite)

{-| #374 coverage for the merge / multi-receipt split / delete semantics
in `Page.Scan.update`, driven directly against the real `update` (asserting
on the returned `Model` queue and the `Effect` it emits — no `ProgramTest`
harness needed).

Covered here:

  - A multi-receipt OCR success defers to `MintIdsThen`, then the
    `GotMintedScanIds` arm fans the source out into N `ScanReady` children,
    merges the source draft into CHILD 0 ONLY, persists every child, and
    deletes the consumed source row from the durable store.
  - A single-receipt OCR success folds the item's typed draft over the OCR
    result (blanks-only) so user input isn't clobbered.
  - `ClearDoneItems` deletes + tombstones every submitted card.

-}

import Data.Category
import Data.DateField as DateField exposing (DateField)
import Data.Location exposing (LocationState(..))
import Data.Money as Money
import Data.Navigation exposing (Route(..))
import Data.PendingEntry as PendingEntry exposing (PendingForm(..))
import Data.Scan as Scan exposing (ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Data.SharedTrips
import Data.Sync
import Data.Tier as Tier
import Data.TripId as TripId
import Data.Trips exposing (TripsState(..))
import Data.UserId as UserId
import Dict
import Effect exposing (Effect(..))
import Expect
import Msg.Scan exposing (Msg(..))
import Page.Scan
import Set
import Test exposing (Test, describe, test)
import Time



-- SEED


seedDate : DateField
seedDate =
    DateField.today Time.utc (Time.millisToPosix 0)


paidModel : Page.Scan.Model
paidModel =
    { activeScanItemId = Nothing
    , basePath = "/"
    , config =
        { anthropicKey = Nothing
        , backendUrl = "https://api.ternpike.com"
        , vapidPublicKey = ""
        }
    , creds =
        { dbName = "ternpike"
        , email = "alice@example.com"
        , password = "pw"
        , subscriptionStatus = Nothing
        , tier = Tier.Osprey
        , trailblazerNumber = Nothing
        }
    , currentUser = UserId.fromString "alice@example.com"
    , duplicateWarning = Nothing
    , error = Nothing
    , form = FreshForm (PendingEntry.defaultPendingEntry seedDate)
    , network = Data.Sync.Online
    , ocrInFlight = Set.empty
    , route = RouteScan (TripId.fromString "trip::2026-05-30::abc")
    , scanQueue = Dict.empty
    , scanSeq = 5
    , scanTombstones = Set.empty
    , sharedTrips = Data.SharedTrips.empty
    , storageAvailable = True
    , tier = Tier.Osprey
    , today = seedDate
    , trips = NoTripsYet
    }


processingItem : String -> ScanItem
processingItem id =
    { draft = Nothing
    , exif = Scan.ExifChecking
    , exifDebug = ""
    , expectedExpenseId = Nothing
    , geocode = Scan.GeocodeNotAttempted
    , id = ScanItemId.fromString id
    , imageUrl = "data:image/jpeg;base64,xxx"
    , lastError = Nothing
    , ocrData = Nothing
    , ocrError = Nothing
    , persistError = False
    , retryCount = 0
    , schemaVersion = Scan.currentSchemaVersion
    , status = ScanProcessing
    }


submittedItem : String -> ScanItem
submittedItem id =
    let
        p =
            processingItem id
    in
    { p | status = ScanSubmitted }


queueOf : List ScanItem -> Dict.Dict String ScanItem
queueOf items =
    items
        |> List.map (\i -> ( ScanItemId.toString i.id, i ))
        |> Dict.fromList


draftWith : { amount : Maybe String, merchant : Maybe String } -> Scan.DraftFields
draftWith opts =
    { address = Nothing
    , amount = opts.amount
    , category = Nothing
    , date = Nothing
    , locationState = LocationIdle
    , longNote = Nothing
    , merchant = opts.merchant
    , note = Nothing
    , paymentMethod = Nothing
    }


ocr : String -> Scan.OcrData
ocr merchant =
    { address = Nothing
    , amount = Just (Money.fromCents 1299)
    , category = Just Data.Category.Food
    , date = Nothing
    , longNote = Nothing
    , merchant = Just merchant
    , note = Nothing
    , paymentMethod = Nothing
    }



-- EFFECT INSPECTION


flatten : Effect -> List Effect
flatten effect =
    case effect of
        Batch effects ->
            List.concatMap flatten effects

        NoEffect ->
            []

        single ->
            [ single ]


deletedIds : Effect -> List String
deletedIds effect =
    flatten effect
        |> List.filterMap
            (\e ->
                case e of
                    DeleteScanItem id ->
                        Just id

                    _ ->
                        Nothing
            )


saveCount : Effect -> Int
saveCount effect =
    flatten effect
        |> List.filter
            (\e ->
                case e of
                    SaveScanItem _ ->
                        True

                    _ ->
                        False
            )
        |> List.length



-- TESTS


suite : Test
suite =
    describe "Page.Scan #374 merge / split / delete"
        [ describe "single-receipt OCR folds the draft (blanks-only)"
            [ test "a single OCR success merges the item's draft over the data" <|
                \() ->
                    let
                        item =
                            let
                                p =
                                    processingItem "scan::1::0"
                            in
                            { p | draft = Just (draftWith { amount = Just "9.99", merchant = Nothing }) }

                        model =
                            { paidModel
                                | ocrInFlight = Set.singleton "scan::1::0"
                                , scanQueue = queueOf [ item ]
                            }

                        ( newModel, _ ) =
                            Page.Scan.update (GotOcrResult "scan::1::0" (Ok anthropicSingle)) model

                        readied =
                            Dict.get "scan::1::0" newModel.scanQueue
                    in
                    Expect.all
                        [ \_ -> Expect.equal (Just ScanReady) (Maybe.map .status readied)

                        -- draft amount wins over OCR amount
                        , \_ -> Expect.equal (Just (Just (Money.fromCents 999))) (Maybe.map (\i -> Maybe.andThen .amount i.ocrData) readied)

                        -- untouched merchant falls through to OCR
                        , \_ -> Expect.equal (Just (Just "Denali Cafe")) (Maybe.map (\i -> Maybe.andThen .merchant i.ocrData) readied)
                        ]
                        ()
            ]
        , describe "multi-receipt split"
            [ test "a multi OCR success defers to MintIdsThen (no queue mutation yet)" <|
                \() ->
                    let
                        model =
                            { paidModel
                                | ocrInFlight = Set.singleton "scan::1::0"
                                , scanQueue = queueOf [ processingItem "scan::1::0" ]
                            }

                        ( newModel, effect ) =
                            Page.Scan.update (GotOcrResult "scan::1::0" (Ok anthropicMulti)) model
                    in
                    Expect.all
                        [ -- source still present until GotMintedScanIds runs
                          \_ -> Expect.equal True (Dict.member "scan::1::0" newModel.scanQueue)
                        , \_ -> Expect.equal False (Set.member "scan::1::0" newModel.ocrInFlight)
                        , \_ -> Expect.equal True (List.any isMintIds (flatten effect))
                        ]
                        ()
            , test "GotMintedScanIds fans into N children, merges draft into child 0 only, deletes source, persists all" <|
                \() ->
                    let
                        source =
                            let
                                p =
                                    processingItem "scan::1::0"
                            in
                            { p | draft = Just (draftWith { amount = Nothing, merchant = Just "Pinned Merchant" }) }

                        model =
                            { paidModel | scanQueue = queueOf [ source ] }

                        results =
                            [ ocr "Receipt A", ocr "Receipt B" ]

                        ( newModel, effect ) =
                            Page.Scan.update (GotMintedScanIds "scan::1::0" results (Time.millisToPosix 1716200000000)) model

                        childIds =
                            Dict.keys newModel.scanQueue |> List.sort

                        child0 =
                            Dict.get "scan::1716200000000::5" newModel.scanQueue

                        child1 =
                            Dict.get "scan::1716200000000::6" newModel.scanQueue
                    in
                    Expect.all
                        [ -- source removed
                          \_ -> Expect.equal False (Dict.member "scan::1::0" newModel.scanQueue)

                        -- two durable children minted from the real millis + scanSeq
                        , \_ -> Expect.equal [ "scan::1716200000000::5", "scan::1716200000000::6" ] childIds

                        -- child 0 carries the source draft; its merchant came from OCR (draft merchant only overrides via merge, but draft set merchant)
                        , \_ -> Expect.equal (Just True) (Maybe.map (\i -> i.draft /= Nothing) child0)
                        , \_ -> Expect.equal (Just (Just "Pinned Merchant")) (Maybe.map (\i -> Maybe.andThen .merchant i.ocrData) child0)

                        -- child 1 has NO draft, keeps its own OCR merchant
                        , \_ -> Expect.equal (Just Nothing) (Maybe.map .draft child1)
                        , \_ -> Expect.equal (Just (Just "Receipt B")) (Maybe.map (\i -> Maybe.andThen .merchant i.ocrData) child1)

                        -- both children ready
                        , \_ -> Expect.equal (Just ScanReady) (Maybe.map .status child0)
                        , \_ -> Expect.equal (Just ScanReady) (Maybe.map .status child1)

                        -- the consumed source is deleted from the durable store
                        , \_ -> Expect.equal [ "scan::1::0" ] (deletedIds effect)

                        -- every child is persisted
                        , \_ -> Expect.equal 2 (saveCount effect)

                        -- scanSeq advanced by the child count
                        , \_ -> Expect.equal 7 newModel.scanSeq
                        ]
                        ()
            , test "GotMintedScanIds for a vanished source still deletes (idempotent), no children" <|
                \() ->
                    let
                        model =
                            { paidModel | scanQueue = Dict.empty }

                        ( newModel, effect ) =
                            Page.Scan.update (GotMintedScanIds "scan::1::0" [ ocr "A", ocr "B" ] (Time.millisToPosix 1716200000000)) model
                    in
                    Expect.all
                        [ \_ -> Expect.equal Dict.empty newModel.scanQueue
                        , \_ -> Expect.equal [ "scan::1::0" ] (deletedIds effect)
                        ]
                        ()
            ]
        , describe "ClearDoneItems deletes + tombstones"
            [ test "every submitted card is removed, deleted from IDB, and tombstoned" <|
                \() ->
                    let
                        model =
                            { paidModel
                                | scanQueue =
                                    queueOf
                                        [ submittedItem "scan::1::0"
                                        , processingItem "scan::2::0"
                                        , submittedItem "scan::3::0"
                                        ]
                            }

                        ( newModel, effect ) =
                            Page.Scan.update ClearDoneItems model
                    in
                    Expect.all
                        [ -- only the non-submitted item survives
                          \_ -> Expect.equal [ "scan::2::0" ] (Dict.keys newModel.scanQueue)

                        -- both submitted ids deleted from the durable store
                        , \_ -> Expect.equal [ "scan::1::0", "scan::3::0" ] (List.sort (deletedIds effect))

                        -- and tombstoned so a late load can't resurrect them
                        , \_ -> Expect.equal True (Set.member "scan::1::0" newModel.scanTombstones)
                        , \_ -> Expect.equal True (Set.member "scan::3::0" newModel.scanTombstones)
                        , \_ -> Expect.equal False (Set.member "scan::2::0" newModel.scanTombstones)
                        ]
                        ()
            ]
        ]


isMintIds : Effect -> Bool
isMintIds effect =
    case effect of
        MintIdsThen _ _ ->
            True

        _ ->
            False



-- ANTHROPIC RESPONSE BODIES


anthropicSingle : String
anthropicSingle =
    anthropicBody "[{\"amount\": 12.99, \"category\": \"food\", \"merchant\": \"Denali Cafe\"}]"


anthropicMulti : String
anthropicMulti =
    anthropicBody "[{\"amount\": 12.99, \"merchant\": \"Receipt A\"}, {\"amount\": 4.50, \"merchant\": \"Receipt B\"}]"


anthropicBody : String -> String
anthropicBody jsonArrayText =
    "{\"content\":[{\"text\":" ++ escapeJsonString jsonArrayText ++ "}]}"


escapeJsonString : String -> String
escapeJsonString raw =
    "\"" ++ String.replace "\"" "\\\"" raw ++ "\""
