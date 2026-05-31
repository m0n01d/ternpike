module Page.Scan exposing (Model, update)

{-| The Scan / OCR feature's `update`, carved out of `Main.updateAuth`
(#368) and re-typed over an `Effect` seam (#369).

`update` operates over a narrow [`Model`](#Model) record slice of
`AuthState` — only the fields the Scan flows actually touch — rather than
the full `AuthState`. `AuthState` embeds `key : Nav.Key`, which cannot be
hand-constructed, so a test can't build a seed `AuthState`; the slice is
fully constructible and so makes the Scan slice drivable under
`avh4/elm-program-test`. The router (`Main.updateAuth`) builds the slice
from `AuthState`, runs `update`, and merges the result back.

Side effects are returned as a description (`Effect`) rather than a raw
`Cmd`; the router lifts via `Effect.perform`, tests via `Effect.simulate`.

@docs Model, update

-}

import Data.Auth exposing (AppConfig, Creds)
import Data.Category
import Data.Currency
import Data.DateField as DateField
import Data.Expense exposing (Expense)
import Data.FuelGrade as FuelGrade
import Data.Gallons as Gallons
import Data.GeoPoint as GeoPoint
import Data.Location
import Data.Money as Money
import Data.Navigation exposing (Route(..), Tab(..))
import Data.OcrPath as OcrPath
import Data.PendingEntry as PendingEntry exposing (PendingForm(..))
import Data.PricePerGallon as PricePerGallon
import Data.Scan as Scan exposing (CaptureRoute(..), ExifPhase(..), GeocodePhase(..), ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Data.SharedTrips exposing (SharedTrips)
import Data.Sync exposing (NetworkState)
import Data.Tier as Tier
import Data.Trip as Trip exposing (Trip)
import Data.Trips as Trips exposing (TripsState(..))
import Data.UserId exposing (UserId)
import Dict
import Effect exposing (Effect(..))
import Json.Decode
import Json.Encode
import List.Extra
import Maybe.Extra
import Msg.Scan exposing (Msg(..))
import Routing
import Set
import Time


{-| The slice of `AuthState` the Scan flows read or write. Constructible
without a `Nav.Key`, so a test can seed it directly (see the module doc).

The `currentUser` / `sharedTrips` / `tier` trio satisfies
`Data.Trip.TierContext` so `geocodeDispatch` can resolve the trip's
effective tier; the rest are the form / queue / routing fields the
handlers touch.

-}
type alias Model =
    { activeScanItemId : Maybe ScanItemId.ScanItemId
    , basePath : String
    , config : AppConfig
    , confirmRemoveScan : Maybe String
    , creds : Creds
    , currentUser : UserId
    , duplicateWarning : Maybe Expense
    , error : Maybe String
    , form : PendingForm
    , network : NetworkState
    , ocrInFlight : Set.Set String
    , route : Route
    , scanQueue : Dict.Dict String ScanItem
    , scanSeq : Int
    , scanTombstones : Set.Set String
    , sharedTrips : SharedTrips
    , storageAvailable : Bool
    , tier : Tier.Tier
    , today : DateField.DateField
    , trips : TripsState
    }


{-| Handle a Scan message against the Scan [`Model`](#Model) slice.
Returns the new slice plus an [`Effect`](Effect#Effect) describing any
side effects; the caller (`Main.updateAuth`) merges the slice back into
`AuthState` and lifts the effect via `Effect.perform`.
-}
update : Msg.Scan.Msg -> Model -> ( Model, Effect )
update msg as_ =
    case msg of
        FilesSelected files ->
            -- Capture the real wall-clock millis before minting ids, so the
            -- durable `scan::<millis>::<seq>` id reflects when the user
            -- actually snapped the receipt. `FilesStamped` does the minting.
            ( as_, Effect.StampCapture files )

        FilesStamped now files ->
            let
                millis : Int
                millis =
                    Time.posixToMillis now

                -- Durable, collision-free ids: the capture millis is the
                -- high-order segment and the per-session counter
                -- (`scanSeq`) advances per item so two captures in the
                -- same millisecond can't collide (see `Scan.mintId`).
                indexed =
                    List.indexedMap (\i f -> ( Scan.mintId millis (as_.scanSeq + i), f )) files

                newQueue =
                    List.foldl (\( id, _ ) d -> Dict.insert id (freshScanItem id) d) as_.scanQueue indexed

                urlEffects =
                    List.map (\( id, f ) -> Effect.FetchFileUrl id f) indexed
            in
            ( { as_ | scanQueue = newQueue, scanSeq = as_.scanSeq + List.length files }
            , Batch urlEffects
            )

        GotFileUrl itemId dataUrl ->
            let
                ocrPath =
                    OcrPath.resolve as_.config.anthropicKey as_.tier

                route : Scan.CaptureRoute
                route =
                    Scan.captureRoute { offline = Data.Sync.isOffline as_.network } ocrPath

                -- EXIF runs locally (`fetch(dataUrl)`, no network) on every
                -- path, so GPS is captured even for a deferred receipt.
                exifEffect : Effect
                exifEffect =
                    Effect.ExtractExifGps { dataUrl = dataUrl, id = itemId }
            in
            case route of
                Now ->
                    let
                        updatedQueue =
                            Dict.update itemId (Maybe.map (\i -> { i | imageUrl = dataUrl, status = ScanProcessing })) as_.scanQueue
                    in
                    ( { as_ | scanQueue = updatedQueue }
                    , Batch
                        [ -- Always route through the JS-side downscaler before
                          -- the OCR call. Anthropic's image limit is 5 MiB on
                          -- the base64 payload; modern phone JPEGs routinely
                          -- run 6–8 MB so we'd otherwise 400 on every photo.
                          -- We use the EXIF data URL for GPS extraction in
                          -- parallel because exifr needs the original bytes.
                          Effect.PrepareOcrImage { dataUrl = dataUrl, id = itemId, maxBytes = ocrMaxBase64Bytes }
                        , exifEffect
                        ]
                    )

                Deferred ->
                    -- Offline (or boot-window `Unknown`): park the capture as
                    -- `ScanDeferred` and persist it IMMEDIATELY, so an iOS
                    -- background-kill right after capture can't lose the
                    -- image. The raw data URL is stored as-is; a later
                    -- downscale-then-replace pass is a future optimization.
                    case Dict.get itemId as_.scanQueue of
                        Nothing ->
                            ( as_, NoEffect )

                        Just item ->
                            let
                                deferredItem =
                                    { item | imageUrl = dataUrl, status = ScanDeferred }

                                updatedQueue =
                                    Dict.insert itemId deferredItem as_.scanQueue
                            in
                            ( { as_ | scanQueue = updatedQueue }
                            , Batch
                                [ Effect.SaveScanItem (Scan.scanItemEncoder deferredItem)
                                , exifEffect
                                ]
                            )

                Manual ->
                    -- No scannable path (free tier, no BYO key): land in
                    -- `ScanReady` so the user fills the form by hand. Same
                    -- as today's online `Unscannable` behavior; no OCR.
                    let
                        updatedQueue =
                            Dict.update itemId (Maybe.map (\i -> { i | imageUrl = dataUrl, status = ScanReady })) as_.scanQueue
                    in
                    ( { as_ | scanQueue = updatedQueue }
                    , exifEffect
                    )

        OcrImagePrepared payload ->
            case Dict.get payload.id as_.scanQueue of
                Nothing ->
                    -- item was cleared/submitted while resize was in flight — no-op
                    ( as_, NoEffect )

                Just _ ->
                    if payload.error /= "" then
                        let
                            updatedQueue =
                                Dict.update payload.id
                                    (Maybe.map
                                        (\i ->
                                            { i
                                                | ocrData = Nothing
                                                , ocrError = Just ("Couldn't prepare image for OCR: " ++ payload.error)
                                                , status = ScanReady
                                            }
                                        )
                                    )
                                    as_.scanQueue
                        in
                        -- Terminal `ScanReady` (resize failed) — persist so a
                        -- reload doesn't drop the item back to processing.
                        ( { as_ | scanQueue = updatedQueue }, persistItem payload.id updatedQueue )

                    else
                        let
                            updatedQueue =
                                Dict.update payload.id
                                    (Maybe.map (\i -> { i | imageUrl = payload.dataUrl }))
                                    as_.scanQueue
                        in
                        -- Persist the downscaled image alongside firing OCR so
                        -- a background-kill mid-call keeps the smaller bytes.
                        ( { as_ | scanQueue = updatedQueue }
                        , Batch
                            [ persistItem payload.id updatedQueue
                            , Effect.MakeOcrCall
                                { backendUrl = as_.config.backendUrl
                                , body = ocrRequestBody (extractBase64 payload.dataUrl) (getMimeType payload.dataUrl)
                                , itemId = payload.id
                                , path = OcrPath.resolve as_.config.anthropicKey as_.tier
                                }
                            ]
                        )

        GotOcrResult itemId result ->
            -- Direct (BYO-key) Anthropic response. `Effect.ocrResponseToResult`
            -- has already collapsed the `Http.Error` to a string, so a
            -- transient flap (network drop / timeout) is recovered from the
            -- sentinel substring via `Scan.byoFailureKind`.
            let
                outcome : OcrOutcome
                outcome =
                    case result of
                        Err httpErr ->
                            OcrFailed (Scan.byoFailureKind httpErr) httpErr

                        Ok responseBody ->
                            outcomeFromBody responseBody
            in
            finishOcr itemId outcome as_

        ScanProxyResult { body, itemId, ok, status } ->
            -- Hosted-proxy response. The raw `status` is intact here, so the
            -- transient-vs-terminal split goes through `Scan.hostedFailureKind`
            -- (status 0 = connection died = flap; 401 / 403 = reconnect
            -- auth-handshake window = flap, see #400).
            let
                outcome : OcrOutcome
                outcome =
                    if ok then
                        outcomeFromBody body

                    else if status == 402 then
                        -- Genuine tier gate (payment required): the user is on
                        -- a free tier hitting the hosted proxy. Permanent — no
                        -- retry will help, surface the upgrade prompt.
                        OcrFailed Scan.Permanent "Hosted scanning requires an Osprey or Trailblazer subscription."

                    else
                        -- Everything else, including 401 / 403, is classified
                        -- by `Scan.hostedFailureKind`. A reconnect-time 401/403
                        -- is the CouchDB-session re-handshake window, NOT a
                        -- permanent auth failure (a truly-expired session is
                        -- caught out-of-band via sync `AuthExpired` →
                        -- guest screen). Treating it transiently requeues the
                        -- item WITHOUT burning `retryCount`, so the next
                        -- reconnect retry succeeds instead of permanently
                        -- stranding the receipt (#400).
                        OcrFailed (Scan.hostedFailureKind status)
                            ("Hosted scan failed (HTTP " ++ String.fromInt status ++ "): " ++ body)
            in
            finishOcr itemId outcome as_

        RetryDeferredScans ->
            -- Connectivity returned (the proven `Synced` sync edge, dispatched
            -- from `Main.SyncStateMsg`). Fire OCR for as many `ScanDeferred`
            -- items as the tier concurrency cap allows. Idempotent: with the
            -- in-flight set already at the cap, `dispatchOnReconnect` returns
            -- no candidates and emits no effects.
            let
                ( newQueue, newInFlight, effects ) =
                    dispatchOnReconnect Set.empty as_
            in
            ( { as_ | ocrInFlight = newInFlight, scanQueue = newQueue }
            , Batch effects
            )

        GotExifCoords itemId (Just lat) (Just lon) _ ->
            let
                point =
                    GeoPoint.fromDegrees lat lon

                newQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | exif = ExifFound point })) as_.scanQueue
            in
            ( syncScanLocationToForm itemId { as_ | scanQueue = newQueue }
            , persistItem itemId newQueue
            )

        GotExifCoords itemId _ _ debug ->
            let
                newQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | exif = ExifMissing, exifDebug = debug })) as_.scanQueue
            in
            ( syncScanLocationToForm itemId { as_ | scanQueue = newQueue }
            , persistItem itemId newQueue
            )

        GotGeocodeResult itemId result ->
            let
                newPhase =
                    case result of
                        Ok geo ->
                            case ( geo.lat, geo.lon ) of
                                ( Just lat, Just lon ) ->
                                    GeocodeResolved (GeoPoint.fromDegrees lat lon)

                                _ ->
                                    GeocodeMissed

                        Err _ ->
                            GeocodeMissed

                newQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | geocode = newPhase })) as_.scanQueue
            in
            ( syncScanLocationToForm itemId { as_ | scanQueue = newQueue }
            , persistItem itemId newQueue
            )

        GotMintedScanIds itemId results now ->
            -- The deferred split for a multi-receipt OCR success. The
            -- `Time.now` resolved, so mint durable `scan::<millis>::<seq>`
            -- ids (fresh capture millis, the per-session `scanSeq` as the
            -- collision suffix) for each parsed receipt and fan them out as
            -- `ScanReady` children. The source item's typed `draft` is merged
            -- into CHILD 0 ONLY (an offline draft describes one receipt, not
            -- N) — the rest carry no draft. Every child is persisted; the
            -- consumed source row is deleted from the durable store so a late
            -- `getAll` can't rehydrate it as a phantom.
            case Dict.get itemId as_.scanQueue of
                Nothing ->
                    -- Source cleared / submitted while `Time.now` was in
                    -- flight — nothing to split. Drop the source row anyway
                    -- (idempotent delete) so no orphan can resurface.
                    ( as_, Effect.DeleteScanItem itemId )

                Just source ->
                    let
                        millis : Int
                        millis =
                            Time.posixToMillis now

                        indexed : List ( String, Scan.ScanItem )
                        indexed =
                            List.indexedMap
                                (\i data ->
                                    let
                                        rawId : String
                                        rawId =
                                            Scan.mintId millis (as_.scanSeq + i)

                                        mergedData : Scan.OcrData
                                        mergedData =
                                            case ( i, source.draft ) of
                                                ( 0, Just draft ) ->
                                                    Scan.mergeOcrIntoDraft draft data

                                                _ ->
                                                    data
                                    in
                                    ( rawId
                                    , { draft =
                                            if i == 0 then
                                                source.draft

                                            else
                                                Nothing
                                      , exif = source.exif
                                      , exifDebug = source.exifDebug
                                      , expectedExpenseId = Nothing
                                      , geocode = source.geocode
                                      , id = ScanItemId.fromString rawId
                                      , imageUrl = source.imageUrl
                                      , lastError = Nothing
                                      , ocrData = Just mergedData
                                      , ocrError = Nothing
                                      , persistError = False
                                      , retryCount = source.retryCount
                                      , schemaVersion = Scan.currentSchemaVersion
                                      , status = ScanReady
                                      }
                                    )
                                )
                                results

                        newQueue : Dict.Dict String Scan.ScanItem
                        newQueue =
                            List.foldl
                                (\( id, item ) d -> Dict.insert id item d)
                                (Dict.remove itemId as_.scanQueue)
                                indexed

                        persistEffects : List Effect
                        persistEffects =
                            List.map
                                (\( _, item ) -> Effect.SaveScanItem (Scan.scanItemEncoder item))
                                indexed
                    in
                    ( { as_
                        | scanQueue = newQueue
                        , scanSeq = as_.scanSeq + List.length results
                      }
                    , Batch (Effect.DeleteScanItem itemId :: persistEffects)
                    )

        ReviewScanItem itemId ->
            case Dict.get itemId as_.scanQueue of
                Nothing ->
                    ( as_, NoEffect )

                Just item ->
                    let
                        newRoute =
                            case Routing.routeTripId as_.route of
                                Just tid ->
                                    RouteAdd tid

                                Nothing ->
                                    as_.route
                    in
                    ( { as_
                        | activeScanItemId = Just (ScanItemId.fromString itemId)
                        , duplicateWarning = Nothing
                        , error = Nothing
                        , form = FreshForm (seedPending as_.today item)
                        , route = newRoute
                      }
                    , NoEffect
                    )

        BackToQueue ->
            let
                newRoute =
                    case Routing.routeTripId as_.route of
                        Just tid ->
                            RouteScan tid

                        Nothing ->
                            as_.route

                navEffect : Effect
                navEffect =
                    case Routing.routeTripId as_.route of
                        Just tid ->
                            Effect.Navigate (Routing.tabToPath as_.basePath tid ScanTab)

                        Nothing ->
                            NoEffect

                -- Persist whatever the user typed onto the active item's
                -- `draft` so it survives a reload (today this discarded the
                -- form). Only fields the user actually set become a `Just`
                -- in `DraftFields`; untouched fields stay `Nothing` so a
                -- later OCR retry isn't clobbered by Fuel/today defaults.
                persisted : Maybe ( Dict.Dict String ScanItem, Effect )
                persisted =
                    activeItem as_
                        |> Maybe.map
                            (\( itemId, item ) ->
                                let
                                    draft =
                                        formToDraft as_.today (PendingEntry.formPending as_.form)

                                    updatedItem =
                                        { item | draft = Just draft }
                                in
                                ( Dict.insert itemId updatedItem as_.scanQueue
                                , Effect.SaveScanItem (Scan.scanItemEncoder updatedItem)
                                )
                            )

                ( newQueue, persistEffect ) =
                    Maybe.withDefault ( as_.scanQueue, NoEffect ) persisted
            in
            ( { as_
                | activeScanItemId = Nothing
                , form = FreshForm (PendingEntry.defaultPendingEntry as_.today)
                , route = newRoute
                , scanQueue = newQueue
              }
            , Batch [ persistEffect, navEffect ]
            )

        ClearDoneItems ->
            -- Drop every `ScanSubmitted` card. Each removed id is deleted
            -- from the durable store AND tombstoned, so a `loadScanQueue`
            -- that completes after this clear (a hydration-window race)
            -- can't resurrect a card the user just dismissed. The delete is
            -- idempotent (absent-key `delete` is a no-op).
            let
                clearedIds : List String
                clearedIds =
                    as_.scanQueue
                        |> Dict.filter (\_ i -> i.status == ScanSubmitted)
                        |> Dict.keys

                newQueue : Dict.Dict String ScanItem
                newQueue =
                    Dict.filter (\_ i -> i.status /= ScanSubmitted) as_.scanQueue
            in
            ( { as_
                | scanQueue = newQueue
                , scanTombstones = List.foldl Set.insert as_.scanTombstones clearedIds
              }
            , Batch (List.map Effect.DeleteScanItem clearedIds)
            )

        RequestRemoveScan itemId ->
            -- Open the confirm modal for this item. No deletion yet.
            ( { as_ | confirmRemoveScan = Just itemId }
            , NoEffect
            )

        CancelRemoveScan ->
            -- Dismiss the confirm modal without deleting anything.
            ( { as_ | confirmRemoveScan = Nothing }
            , NoEffect
            )

        ConfirmRemoveScan itemId ->
            -- Remove the item from the in-memory queue, tombstone it so a
            -- mid-flight `loadScanQueue` can't resurrect it (#374 resurrect-
            -- bug guard), and fire the durable-store delete. If the id is no
            -- longer in the queue (submitted/cleared while the modal was
            -- open), Dict.remove is a clean no-op and the modal still clears.
            ( { as_
                | confirmRemoveScan = Nothing
                , ocrInFlight = Set.remove itemId as_.ocrInFlight
                , scanQueue = Dict.remove itemId as_.scanQueue
                , scanTombstones = Set.insert itemId as_.scanTombstones
              }
            , Batch [ Effect.DeleteScanItem itemId ]
            )



