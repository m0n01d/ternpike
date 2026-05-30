module Data.Scan exposing
    ( CaptureRoute(..)
    , DraftFields
    , ExifPhase(..)
    , GeocodePhase(..)
    , OcrData
    , OcrFailureKind(..)
    , ScanCardState(..)
    , ScanItem
    , ScanStatus(..)
    , byoFailureKind
    , captureRoute
    , cardState
    , currentSchemaVersion
    , effectiveLocation
    , hostedFailureKind
    , idsWithExpectedExpense
    , maxOcrRetries
    , mergeHydratedQueue
    , mergeOcrIntoDraft
    , mintId
    , needsReview
    , ocrDataDecoder
    , ocrDataEncoder
    , ocrDataListDecoder
    , reconcileHydratedQueue
    , reconnectCandidates
    , scanItemDecoder
    , scanItemEncoder
    )

{-| Receipt-scan queue: one `ScanItem` per receipt the user has dropped
into the Scan tab, plus the OCR result the Anthropic API hands back and
any fields the user has typed by hand.

The queue is a `Dict String ScanItem` keyed by the item's durable id
(`scan::<millis>::<seq>` — see `Data.ScanItemId`). An item moves through
`ScanQueued → ScanProcessing → ScanReady → ScanSubmitted` on the online
happy path; an offline capture lands in `ScanDeferred` until the network
returns. Because the captured image plus the user's typed draft must
survive a reload, a `ScanItem` (de)serializes losslessly to the durable
store via `scanItemEncoder` / `scanItemDecoder`, and `reconcileHydratedQueue`
normalizes the queue at boot (in-flight statuses can't survive a reload —
no OCR request is still alive — so they reset to `ScanDeferred`, while
`ScanReady` / `ScanSubmitted` are preserved).

Why optional fields on `OcrData`: Anthropic returns "best effort" JSON
and any field may be missing or unreadable. The Add page fills them in
from `OcrData` and falls back to defaults for whatever's missing, so
making them required would force fake placeholder values into the
domain. `DraftFields` is `Maybe`-typed for the same reason — see its
own doc.

-}

import Data.Category as Category exposing (Category)
import Data.DateField as DateField exposing (DateField)
import Data.GeoPoint as GeoPoint exposing (GeoPoint)
import Data.Location exposing (LocationSource(..), LocationState(..))
import Data.Money as Money exposing (Money)
import Data.OcrPath exposing (OcrPath(..))
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod)
import Data.ScanItemId exposing (ScanItemId)
import Dict exposing (Dict)
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode
import Maybe.Extra
import Set exposing (Set)


{-| Lifecycle stage of one queued receipt.

  - `ScanDeferred` — captured offline (or while the network state is
    still unknown at boot): the image is persisted and the user may type
    fields by hand, but no OCR has run. A reconnect / retry later moves
    it on; `reconcileHydratedQueue` also parks any reload-orphaned
    in-flight item here.
  - `ScanProcessing` — OCR request in flight to Anthropic.
  - `ScanQueued` — file picked, not yet read into a data URL.
  - `ScanReady` — OCR returned (with or without data); user can review.
  - `ScanSubmitted` — review confirmed and the expense was saved; the
    card stays visible (greyed out) until "Clear submitted" is tapped.

-}
type ScanStatus
    = ScanDeferred
    | ScanProcessing
    | ScanQueued
    | ScanReady
    | ScanSubmitted


{-| Best-effort fields parsed from a receipt photo by the Anthropic OCR
prompt (see `Main.ocrSystemPrompt`).

Every field is optional because the model may fail to read any subset of
them — for example a faded thermal receipt can produce a clear amount
but unreadable date. The Add-page review step is the user's chance to
correct anything missing or wrong.

-}
type alias OcrData =
    { address : Maybe String
    , amount : Maybe Money
    , category : Maybe Category
    , date : Maybe DateField
    , longNote : Maybe String
    , merchant : Maybe String
    , note : Maybe String
    , paymentMethod : Maybe PaymentMethod
    }


{-| Phase of the EXIF-GPS extraction for one scan item.

  - `ExifChecking` — extraction in flight (port call out).
  - `ExifFound point` — photo had embedded GPS; coords are kept as a
    fallback for when no resolvable receipt address is available.
  - `ExifMissing` — extraction returned no GPS coords.

-}
type ExifPhase
    = ExifChecking
    | ExifFound GeoPoint
    | ExifMissing


{-| Phase of the address-geocode call for one scan item.

`Data.Scan` does not know how to dispatch the geocode HTTP call — that
lives in `Main.elm` because it needs `Creds`, the trip's tier, and the
active route. The phase here is what `Main` writes to and what
`effectiveLocation` reads when projecting back to a `LocationState`.

  - `GeocodeNotAttempted` — initial state; either OCR hasn't returned,
    OCR returned without an `address`, or the active trip's tier isn't
    paid (free users skip the call entirely).
  - `GeocodeRequested` — request fired; result still in flight.
  - `GeocodeResolved point` — Google returned coordinates.
  - `GeocodeMissed` — Google returned ZERO\_RESULTS, the request
    errored, or the network was offline. Caller falls through to
    EXIF / manual.

-}
type GeocodePhase
    = GeocodeMissed
    | GeocodeNotAttempted
    | GeocodeRequested
    | GeocodeResolved GeoPoint


