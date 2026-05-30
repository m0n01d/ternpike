module PageScanReconnectTest exposing (suite)

{-| Reconnect-orchestration coverage (#373): the `Synced`-edge retry, the
tier concurrency gate, the transient-vs-terminal failure split, and the
`Unscannable`-keeps-draft path. Drives the _real_ `Page.Scan.update`
directly (no `ProgramTest` harness needed — we assert on the returned
`Model` queue and the `Effect` it emits) and the pure
`Data.Scan` reconnect helpers.
-}

import Data.Category
import Data.DateField as DateField exposing (DateField)
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


{-| A Tern (free) seed model, no BYO key → `Unscannable` path; tier cap 1.
Override fields per test.
-}
ternModel : Page.Scan.Model
ternModel =
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
        , tier = Tier.Tern
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
    , scanSeq = 0
    , scanTombstones = Set.empty
    , sharedTrips = Data.SharedTrips.empty
    , storageAvailable = True
    , tier = Tier.Tern
    , today = seedDate
    , trips = NoTripsYet
    }


{-| A paid (Osprey) model, no BYO key → `HostedPath` (scannable); tier
cap 3.
-}
paidModel : Page.Scan.Model
paidModel =
    { ternModel | tier = Tier.Osprey }


deferredItem : String -> ScanItem
deferredItem id =
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
    , status = ScanDeferred
    }


processingItem : String -> ScanItem
processingItem id =
    let
        base =
            deferredItem id
    in
    { base | status = ScanProcessing }


queueOf : List ScanItem -> Dict.Dict String ScanItem
queueOf items =
    items
        |> List.map (\i -> ( ScanItemId.toString i.id, i ))
        |> Dict.fromList


statusOf : String -> Page.Scan.Model -> Maybe ScanStatus
statusOf id model =
    Dict.get id model.scanQueue |> Maybe.map .status


retryOf : String -> Page.Scan.Model -> Maybe Int
retryOf id model =
    Dict.get id model.scanQueue |> Maybe.map .retryCount



-- TESTS


