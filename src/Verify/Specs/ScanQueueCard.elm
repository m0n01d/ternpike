module Verify.Specs.ScanQueueCard exposing (Input, results, seededItem, seededStorageAvailable, surface)

{-| Verification unit for the scan-queue card-state decision.

`Data.Scan.cardState` is the single source of truth shared by both
`Pages.Scan.viewScanCardBody` and this surface — changing one without the other
produces a compiler error (exhaustive `case` on `ScanCardState`).

One fixture per `ScanCardState` constructor, plus one adversarial `probe`
fixture that must FAIL to prove the harness catches lies. Seeding for the DOM
tier sets `route = RouteScan <tripId>` with a minimal trip + one item in
`AuthState.scanQueue` per fixture.

@docs Input, results, seededItem, seededStorageAvailable, surface

-}

import Data.DateField as DateField
import Data.Money as Money
import Data.OcrPath as OcrPath exposing (OcrPath(..))
import Data.Scan as Scan exposing (ScanCardState(..), ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


{-| The slice this unit observes. `corrupt = True` (probe only) flips the
card-state label so at least one invariant fires.
-}
type alias Input =
    { corrupt : Bool
    , item : ScanItem
    , ocrPath : OcrPath
    , storageAvailable : Bool
    }


{-| Build an honest (non-corrupt) input for a fixture.
-}
cardInput : ScanItem -> OcrPath -> Bool -> Input
cardInput item ocrPath storageAvailable =
    { corrupt = False
    , item = item
    , ocrPath = ocrPath
    , storageAvailable = storageAvailable
    }


{-| Derive the card's observable surface. Delegates to `Scan.cardState` — the
same function the real `viewScanCardBody` calls — so the surface cannot drift
from the view without a compiler error.
-}
surface : Input -> Contract.Surface
surface input =
    let
        state : ScanCardState
        state =
            if input.corrupt then
                corruptedState
                    (Scan.cardState
                        { storageAvailable = input.storageAvailable }
                        input.item
                        input.ocrPath
                    )

            else
                Scan.cardState
                    { storageAvailable = input.storageAvailable }
                    input.item
                    input.ocrPath
    in
    [ ( "card-state", cardStateKey state ) ]


{-| The pure-tier results for this unit, collected by `Verify.Registry`.
-}
results : List Core.RunResult
results =
    Runner.runUnit spec


{-| The scan item seeded for a given fixture name. Used by `Main.applyUnitSeed`
to put the right item into `AuthState.scanQueue` for the DOM tier.
-}
seededItem : String -> ScanItem
seededItem fixture =
    case fixture of
        "deferred" ->
            deferredItem

        "needs-review" ->
            needsReviewItem

        "ocr-failed" ->
            ocrFailedItem

        "persist-error" ->
            persistErrorItem

        "processing" ->
            processingItem

        "ready" ->
            readyItem

        "submitted" ->
            submittedItem

        "unavailable" ->
            unavailableItem

        _ ->
            deferredItem


{-| Storage availability seeded for a given fixture name. Used by
`Main.applyUnitSeed`.
-}
seededStorageAvailable : String -> Bool
seededStorageAvailable fixture =
    case fixture of
        "persist-error" ->
            False

        _ ->
            True



-- INTERNALS


sampleId : ScanItemId.ScanItemId
sampleId =
    ScanItemId.fromString "scan::1716200000000::0"


baseItem : ScanItem
baseItem =
    { draft = Nothing
    , exif = Scan.ExifMissing
    , exifDebug = ""
    , expectedExpenseId = Nothing
    , geocode = Scan.GeocodeNotAttempted
    , id = sampleId
    , imageUrl = ""
    , lastError = Nothing
    , ocrData = Nothing
    , ocrError = Nothing
    , persistError = False
    , retryCount = 0
    , schemaVersion = 1
    , status = ScanDeferred
    }


deferredItem : ScanItem
deferredItem =
    { baseItem | status = ScanDeferred }


persistErrorItem : ScanItem
persistErrorItem =
    { baseItem | persistError = True, status = ScanDeferred }


unavailableItem : ScanItem
unavailableItem =
    { baseItem | status = ScanDeferred }


processingItem : ScanItem
processingItem =
    { baseItem | status = ScanProcessing }


needsReviewItem : ScanItem
needsReviewItem =
    -- amount = Nothing, merchant = Just, date = Nothing → needsReview = True
    let
        ocr : Scan.OcrData
        ocr =
            { address = Nothing
            , amount = Nothing
            , category = Nothing
            , date = Nothing
            , longNote = Nothing
            , merchant = Just "Trailside Diner"
            , note = Nothing
            , paymentMethod = Nothing
            }
    in
    { baseItem | ocrData = Just ocr, status = ScanReady }


readyItem : ScanItem
readyItem =
    -- All structural fields present → needsReview = False
    let
        ocr : Scan.OcrData
        ocr =
            { address = Nothing
            , amount = Just (Money.fromCents 1250)
            , category = Nothing
            , date = DateField.fromIso "2024-05-21"
            , longNote = Nothing
            , merchant = Just "Glacier Café"
            , note = Nothing
            , paymentMethod = Nothing
            }
    in
    { baseItem | ocrData = Just ocr, status = ScanReady }


ocrFailedItem : ScanItem
ocrFailedItem =
    -- ScanReady with ocrData = Nothing → CardOcrFailed
    { baseItem | ocrData = Nothing, status = ScanReady }


submittedItem : ScanItem
submittedItem =
    { baseItem | status = ScanSubmitted }


spec : Spec.UnitSpec Input
spec =
    { fixtures =
        [ { input = cardInput deferredItem HostedPath True, name = "deferred", probe = False }
        , { input = cardInput needsReviewItem HostedPath True, name = "needs-review", probe = False }
        , { input = cardInput ocrFailedItem HostedPath True, name = "ocr-failed", probe = False }
        , { input = cardInput persistErrorItem HostedPath False, name = "persist-error", probe = False }
        , { input = cardInput processingItem HostedPath True, name = "processing", probe = False }
        , { input = cardInput readyItem HostedPath True, name = "ready", probe = False }
        , { input = cardInput submittedItem HostedPath True, name = "submitted", probe = False }
        , { input = cardInput unavailableItem Unscannable True, name = "unavailable", probe = False }
        , -- Adversarial probe: a normal deferred item with corrupt surface claiming
          -- "submitted". The deferredScannableYieldsDeferred invariant must fire.
          { input = { corrupt = True, item = deferredItem, ocrPath = HostedPath, storageAvailable = True }
          , name = "probe-deferred-claims-submitted"
          , probe = True
          }
        ]
    , invariants =
        [ { name = "persistError or no-storage yields persist-error card", check = persistErrorYieldsPersistError }
        , { name = "ScanSubmitted yields submitted card", check = submittedYieldsSubmitted }
        , { name = "offline-deferred scannable yields deferred card", check = deferredScannableYieldsDeferred }
        , { name = "ScanReady with needsReview data yields needs-review card", check = readyNeedsReviewYieldsNeedsReview }
        , { name = "Unscannable deferred yields unavailable card", check = unscannableYieldsUnavailable }
        ]
    , name = "ScanQueueCard"
    , surface = surface
    }


cardStateKey : ScanCardState -> String
cardStateKey state =
    case state of
        CardDeferred ->
            "deferred"

        CardNeedsReview ->
            "needs-review"

        CardOcrFailed ->
            "ocr-failed"

        CardPersistError ->
            "persist-error"

        CardProcessing ->
            "processing"

        CardReady ->
            "ready"

        CardSubmitted ->
            "submitted"

        CardUnavailable ->
            "unavailable"


{-| Flip the card state to a different (wrong) value for the probe fixture.
Any state other than `CardSubmitted` is flipped to `CardSubmitted`, so the
invariants that check for non-submitted states will fire.
-}
corruptedState : ScanCardState -> ScanCardState
corruptedState state =
    case state of
        CardDeferred ->
            CardSubmitted

        CardNeedsReview ->
            CardSubmitted

        CardOcrFailed ->
            CardSubmitted

        CardPersistError ->
            CardSubmitted

        CardProcessing ->
            CardSubmitted

        CardReady ->
            CardSubmitted

        CardSubmitted ->
            CardDeferred

        CardUnavailable ->
            CardSubmitted



-- INVARIANTS


persistErrorYieldsPersistError : Input -> Contract.Surface -> Maybe String
persistErrorYieldsPersistError input observed =
    if input.item.persistError || not input.storageAvailable then
        case value "card-state" observed of
            Just "persist-error" ->
                Nothing

            other ->
                Just
                    ("persistError/no-storage produced '"
                        ++ Maybe.withDefault "nothing" other
                        ++ "' instead of 'persist-error'"
                    )

    else
        Nothing


submittedYieldsSubmitted : Input -> Contract.Surface -> Maybe String
submittedYieldsSubmitted input observed =
    if input.item.status /= ScanSubmitted then
        Nothing

    else
        case value "card-state" observed of
            Just "submitted" ->
                Nothing

            other ->
                Just
                    ("ScanSubmitted produced '"
                        ++ Maybe.withDefault "nothing" other
                        ++ "' instead of 'submitted'"
                    )


deferredScannableYieldsDeferred : Input -> Contract.Surface -> Maybe String
deferredScannableYieldsDeferred input observed =
    if input.item.status /= ScanDeferred then
        Nothing

    else if input.item.persistError || not input.storageAvailable then
        Nothing

    else
        case input.ocrPath of
            OcrPath.Unscannable ->
                Nothing

            OcrPath.ByoPath _ ->
                checkIs "deferred" observed

            OcrPath.HostedPath ->
                checkIs "deferred" observed


readyNeedsReviewYieldsNeedsReview : Input -> Contract.Surface -> Maybe String
readyNeedsReviewYieldsNeedsReview input observed =
    if input.item.status /= ScanReady then
        Nothing

    else
        case input.item.ocrData of
            Nothing ->
                Nothing

            Just ocr ->
                if not (Scan.needsReview ocr) then
                    Nothing

                else
                    checkIs "needs-review" observed


unscannableYieldsUnavailable : Input -> Contract.Surface -> Maybe String
unscannableYieldsUnavailable input observed =
    if input.item.status /= ScanDeferred then
        Nothing

    else if input.item.persistError || not input.storageAvailable then
        Nothing

    else
        case input.ocrPath of
            OcrPath.Unscannable ->
                checkIs "unavailable" observed

            OcrPath.ByoPath _ ->
                Nothing

            OcrPath.HostedPath ->
                Nothing


checkIs : String -> Contract.Surface -> Maybe String
checkIs expected observed =
    case value "card-state" observed of
        Just actual ->
            if actual == expected then
                Nothing

            else
                Just ("expected '" ++ expected ++ "' but got '" ++ actual ++ "'")

        Nothing ->
            Just ("expected '" ++ expected ++ "' but card-state was absent")


value : String -> Contract.Surface -> Maybe String
value key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
