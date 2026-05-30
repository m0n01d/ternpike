module PageScanRemoveTest exposing (suite)

{-| Unit tests for the per-item remove flow added in #404.

Drives the real `Page.Scan.update` directly (no ProgramTest harness —
we assert on the returned `Model` and `Effect` to keep it fast). Covers:

  - `RequestRemoveScan` sets `confirmRemoveScan` without touching the queue.
  - `CancelRemoveScan` clears `confirmRemoveScan` without deleting anything.
  - `ConfirmRemoveScan id` removes from `scanQueue`, adds to
    `scanTombstones`, clears `ocrInFlight`, and emits `DeleteScanItem id`.
  - `ConfirmRemoveScan` on a stale id (already gone from the queue) is a
    clean no-op that still clears the modal — no crash.

-}

import Data.DateField as DateField exposing (DateField)
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


seedDate : DateField
seedDate =
    DateField.today Time.utc (Time.millisToPosix 0)


{-| Minimal seed model with a single deferred item in the queue.
-}
baseModel : Page.Scan.Model
baseModel =
    { activeScanItemId = Nothing
    , basePath = "/"
    , config =
        { anthropicKey = Nothing
        , backendUrl = "https://api.ternpike.com"
        , vapidPublicKey = ""
        }
    , confirmRemoveScan = Nothing
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
    , scanQueue = Dict.singleton itemId deferredItem
    , scanSeq = 0
    , scanTombstones = Set.empty
    , sharedTrips = Data.SharedTrips.empty
    , storageAvailable = True
    , tier = Tier.Tern
    , today = seedDate
    , trips = NoTripsYet
    }


itemId : String
itemId =
    "scan::1748646000000::0"


deferredItem : ScanItem
deferredItem =
    { draft = Nothing
    , exif = Scan.ExifChecking
    , exifDebug = ""
    , expectedExpenseId = Nothing
    , geocode = Scan.GeocodeNotAttempted
    , id = ScanItemId.fromString itemId
    , imageUrl = "data:image/jpeg;base64,xxx"
    , lastError = Nothing
    , ocrData = Nothing
    , ocrError = Nothing
    , persistError = False
    , retryCount = 0
    , schemaVersion = Scan.currentSchemaVersion
    , status = ScanDeferred
    }


suite : Test
suite =
    describe "Page.Scan remove-receipt flow (#404)"
        [ test "RequestRemoveScan sets confirmRemoveScan to Just id" <|
            \() ->
                let
                    ( model, effect ) =
                        Page.Scan.update (RequestRemoveScan itemId) baseModel
                in
                Expect.all
                    [ \_ -> Expect.equal (Just itemId) model.confirmRemoveScan
                    , \_ -> Expect.equal (Dict.singleton itemId deferredItem) model.scanQueue
                    , \_ -> Expect.equal Set.empty model.scanTombstones
                    , \_ -> Expect.equal NoEffect effect
                    ]
                    ()
        , test "CancelRemoveScan clears confirmRemoveScan without deleting" <|
            \() ->
                let
                    modelWithModal =
                        { baseModel | confirmRemoveScan = Just itemId }

                    ( model, effect ) =
                        Page.Scan.update CancelRemoveScan modelWithModal
                in
                Expect.all
                    [ \_ -> Expect.equal Nothing model.confirmRemoveScan
                    , \_ -> Expect.equal (Dict.singleton itemId deferredItem) model.scanQueue
                    , \_ -> Expect.equal Set.empty model.scanTombstones
                    , \_ -> Expect.equal NoEffect effect
                    ]
                    ()
        , test "ConfirmRemoveScan removes item, tombstones it, and fires DeleteScanItem" <|
            \() ->
                let
                    modelWithModal =
                        { baseModel | confirmRemoveScan = Just itemId }

                    ( model, effect ) =
                        Page.Scan.update (ConfirmRemoveScan itemId) modelWithModal
                in
                Expect.all
                    [ \_ -> Expect.equal Nothing model.confirmRemoveScan
                    , \_ -> Expect.equal Dict.empty model.scanQueue
                    , \_ -> Expect.equal (Set.singleton itemId) model.scanTombstones
                    , \_ -> Expect.equal (Batch [ DeleteScanItem itemId ]) effect
                    ]
                    ()
        , test "ConfirmRemoveScan clears ocrInFlight for the removed id (defensive)" <|
            \() ->
                let
                    modelWithInFlight =
                        { baseModel
                            | confirmRemoveScan = Just itemId
                            , ocrInFlight = Set.singleton itemId
                        }

                    ( model, _ ) =
                        Page.Scan.update (ConfirmRemoveScan itemId) modelWithInFlight
                in
                Expect.equal Set.empty model.ocrInFlight
        , test "ConfirmRemoveScan on a stale id is a clean no-op (modal still clears)" <|
            \() ->
                let
                    staleId =
                        "scan::0000000000000::0"

                    modelWithStaleModal =
                        { baseModel | confirmRemoveScan = Just staleId }

                    ( model, effect ) =
                        Page.Scan.update (ConfirmRemoveScan staleId) modelWithStaleModal
                in
                Expect.all
                    [ \_ -> Expect.equal Nothing model.confirmRemoveScan
                    , \_ -> Expect.equal (Dict.singleton itemId deferredItem) model.scanQueue
                    , \_ -> Expect.equal (Set.singleton staleId) model.scanTombstones
                    , \_ -> Expect.equal (Batch [ DeleteScanItem staleId ]) effect
                    ]
                    ()
        ]