suite : Test
suite =
    describe "Page.Scan reconnect orchestration (#373)"
        [ describe "Data.Scan.reconnectCandidates (pure gate)"
            [ test "no free slots → dispatches zero even with deferred items" <|
                \() ->
                    Scan.reconnectCandidates 1 1 Set.empty (queueOf [ deferredItem "scan::1::0" ])
                        |> Expect.equal []
            , test "respects the slot count (cap 3, one in flight → take 2)" <|
                \() ->
                    Scan.reconnectCandidates 3
                        1
                        Set.empty
                        (queueOf
                            [ deferredItem "scan::1::0"
                            , deferredItem "scan::2::0"
                            , deferredItem "scan::3::0"
                            ]
                        )
                        |> Expect.equal [ "scan::1::0", "scan::2::0" ]
            , test "ScanDeferred-only — never picks processing / ready items" <|
                \() ->
                    Scan.reconnectCandidates 5
                        0
                        Set.empty
                        (queueOf
                            [ processingItem "scan::1::0"
                            , deferredItem "scan::2::0"
                            ]
                        )
                        |> Expect.equal [ "scan::2::0" ]
            , test "skips persistError items and excluded ids" <|
                \() ->
                    let
                        bad =
                            let
                                d =
                                    deferredItem "scan::1::0"
                            in
                            { d | persistError = True }
                    in
                    Scan.reconnectCandidates 5
                        0
                        (Set.singleton "scan::2::0")
                        (queueOf
                            [ bad
                            , deferredItem "scan::2::0"
                            , deferredItem "scan::3::0"
                            ]
                        )
                        |> Expect.equal [ "scan::3::0" ]
            ]
        , describe "RetryDeferredScans dispatch"
            [ test "redundant Synced edge with in-flight at cap dispatches zero (idempotent)" <|
                \() ->
                    let
                        model =
                            { ternModel
                                | ocrInFlight = Set.singleton "scan::0::0"
                                , scanQueue =
                                    queueOf
                                        [ processingItem "scan::0::0"
                                        , deferredItem "scan::1::0"
                                        ]
                            }

                        ( newModel, effect ) =
                            Page.Scan.update RetryDeferredScans model
                    in
                    Expect.all
                        [ \_ -> Expect.equal NoEffect (flattenSingle effect)
                        , \_ -> Expect.equal (Just ScanDeferred) (statusOf "scan::1::0" newModel)
                        , \_ -> Expect.equal (Set.singleton "scan::0::0") newModel.ocrInFlight
                        ]
                        ()
            , test "paid BYO: flips a deferred item to processing, adds to in-flight, fires OCR" <|
                \() ->
                    let
                        model =
                            { paidModel | scanQueue = queueOf [ deferredItem "scan::1::0" ] }

                        ( newModel, effect ) =
                            Page.Scan.update RetryDeferredScans model
                    in
                    Expect.all
                        [ \_ -> Expect.equal (Just ScanProcessing) (statusOf "scan::1::0" newModel)
                        , \_ -> Expect.equal True (Set.member "scan::1::0" newModel.ocrInFlight)
                        , \_ -> Expect.equal True (hasPrepareOcr effect)
                        ]
                        ()
            , test "Unscannable-on-reconnect keeps the draft: ScanReady + draft folded into ocrData" <|
                \() ->
                    let
                        item =
                            let
                                d =
                                    deferredItem "scan::1::0"
                            in
                            { d
                                | draft =
                                    Just
                                        { address = Nothing
                                        , amount = Just "42.00"
                                        , category = Just Data.Category.Food
                                        , date = Nothing
                                        , locationState = (PendingEntry.defaultPendingEntry seedDate).locationState
                                        , longNote = Nothing
                                        , merchant = Just "Roadhouse"
                                        , note = Nothing
                                        , paymentMethod = Nothing
                                        }
                            }

                        model =
                            -- Tern + no key → Unscannable
                            { ternModel | scanQueue = queueOf [ item ] }

                        ( newModel, _ ) =
                            Page.Scan.update RetryDeferredScans model

                        readied =
                            Dict.get "scan::1::0" newModel.scanQueue
                    in
                    Expect.all
                        [ \_ -> Expect.equal (Just ScanReady) (Maybe.map .status readied)
                        , \_ -> Expect.equal False (Set.member "scan::1::0" newModel.ocrInFlight)
                        , \_ -> Expect.equal (Just (Just "Roadhouse")) (Maybe.map (\i -> Maybe.andThen .merchant i.ocrData) readied)
                        , \_ -> Expect.equal (Just (Just (Money.fromCents 4200))) (Maybe.map (\i -> Maybe.andThen .amount i.ocrData) readied)
                        ]
                        ()
            ]
        , describe "transient vs terminal failure"
            [ test "transient flap (BYO network error) returns item to ScanDeferred, retryCount unchanged" <|
                \() ->
                    let
                        model =
                            { paidModel
                                | ocrInFlight = Set.singleton "scan::1::0"
                                , scanQueue = queueOf [ processingItem "scan::1::0" ]
                            }

                        ( newModel, _ ) =
                            Page.Scan.update (GotOcrResult "scan::1::0" (Err "Network error — check your connection and try again")) model
                    in
                    Expect.all
                        [ \_ -> Expect.equal (Just ScanDeferred) (statusOf "scan::1::0" newModel)
                        , \_ -> Expect.equal (Just 0) (retryOf "scan::1::0" newModel)
                        , \_ -> Expect.equal False (Set.member "scan::1::0" newModel.ocrInFlight)
                        ]
                        ()
            , test "retryable HTTP response under cap requeues with retryCount bumped" <|
                \() ->
                    let
                        model =
                            { paidModel
                                | ocrInFlight = Set.singleton "scan::1::0"
                                , scanQueue = queueOf [ processingItem "scan::1::0" ]
                            }

                        ( newModel, _ ) =
                            Page.Scan.update (GotOcrResult "scan::1::0" (Err "Anthropic error (HTTP 503): overloaded")) model
                    in
                    Expect.all
                        [ \_ -> Expect.equal (Just ScanDeferred) (statusOf "scan::1::0" newModel)
                        , \_ -> Expect.equal (Just 1) (retryOf "scan::1::0" newModel)
                        ]
                        ()
            , test "retryable at the cap goes terminal: ScanReady with ocrError" <|
                \() ->
                    let
                        atCap =
                            let
                                p =
                                    processingItem "scan::1::0"
                            in
                            { p | retryCount = Scan.maxOcrRetries - 1 }

                        model =
                            { paidModel
                                | ocrInFlight = Set.singleton "scan::1::0"
                                , scanQueue = queueOf [ atCap ]
                            }

                        ( newModel, _ ) =
                            Page.Scan.update (GotOcrResult "scan::1::0" (Err "OCR request failed (HTTP 429)")) model

                        readied =
                            Dict.get "scan::1::0" newModel.scanQueue
                    in
                    Expect.all
                        [ \_ -> Expect.equal (Just ScanReady) (Maybe.map .status readied)
                        , \_ -> Expect.equal (Just True) (Maybe.map (\i -> i.ocrError /= Nothing) readied)
                        ]
                        ()
            , test "hosted status 0 (connection died) is transient — requeue, no bump" <|
                \() ->
                    let
                        model =
                            { paidModel
                                | ocrInFlight = Set.singleton "scan::1::0"
                                , scanQueue = queueOf [ processingItem "scan::1::0" ]
                            }

                        ( newModel, _ ) =
                            Page.Scan.update (ScanProxyResult { body = "", itemId = "scan::1::0", ok = False, status = 0 }) model
                    in
                    Expect.all
                        [ \_ -> Expect.equal (Just ScanDeferred) (statusOf "scan::1::0" newModel)
                        , \_ -> Expect.equal (Just 0) (retryOf "scan::1::0" newModel)
                        ]
                        ()
            ]
        ]



-- EFFECT INTROSPECTION


{-| Collapse a `Batch [ e ]` (or `Batch []`) down for an equality check.
-}
flattenSingle : Effect -> Effect
flattenSingle effect =
    case effect of
        Batch [] ->
            NoEffect

        Batch [ Batch [] ] ->
            NoEffect

        other ->
            other


{-| True when the effect tree contains a `PrepareOcrImage`.
-}
hasPrepareOcr : Effect -> Bool
hasPrepareOcr effect =
    case effect of
        Batch effects ->
            List.any hasPrepareOcr effects

        PrepareOcrImage _ ->
            True

        _ ->
            False
