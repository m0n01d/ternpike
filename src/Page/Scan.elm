module Page.Scan exposing (update)

{-| The Scan / OCR feature's `update`, carved out of `Main.updateAuth`
(#368). This is a pure mechanical extraction — same messages produce the
same state transitions; only the code's home moved.

`update` operates over the whole `AuthState` rather than a self-contained
`Scan.Model` because the geo arms (`GotExifCoords` / `GotGeocodeResult`)
still write back into `as_.form` via `syncScanLocationToForm`. Narrowing
the seam to a dedicated model is deferred to #F2.

@docs update

-}

import Browser.Navigation as Nav
import Data.AnthropicKey as AnthropicKey
import Data.Auth exposing (AppConfig)
import Data.Category
import Data.DateField as DateField
import Data.GeoPoint as GeoPoint
import Data.Location
import Data.Money as Money
import Data.Navigation exposing (Route(..), Tab(..))
import Data.OcrPath as OcrPath exposing (OcrPath(..))
import Data.PendingEntry as PendingEntry exposing (PendingForm(..))
import Data.Scan as Scan exposing (ExifPhase(..), GeocodePhase(..), ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Data.Tier as Tier
import Data.Trip as Trip exposing (Trip)
import Data.Trips as Trips exposing (TripsState(..))
import Dict
import File
import Http
import Http.GeocodeApi
import Json.Decode
import Json.Encode
import List.Extra
import Maybe.Extra
import Msg.Scan exposing (Msg(..))
import Ports
import Routing
import Task
import Types exposing (AuthState)


{-| Handle a Scan message against the current `AuthState`. Returns the
new `AuthState` plus any `Cmd`; the caller (`Main.updateAuth`) lifts the
`AuthState` into a `Model`.
-}
update : Msg.Scan.Msg -> AuthState -> ( AuthState, Cmd Types.Msg )
update msg as_ =
    case msg of
        FilesSelected files ->
            let
                startIdx =
                    Dict.size as_.scanQueue

                indexed =
                    List.indexedMap (\i f -> ( "scan-" ++ String.fromInt (startIdx + i), f )) files

                newQueue =
                    List.foldl (\( id, _ ) d -> Dict.insert id (freshScanItem id) d) as_.scanQueue indexed

                urlCmds =
                    List.map (\( id, f ) -> Task.perform (Types.AuthMsg << Types.ScanMsg << GotFileUrl id) (File.toUrl f)) indexed
            in
            ( { as_ | scanQueue = newQueue }, Cmd.batch urlCmds )

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
            , Cmd.batch
                [ if canScan then
                    -- Always route through the JS-side downscaler before
                    -- the OCR call. Anthropic's image limit is 5 MiB on
                    -- the base64 payload; modern phone JPEGs routinely
                    -- run 6–8 MB so we'd otherwise 400 on every photo.
                    -- We use the EXIF data URL for GPS extraction in
                    -- parallel because exifr needs the original bytes.
                    Ports.prepareOcrImage { dataUrl = dataUrl, id = itemId, maxBytes = ocrMaxBase64Bytes }

                  else
                    Cmd.none
                , Ports.extractExifGps { id = itemId, dataUrl = dataUrl }
                ]
            )

        OcrImagePrepared payload ->
            case Dict.get payload.id as_.scanQueue of
                Nothing ->
                    -- item was cleared/submitted while resize was in flight — no-op
                    ( as_, Cmd.none )

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
                        ( { as_ | scanQueue = updatedQueue }, Cmd.none )

                    else
                        let
                            updatedQueue =
                                Dict.update payload.id
                                    (Maybe.map (\i -> { i | imageUrl = payload.dataUrl }))
                                    as_.scanQueue
                        in
                        ( { as_ | scanQueue = updatedQueue }
                        , makeOcrCall payload.id (OcrPath.resolve as_.config.anthropicKey as_.tier) as_.config (extractBase64 payload.dataUrl) (getMimeType payload.dataUrl)
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

                ( afterGeocodeFlip, geocodeCmds ) =
                    geocodeDispatch touchedIds afterOcr as_
            in
            ( { as_ | scanQueue = afterGeocodeFlip }
            , Cmd.batch geocodeCmds
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

                ( afterGeocodeFlip, geocodeCmds ) =
                    geocodeDispatch touchedIds afterOcr as_
            in
            ( { as_ | scanQueue = afterGeocodeFlip }
            , Cmd.batch geocodeCmds
            )

        GotExifCoords itemId (Just lat) (Just lon) _ ->
            let
                point =
                    GeoPoint.fromDegrees lat lon

                newQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | exif = ExifFound point })) as_.scanQueue
            in
            ( syncScanLocationToForm itemId { as_ | scanQueue = newQueue }
            , Cmd.none
            )

        GotExifCoords itemId _ _ debug ->
            let
                newQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | exif = ExifMissing, exifDebug = debug })) as_.scanQueue
            in
            ( syncScanLocationToForm itemId { as_ | scanQueue = newQueue }
            , Cmd.none
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
            , Cmd.none
            )

        ReviewScanItem itemId ->
            case Dict.get itemId as_.scanQueue of
                Nothing ->
                    ( as_, Cmd.none )

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
                    , Cmd.none
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
                    Nav.pushUrl as_.key (Routing.tabToPath as_.basePath tid ScanTab)

                Nothing ->
                    Cmd.none
            )

        ClearDoneItems ->
            ( { as_ | scanQueue = Dict.filter (\_ i -> i.status /= ScanSubmitted) as_.scanQueue }
            , Cmd.none
            )