{-| One receipt in the scan queue.

  - `draft` — fields the user has typed by hand while the item is
    deferred / under review, persisted so they survive a reload.
    `Nothing` until the user touches the form (see `DraftFields`).
  - `exif` — phase of the EXIF-GPS extraction (see `ExifPhase`).
  - `exifDebug` — raw EXIF dump shown in the "debug info" disclosure
    when EXIF parsing finds no GPS. Useful for diagnosing why a photo
    we'd expect to have coordinates didn't.
  - `expectedExpenseId` — the `ExpenseId` (as a `String`) the item's
    eventual save will write, stamped at submit so the PouchDB change
    echo can match the saved expense back to its queue item and clear
    it. `Nothing` until the item is submitted.
  - `geocode` — phase of the address-geocode call (see `GeocodePhase`).
  - `id` — durable, local-only key (`scan::<millis>::<seq>`); persisted
    to the offline scan store but never reaches PouchDB.
  - `imageUrl` — base64 data URL of the picked image, used as both the
    preview src and the OCR upload, and persisted so the photo survives
    a reload.
  - `lastError` — human-readable reason the most recent persist / retry
    attempt failed, distinct from `ocrError` (which is OCR-specific).
    `Nothing` when the last attempt succeeded.
  - `ocrData` — `Nothing` until OCR returns; `Just` even if the model
    extracted nothing (so we know it ran).
  - `ocrError` — human-readable reason the most recent OCR attempt
    failed (HTTP error, refusal, unparseable JSON, etc.). `Nothing`
    while OCR is in flight or after a successful read; surfaced on the
    Scan card so the user can tell why an item is in fill-manually
    mode instead of guessing.
  - `persistError` — `True` when the last write to the durable store
    failed, so the UI can surface a "couldn't save offline" warning.
  - `retryCount` — how many times the OCR / persist pipeline has been
    re-attempted for this item; drives backoff and a give-up cap.
  - `schemaVersion` — the `ScanItem` schema version the doc was written
    with, so a future field change can migrate stored docs (see
    `currentSchemaVersion`).
  - `status` — the lifecycle stage above.

EXIF and geocode are tracked as independent phases rather than a
single `LocationState` because they're driven by independent async
sources and the priority between them is non-trivial (geocode wins —
see `effectiveLocation` and the module-level doc on `Data.Location`).
Conflating them into one state machine, as the original
`locationState` field did, made it possible to represent
"OCR found an address but we never tried to geocode it" — a state the
type system should rule out.

-}
type alias ScanItem =
    { draft : Maybe DraftFields
    , exif : ExifPhase
    , exifDebug : String
    , expectedExpenseId : Maybe String
    , geocode : GeocodePhase
    , id : ScanItemId
    , imageUrl : String
    , lastError : Maybe String
    , ocrData : Maybe OcrData
    , ocrError : Maybe String
    , persistError : Bool
    , retryCount : Int
    , schemaVersion : Int
    , status : ScanStatus
    }


{-| Fields the user has typed (or corrected) by hand on the Add review
form while a scan item is deferred or under review, persisted onto the
item so they survive a reload.

**Every field is `Maybe`-typed on purpose — `DraftFields` is NOT a
`PendingEntry` clone.** A `PendingEntry` defaults `category` to `Fuel`
and `date` to today (and stores the rest as plain `String`s, where
`""` is indistinguishable from "untouched"). Those defaults are the
right shape for a brand-new form, but the wrong shape for a draft laid
on top of OCR output: persisting a defaulted `Fuel` / today over a
field the user never touched would silently clobber whatever OCR (or a
later retry) extracted. So `Nothing` here means "user hasn't set this —
fall through to `ocrData`, then to the form default," and only a `Just`
represents an actual user choice. This is the #93 sentinel lesson:
model "unset" as `Nothing`, never as a defaulted value that can't be
told apart from a real one.

  - `address` / `merchant` / `note` / `longNote` — `Nothing` for an
    untouched field (empty input is normalized to `Nothing`, never `""`).
  - `amount` — kept as the raw `String` the user is editing (so a
    half-typed `"12."` round-trips); `Nothing` / empty, never `"0"`.
  - `category` — `Just` only once the user picks one; no `Fuel` default.
  - `date` — `Just` only once the user sets one; no today default.
  - `locationState` — the form's current location provenance (manual
    pin, browser geo, skip, …), which is itself a closed sum so it
    needs no `Maybe` wrapper.
  - `paymentMethod` — `Just` only once the user picks one.

-}
type alias DraftFields =
    { address : Maybe String
    , amount : Maybe String
    , category : Maybe Category
    , date : Maybe DateField
    , locationState : LocationState
    , longNote : Maybe String
    , merchant : Maybe String
    , note : Maybe String
    , paymentMethod : Maybe PaymentMethod
    }


{-| The current `ScanItem` schema version. Stamped into every doc by
`scanItemEncoder` and read back by `scanItemDecoder` (defaulting to this
value when a legacy doc omits it) so a future field change can migrate
stored offline docs in place.
-}
currentSchemaVersion : Int
currentSchemaVersion =
    1


{-| Merge a user's typed `draft` over an OCR result, **blanks-only**: a
field the user actually set (a `Just` in `DraftFields`) wins; an untouched
field (`Nothing`) falls through to whatever OCR extracted. Every `OcrData`
field is covered.

This is the "fill blanks, never clobber user input" rule made pure. The
`category` and `date` fields are `Maybe` in `DraftFields` precisely so that
"untouched" is distinguishable from a real choice — an untouched `category`
is `Nothing` here (NOT `Fuel`), so it can't overwrite an OCR-read category,
and likewise an untouched `date` is `Nothing` (NOT today). The `amount`
draft is the raw string the user is editing; it's parsed through
`Money.fromDollarString` and only overrides when it parses to a real value.

    import Data.Category exposing (Category(..))
    import Data.DateField as DateField
    import Data.Location exposing (LocationState(..))
    import Data.Money as Money
    import Data.PaymentMethod exposing (PaymentMethod(..))

    -- An empty draft is the identity: OCR passes through untouched.
    mergeOcrIntoDraft
        { address = Nothing, amount = Nothing, category = Nothing, date = Nothing, locationState = LocationIdle, longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }
        { address = Just "1 Main St", amount = Just (Money.fromCents 1299), category = Just Food, date = DateField.fromIso "2024-05-21", longNote = Just "ln", merchant = Just "Trader Joe's", note = Just "n", paymentMethod = Just Cash }
    --> { address = Just "1 Main St", amount = Just (Money.fromCents 1299), category = Just Food, date = DateField.fromIso "2024-05-21", longNote = Just "ln", merchant = Just "Trader Joe's", note = Just "n", paymentMethod = Just Cash }

    -- A set draft field wins over OCR; untouched fields keep OCR.
    mergeOcrIntoDraft
        { address = Just "9 Draft Rd", amount = Just "5.00", category = Just Lodging, date = DateField.fromIso "2024-01-02", locationState = LocationIdle, longNote = Just "draft ln", merchant = Just "My Merchant", note = Just "draft note", paymentMethod = Just Credit }
        { address = Just "1 Main St", amount = Just (Money.fromCents 1299), category = Just Food, date = DateField.fromIso "2024-05-21", longNote = Just "ocr ln", merchant = Just "Trader Joe's", note = Just "ocr note", paymentMethod = Just Cash }
    --> { address = Just "9 Draft Rd", amount = Just (Money.fromCents 500), category = Just Lodging, date = DateField.fromIso "2024-01-02", longNote = Just "draft ln", merchant = Just "My Merchant", note = Just "draft note", paymentMethod = Just Credit }

    -- Untouched category/date do NOT fall back to Fuel/today — they stay OCR.
    mergeOcrIntoDraft
        { address = Nothing, amount = Nothing, category = Nothing, date = Nothing, locationState = LocationIdle, longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }
        { address = Nothing, amount = Nothing, category = Just Food, date = DateField.fromIso "2024-05-21", longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }
    --> { address = Nothing, amount = Nothing, category = Just Food, date = DateField.fromIso "2024-05-21", longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }

    -- An unparseable draft amount can't clobber a real OCR amount.
    mergeOcrIntoDraft
        { address = Nothing, amount = Just "abc", category = Nothing, date = Nothing, locationState = LocationIdle, longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }
        { address = Nothing, amount = Just (Money.fromCents 1299), category = Nothing, date = Nothing, longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }
    --> { address = Nothing, amount = Just (Money.fromCents 1299), category = Nothing, date = Nothing, longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }

-}
mergeOcrIntoDraft : DraftFields -> OcrData -> OcrData
mergeOcrIntoDraft draft ocr =
    { address = Maybe.Extra.or draft.address ocr.address
    , amount = Maybe.Extra.or (Maybe.andThen Money.fromDollarString draft.amount) ocr.amount
    , category = Maybe.Extra.or draft.category ocr.category
    , date = Maybe.Extra.or draft.date ocr.date
    , longNote = Maybe.Extra.or draft.longNote ocr.longNote
    , merchant = Maybe.Extra.or draft.merchant ocr.merchant
    , note = Maybe.Extra.or draft.note ocr.note
    , paymentMethod = Maybe.Extra.or draft.paymentMethod ocr.paymentMethod
    }