-- SCAN QUEUE


freshScanItem : String -> ScanItem
freshScanItem id =
    { draft = Nothing
    , exif = ExifChecking
    , exifDebug = ""
    , expectedExpenseId = Nothing
    , geocode = GeocodeNotAttempted
    , id = ScanItemId.fromString id
    , imageUrl = ""
    , lastError = Nothing
    , ocrData = Nothing
    , ocrError = Nothing
    , persistError = False
    , retryCount = 0
    , schemaVersion = Scan.currentSchemaVersion
    , status = ScanQueued
    }


{-| The queue item the user is currently reviewing, if any. Pairs the
durable id (the `Dict` key) with the item, so write-back can re-insert.
-}
activeItem : Model -> Maybe ( String, ScanItem )
activeItem as_ =
    as_.activeScanItemId
        |> Maybe.map ScanItemId.toString
        |> Maybe.andThen (\id -> Dict.get id as_.scanQueue |> Maybe.map (Tuple.pair id))


{-| Persist the item at `id` in `queue` to the durable store, if it's
present. A missing id (the item was cleared mid-flight) is a no-op. Every
queue-mutating handler routes through this so the durable store tracks the
in-memory queue and a reload can't lose a status / location / OCR change.
-}
persistItem : String -> Dict.Dict String ScanItem -> Effect
persistItem id queue =
    Dict.get id queue
        |> Maybe.map (Scan.scanItemEncoder >> Effect.SaveScanItem)
        |> Maybe.withDefault NoEffect