-- SCAN QUEUE


freshScanItem : String -> ScanItem
freshScanItem id =
    { exif = ExifChecking
    , exifDebug = ""
    , geocode = GeocodeNotAttempted
    , id = ScanItemId.fromString id
    , imageUrl = ""
    , ocrData = Nothing
    , ocrError = Nothing
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
syncScanLocationToForm : String -> AuthState -> AuthState
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
emit a `POST /geocode` Cmd. Returns the updated queue alongside the
Cmds so the caller writes both into the model in one go.

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
    -> AuthState
    -> ( Dict.Dict String ScanItem, List (Cmd Types.Msg) )
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
    Data.Auth.Creds
    -> String
    -> ( Dict.Dict String ScanItem, List (Cmd Types.Msg) )
    -> ( Dict.Dict String ScanItem, List (Cmd Types.Msg) )
geocodeDispatchOne creds id ( queue, cmds ) =
    case Dict.get id queue |> Maybe.andThen (\item -> Maybe.andThen .address item.ocrData) of
        Just rawAddress ->
            if String.trim rawAddress /= "" then
                ( Dict.update id (Maybe.map (\item -> { item | geocode = GeocodeRequested })) queue
                , Http.GeocodeApi.geocode creds { address = rawAddress } (Types.AuthMsg << Types.ScanMsg << GotGeocodeResult id) :: cmds
                )

            else
                ( queue, cmds )

        Nothing ->
            ( queue, cmds )


activeTripForGeocode : AuthState -> Maybe Trip
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


makeOcrCall : String -> OcrPath -> AppConfig -> String -> String -> Cmd Types.Msg
makeOcrCall itemId path config base64Data mimeType =
    let
        body =
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
    in
    case path of
        ByoPath key ->
            Http.request
                { method = "POST"
                , headers =
                    [ Http.header "x-api-key" (AnthropicKey.toHeader key)
                    , Http.header "anthropic-version" "2023-06-01"
                    , Http.header "anthropic-dangerous-direct-browser-access" "true"
                    ]
                , url = "https://api.anthropic.com/v1/messages"
                , body = Http.jsonBody body
                , expect = Http.expectStringResponse (Types.AuthMsg << Types.ScanMsg << GotOcrResult itemId) ocrResponseToResult
                , timeout = Nothing
                , tracker = Nothing
                }

        HostedPath ->
            Ports.scanProxyOut { backendUrl = config.backendUrl, body = body, itemId = itemId }

        Unscannable ->
            Cmd.none


{-| Target max-byte budget for the base64-encoded image we send to
Anthropic. The API enforces 5 MiB (5\_242\_880 bytes) on the
`messages.0.content.0.image.source.base64` string. We aim well below
that so JPEG quality jitter and downscaling rounding can't push us
over: 4 MiB ≈ a 3 MiB binary image, plenty for a receipt.
-}
ocrMaxBase64Bytes : Int
ocrMaxBase64Bytes =
    4 * 1024 * 1024


{-| Convert an Anthropic HTTP response into a human-readable error
string or the raw success body. We use `expectStringResponse` (rather
than `expectString`) so that non-2xx responses keep their body — the
body is where Anthropic's actual error message lives, and surfacing it
on the Scan card is the whole point of #N.
-}
ocrResponseToResult : Http.Response String -> Result String String
ocrResponseToResult response =
    case response of
        Http.BadUrl_ url ->
            Err ("Bad URL: " ++ url)

        Http.Timeout_ ->
            Err "OCR request timed out — try again"

        Http.NetworkError_ ->
            Err "Network error — check your connection and try again"

        Http.BadStatus_ meta body ->
            Err (formatAnthropicError meta.statusCode body)

        Http.GoodStatus_ _ body ->
            Ok body


{-| Pull the `error.message` field out of an Anthropic error JSON body
(`{"type":"error","error":{"type":"...","message":"..."}}`) and frame
it for display. Falls back to a status-only message if the body isn't
the expected shape.
-}
formatAnthropicError : Int -> String -> String
formatAnthropicError status body =
    case Json.Decode.decodeString (Json.Decode.field "error" (Json.Decode.field "message" Json.Decode.string)) body of
        Ok msg ->
            "Anthropic error (HTTP " ++ String.fromInt status ++ "): " ++ msg

        Err _ ->
            "OCR request failed (HTTP " ++ String.fromInt status ++ ")"


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

                        startIdx =
                            Dict.size queueWithoutSource

                        indexed =
                            List.indexedMap
                                (\i data ->
                                    let
                                        rawId =
                                            "scan-" ++ String.fromInt (startIdx + i)
                                    in
                                    ( rawId
                                    , { exif = source.exif
                                      , exifDebug = source.exifDebug
                                      , geocode = source.geocode
                                      , id = ScanItemId.fromString rawId
                                      , imageUrl = source.imageUrl
                                      , ocrData = Just data
                                      , ocrError = Nothing
                                      , status = ScanReady
                                      }
                                    )
                                )
                                multi
                    in
                    ( List.foldl (\( id, item ) d -> Dict.insert id item d) queueWithoutSource indexed
                    , List.map Tuple.first indexed
                    )