{-| Project the scan item's EXIF + geocode phases into the
form-facing `LocationState`. This is the priority enforcement point.

The order of precedence (highest first), per `Data.Location`:

1.  **A draft manual pin** — if the user dropped a map pin while reviewing
    the item offline, it was persisted into `draft.locationState` (the
    `BackToQueue` write-back, #372). The user's pin is their final say, so
    it beats everything — even a geocode that only resolves on a late
    reconnect can't clobber it across a reload.
2.  **Geocode** — the receipt's printed address wins over EXIF (see
    `Data.Location` for why).
3.  **EXIF GPS** — falls through when geocode missed / wasn't attempted.

Only a `ManualPin` draft is honored here; the form's other location
sources (browser geo, skip, idle, resolving) are transient UI state that
`syncScanLocationToForm` already guards, and surfacing them from a
persisted draft would defeat a later geocode improving on them.

    import Data.GeoPoint as GeoPoint
    import Data.Location exposing (LocationSource(..), LocationState(..))
    import Data.ScanItemId

    -- A draft manual pin beats a late geocode — the user's pin is final.
    effectiveLocation
        { draft = Just { address = Nothing, amount = Nothing, category = Nothing, date = Nothing, locationState = LocationGot (GeoPoint.fromDegrees 61.2 -149.9) ManualPin, longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }
        , exif = ExifMissing
        , exifDebug = ""
        , expectedExpenseId = Nothing
        , geocode = GeocodeResolved (GeoPoint.fromDegrees 48.8 2.3)
        , id = Data.ScanItemId.fromString "scan::0::0"
        , imageUrl = ""
        , lastError = Nothing
        , ocrData = Nothing
        , ocrError = Nothing
        , persistError = False
        , retryCount = 0
        , schemaVersion = 1
        , status = ScanReady
        }
    --> LocationGot (GeoPoint.fromDegrees 61.2 -149.9) ManualPin

    -- Geocode resolved: receipt's printed address wins, even when EXIF
    -- has its own coords (the photo was taken at home).
    effectiveLocation
        { draft = Nothing
        , exif = ExifFound (GeoPoint.fromDegrees 37.7 -122.4)
        , exifDebug = ""
        , expectedExpenseId = Nothing
        , geocode = GeocodeResolved (GeoPoint.fromDegrees 48.8 2.3)
        , id = Data.ScanItemId.fromString "scan::0::0"
        , imageUrl = ""
        , lastError = Nothing
        , ocrData = Nothing
        , ocrError = Nothing
        , persistError = False
        , retryCount = 0
        , schemaVersion = 1
        , status = ScanReady
        }
    --> LocationGot (GeoPoint.fromDegrees 48.8 2.3) Geocoded

    -- Geocode in flight: surface as "resolving" so the form doesn't
    -- offer the manual-pin prompt yet.
    effectiveLocation
        { draft = Nothing
        , exif = ExifMissing
        , exifDebug = ""
        , expectedExpenseId = Nothing
        , geocode = GeocodeRequested
        , id = Data.ScanItemId.fromString "scan::0::0"
        , imageUrl = ""
        , lastError = Nothing
        , ocrData = Nothing
        , ocrError = Nothing
        , persistError = False
        , retryCount = 0
        , schemaVersion = 1
        , status = ScanReady
        }
    --> LocationResolving

    -- Geocode missed / not attempted: fall through to EXIF if present.
    effectiveLocation
        { draft = Nothing
        , exif = ExifFound (GeoPoint.fromDegrees 37.7 -122.4)
        , exifDebug = ""
        , expectedExpenseId = Nothing
        , geocode = GeocodeMissed
        , id = Data.ScanItemId.fromString "scan::0::0"
        , imageUrl = ""
        , lastError = Nothing
        , ocrData = Nothing
        , ocrError = Nothing
        , persistError = False
        , retryCount = 0
        , schemaVersion = 1
        , status = ScanReady
        }
    --> LocationGot (GeoPoint.fromDegrees 37.7 -122.4) ExifGps

    -- Nothing worked: surface "no GPS" so the user gets the manual
    -- pin button.
    effectiveLocation
        { draft = Nothing
        , exif = ExifMissing
        , exifDebug = ""
        , expectedExpenseId = Nothing
        , geocode = GeocodeMissed
        , id = Data.ScanItemId.fromString "scan::0::0"
        , imageUrl = ""
        , lastError = Nothing
        , ocrData = Nothing
        , ocrError = Nothing
        , persistError = False
        , retryCount = 0
        , schemaVersion = 1
        , status = ScanReady
        }
    --> LocationNoExifGps

-}
effectiveLocation : ScanItem -> LocationState
effectiveLocation item =
    case draftManualPin item.draft of
        Just pinned ->
            pinned

        Nothing ->
            case item.geocode of
                GeocodeResolved point ->
                    LocationGot point Geocoded

                GeocodeRequested ->
                    LocationResolving

                GeocodeMissed ->
                    fromExif item.exif

                GeocodeNotAttempted ->
                    fromExif item.exif