{-| Seed the Add-review form for a scan item, layering the user's typed
`draft` over the OCR result over the bare defaults. A deferred item with
no OCR seeds entirely from the draft (or defaults); a reviewed OCR item
shows OCR values that any prior draft edits override.
-}
seedPending : DateField.DateField -> ScanItem -> PendingEntry.PendingEntry
seedPending today item =
    let
        ocr =
            item.ocrData

        draft =
            item.draft

        fromOcr : (Scan.OcrData -> Maybe a) -> Maybe a
        fromOcr get =
            Maybe.andThen get ocr

        fromDraft : (Scan.DraftFields -> Maybe a) -> Maybe a
        fromDraft get =
            Maybe.andThen get draft

        layeredString : (Scan.DraftFields -> Maybe String) -> (Scan.OcrData -> Maybe String) -> String
        layeredString getDraft getOcr =
            Maybe.Extra.or (fromDraft getDraft) (fromOcr getOcr)
                |> Maybe.withDefault ""
    in
    { address = layeredString .address .address
    , amount =
        Maybe.Extra.or
            (fromDraft .amount)
            (fromOcr .amount |> Maybe.map Money.toDollarString)
            |> Maybe.withDefault ""
    , category =
        Maybe.Extra.or (fromDraft .category) (fromOcr .category)
            |> Maybe.withDefault Data.Category.Fuel
    , currency = Data.Currency.USD
    , date =
        Maybe.Extra.or (fromDraft .date) (fromOcr .date)
            |> Maybe.withDefault today
            |> DateField.toIso
    , fuelGallons =
        fromOcr .fuelDetail |> Maybe.andThen .gallons |> Maybe.map Gallons.toInputString |> Maybe.withDefault ""
    , fuelGrade =
        fromOcr .fuelDetail |> Maybe.andThen .grade |> Maybe.map FuelGrade.display |> Maybe.withDefault ""
    , fuelPricePerGallon =
        fromOcr .fuelDetail |> Maybe.andThen .pricePerGallon |> Maybe.map PricePerGallon.toInputString |> Maybe.withDefault ""
    , locationState =
        case draft of
            Just d ->
                d.locationState

            Nothing ->
                Scan.effectiveLocation item
    , longNote = layeredString .longNote .longNote
    , merchant = layeredString .merchant .merchant
    , note = layeredString .note .note
    , paymentMethod = Maybe.Extra.or (fromDraft .paymentMethod) (fromOcr .paymentMethod)
    }


