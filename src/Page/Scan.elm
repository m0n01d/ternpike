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
import Data.DateField as DateField
import Data.Expense exposing (Expense)
import Data.GeoPoint as GeoPoint
import Data.Location
import Data.Money as Money
import Data.Navigation exposing (Route(..), Tab(..))
import Data.OcrPath as OcrPath exposing (OcrPath(..))
import Data.PendingEntry as PendingEntry exposing (PendingForm(..))
import Data.Scan as Scan exposing (ExifPhase(..), GeocodePhase(..), ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Data.SharedTrips exposing (SharedTrips)
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
    , creds : Creds
    , currentUser : UserId
    , duplicateWarning : Maybe Expense
    , error : Maybe String
    , form : PendingForm
    , route : Route
    , scanQueue : Dict.Dict String ScanItem
    , scanSeq : Int
    , sharedTrips : SharedTrips
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
            let
                -- Durable, collision-free ids: the per-session counter
                -- (`scanSeq`) is the high-order segment and the file's
                -- position in this batch the low-order one, so two
                -- captures in the same millisecond can't collide. #372
                -- swaps the first segment for the real capture millis
                -- once it wires a `Time.now` task into the capture path.
                indexed =
                    List.indexedMap (\i f -> ( Scan.mintId as_.scanSeq i, f )) files

                newQueue =
                    List.foldl (\( id, _ ) d -> Dict.insert id (freshScanItem id) d) as_.scanQueue indexed

                urlEffects =
                    List.map (\( id, f ) -> Effect.FetchFileUrl id f) indexed
            in
            ( { as_ | scanQueue = newQueue, scanSeq = as_.scanSeq + 1 }, Batch urlEffects )

        GotFileUrl itemId dataUrl ->
            let
                ocrPath =
                    OcrPath.resolve as_.config.anthropicKey as_.tier

                canScan =
                    ocrPath /= Unscannable

                newStatus =
                    if canScan then
                        ScanProcessing

                    else
                        ScanReady

                updatedQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | imageUrl = dataUrl, status = newStatus })) as_.scanQueue
            in
            ( { as_ | scanQueue = updatedQueue }
            , Batch
                [ if canScan then
                    -- Always route through the JS-side downscaler before
                    -- the OCR call. Anthropic's image limit is 5 MiB on
                    -- the base64 payload; modern phone JPEGs routinely
                    -- run 6–8 MB so we'd otherwise 400 on every photo.
                    -- We use the EXIF data URL for GPS extraction in
                    -- parallel because exifr needs the original bytes.
                    Effect.PrepareOcrImage { dataUrl = dataUrl, id = itemId, maxBytes = ocrMaxBase64Bytes }

                  else
                    NoEffect
                , Effect.ExtractExifGps { dataUrl = dataUrl, id = itemId }
                ]
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
                        ( { as_ | scanQueue = updatedQueue }, NoEffect )

                    else
                        let
                            updatedQueue =
                                Dict.update payload.id
                                    (Maybe.map (\i -> { i | imageUrl = payload.dataUrl }))
                                    as_.scanQueue
                        in
                        ( { as_ | scanQueue = updatedQueue }
                        , Effect.MakeOcrCall
                            { backendUrl = as_.config.backendUrl
                            , body = ocrRequestBody (extractBase64 payload.dataUrl) (getMimeType payload.dataUrl)
                            , itemId = payload.id
                            , path = OcrPath.resolve as_.config.anthropicKey as_.tier
                            }
                        )

        GotOcrResult itemId result ->
            let
                parsed : Result String (List Scan.OcrData)
                parsed =
                    case result of
                        Err httpErr ->
                            Err httpErr

                        Ok responseBody ->
                            parseOcrResponseBody responseBody

                ( afterOcr, touchedIds ) =
                    applyOcrResult itemId parsed as_.scanQueue

                ( afterGeocodeFlip, geocodeEffects ) =
                    geocodeDispatch touchedIds afterOcr as_
            in
            ( { as_ | scanQueue = afterGeocodeFlip }
            , Batch geocodeEffects
            )

        ScanProxyResult { body, itemId, ok, status } ->
            let
                result : Result String (List Scan.OcrData)
                result =
                    if ok then
                        parseOcrResponseBody body

                    else if status == 402 then
                        Err "Hosted scanning requires an Osprey or Trailblazer subscription."

                    else if status == 401 then
                        Err "Sign in again to continue scanning."

                    else
                        Err ("Hosted scan failed (HTTP " ++ String.fromInt status ++ "): " ++ body)

                ( afterOcr, touchedIds ) =
                    applyOcrResult itemId result as_.scanQueue

                ( afterGeocodeFlip, geocodeEffects ) =
                    geocodeDispatch touchedIds afterOcr as_
            in
            ( { as_ | scanQueue = afterGeocodeFlip }
            , Batch geocodeEffects
            )

        GotExifCoords itemId (Just lat) (Just lon) _ ->
            let
                point =
                    GeoPoint.fromDegrees lat lon

                newQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | exif = ExifFound point })) as_.scanQueue
            in
            ( syncScanLocationToForm itemId { as_ | scanQueue = newQueue }
            , NoEffect
            )

        GotExifCoords itemId _ _ debug ->
            let
                newQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | exif = ExifMissing, exifDebug = debug })) as_.scanQueue
            in
            ( syncScanLocationToForm itemId { as_ | scanQueue = newQueue }
            , NoEffect
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
            , NoEffect
            )

        ReviewScanItem itemId ->
            case Dict.get itemId as_.scanQueue of
                Nothing ->
                    ( as_, NoEffect )

                Just item ->
                    let
                        ocr =
                            Maybe.withDefault
                                { address = Nothing, amount = Nothing, category = Nothing, date = Nothing, longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }
                                item.ocrData

                        newPending =
                            { address = Maybe.withDefault "" ocr.address
                            , amount =
                                ocr.amount
                                    |> Maybe.map Money.toDollarString
                                    |> Maybe.withDefault ""
                            , category = Maybe.withDefault Data.Category.Fuel ocr.category
                            , date =
                                ocr.date
                                    |> Maybe.withDefault as_.today
                                    |> DateField.toIso
                            , locationState = Scan.effectiveLocation item
                            , longNote = Maybe.withDefault "" ocr.longNote
                            , merchant = Maybe.withDefault "" ocr.merchant
                            , note = Maybe.withDefault "" ocr.note
                            , paymentMethod = ocr.paymentMethod
                            }

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
                        , form = FreshForm newPending
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
            in
            ( { as_
                | activeScanItemId = Nothing
                , form = FreshForm (PendingEntry.defaultPendingEntry as_.today)
                , route = newRoute
              }
            , case Routing.routeTripId as_.route of
                Just tid ->
                    Effect.Navigate (Routing.tabToPath as_.basePath tid ScanTab)

                Nothing ->
                    NoEffect
            )

        ClearDoneItems ->
            ( { as_ | scanQueue = Dict.filter (\_ i -> i.status /= ScanSubmitted) as_.scanQueue }
            , NoEffect
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
    "You are a receipt parser. The image may contain one or many receipts (e.g. laid out on a table). Extract expense info for EVERY receipt visible and return ONLY a raw valid JSON array with no markdown, no code fences, no explanation. Each element of the array is one receipt, formatted exactly: {\"amount\": <number>, \"category\": \"<activities|camp|ferry|food|fuel|gear|lodging|medical|misc|parks|shopping|transport>\", \"note\": \"<brief description max 50 chars>\", \"longNote\": \"<detailed description max 560 chars, include what was purchased, where, any relevant context>\", \"merchant\": \"<store name>\", \"address\": \"<street address as printed on receipt, include city and state/region when visible, or null if not visible>\", \"date\": \"<YYYY-MM-DD or null if not visible on receipt>\", \"paymentMethod\": \"<cash|credit|null>\"}. If only one receipt is visible, still return a one-element array. For paymentMethod: use cash if receipt shows cash tendered/change; use credit if receipt shows card/credit/debit/visa/mastercard/chip; use null if unclear. Choose the best matching category. Use parks for national/state park entry fees. Use these note formats by category — fuel: \"$X.XX/gal Xgal Grade\" (e.g. \"$4.29/gal 12.3gal Regular\"); camp: \"$XX/night HookupType\" (e.g. \"$35/night Full\"); lodging: \"$XX/night Xnights\" (e.g. \"$89/night 2nights\"); ferry: \"Origin→Dest vehicle|foot\" (e.g. \"Juneau→Haines car\"); parks: \"PassType ParkName\" (e.g. \"Day Pass Denali\"); activities: \"Xppl Activity\" (e.g. \"2ppl Kayaking\"); food: \"Xppl MealType\" (e.g. \"3ppl Dinner\"); all others: brief description."


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


{-| Apply a parsed OCR result (or error) to the scan queue, returning the
updated queue and the list of touched item ids (for geocode dispatch).
Shared by `GotOcrResult` and `ScanProxyResult`.
-}
applyOcrResult :
    String
    -> Result String (List Scan.OcrData)
    -> Dict.Dict String Scan.ScanItem
    -> ( Dict.Dict String Scan.ScanItem, List String )
applyOcrResult itemId parsed queue =
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
    in
    case parsed of
        Err errMsg ->
            ( markReady Nothing (Just errMsg), [ itemId ] )

        Ok [] ->
            ( markReady Nothing (Just "No receipts detected in the image — try a clearer photo or a tighter crop")
            , [ itemId ]
            )

        Ok [ single ] ->
            ( markReady (Just single) Nothing, [ itemId ] )

        Ok ((_ :: _ :: _) as multi) ->
            case Dict.get itemId queue of
                Nothing ->
                    -- item disappeared mid-flight (cleared/submitted) — no-op
                    ( queue, [] )

                Just source ->
                    let
                        queueWithoutSource =
                            Dict.remove itemId queue

                        indexed =
                            List.indexedMap
                                (\i data ->
                                    let
                                        rawId =
                                            Scan.childId itemId i
                                    in
                                    ( rawId
                                    , { draft = source.draft
                                      , exif = source.exif
                                      , exifDebug = source.exifDebug
                                      , expectedExpenseId = Nothing
                                      , geocode = source.geocode
                                      , id = ScanItemId.fromString rawId
                                      , imageUrl = source.imageUrl
                                      , lastError = Nothing
                                      , ocrData = Just data
                                      , ocrError = Nothing
                                      , persistError = False
                                      , retryCount = source.retryCount
                                      , schemaVersion = Scan.currentSchemaVersion
                                      , status = ScanReady
                                      }
                                    )
                                )
                                multi
                    in
                    ( List.foldl (\( id, item ) d -> Dict.insert id item d) queueWithoutSource indexed
                    , List.map Tuple.first indexed
                    )