{-| The user's persisted manual map pin, if any. Only a `ManualPin`
draft `locationState` counts — every other source is transient form state
that must not override a later geocode (see `effectiveLocation`).
-}
draftManualPin : Maybe DraftFields -> Maybe LocationState
draftManualPin maybeDraft =
    case maybeDraft of
        Just draft ->
            case draft.locationState of
                LocationGot point ManualPin ->
                    Just (LocationGot point ManualPin)

                _ ->
                    Nothing

        Nothing ->
            Nothing


fromExif : ExifPhase -> LocationState
fromExif phase =
    case phase of
        ExifFound point ->
            LocationGot point ExifGps

        ExifChecking ->
            LocationResolving

        ExifMissing ->
            LocationNoExifGps


{-| True when any structural field — amount, merchant, or date — is
missing from the OCR result. The user must fill these in before the
expense is safe to file; the badge on the Scan card pulls focus to
items that need attention.

    -- amount missing
    needsReview { amount = Nothing, merchant = Just "Trattoria", date = Nothing, address = Nothing, category = Nothing, longNote = Nothing, note = Nothing, paymentMethod = Nothing }
    --> True

    -- merchant missing
    needsReview { amount = Nothing, merchant = Nothing, date = Nothing, address = Nothing, category = Nothing, longNote = Nothing, note = Nothing, paymentMethod = Nothing }
    --> True

-}
needsReview : OcrData -> Bool
needsReview ocr =
    ocr.amount == Nothing || ocr.merchant == Nothing || ocr.date == Nothing


{-| Which visual card a `ScanItem` renders as in the scan queue.

This is the single source of truth shared by both `Pages.Scan.viewScanCardBody`
and `Verify.Specs.ScanQueueCard` — changing one without changing the other
produces a compiler error (the `case` must be exhaustive on both sides).

Constructors (alphabetised):

  - `CardDeferred` — durably saved offline; OCR will run on reconnect.
  - `CardNeedsReview` — OCR returned but a structural field (amount, merchant,
    or date) is missing; the "Needs review" badge appears.
  - `CardOcrFailed` — OCR ran but produced no usable data (`ocrData = Nothing`).
  - `CardPersistError` — the durable-store write failed (`persistError = True`)
    or IndexedDB is unavailable (`storageAvailable = False`); the image may not
    survive a reload.
  - `CardProcessing` — OCR in flight (`ScanProcessing`) or file freshly picked
    but not yet read (`ScanQueued`).
  - `CardReady` — OCR returned with all structural fields present; ready to
    review without the "Needs review" badge.
  - `CardSubmitted` — the expense was filed; the card stays visible (greyed out)
    until "Clear submitted" is tapped.
  - `CardUnavailable` — OCR path is `Unscannable` while deferred (tier lapsed /
    no BYO key); receipt is saved but can't be scanned automatically.

-}
type ScanCardState
    = CardDeferred
    | CardNeedsReview
    | CardOcrFailed
    | CardPersistError
    | CardProcessing
    | CardReady
    | CardSubmitted
    | CardUnavailable


{-| Derive the card state for a queued scan item, given the current OCR path
and storage availability. This is the pure decision the view and the Verify
surface both call — see `ScanCardState` for the full case matrix.

    import Data.OcrPath exposing (OcrPath(..))
    import Data.ScanItemId

    -- A deferred item with storage available and a hosted path → CardDeferred.
    cardState { storageAvailable = True }
        { draft = Nothing
        , exif = ExifMissing
        , exifDebug = ""
        , expectedExpenseId = Nothing
        , geocode = GeocodeNotAttempted
        , id = Data.ScanItemId.fromString "scan::0::0"
        , imageUrl = ""
        , lastError = Nothing
        , ocrData = Nothing
        , ocrError = Nothing
        , persistError = False
        , retryCount = 0
        , schemaVersion = 1
        , status = ScanDeferred
        }
        HostedPath
    --> CardDeferred

    -- A persist-error item → CardPersistError (beats ocrPath).
    cardState { storageAvailable = True }
        { draft = Nothing
        , exif = ExifMissing
        , exifDebug = ""
        , expectedExpenseId = Nothing
        , geocode = GeocodeNotAttempted
        , id = Data.ScanItemId.fromString "scan::0::0"
        , imageUrl = ""
        , lastError = Nothing
        , ocrData = Nothing
        , ocrError = Nothing
        , persistError = True
        , retryCount = 0
        , schemaVersion = 1
        , status = ScanDeferred
        }
        HostedPath
    --> CardPersistError

    -- ScanSubmitted → CardSubmitted regardless of ocrPath.
    cardState { storageAvailable = True }
        { draft = Nothing
        , exif = ExifMissing
        , exifDebug = ""
        , expectedExpenseId = Nothing
        , geocode = GeocodeNotAttempted
        , id = Data.ScanItemId.fromString "scan::0::0"
        , imageUrl = ""
        , lastError = Nothing
        , ocrData = Nothing
        , ocrError = Nothing
        , persistError = False
        , retryCount = 0
        , schemaVersion = 1
        , status = ScanSubmitted
        }
        HostedPath
    --> CardSubmitted

-}
cardState : { storageAvailable : Bool } -> ScanItem -> OcrPath -> ScanCardState
cardState { storageAvailable } item ocrPath =
    case item.status of
        ScanDeferred ->
            if item.persistError || not storageAvailable then
                CardPersistError

            else
                case ocrPath of
                    Unscannable ->
                        CardUnavailable

                    ByoPath _ ->
                        CardDeferred

                    HostedPath ->
                        CardDeferred

        ScanProcessing ->
            CardProcessing

        ScanQueued ->
            CardProcessing

        ScanReady ->
            case item.ocrData of
                Just ocr ->
                    if needsReview ocr then
                        CardNeedsReview

                    else
                        CardReady

                Nothing ->
                    CardOcrFailed

        ScanSubmitted ->
            CardSubmitted