{-| Project the in-progress form back into a `DraftFields` for persistence.
Empty strings and the bare Fuel / today defaults collapse to `Nothing`
(the #93 sentinel rule): only fields the user actually set are captured,
so a later OCR retry isn't clobbered by a defaulted value.
-}
formToDraft : DateField.DateField -> PendingEntry.PendingEntry -> Scan.DraftFields
formToDraft today pending =
    let
        nonEmpty : String -> Maybe String
        nonEmpty s =
            if String.trim s == "" then
                Nothing

            else
                Just s
    in
    { address = nonEmpty pending.address
    , amount = nonEmpty pending.amount
    , category =
        if pending.category == Data.Category.Fuel then
            Nothing

        else
            Just pending.category
    , date =
        if pending.date == DateField.toIso today then
            Nothing

        else
            DateField.fromIso pending.date
    , locationState = pending.locationState
    , longNote = nonEmpty pending.longNote
    , merchant = nonEmpty pending.merchant
    , note = nonEmpty pending.note
    , paymentMethod = pending.paymentMethod
    }


{-| Propagate a scan item's `effectiveLocation` to the active form, if
the user is reviewing that exact item AND the form's current state is
"willing to accept" a new location (still resolving, an EXIF fallback
that geocode can now improve on, or a stale Geocoded value to refresh).

User-initiated locations — manual pin, browser geo, explicit skip —
are never overridden; the user's intent wins. Idle is also left alone
to match how new scans behave on the fresh form path.

-}
syncScanLocationToForm : String -> Model -> Model
syncScanLocationToForm itemId as_ =
    case ( as_.activeScanItemId, Dict.get itemId as_.scanQueue ) of
        ( Just activeId, Just item ) ->
            if ScanItemId.toString activeId == itemId then
                let
                    formLs =
                        (PendingEntry.formPending as_.form).locationState

                    accept =
                        case formLs of
                            Data.Location.LocationGot _ Data.Location.ManualPin ->
                                False

                            Data.Location.LocationGot _ Data.Location.BrowserGeo ->
                                False

                            Data.Location.LocationSkipped ->
                                False

                            Data.Location.LocationIdle ->
                                False

                            Data.Location.LocationGot _ Data.Location.ExifGps ->
                                True

                            Data.Location.LocationGot _ Data.Location.Geocoded ->
                                True

                            Data.Location.LocationResolving ->
                                True

                            Data.Location.LocationNoExifGps ->
                                True
                in
                if accept then
                    { as_ | form = PendingEntry.mapForm (PendingEntry.setLocation (Scan.effectiveLocation item)) as_.form }

                else
                    as_

            else
                as_

        _ ->
            as_



-- GEOCODE


{-| For each touched scan item that has a non-empty OCR-extracted
address, flip the item's `geocode` phase to `GeocodeRequested` and
emit a `Geocode` effect (`POST /geocode`). Returns the updated queue
alongside the effects so the caller writes both into the model in one go.

Only fires on paid-tier trips — free users skip the call entirely
(the server would 403 it). EXIF GPS no longer blocks the dispatch:
the receipt's printed address tells us where the _transaction_
happened, which beats the photo's location (frequently the user's
kitchen on batch scans). The geocode result overrides EXIF in
`GotGeocodeResult`.

-}
geocodeDispatch :
    List String
    -> Dict.Dict String ScanItem
    -> Model
    -> ( Dict.Dict String ScanItem, List Effect )
geocodeDispatch ids queue as_ =
    let
        eligible : Bool
        eligible =
            case activeTripForGeocode as_ of
                Just trip ->
                    Tier.isPaid (Trip.effectiveTier trip as_)

                Nothing ->
                    False
    in
    if eligible then
        List.foldl (geocodeDispatchOne as_.creds) ( queue, [] ) ids

    else
        ( queue, [] )


geocodeDispatchOne :
    Creds
    -> String
    -> ( Dict.Dict String ScanItem, List Effect )
    -> ( Dict.Dict String ScanItem, List Effect )
geocodeDispatchOne creds id ( queue, effects ) =
    case Dict.get id queue |> Maybe.andThen (\item -> Maybe.andThen .address item.ocrData) of
        Just rawAddress ->
            if String.trim rawAddress /= "" then
                ( Dict.update id (Maybe.map (\item -> { item | geocode = GeocodeRequested })) queue
                , Effect.Geocode creds id rawAddress :: effects
                )

            else
                ( queue, effects )

        Nothing ->
            ( queue, effects )


activeTripForGeocode : Model -> Maybe Trip
activeTripForGeocode as_ =
    case ( Routing.routeTripId as_.route, as_.trips ) of
        ( Just tripId, TripsLoaded loadedTrips ) ->
            Trips.findTrip tripId loadedTrips

        _ ->
            Nothing



-- OCR


ocrSystemPrompt : String
ocrSystemPrompt =
    "You are a receipt parser. The image may contain one or many receipts (e.g. laid out on a table). Extract expense info for EVERY receipt visible and return ONLY a raw valid JSON array with no markdown, no code fences, no explanation. Each element of the array is one receipt, formatted exactly: {\"amount\": <number>, \"category\": \"<activities|camp|ferry|food|fuel|gear|lodging|medical|misc|parks|shopping|transport>\", \"note\": \"<brief description max 50 chars>\", \"longNote\": \"<detailed description max 560 chars, include what was purchased, where, any relevant context>\", \"merchant\": \"<store name>\", \"address\": \"<street address as printed on receipt, include city and state/region when visible, or null if not visible>\", \"date\": \"<YYYY-MM-DD or null if not visible on receipt>\", \"paymentMethod\": \"<cash|credit|null>\", \"pricePerGallon\": <fuel receipts only: the per-gallon unit price as a number, including the trailing 9/10 cent when printed, e.g. 4.299; null otherwise>, \"gallons\": <fuel receipts only: the volume pumped as a number, e.g. 12.345; null otherwise>, \"grade\": \"<fuel receipts only: regular|midgrade|premium|diesel, or the grade exactly as printed; null otherwise>\"}. If only one receipt is visible, still return a one-element array. For paymentMethod: use cash if receipt shows cash tendered/change; use credit if receipt shows card/credit/debit/visa/mastercard/chip; use null if unclear. Choose the best matching category. Use parks for national/state park entry fees. Use these note formats by category — fuel: \"$X.XX/gal Xgal Grade\" (e.g. \"$4.29/gal 12.3gal Regular\"); camp: \"$XX/night HookupType\" (e.g. \"$35/night Full\"); lodging: \"$XX/night Xnights\" (e.g. \"$89/night 2nights\"); ferry: \"Origin→Dest vehicle|foot\" (e.g. \"Juneau→Haines car\"); parks: \"PassType ParkName\" (e.g. \"Day Pass Denali\"); activities: \"Xppl Activity\" (e.g. \"2ppl Kayaking\"); food: \"Xppl MealType\" (e.g. \"3ppl Dinner\"); all others: brief description."