{-| The queue keys of every item whose `expectedExpenseId` matches the
given expense id. Drives the change-feed echo delete: when an expense
arrives over the change feed, the items that were stamped to produce it
(at submit) are the ones to retire. Returns `[]` when nothing matches —
the idempotency property that makes a re-delivered echo a no-op.
-}
idsWithExpectedExpense : String -> Dict String ScanItem -> List String
idsWithExpectedExpense expenseId queue =
    queue
        |> Dict.filter (\_ item -> item.expectedExpenseId == Just expenseId)
        |> Dict.keys


{-| What to do with a freshly-captured image, given connectivity and the
OCR path. The Scan `update` branches on this in `GotFileUrl`.

  - `Now` — fire OCR immediately (online, and a scannable path exists).
  - `Deferred` — persist the image and park it as `ScanDeferred`; no OCR
    yet. The user may type fields by hand and a later retry runs OCR.
  - `Manual` — no scannable path at all (free tier, no BYO key): the
    image lands in `ScanReady` so the user fills the form manually,
    same as today's online `Unscannable` behavior.

-}
type CaptureRoute
    = Deferred
    | Manual
    | Now


{-| Decide the capture route from connectivity and the resolved OCR path.

Offline (treating an `Unknown` network as offline-safe — see
`Data.Sync.isOffline`) always defers _when there is a scannable path_,
so the boot window can't fire a doomed OCR call. With no scannable path
the route is always `Manual` regardless of connectivity: there is
nothing to defer to, so we go straight to the manual-fill card.

    import Data.OcrPath exposing (OcrPath(..))

    -- Online + a hosted (paid) path → scan now.
    captureRoute { offline = False } HostedPath
    --> Now

    -- Offline + a hosted (paid) path → defer; OCR runs on reconnect.
    captureRoute { offline = True } HostedPath
    --> Deferred

    -- No scannable path → always manual, online or off.
    captureRoute { offline = False } Unscannable
    --> Manual

    captureRoute { offline = True } Unscannable
    --> Manual

-}
captureRoute : { offline : Bool } -> OcrPath -> CaptureRoute
captureRoute { offline } ocrPath =
    case ocrPath of
        Unscannable ->
            Manual

        ByoPath _ ->
            if offline then
                Deferred

            else
                Now

        HostedPath ->
            if offline then
                Deferred

            else
                Now