{-| Build the Anthropic `/v1/messages` request body for an OCR call. The
same JSON is sent by the direct (BYO-key) and hosted-proxy paths; the
`Effect.MakeOcrCall` interpreter picks the transport from the `OcrPath`.
-}
ocrRequestBody : String -> String -> Json.Encode.Value
ocrRequestBody base64Data mimeType =
    Json.Encode.object
        [ ( "model", Json.Encode.string "claude-sonnet-4-6" )
        , ( "max_tokens", Json.Encode.int 2048 )
        , ( "system", Json.Encode.string ocrSystemPrompt )
        , ( "messages"
          , Json.Encode.list identity
                [ Json.Encode.object
                    [ ( "role", Json.Encode.string "user" )
                    , ( "content"
                      , Json.Encode.list identity
                            [ Json.Encode.object
                                [ ( "type", Json.Encode.string "image" )
                                , ( "source"
                                  , Json.Encode.object
                                        [ ( "type", Json.Encode.string "base64" )
                                        , ( "media_type", Json.Encode.string mimeType )
                                        , ( "data", Json.Encode.string base64Data )
                                        ]
                                  )
                                ]
                            , Json.Encode.object
                                [ ( "type", Json.Encode.string "text" )
                                , ( "text", Json.Encode.string "Extract expense info from every receipt visible in this image." )
                                ]
                            ]
                      )
                    ]
                ]
          )
        ]


{-| Target max-byte budget for the base64-encoded image we send to
Anthropic. The API enforces 5 MiB (5\_242\_880 bytes) on the
`messages.0.content.0.image.source.base64` string. We aim well below
that so JPEG quality jitter and downscaling rounding can't push us
over: 4 MiB ≈ a 3 MiB binary image, plenty for a receipt.
-}
ocrMaxBase64Bytes : Int
ocrMaxBase64Bytes =
    4 * 1024 * 1024


{-| Truncate a string to `n` characters, appending an ellipsis if it
was shortened. Used when embedding raw Anthropic output in an error
message so a giant refusal doesn't blow out the Scan card.
-}
truncate : Int -> String -> String
truncate n s =
    if String.length s > n then
        String.left n s ++ "…"

    else
        s


claudeTextDecoder : Json.Decode.Decoder String
claudeTextDecoder =
    Json.Decode.field "content" (Json.Decode.index 0 (Json.Decode.field "text" Json.Decode.string))


stripCodeFence : String -> String
stripCodeFence s =
    let
        trimmed =
            String.trim s
    in
    if String.startsWith "```" trimmed then
        trimmed
            |> String.lines
            |> List.drop 1
            |> (\lines ->
                    if List.Extra.last lines |> Maybe.Extra.unwrap False (String.startsWith "```") then
                        List.reverse lines |> List.drop 1 |> List.reverse

                    else
                        lines
               )
            |> String.join "\n"
            |> String.trim

    else
        trimmed


extractBase64 : String -> String
extractBase64 dataUrl =
    case String.split "," dataUrl of
        _ :: b64 :: _ ->
            b64

        _ ->
            dataUrl


getMimeType : String -> String
getMimeType dataUrl =
    if String.contains "image/png" dataUrl then
        "image/png"

    else if String.contains "image/gif" dataUrl then
        "image/gif"

    else if String.contains "image/webp" dataUrl then
        "image/webp"

    else
        "image/jpeg"


{-| Parse the raw Anthropic response body (as returned by either the
direct-Anthropic path or the hosted proxy) into a list of `OcrData`
records. Both paths return the same Anthropic `/v1/messages` JSON shape
verbatim, so one parser covers both.
-}
parseOcrResponseBody : String -> Result String (List Scan.OcrData)
parseOcrResponseBody responseBody =
    case Json.Decode.decodeString claudeTextDecoder responseBody of
        Err decodeErr ->
            Err
                ("Couldn't read Anthropic response: "
                    ++ Json.Decode.errorToString decodeErr
                )

        Ok innerJson ->
            let
                stripped =
                    stripCodeFence innerJson
            in
            case Json.Decode.decodeString Scan.ocrDataListDecoder stripped of
                Ok list ->
                    Ok list

                Err decodeErr ->
                    Err
                        ("Couldn't parse receipt JSON: "
                            ++ Json.Decode.errorToString decodeErr
                            ++ "\n\nModel returned: "
                            ++ truncate 240 stripped
                        )


{-| A terminal OCR result for one item, normalized so the success and
failure paths can be applied uniformly across the BYO (`GotOcrResult`)
and hosted (`ScanProxyResult`) callers.

  - `OcrSucceeded list` — Anthropic returned a (possibly empty,
    possibly multi-receipt) list of parsed receipts.
  - `OcrFailed kind message` — the call failed; `kind` decides whether
    to spend the retry budget (see `Scan.OcrFailureKind`).

-}
type OcrOutcome
    = OcrFailed Scan.OcrFailureKind String
    | OcrSucceeded (List Scan.OcrData)


{-| Parse a raw OCR response body into an `OcrOutcome`. A body that the
parser can't read is a `Permanent` failure — retrying won't fix bad JSON
or a model refusal.
-}
outcomeFromBody : String -> OcrOutcome
outcomeFromBody body =
    case parseOcrResponseBody body of
        Ok list ->
            OcrSucceeded list

        Err errMsg ->
            OcrFailed Scan.Permanent errMsg


{-| Apply a terminal OCR outcome for one item: drop it from the
in-flight set, write the result into the queue, persist every touched
item, then run geocode dispatch for any touched items AND refill the
freed concurrency slot(s) from the remaining `ScanDeferred` backlog
(`dispatchOnReconnect`). This is the single dispatch-next point both
terminal OCR handlers funnel through.

A multi-receipt success (two-or-more parsed receipts) is special: the
split mints durable child ids from real capture millis, which a pure
function can't reach. So the multi case clears the item from the in-flight
set and fires `Effect.MintIdsThen` — the actual split + persist + source
delete happens in the `GotMintedScanIds` arm. The single / empty / failure
cases stay inline here.

-}
finishOcr : String -> OcrOutcome -> Model -> ( Model, Effect )
finishOcr itemId outcome as_ =
    let
        inFlightCleared : Set.Set String
        inFlightCleared =
            Set.remove itemId as_.ocrInFlight
    in
    case outcome of
        OcrSucceeded ((_ :: _ :: _) as multi) ->
            -- Defer the split to `GotMintedScanIds` (needs `Time.now`).
            ( { as_ | ocrInFlight = inFlightCleared }
            , Effect.MintIdsThen itemId multi
            )

        _ ->
            let
                ( afterOcr, touchedIds ) =
                    applyOcrOutcome itemId outcome as_.scanQueue

                ( afterGeocodeFlip, geocodeEffects ) =
                    geocodeDispatch touchedIds afterOcr as_

                -- Persist every item whose status / data the outcome touched
                -- so the durable store matches the in-memory queue (a reload
                -- mustn't lose an OCR result or a failure's `lastError`).
                persistEffects : List Effect
                persistEffects =
                    touchedIds
                        |> List.filterMap
                            (\id ->
                                Dict.get id afterGeocodeFlip
                                    |> Maybe.map (Scan.scanItemEncoder >> Effect.SaveScanItem)
                            )

                -- Exclude the just-handled id from dispatch-next: if a Transient /
                -- under-cap Retryable failure bounced it back to `ScanDeferred`,
                -- it must wait for the next `Synced` edge rather than busy-retry
                -- in the same tick (the network is likely still flapping).
                ( afterDispatch, nextInFlight, dispatchEffects ) =
                    dispatchOnReconnect (Set.singleton itemId) { as_ | ocrInFlight = inFlightCleared, scanQueue = afterGeocodeFlip }
            in
            ( { as_ | ocrInFlight = nextInFlight, scanQueue = afterDispatch }
            , Batch (persistEffects ++ geocodeEffects ++ dispatchEffects)
            )


{-| Write a terminal OCR outcome into the queue for one item, returning
the updated queue and the touched ids (for geocode dispatch + persist).
The failure branch consults `Scan.OcrFailureKind`:

  - `Transient` — connectivity flap: return the item to `ScanDeferred`
    WITHOUT bumping `retryCount`, so the next reconnect retries it for
    free. Record the reason on `lastError`.
  - `Retryable` — a real retryable server response: bump `retryCount`.
    Still under `Scan.maxOcrRetries` → back to `ScanDeferred` to retry
    next reconnect; at the cap → terminal `ScanReady` with `ocrError`.
  - `Permanent` — terminal `ScanReady` with `ocrError` immediately.

A single-receipt success folds the item's typed `draft` over the OCR
result (`Scan.mergeOcrIntoDraft`) so the user's offline edits aren't
clobbered (blanks-only merge; `draft == Nothing` is the identity). The
multi-receipt success is handled out-of-band in `finishOcr` /
`GotMintedScanIds` (it needs `Time.now`), so the multi branch here is a
defensive no-op — `finishOcr` never routes a multi outcome through this
function.

-}
applyOcrOutcome :
    String
    -> OcrOutcome
    -> Dict.Dict String Scan.ScanItem
    -> ( Dict.Dict String Scan.ScanItem, List String )
applyOcrOutcome itemId outcome queue =
    let
        markReady : Maybe Scan.OcrData -> Maybe String -> Dict.Dict String Scan.ScanItem
        markReady ocrData ocrError =
            Dict.update itemId
                (Maybe.map
                    (\i ->
                        { i
                            | ocrData = ocrData
                            , ocrError = ocrError
                            , status = ScanReady
                        }
                    )
                )
                queue

        -- A single-receipt success: lay the typed draft over the OCR data
        -- per item, so the blanks-only merge sees this item's own draft.
        markReadyMerged : Scan.OcrData -> Dict.Dict String Scan.ScanItem
        markReadyMerged data =
            Dict.update itemId
                (Maybe.map
                    (\i ->
                        { i
                            | ocrData =
                                Just
                                    (case i.draft of
                                        Just draft ->
                                            Scan.mergeOcrIntoDraft draft data

                                        Nothing ->
                                            data
                                    )
                            , ocrError = Nothing
                            , status = ScanReady
                        }
                    )
                )
                queue

        defer : Maybe String -> Int -> Dict.Dict String Scan.ScanItem
        defer lastError retryCount =
            Dict.update itemId
                (Maybe.map
                    (\i ->
                        { i
                            | lastError = lastError
                            , ocrError = Nothing
                            , retryCount = retryCount
                            , status = ScanDeferred
                        }
                    )
                )
                queue
    in
    case outcome of
        OcrFailed kind errMsg ->
            case kind of
                Scan.Transient ->
                    -- A flap must not burn the budget: requeue, count unchanged.
                    ( defer (Just errMsg) (currentRetryCount itemId queue), [] )

                Scan.Retryable ->
                    let
                        bumped =
                            currentRetryCount itemId queue + 1
                    in
                    if bumped >= Scan.maxOcrRetries then
                        ( markReady Nothing (Just errMsg), [ itemId ] )

                    else
                        ( defer (Just errMsg) bumped, [] )

                Scan.Permanent ->
                    ( markReady Nothing (Just errMsg), [ itemId ] )

        OcrSucceeded [] ->
            ( markReady Nothing (Just "No receipts detected in the image — try a clearer photo or a tighter crop")
            , [ itemId ]
            )

        OcrSucceeded [ single ] ->
            ( markReadyMerged single, [ itemId ] )

        OcrSucceeded (_ :: _ :: _) ->
            -- Multi-receipt: handled in `finishOcr` → `GotMintedScanIds`
            -- (needs `Time.now`); never routed here. No-op defensively.
            ( queue, [] )