-- RECONNECT ORCHESTRATION (#373)


{-| How many times the OCR pipeline may be re-attempted for one item
before it gives up and surfaces a terminal error. Only a real retryable
HTTP response (429 / 5xx with a body) bumps the count — a bare
connectivity flap (network error / timeout / status 0) returns the item
to `ScanDeferred` without spending from this budget, so flapping
connectivity on the days-later reconnect can't burn through it.

    maxOcrRetries
    --> 3

-}
maxOcrRetries : Int
maxOcrRetries =
    3


{-| Classify an OCR failure as transient (a connectivity flap that must
NOT spend the retry budget) or terminal (a real server response that
should). Drives the reconnect-retry bookkeeping in `Page.Scan`.

  - `Transient` — the request never got a response: the connection died,
    timed out, or returned status 0. Return the item to `ScanDeferred`
    and try again on the next reconnect WITHOUT incrementing `retryCount`.
  - `Retryable` — a real retryable HTTP response (429 / 500 / 502 / 503
    with a body): bump `retryCount`; at `maxOcrRetries` give up with a
    terminal error.
  - `Permanent` — any other failure (400, 401, 402, 403, parse error,
    refusal): there is no point retrying, so go terminal immediately.

-}
type OcrFailureKind
    = Permanent
    | Retryable
    | Transient


{-| Classify a hosted-proxy OCR failure from its raw HTTP status.

`0` is the "connection died, never got a response" sentinel the proxy
port reports for a network drop — treat it as a flap (`Transient`).
`429` and the retryable `5xx` family are real server responses worth a
bounded retry.

`401` / `403` are also `Transient`. The proxy auth rides on the same
CouchDB session that re-handshakes on reconnect, so a scan fired the
instant the network returns — before the token is accepted again — gets
a 401/403 that is NOT a permanent auth failure, it's the reconnect
window (#400). Requeuing transiently (no `retryCount` burn, no terminal
`ScanReady` error) lets the next retry succeed instead of permanently
stranding the receipt. A genuinely-expired session is handled
out-of-band: sync reports `AuthExpired` and the app drops to the guest
screen, leaving the scan flow entirely.

Everything else is `Permanent`.

    hostedFailureKind 0
    --> Transient

    hostedFailureKind 401
    --> Transient

    hostedFailureKind 403
    --> Transient

    hostedFailureKind 503
    --> Retryable

    hostedFailureKind 402
    --> Permanent

-}
hostedFailureKind : Int -> OcrFailureKind
hostedFailureKind status =
    if status == 0 || status == 401 || status == 403 then
        Transient

    else if status == 429 || status == 500 || status == 502 || status == 503 then
        Retryable

    else
        Permanent


{-| Classify a BYO (direct-Anthropic) OCR failure from its
already-collapsed error string. The direct path runs through
`Effect.ocrResponseToResult`, which folds the `Http.Error` down to a
human string before it reaches `Page.Scan`, so the status is recovered
from the sentinel substrings that helper emits:

  - "Network error …" / "… timed out …" → the request never landed
    (`Transient`); a flap, don't spend the budget.

  - "(HTTP 429)" / "(HTTP 500|502|503)" → a real retryable response
    (`Retryable`).

  - anything else (parse error, refusal, 4xx) → `Permanent`.

    byoFailureKind "Network error — check your connection and try again"
    --> Transient

    byoFailureKind "Anthropic error (HTTP 503): overloaded"
    --> Retryable

    byoFailureKind "OCR request failed (HTTP 429)"
    --> Retryable

    byoFailureKind "Couldn't parse receipt JSON: unexpected token"
    --> Permanent

-}
byoFailureKind : String -> OcrFailureKind
byoFailureKind err =
    if String.contains "Network error" err || String.contains "timed out" err then
        Transient

    else if
        String.contains "(HTTP 429)" err
            || String.contains "(HTTP 500)" err
            || String.contains "(HTTP 502)" err
            || String.contains "(HTTP 503)" err
    then
        Retryable

    else
        Permanent


{-| Pick the ids of the deferred scan items to start OCR for on
reconnect, honouring the concurrency cap.

`slots = max 0 (tierCap - inFlightCount)`; candidates are ONLY items in
`ScanDeferred` (never an already-processing / ready / submitted item),
excluding any id already in flight, any item whose last persist failed
(`persistError == True` — its image may not be durable, so don't spend
an OCR call on it), and any id in `excluded`. `excluded` is how the
dispatch-next path keeps a just-failed item that bounced back to
`ScanDeferred` from being retried in the same tick (no backoff): it
waits for the next `Synced` edge instead. The first `slots` such ids
(Dict order, i.e. id-sorted, which is capture order) are returned.

Idempotent by construction: once the in-flight set is at the cap,
`slots` is `0` and the result is `[]`, so the oscillating `Synced` edge
(Synced → Syncing → Synced each replication cycle) can fire this as
often as it likes without double-dispatching.

    import Dict
    import Set

    -- No free slots → dispatch nothing, however many are deferred.
    reconnectCandidates 1 1 Set.empty Dict.empty
    --> []

-}
reconnectCandidates : Int -> Int -> Set String -> Dict String ScanItem -> List String
reconnectCandidates tierCap inFlightCount excluded queue =
    let
        slots : Int
        slots =
            max 0 (tierCap - inFlightCount)
    in
    queue
        |> Dict.toList
        |> List.filter
            (\( id, item ) ->
                item.status
                    == ScanDeferred
                    && not item.persistError
                    && not (Set.member id excluded)
            )
        |> List.take slots
        |> List.map Tuple.first


{-| Decode one OCR JSON object into an `OcrData`. Every field is
optional — Anthropic's "best effort" parser may omit any of them, return
JSON `null`, or hand back a value the strict per-field decoder doesn't
recognize (e.g. `"paymentMethod": "visa"` when the type only models
`cash` / `credit`). All such cases collapse to `Nothing` on that one
field rather than failing the whole receipt — which would otherwise
fail `Json.Decode.list` and lose every receipt in a batch photo. The
Add-page review step is where the user fills anything that came back
empty.

`address` was added in #150 so receipts batch-scanned at home can be
geocoded to where they were actually issued (paid tier) or manually
pinned (free tier).

-}
ocrDataDecoder : Json.Decode.Decoder OcrData
ocrDataDecoder =
    Json.Decode.succeed OcrData
        |> Pipeline.optional "address" (lenient Json.Decode.string) Nothing
        |> Pipeline.optional "amount" (lenient Money.decoder) Nothing
        |> Pipeline.optional "category" (Json.Decode.map Just (Json.Decode.map Category.fromString Json.Decode.string)) Nothing
        |> Pipeline.optional "date" (lenient DateField.decoder) Nothing
        |> Pipeline.optional "longNote" (lenient Json.Decode.string) Nothing
        |> Pipeline.optional "merchant" (lenient Json.Decode.string) Nothing
        |> Pipeline.optional "note" (lenient Json.Decode.string) Nothing
        |> Pipeline.optional "paymentMethod" (lenient paymentMethodDecoder) Nothing


{-| Wrap a strict decoder so that JSON `null`, the wrong JSON type, or
any other decode failure on this single field collapses to `Nothing`
instead of failing the surrounding object. Used on every field of
`OcrData` whose strict decoder could otherwise reject Anthropic's
output and take the whole list with it.
-}
lenient : Json.Decode.Decoder a -> Json.Decode.Decoder (Maybe a)
lenient strict =
    Json.Decode.oneOf
        [ Json.Decode.null Nothing
        , Json.Decode.map Just strict
        , Json.Decode.succeed Nothing
        ]


{-| Map an Anthropic-returned payment-method string to a
`PaymentMethod`. Anything outside the recognized set causes a decode
failure here, but `lenient` upstream converts that into a `Nothing`
field so the rest of the receipt still parses.
-}
paymentMethodDecoder : Json.Decode.Decoder PaymentMethod
paymentMethodDecoder =
    Json.Decode.string
        |> Json.Decode.andThen
            (\s ->
                case PaymentMethod.fromString s of
                    Just pm ->
                        Json.Decode.succeed pm

                    Nothing ->
                        Json.Decode.fail ("Unknown paymentMethod: " ++ s)
            )


{-| Decode either a single OCR object or a JSON array of them into a
list. The Anthropic prompt asks for an array, but legacy single-object
responses still parse for backward compatibility.
-}
ocrDataListDecoder : Json.Decode.Decoder (List OcrData)
ocrDataListDecoder =
    Json.Decode.oneOf
        [ Json.Decode.list ocrDataDecoder
        , Json.Decode.map List.singleton ocrDataDecoder
        ]


{-| Encode an `OcrData` for the durable scan store. Reuses the field
codecs (`Money.encoder` for `amount`, `DateField.encoder` for `date`,
`Category.label` / `PaymentMethod.toString` for the enums) so what we
persist round-trips back through `ocrDataDecoder`. `Nothing` fields are
written as JSON `null`, which `ocrDataDecoder` reads back as `Nothing`.
-}
ocrDataEncoder : OcrData -> Json.Encode.Value
ocrDataEncoder ocr =
    Json.Encode.object
        [ ( "address", maybe Json.Encode.string ocr.address )
        , ( "amount", maybe Money.encoder ocr.amount )
        , ( "category", maybe (Category.label >> Json.Encode.string) ocr.category )
        , ( "date", maybe DateField.encoder ocr.date )
        , ( "longNote", maybe Json.Encode.string ocr.longNote )
        , ( "merchant", maybe Json.Encode.string ocr.merchant )
        , ( "note", maybe Json.Encode.string ocr.note )
        , ( "paymentMethod", maybe (PaymentMethod.toString >> Json.Encode.string) ocr.paymentMethod )
        ]


{-| Encode a `Maybe a` as either the wrapped value (via `enc`) or JSON
`null`. The matching `lenient` / `optional` decoders read `null` back as
`Nothing`.
-}
maybe : (a -> Json.Encode.Value) -> Maybe a -> Json.Encode.Value
maybe enc m =
    case m of
        Just a ->
            enc a

        Nothing ->
            Json.Encode.null



-- DURABLE IDS


{-| Mint a durable scan-queue id from a capture timestamp (millis since
epoch) and the monotonic per-session counter (`AuthState.scanSeq`).

The counter — not the file's position in its batch — is the collision
guard: two photos picked in the same millisecond still get distinct ids
because the counter advances per item.

    mintId 1716200000000 7
    --> "scan::1716200000000::7"

-}
mintId : Int -> Int -> String
mintId millis seq =
    "scan::" ++ String.fromInt millis ++ "::" ++ String.fromInt seq



-- DURABLE STORE CODECS


{-| Encode a `ScanItem` for the durable (IndexedDB) scan store. Every
field is written so the item — image, OCR result, user draft, status,
retry bookkeeping — survives a reload losslessly. `id` is flattened to
its raw `String`; the `schemaVersion` is stamped at `currentSchemaVersion`.
-}
scanItemEncoder : ScanItem -> Json.Encode.Value
scanItemEncoder item =
    Json.Encode.object
        [ ( "draft", maybe draftFieldsEncoder item.draft )
        , ( "exif", exifPhaseEncoder item.exif )
        , ( "exifDebug", Json.Encode.string item.exifDebug )
        , ( "expectedExpenseId", maybe Json.Encode.string item.expectedExpenseId )
        , ( "geocode", geocodePhaseEncoder item.geocode )
        , ( "id", Json.Encode.string (Data.ScanItemId.toString item.id) )
        , ( "imageUrl", Json.Encode.string item.imageUrl )
        , ( "lastError", maybe Json.Encode.string item.lastError )
        , ( "ocrData", maybe ocrDataEncoder item.ocrData )
        , ( "ocrError", maybe Json.Encode.string item.ocrError )
        , ( "persistError", Json.Encode.bool item.persistError )
        , ( "retryCount", Json.Encode.int item.retryCount )
        , ( "schemaVersion", Json.Encode.int currentSchemaVersion )
        , ( "status", statusEncoder item.status )
        ]


{-| Decode one `ScanItem` from the durable store. Tolerant of legacy /
partial docs: a missing `status` defaults to `ScanDeferred` (the safe
"needs another pass" state), a missing `draft` to `Nothing`, and a
missing `schemaVersion` to `currentSchemaVersion`. The booleans and
counters likewise default so an older doc that predates those fields
still decodes.
-}
scanItemDecoder : Json.Decode.Decoder ScanItem
scanItemDecoder =
    Json.Decode.succeed ScanItem
        |> Pipeline.optional "draft" (Json.Decode.nullable draftFieldsDecoder) Nothing
        |> Pipeline.optional "exif" exifPhaseDecoder ExifMissing
        |> Pipeline.optional "exifDebug" Json.Decode.string ""
        |> Pipeline.optional "expectedExpenseId" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "geocode" geocodePhaseDecoder GeocodeNotAttempted
        |> Pipeline.required "id" (Json.Decode.map Data.ScanItemId.fromString Json.Decode.string)
        |> Pipeline.optional "imageUrl" Json.Decode.string ""
        |> Pipeline.optional "lastError" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "ocrData" (Json.Decode.nullable ocrDataDecoder) Nothing
        |> Pipeline.optional "ocrError" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "persistError" Json.Decode.bool False
        |> Pipeline.optional "retryCount" Json.Decode.int 0
        |> Pipeline.optional "schemaVersion" Json.Decode.int currentSchemaVersion
        |> Pipeline.optional "status" statusDecoder ScanDeferred


draftFieldsEncoder : DraftFields -> Json.Encode.Value
draftFieldsEncoder draft =
    Json.Encode.object
        [ ( "address", maybe Json.Encode.string draft.address )
        , ( "amount", maybe Json.Encode.string draft.amount )
        , ( "category", maybe (Category.label >> Json.Encode.string) draft.category )
        , ( "date", maybe DateField.encoder draft.date )
        , ( "locationState", locationStateEncoder draft.locationState )
        , ( "longNote", maybe Json.Encode.string draft.longNote )
        , ( "merchant", maybe Json.Encode.string draft.merchant )
        , ( "note", maybe Json.Encode.string draft.note )
        , ( "paymentMethod", maybe (PaymentMethod.toString >> Json.Encode.string) draft.paymentMethod )
        ]


draftFieldsDecoder : Json.Decode.Decoder DraftFields
draftFieldsDecoder =
    Json.Decode.succeed DraftFields
        |> Pipeline.optional "address" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "amount" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "category" (Json.Decode.nullable (Json.Decode.map Category.fromString Json.Decode.string)) Nothing
        |> Pipeline.optional "date" (lenient DateField.decoder) Nothing
        |> Pipeline.optional "locationState" locationStateDecoder LocationIdle
        |> Pipeline.optional "longNote" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "merchant" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "note" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "paymentMethod" (lenient paymentMethodDecoder) Nothing


statusEncoder : ScanStatus -> Json.Encode.Value
statusEncoder status =
    Json.Encode.string (statusToString status)


statusToString : ScanStatus -> String
statusToString status =
    case status of
        ScanDeferred ->
            "deferred"

        ScanProcessing ->
            "processing"

        ScanQueued ->
            "queued"

        ScanReady ->
            "ready"

        ScanSubmitted ->
            "submitted"


statusDecoder : Json.Decode.Decoder ScanStatus
statusDecoder =
    Json.Decode.map
        (\s ->
            case s of
                "deferred" ->
                    ScanDeferred

                "processing" ->
                    ScanProcessing

                "queued" ->
                    ScanQueued

                "ready" ->
                    ScanReady

                "submitted" ->
                    ScanSubmitted

                _ ->
                    ScanDeferred
        )
        Json.Decode.string


exifPhaseEncoder : ExifPhase -> Json.Encode.Value
exifPhaseEncoder phase =
    case phase of
        ExifChecking ->
            Json.Encode.object [ ( "phase", Json.Encode.string "checking" ) ]

        ExifFound point ->
            Json.Encode.object
                [ ( "phase", Json.Encode.string "found" )
                , ( "point", GeoPoint.encoder point )
                ]

        ExifMissing ->
            Json.Encode.object [ ( "phase", Json.Encode.string "missing" ) ]


exifPhaseDecoder : Json.Decode.Decoder ExifPhase
exifPhaseDecoder =
    Json.Decode.field "phase" Json.Decode.string
        |> Json.Decode.andThen
            (\phase ->
                case phase of
                    "found" ->
                        Json.Decode.map
                            (\maybePoint ->
                                case maybePoint of
                                    Just point ->
                                        ExifFound point

                                    Nothing ->
                                        ExifMissing
                            )
                            (Json.Decode.field "point" GeoPoint.decoderPair)

                    "checking" ->
                        Json.Decode.succeed ExifChecking

                    _ ->
                        Json.Decode.succeed ExifMissing
            )


geocodePhaseEncoder : GeocodePhase -> Json.Encode.Value
geocodePhaseEncoder phase =
    case phase of
        GeocodeMissed ->
            Json.Encode.object [ ( "phase", Json.Encode.string "missed" ) ]

        GeocodeNotAttempted ->
            Json.Encode.object [ ( "phase", Json.Encode.string "notAttempted" ) ]

        GeocodeRequested ->
            Json.Encode.object [ ( "phase", Json.Encode.string "requested" ) ]

        GeocodeResolved point ->
            Json.Encode.object
                [ ( "phase", Json.Encode.string "resolved" )
                , ( "point", GeoPoint.encoder point )
                ]


geocodePhaseDecoder : Json.Decode.Decoder GeocodePhase
geocodePhaseDecoder =
    Json.Decode.field "phase" Json.Decode.string
        |> Json.Decode.andThen
            (\phase ->
                case phase of
                    "resolved" ->
                        Json.Decode.map
                            (\maybePoint ->
                                case maybePoint of
                                    Just point ->
                                        GeocodeResolved point

                                    Nothing ->
                                        GeocodeMissed
                            )
                            (Json.Decode.field "point" GeoPoint.decoderPair)

                    "missed" ->
                        Json.Decode.succeed GeocodeMissed

                    "requested" ->
                        Json.Decode.succeed GeocodeRequested

                    _ ->
                        Json.Decode.succeed GeocodeNotAttempted
            )


locationStateEncoder : LocationState -> Json.Encode.Value
locationStateEncoder state =
    case state of
        LocationGot point source ->
            Json.Encode.object
                [ ( "kind", Json.Encode.string "got" )
                , ( "point", GeoPoint.encoder point )
                , ( "source", Json.Encode.string (locationSourceToString source) )
                ]

        LocationIdle ->
            Json.Encode.object [ ( "kind", Json.Encode.string "idle" ) ]

        LocationNoExifGps ->
            Json.Encode.object [ ( "kind", Json.Encode.string "noExifGps" ) ]

        LocationResolving ->
            Json.Encode.object [ ( "kind", Json.Encode.string "resolving" ) ]

        LocationSkipped ->
            Json.Encode.object [ ( "kind", Json.Encode.string "skipped" ) ]


locationStateDecoder : Json.Decode.Decoder LocationState
locationStateDecoder =
    Json.Decode.field "kind" Json.Decode.string
        |> Json.Decode.andThen
            (\kind ->
                case kind of
                    "got" ->
                        Json.Decode.map2
                            (\maybePoint source ->
                                case maybePoint of
                                    Just point ->
                                        LocationGot point source

                                    Nothing ->
                                        LocationNoExifGps
                            )
                            (Json.Decode.field "point" GeoPoint.decoderPair)
                            (Json.Decode.field "source" locationSourceDecoder)

                    "skipped" ->
                        Json.Decode.succeed LocationSkipped

                    "resolving" ->
                        Json.Decode.succeed LocationResolving

                    "noExifGps" ->
                        Json.Decode.succeed LocationNoExifGps

                    _ ->
                        Json.Decode.succeed LocationIdle
            )


locationSourceToString : LocationSource -> String
locationSourceToString source =
    case source of
        BrowserGeo ->
            "browserGeo"

        ExifGps ->
            "exifGps"

        Geocoded ->
            "geocoded"

        ManualPin ->
            "manualPin"


locationSourceDecoder : Json.Decode.Decoder LocationSource
locationSourceDecoder =
    Json.Decode.map
        (\s ->
            case s of
                "browserGeo" ->
                    BrowserGeo

                "exifGps" ->
                    ExifGps

                "geocoded" ->
                    Geocoded

                _ ->
                    ManualPin
        )
        Json.Decode.string



-- BOOT RECONCILE


{-| Normalize a hydrated scan queue at boot.

In-flight statuses can't survive a reload — no OCR request is still
alive after the page is gone — so any `ScanProcessing` / `ScanQueued`
item is reset to `ScanDeferred`, where the retry / reconnect machinery
(later issues) can pick it back up. `ScanReady` and `ScanSubmitted` are
left untouched: a `ScanReady` item still has its parsed OCR result, and
a `ScanSubmitted` item's expense is already filed.

This is deliberately NOT where delete-vs-keep is decided for submitted
items. At boot `AuthState.expenses` is still empty, so "this submitted
scan's expense exists, drop the card" can't be answered yet — the
PouchDB change echo owns that (a later issue).

    import Data.ScanItemId
    import Dict

    Dict.get "a"
        (reconcileHydratedQueue
            (Dict.singleton "a"
                { draft = Nothing
                , exif = ExifMissing
                , exifDebug = ""
                , expectedExpenseId = Nothing
                , geocode = GeocodeNotAttempted
                , id = Data.ScanItemId.fromString "a"
                , imageUrl = ""
                , lastError = Nothing
                , ocrData = Nothing
                , ocrError = Nothing
                , persistError = False
                , retryCount = 0
                , schemaVersion = 1
                , status = ScanProcessing
                }
            )
        )
        |> Maybe.map .status
    --> Just ScanDeferred

-}
reconcileHydratedQueue : Dict String ScanItem -> Dict String ScanItem
reconcileHydratedQueue queue =
    Dict.map (\_ item -> { item | status = reconcileStatus item.status }) queue


{-| Merge a freshly-hydrated durable queue into the live in-memory queue
at boot / re-login, respecting the hydration-window tombstones (#374).

`Dict.union inMemory (hydrated minus tombstones)`:

  - the in-memory item wins a key collision (a live capture / OCR result
    is never overwritten by its stale persisted form), and
  - any id tombstoned since the last load — a submit-cleared card (the
    `ExpenseChanged` echo), a consumed multi-receipt split source, or a
    `ClearDoneItems` removal — is dropped from the hydrated side, so a
    `getAll` that completes after the delete can't resurrect it.

`inMemory` is assumed already-normalized (live); only `hydrated` is
filtered, since tombstones can only mask just-removed durable rows.

-}
mergeHydratedQueue : Set String -> Dict String ScanItem -> Dict String ScanItem -> Dict String ScanItem
mergeHydratedQueue tombstones inMemory hydrated =
    Dict.union inMemory
        (Dict.filter (\key _ -> not (Set.member key tombstones)) hydrated)


reconcileStatus : ScanStatus -> ScanStatus
reconcileStatus status =
    case status of
        ScanProcessing ->
            ScanDeferred

        ScanQueued ->
            ScanDeferred

        ScanDeferred ->
            ScanDeferred

        ScanReady ->
            ScanReady

        ScanSubmitted ->
            ScanSubmitted