{-| The current `retryCount` for an item, or `0` if it's gone.
-}
currentRetryCount : String -> Dict.Dict String Scan.ScanItem -> Int
currentRetryCount itemId queue =
    Dict.get itemId queue
        |> Maybe.map .retryCount
        |> Maybe.withDefault 0



-- RECONNECT ORCHESTRATION (#373)


{-| The concurrency cap for reconnect OCR retries: free `Tern` runs one
scan at a time, paid tiers run up to three. Resolved from the active
trip's effective tier when there is one (a shared trip can grant paid via
its owner), falling back to the user's own tier — mirroring how
`geocodeDispatch` resolves eligibility.
-}
reconnectTierCap : Model -> Int
reconnectTierCap as_ =
    let
        paid : Bool
        paid =
            case activeTripForGeocode as_ of
                Just trip ->
                    Tier.isPaid (Trip.effectiveTier trip as_)

                Nothing ->
                    Tier.isPaid as_.tier
    in
    if paid then
        3

    else
        1


{-| Orchestrate a reconnect retry: for each `ScanDeferred` candidate the
tier cap leaves room for (`Scan.reconnectCandidates`), resolve the OCR
path and either:

  - `Unscannable` (tier lapsed / BYO key removed since capture) — DON'T
    spend a slot. Flip the item to `ScanReady` and fold its offline-typed
    `draft` into `ocrData` so the review form still shows what the user
    entered. Never strand the receipt.
  - scannable (`ByoPath` / `HostedPath`) — flip `ScanDeferred →
    ScanProcessing`, add the id to the in-flight set, persist the status
    change, and fire the OCR pipeline (`PrepareOcrImage` → `MakeOcrCall`).

Returns the updated queue, the updated in-flight set, and the effects to
run. Idempotent: with the in-flight set at the cap there are no
candidates, so it returns the inputs unchanged with no effects — the
oscillating `Synced` edge can fire it freely. `excluded` keeps a
just-failed item that bounced back to `ScanDeferred` from being retried
in the same dispatch-next tick (it waits for the next `Synced` edge).

-}
dispatchOnReconnect : Set.Set String -> Model -> ( Dict.Dict String Scan.ScanItem, Set.Set String, List Effect )
dispatchOnReconnect excluded as_ =
    let
        ocrPath : OcrPath.OcrPath
        ocrPath =
            OcrPath.resolve as_.config.anthropicKey as_.tier

        candidates : List String
        candidates =
            Scan.reconnectCandidates (reconnectTierCap as_) (Set.size as_.ocrInFlight) excluded as_.scanQueue
    in
    List.foldl (dispatchOne ocrPath) ( as_.scanQueue, as_.ocrInFlight, [] ) candidates


{-| Process one reconnect candidate: either keep-draft (`Unscannable`) or
start OCR (scannable). See `dispatchOnReconnect`.
-}
dispatchOne :
    OcrPath.OcrPath
    -> String
    -> ( Dict.Dict String Scan.ScanItem, Set.Set String, List Effect )
    -> ( Dict.Dict String Scan.ScanItem, Set.Set String, List Effect )
dispatchOne ocrPath itemId ( queue, inFlight, effects ) =
    case Dict.get itemId queue of
        Nothing ->
            ( queue, inFlight, effects )

        Just item ->
            case ocrPath of
                OcrPath.Unscannable ->
                    let
                        readied : Scan.ScanItem
                        readied =
                            { item
                                | ocrData = draftIntoOcrData item.draft item.ocrData
                                , status = ScanReady
                            }
                    in
                    ( Dict.insert itemId readied queue
                    , inFlight
                    , Effect.SaveScanItem (Scan.scanItemEncoder readied) :: effects
                    )

                _ ->
                    let
                        processing : Scan.ScanItem
                        processing =
                            { item | status = ScanProcessing }
                    in
                    ( Dict.insert itemId processing queue
                    , Set.insert itemId inFlight
                    , Effect.PrepareOcrImage { dataUrl = item.imageUrl, id = itemId, maxBytes = ocrMaxBase64Bytes }
                        :: Effect.SaveScanItem (Scan.scanItemEncoder processing)
                        :: effects
                    )


{-| Fold the user's offline-typed `draft` into the item's `ocrData` for
the `Unscannable`-on-reconnect keep-draft path.

  - No draft → leave `ocrData` untouched (merge-with-`Nothing` = identity).
  - A draft over existing OCR → only the fields the user actually set
    (a `Just` in `DraftFields`) override.
  - A draft over no OCR → build an `OcrData` from the draft so the review
    form shows the typed fields; an empty draft over no OCR stays
    `Nothing` and falls through to the form defaults (the manual path).

-}
draftIntoOcrData : Maybe Scan.DraftFields -> Maybe Scan.OcrData -> Maybe Scan.OcrData
draftIntoOcrData maybeDraft maybeOcr =
    case maybeDraft of
        Nothing ->
            maybeOcr

        Just draft ->
            -- Reuse the pure blanks-only merge over an `emptyOcrData` base so
            -- the per-field precedence lives in ONE place (`mergeOcrIntoDraft`).
            Just (Scan.mergeOcrIntoDraft draft (Maybe.withDefault emptyOcrData maybeOcr))


{-| An all-`Nothing` `OcrData`, used as the merge base when folding a
draft into an item that never got an OCR result.
-}
emptyOcrData : Scan.OcrData
emptyOcrData =
    { address = Nothing
    , amount = Nothing
    , category = Nothing
    , date = Nothing
    , fuelDetail = Nothing
    , longNote = Nothing
    , merchant = Nothing
    , note = Nothing
    , paymentMethod = Nothing
    }
