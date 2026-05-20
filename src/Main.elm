port module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Data.Amendment as Amendment
import Data.Category as Category exposing (Category(..))
import Data.Entry as Entry
import Data.Expense as Expense
import Data.ExpenseId as ExpenseId
import Data.Trip as Trip exposing (TripField(..))
import Data.TripId as TripId
import Http
import Data.Void as Void
import Dict
import File
import Helpers
import Html exposing (Html)
import Html.Attributes
import Json.Decode as D
import Json.Decode.Pipeline as Pipeline
import Json.Encode as E
import Pages.Add
import Pages.Guest exposing (viewGuest)
import Pages.Ledger
import Pages.Scan
import Pages.Settings
import Pages.Stats
import Pages.Trips
import Process
import Routing
import Task
import Time
import Types exposing (..)
import UI.Layout
import Url
import Validate



-- PORTS


port saveStorage : { key : String, value : String } -> Cmd msg


port clearStorage : () -> Cmd msg


port clearAllStorage : () -> Cmd msg


port pouchOut : D.Value -> Cmd msg


port pouchIn : (D.Value -> msg) -> Sub msg


port requestGeolocation : () -> Cmd msg


port extractExifGps : { id : String, dataUrl : String } -> Cmd msg


port gotGpsCoords : ({ lat : Float, lon : Float, denied : Bool } -> msg) -> Sub msg


port gotExifResult : ({ id : String, lat : Float, lon : Float, hasGps : Bool, debug : String } -> msg) -> Sub msg



-- ROUTING
-- See src/Routing.elm



-- SESSION HELPERS


mapGuestConfig : (AppConfig -> AppConfig) -> GuestSession -> GuestSession
mapGuestConfig f gs =
    { gs | config = f gs.config }


toAuthState : Creds -> TripId.TripId -> Tab -> GuestState -> AuthState
toAuthState creds initialTripId initialTab gs =
    { activeScanItemId  = Nothing
    , amendments        = []
    , basePath          = gs.basePath
    , config            = gs.session.config
    , confirmDeleteTrip = Nothing
    , creds             = creds
    , currentTripId     = initialTripId
    , editingEntry      = Nothing
    , error             = Nothing
    , expensesState     = NotAsked
    , geoBlocked        = False
    , key               = gs.key
    , pendingEditEntry  = Nothing
    , pendingEntry      = defaultPendingEntry gs.today
    , rawExpenses       = []
    , scanQueue         = Dict.empty
    , showLedgerMap     = False
    , showMapPicker     = False
    , submitting        = False
    , syncState         = NotEnabled
    , tab               = initialTab
    , toast             = Nothing
    , today             = gs.today
    , tripForm          = Nothing
    , trips             = Dict.empty
    , version           = gs.version
    , voids             = []
    }


toGuestState : GuestReason -> AuthState -> GuestState
toGuestState reason as_ =
    { authError    = Nothing
    , basePath     = as_.basePath
    , codeInput    = ""
    , emailInput   = ""
    , key          = as_.key
    , session      = { config = as_.config, reason = reason }
    , showSettings = reason == SessionExpired
    , today        = as_.today
    , version      = as_.version
    }



-- POUCHDB PROTOCOL


encodePouchOut : PouchOutbound -> D.Value
encodePouchOut msg =
    case msg of
        GetAllTrips      -> E.object [ ( "tag", E.string "GetAllTrips" ) ]
        GetExpenses id   -> E.object [ ( "tag", E.string "GetExpenses" ), ( "tripId", E.string id ) ]
        SaveAmend doc    -> E.object [ ( "tag", E.string "SaveAmend" ),   ( "doc", doc ) ]
        SaveExpense doc  -> E.object [ ( "tag", E.string "SaveExpense" ), ( "doc", doc ) ]
        SaveTrip doc     -> E.object [ ( "tag", E.string "SaveTrip" ),    ( "doc", doc ) ]
        SaveVoid doc     -> E.object [ ( "tag", E.string "SaveVoid" ),    ( "doc", doc ) ]


sendPouch : PouchOutbound -> Cmd Msg
sendPouch =
    pouchOut << encodePouchOut


pouchInDecoder : D.Decoder PouchInbound
pouchInDecoder =
    D.field "tag" D.string
        |> D.andThen
            (\tag ->
                case tag of
                    "AuthExpired"   -> D.succeed AuthExpiredMsg
                    "DbChange"      -> D.map DbChange dbChangeDataDecoder
                    "DbError"       -> D.map DbError (D.field "message" D.string)
                    "QueryComplete" -> D.map QueryComplete (D.field "queryType" D.string)
                    "SyncState"     -> D.map SyncStateMsg (D.field "state" syncStateDecoder)
                    _               -> D.fail ("Unknown pouchIn tag: " ++ tag)
            )


dbChangeDataDecoder : D.Decoder DbChangeData
dbChangeDataDecoder =
    D.map3 DbChangeData
        (D.field "deleted" D.bool)
        (D.field "doc" D.value)
        (D.field "id" D.string)


syncStateDecoder : D.Decoder SyncState
syncStateDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "auth_error" -> D.succeed AuthExpired
                    "error"      -> D.succeed SyncError
                    "synced"     -> D.succeed Synced
                    "syncing"    -> D.succeed Syncing
                    _            -> D.succeed NotEnabled
            )



-- DB HELPERS


upsertBy : (a -> String) -> a -> List a -> List a
upsertBy getId item list =
    if List.any (\x -> getId x == getId item) list then
        List.map (\x -> if getId x == getId item then item else x) list
    else
        list ++ [ item ]


recomputeEntries : AuthState -> AuthState
recomputeEntries as_ =
    case as_.expensesState of
        Loading ->
            as_

        _ ->
            { as_ | expensesState = Loaded (Entry.resolve as_.rawExpenses as_.amendments as_.voids as_.currentTripId) }


handleDbChange : D.Value -> AuthState -> ( Model, Cmd Msg )
handleDbChange doc as_ =
    case D.decodeValue (D.field "type" D.string) doc of
        Ok "trip" ->
            case D.decodeValue Trip.decoder doc of
                Ok trip ->
                    ( AuthModel { as_ | trips = Dict.insert (TripId.toString trip.id) trip as_.trips }
                    , Cmd.none
                    )

                Err _ ->
                    ( AuthModel as_, Cmd.none )

        Ok "expense" ->
            case D.decodeValue Expense.decoder doc of
                Ok expense ->
                    let
                        rawExpenses =
                            upsertBy (ExpenseId.toString << .id) expense as_.rawExpenses
                    in
                    ( AuthModel (recomputeEntries { as_ | rawExpenses = rawExpenses }), Cmd.none )

                Err _ ->
                    ( AuthModel as_, Cmd.none )

        Ok "amend" ->
            case D.decodeValue Amendment.decoder doc of
                Ok amend ->
                    let
                        amendments =
                            upsertBy .id amend as_.amendments
                    in
                    ( AuthModel (recomputeEntries { as_ | amendments = amendments }), Cmd.none )

                Err _ ->
                    ( AuthModel as_, Cmd.none )

        Ok "void" ->
            case D.decodeValue Void.decoder doc of
                Ok v ->
                    let
                        voids =
                            upsertBy .id v as_.voids
                    in
                    ( AuthModel (recomputeEntries { as_ | voids = voids }), Cmd.none )

                Err _ ->
                    ( AuthModel as_, Cmd.none )

        _ ->
            ( AuthModel as_, Cmd.none )


handleDbDelete : String -> AuthState -> ( Model, Cmd Msg )
handleDbDelete id as_ =
    let
        rawExpenses =
            List.filter (\e -> ExpenseId.toString e.id /= id) as_.rawExpenses

        newTrips =
            Dict.remove id as_.trips

        newCurrentTripId =
            if TripId.toString as_.currentTripId == id then
                Dict.values newTrips
                    |> List.sortBy (TripId.toString << .id)
                    |> List.head
                    |> Maybe.map .id
                    |> Maybe.withDefault as_.currentTripId
            else
                as_.currentTripId

        amendments =
            List.filter (\a -> a.id /= id) as_.amendments

        newVoids =
            List.filter (\v -> v.id /= id) as_.voids
    in
    ( AuthModel
        (recomputeEntries
            { as_
                | amendments    = amendments
                , currentTripId = newCurrentTripId
                , rawExpenses   = rawExpenses
                , trips         = newTrips
                , voids         = newVoids
            }
        )
    , Cmd.none
    )



-- APP STATE HELPERS


defaultPendingEntry : String -> PendingEntry
defaultPendingEntry today =
    { amount        = ""
    , category      = Fuel
    , date          = today
    , locationState = LocationIdle
    , longNote      = ""
    , merchant      = ""
    , note          = ""
    }


expenseToPending : Expense.Expense -> PendingEntry
expenseToPending e =
    { amount        = String.fromFloat e.amount
    , category      = e.category
    , date          = e.date
    , locationState =
        case ( e.lat, e.lon ) of
            ( Just la, Just lo ) -> LocationGot la lo ManualPin
            _                    -> LocationIdle
    , longNote      = e.longNote
    , merchant      = e.merchant
    , note          = e.note
    }


toastFor : String -> Cmd Msg
toastFor _ =
    Task.perform (\_ -> ToastExpired) (Process.sleep 4000)


setLocation : LocationState -> PendingEntry -> PendingEntry
setLocation ls p =
    { p | locationState = ls }


freshScanItem : String -> ScanItem
freshScanItem id =
    { exifDebug     = ""
    , id            = id
    , imageUrl      = ""
    , locationState = LocationCheckingExif
    , ocrData       = Nothing
    , status        = ScanQueued
    }


authPending : (PendingEntry -> PendingEntry) -> AuthState -> ( Model, Cmd Msg )
authPending f as_ =
    ( AuthModel { as_ | pendingEntry = f as_.pendingEntry }, Cmd.none )



-- OCR


ocrSystemPrompt : String
ocrSystemPrompt =
    "You are a receipt parser. Extract expense info and return ONLY raw valid JSON with no markdown, no code fences, no explanation. Format exactly: {\"amount\": <number>, \"category\": \"<activities|camp|ferry|food|fuel|gear|lodging|medical|misc|parks|shopping|transport>\", \"note\": \"<brief description max 50 chars>\", \"longNote\": \"<detailed description max 560 chars, include what was purchased, where, any relevant context>\", \"merchant\": \"<store name>\", \"date\": \"<YYYY-MM-DD or null if not visible on receipt>\"}. Choose the best matching category. Use parks for national/state park entry fees. Use these note formats by category — fuel: \"$X.XX/gal Xgal Grade\" (e.g. \"$4.29/gal 12.3gal Regular\"); camp: \"$XX/night HookupType\" (e.g. \"$35/night Full\"); lodging: \"$XX/night Xnights\" (e.g. \"$89/night 2nights\"); ferry: \"Origin→Dest vehicle|foot\" (e.g. \"Juneau→Haines car\"); parks: \"PassType ParkName\" (e.g. \"Day Pass Denali\"); activities: \"Xppl Activity\" (e.g. \"2ppl Kayaking\"); food: \"Xppl MealType\" (e.g. \"3ppl Dinner\"); all others: brief description."


makeOcrCall : String -> String -> String -> String -> Cmd Msg
makeOcrCall itemId apiKey base64Data mimeType =
    let
        body =
            E.object
                [ ( "model", E.string "claude-sonnet-4-6" )
                , ( "max_tokens", E.int 256 )
                , ( "system", E.string ocrSystemPrompt )
                , ( "messages"
                  , E.list identity
                        [ E.object
                            [ ( "role", E.string "user" )
                            , ( "content"
                              , E.list identity
                                    [ E.object
                                        [ ( "type", E.string "image" )
                                        , ( "source"
                                          , E.object
                                                [ ( "type", E.string "base64" )
                                                , ( "media_type", E.string mimeType )
                                                , ( "data", E.string base64Data )
                                                ]
                                          )
                                        ]
                                    , E.object
                                        [ ( "type", E.string "text" )
                                        , ( "text", E.string "Extract the expense info from this receipt." )
                                        ]
                                    ]
                              )
                            ]
                        ]
                  )
                ]
    in
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "x-api-key" apiKey
            , Http.header "anthropic-version" "2023-06-01"
            , Http.header "anthropic-dangerous-direct-browser-access" "true"
            ]
        , url = "https://api.anthropic.com/v1/messages"
        , body = Http.jsonBody body
        , expect = Http.expectString (GotOcrResult itemId)
        , timeout = Nothing
        , tracker = Nothing
        }


claudeTextDecoder : D.Decoder String
claudeTextDecoder =
    D.field "content" (D.index 0 (D.field "text" D.string))


ocrDataDecoder : D.Decoder OcrData
ocrDataDecoder =
    D.succeed OcrData
        |> Pipeline.optional "amount"   (D.map Just D.float) Nothing
        |> Pipeline.optional "category" (D.map Just (D.map Category.fromString D.string)) Nothing
        |> Pipeline.optional "date"     (D.map Just D.string) Nothing
        |> Pipeline.optional "longNote" (D.map Just D.string) Nothing
        |> Pipeline.optional "merchant" (D.map Just D.string) Nothing
        |> Pipeline.optional "note"     (D.map Just D.string) Nothing


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
                    if List.reverse lines |> List.head |> Maybe.map (String.startsWith "```") |> Maybe.withDefault False then
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
        _ :: b64 :: _ -> b64
        _              -> dataUrl


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



-- TIME


posixToIso : Time.Posix -> String
posixToIso posix =
    let
        y  = String.fromInt (Time.toYear Time.utc posix)
        m  = String.fromInt (monthNum (Time.toMonth Time.utc posix)) |> String.padLeft 2 '0'
        d  = String.fromInt (Time.toDay Time.utc posix) |> String.padLeft 2 '0'
        h  = String.fromInt (Time.toHour Time.utc posix) |> String.padLeft 2 '0'
        mi = String.fromInt (Time.toMinute Time.utc posix) |> String.padLeft 2 '0'
        s  = String.fromInt (Time.toSecond Time.utc posix) |> String.padLeft 2 '0'
    in
    y ++ "-" ++ m ++ "-" ++ d ++ "T" ++ h ++ ":" ++ mi ++ ":" ++ s ++ "Z"


monthNum : Time.Month -> Int
monthNum month =
    case month of
        Time.Jan -> 1
        Time.Feb -> 2
        Time.Mar -> 3
        Time.Apr -> 4
        Time.May -> 5
        Time.Jun -> 6
        Time.Jul -> 7
        Time.Aug -> 8
        Time.Sep -> 9
        Time.Oct -> 10
        Time.Nov -> 11
        Time.Dec -> 12



-- INIT


init : D.Value -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flagsJson url key =
    let
        dec field_ =
            D.decodeValue (D.field field_ D.string) flagsJson
                |> Result.withDefault ""

        sessionToken =
            D.decodeValue (D.maybe (D.field "sessionToken" D.string)) flagsJson
                |> Result.withDefault Nothing
                |> Maybe.andThen (\t -> if t == "" then Nothing else Just t)

        cfg =
            { anthropicKey = dec "anthropicKey"
            , backendUrl   = dec "backendUrl"
            }

        basePath =
            dec "basePath"

        gs =
            { authError    = Nothing
            , basePath     = basePath
            , codeInput    = ""
            , emailInput   = ""
            , key          = key
            , session      = { config = cfg, reason = NotLoggedIn }
            , showSettings = False
            , today        = dec "today"
            , version      = dec "version"
            }
    in
    case sessionToken of
        Nothing ->
            ( GuestModel gs, Cmd.none )

        Just userId ->
            let
                initialRoute =
                    Routing.routeFromUrl basePath url

                initialTripId =
                    Routing.routeTripId initialRoute
                        |> Maybe.withDefault (TripId.fromString "trip::placeholder")

                as_ =
                    toAuthState { userId = userId } initialTripId (Routing.routeToTab initialRoute) gs

                pendingEdit =
                    case initialRoute of
                        RouteEditEntry tripId entryId ->
                            Just { entryId = entryId, tripId = tripId }

                        _ ->
                            Nothing
            in
            ( AuthModel { as_ | pendingEditEntry = pendingEdit }, sendPouch GetAllTrips )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case model of
        GuestModel gs ->
            updateGuest msg gs

        AuthModel as_ ->
            updateAuth msg as_


updateGuest : Msg -> GuestState -> ( Model, Cmd Msg )
updateGuest msg gs =
    case msg of
        EmailInputChanged s ->
            ( GuestModel { gs | emailInput = s }, Cmd.none )

        SubmitEmail ->
            if String.trim gs.emailInput == "" then
                ( GuestModel { gs | authError = Just "Enter your email address." }, Cmd.none )
            else
                ( GuestModel
                    { gs
                        | authError = Nothing
                        , session   = { config = gs.session.config, reason = AwaitingCode gs.emailInput }
                    }
                , Cmd.none
                )

        CodeInputChanged s ->
            ( GuestModel { gs | codeInput = s }, Cmd.none )

        SubmitCode ->
            let
                userId = gs.emailInput
                creds  = { userId = userId }
                as_    = toAuthState creds (TripId.fromString "trip::placeholder") TripsTab gs
            in
            ( AuthModel as_
            , Cmd.batch
                [ saveStorage { key = "session_token", value = userId }
                , sendPouch GetAllTrips
                , Nav.replaceUrl gs.key (gs.basePath ++ "trips")
                ]
            )

        ToggleGuestSettings ->
            ( GuestModel { gs | showSettings = not gs.showSettings }, Cmd.none )

        ApiKeyChanged s ->
            ( GuestModel { gs | session = mapGuestConfig (\c -> { c | anthropicKey = s }) gs.session }
            , saveStorage { key = "anthropic_key", value = s }
            )

        ResetSettingsClicked ->
            ( GuestModel
                { gs
                    | authError    = Nothing
                    , codeInput    = ""
                    , emailInput   = ""
                    , session      = { config = { anthropicKey = "", backendUrl = "" }, reason = NotLoggedIn }
                    , showSettings = False
                }
            , clearAllStorage ()
            )

        GotPouchMsg raw ->
            case D.decodeValue pouchInDecoder raw of
                Ok (DbChange data) ->
                    case D.decodeValue (D.field "type" D.string) data.doc of
                        Ok "trip" ->
                            case D.decodeValue Trip.decoder data.doc of
                                Ok trip ->
                                    let
                                        storedUserId =
                                            case gs.session.reason of
                                                AwaitingCode email -> email
                                                _                  -> gs.emailInput

                                        creds = { userId = storedUserId }
                                        as_   = toAuthState creds trip.id LedgerTab gs
                                    in
                                    ( AuthModel as_
                                    , Cmd.batch
                                        [ sendPouch GetAllTrips
                                        , Nav.replaceUrl gs.key (Routing.tabToPath gs.basePath trip.id LedgerTab)
                                        ]
                                    )

                                Err _ ->
                                    ( GuestModel gs, Cmd.none )

                        _ ->
                            ( GuestModel gs, Cmd.none )

                _ ->
                    ( GuestModel gs, Cmd.none )

        LinkClicked (Browser.Internal url) ->
            ( GuestModel gs, Nav.pushUrl gs.key (Url.toString url) )

        LinkClicked (Browser.External href) ->
            ( GuestModel gs, Nav.load href )

        _ ->
            ( GuestModel gs, Cmd.none )


updateAuth : Msg -> AuthState -> ( Model, Cmd Msg )
updateAuth msg as_ =
    case msg of
        GotPouchMsg raw ->
            case D.decodeValue pouchInDecoder raw of
                Ok (DbChange data) ->
                    if data.deleted then
                        handleDbDelete data.id as_
                    else
                        handleDbChange data.doc as_

                Ok (QueryComplete "expenses") ->
                    let
                        resolved =
                            Entry.resolve as_.rawExpenses as_.amendments as_.voids as_.currentTripId
                    in
                    case as_.pendingEditEntry of
                        Just { entryId } ->
                            case resolved |> List.filter (\e -> e.id == entryId) |> List.head of
                                Just effective ->
                                    let
                                        expense =
                                            Helpers.effectiveEntryToExpense effective
                                    in
                                    ( AuthModel
                                        { as_
                                            | editingEntry     = Just expense
                                            , expensesState    = Loaded resolved
                                            , pendingEditEntry = Nothing
                                            , pendingEntry     = expenseToPending expense
                                            , tab              = AddTab
                                        }
                                    , Cmd.none
                                    )

                                Nothing ->
                                    ( AuthModel { as_ | expensesState = Loaded resolved, pendingEditEntry = Nothing }
                                    , Cmd.none
                                    )

                        Nothing ->
                            ( AuthModel { as_ | expensesState = Loaded resolved }, Cmd.none )

                Ok (QueryComplete "trips") ->
                    case as_.pendingEditEntry of
                        Just { tripId } ->
                            ( AuthModel
                                { as_
                                    | currentTripId    = tripId
                                    , expensesState    = Loading
                                    , pendingEditEntry = Nothing
                                }
                            , sendPouch (GetExpenses (TripId.toString tripId))
                            )

                        Nothing ->
                            ( AuthModel { as_ | expensesState = Loading }
                            , sendPouch (GetExpenses (TripId.toString as_.currentTripId))
                            )

                Ok (QueryComplete _) ->
                    ( AuthModel as_, Cmd.none )

                Ok (DbError msg_) ->
                    ( AuthModel { as_ | error = Just msg_ }, Cmd.none )

                Ok (SyncStateMsg state) ->
                    ( AuthModel { as_ | syncState = state }, Cmd.none )

                Ok AuthExpiredMsg ->
                    ( GuestModel (toGuestState SessionExpired as_), clearStorage () )

                Err _ ->
                    ( AuthModel as_, Cmd.none )

        SignOutClicked ->
            ( GuestModel (toGuestState NotLoggedIn as_), clearStorage () )

        ResetSettingsClicked ->
            ( GuestModel
                { authError    = Nothing
                , basePath     = as_.basePath
                , codeInput    = ""
                , emailInput   = ""
                , key          = as_.key
                , session      = { config = { anthropicKey = "", backendUrl = "" }, reason = NotLoggedIn }
                , showSettings = False
                , today        = as_.today
                , version      = as_.version
                }
            , clearAllStorage ()
            )

        FilesSelected files ->
            let
                startIdx =
                    Dict.size as_.scanQueue

                indexed =
                    List.indexedMap (\i f -> ( "scan-" ++ String.fromInt (startIdx + i), f )) files

                newQueue =
                    List.foldl (\( id, _ ) d -> Dict.insert id (freshScanItem id) d) as_.scanQueue indexed

                urlCmds =
                    List.map (\( id, f ) -> Task.perform (GotFileUrl id) (File.toUrl f)) indexed
            in
            ( AuthModel { as_ | scanQueue = newQueue }, Cmd.batch urlCmds )

        GotFileUrl itemId dataUrl ->
            let
                newStatus =
                    if as_.config.anthropicKey /= "" then ScanProcessing else ScanReady

                updatedQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | imageUrl = dataUrl, status = newStatus })) as_.scanQueue
            in
            ( AuthModel { as_ | scanQueue = updatedQueue }
            , Cmd.batch
                [ if as_.config.anthropicKey /= "" then
                    makeOcrCall itemId as_.config.anthropicKey (extractBase64 dataUrl) (getMimeType dataUrl)
                  else
                    Cmd.none
                , extractExifGps { id = itemId, dataUrl = dataUrl }
                ]
            )

        GotOcrResult itemId result ->
            let
                ocrData =
                    case result of
                        Ok responseBody ->
                            case D.decodeString claudeTextDecoder responseBody of
                                Ok innerJson ->
                                    case D.decodeString ocrDataDecoder (stripCodeFence innerJson) of
                                        Ok data -> Just data
                                        Err _   -> Nothing
                                Err _ -> Nothing
                        Err _ -> Nothing

                updatedQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | status = ScanReady, ocrData = ocrData })) as_.scanQueue
            in
            ( AuthModel { as_ | scanQueue = updatedQueue }, Cmd.none )

        AmountChanged s   -> authPending (\p -> { p | amount = s }) as_
        CategorySelected c -> authPending (\p -> { p | category = c }) as_
        NoteChanged s     -> authPending (\p -> { p | note = s }) as_
        LongNoteChanged s -> authPending (\p -> { p | longNote = s }) as_
        MerchantChanged s -> authPending (\p -> { p | merchant = s }) as_
        DateChanged s     -> authPending (\p -> { p | date = s }) as_

        SubmitEntry ->
            case String.toFloat as_.pendingEntry.amount of
                Just _ ->
                    ( AuthModel { as_ | submitting = True, error = Nothing }
                    , Task.perform GotSubmitTime Time.now
                    )
                Nothing ->
                    ( AuthModel { as_ | error = Just "Enter a valid amount." }, Cmd.none )

        GotSubmitTime posix ->
            let
                p         = as_.pendingEntry
                timestamp = String.fromInt (Time.posixToMillis posix)

                ( eLat, eLon ) =
                    case p.locationState of
                        LocationGot la lo _ -> ( Just la, Just lo )
                        _                   -> ( Nothing, Nothing )
            in
            case as_.editingEntry of
                Just original ->
                    let
                        amendId =
                            "amend::" ++ ExpenseId.toString original.id ++ "::" ++ String.left 8 timestamp

                        amend =
                            { id        = amendId
                            , targetId  = original.id
                            , amount    = if p.amount /= String.fromFloat original.amount then String.toFloat p.amount else Nothing
                            , category  = if p.category /= original.category then Just p.category else Nothing
                            , createdAt = posixToIso posix
                            , date      = if p.date /= original.date then Just p.date else Nothing
                            , longNote  = if p.longNote /= original.longNote then Just p.longNote else Nothing
                            , merchant  = if p.merchant /= original.merchant then Just p.merchant else Nothing
                            , note      = if p.note /= original.note then Just p.note else Nothing
                            }

                        updatedQueue =
                            case as_.activeScanItemId of
                                Just id -> Dict.update id (Maybe.map (\i -> { i | status = ScanSubmitted })) as_.scanQueue
                                Nothing -> as_.scanQueue

                        hasRemaining =
                            Dict.values updatedQueue |> List.any (\i -> i.status /= ScanSubmitted)

                        nextTab =
                            if as_.activeScanItemId /= Nothing && hasRemaining then ScanTab else LedgerTab
                    in
                    ( AuthModel
                        { as_
                            | activeScanItemId = Nothing
                            , editingEntry     = Nothing
                            , pendingEntry     = defaultPendingEntry as_.today
                            , scanQueue        = updatedQueue
                            , submitting       = False
                            , tab              = nextTab
                        }
                    , sendPouch (SaveAmend (Amendment.encoder amend))
                    )

                Nothing ->
                    let
                        expenseId =
                            "expense::" ++ posixToIso posix ++ "::" ++ String.left 8 timestamp

                        expense =
                            { id        = ExpenseId.fromString expenseId
                            , tripId    = as_.currentTripId
                            , amount    = String.toFloat p.amount |> Maybe.withDefault 0
                            , category  = p.category
                            , createdAt = posixToIso posix
                            , date      = p.date
                            , lat       = eLat
                            , lon       = eLon
                            , longNote  = p.longNote
                            , merchant  = p.merchant
                            , note      = p.note
                            }

                        updatedQueue =
                            case as_.activeScanItemId of
                                Just id -> Dict.update id (Maybe.map (\i -> { i | status = ScanSubmitted })) as_.scanQueue
                                Nothing -> as_.scanQueue

                        hasRemaining =
                            Dict.values updatedQueue |> List.any (\i -> i.status /= ScanSubmitted)

                        nextTab =
                            if as_.activeScanItemId /= Nothing && hasRemaining then ScanTab else LedgerTab
                    in
                    ( AuthModel
                        { as_
                            | activeScanItemId = Nothing
                            , pendingEntry     = defaultPendingEntry as_.today
                            , scanQueue        = updatedQueue
                            , submitting       = False
                            , tab              = nextTab
                        }
                    , sendPouch (SaveExpense (Expense.encoder expense))
                    )

        VoidEntry expense ->
            let
                voidId =
                    "void::" ++ ExpenseId.toString expense.id ++ "::del"

                updatedState =
                    case as_.expensesState of
                        Loaded entries -> Loaded (List.filter (\e -> e.id /= expense.id) entries)
                        other          -> other
            in
            ( AuthModel { as_ | expensesState = updatedState }
            , sendPouch
                (SaveVoid
                    (E.object
                        [ ( "_id",      E.string voidId )
                        , ( "targetId", E.string (ExpenseId.toString expense.id) )
                        , ( "createdAt", E.string as_.today )
                        , ( "type",     E.string "void" )
                        ]
                    )
                )
            )

        EditEntry expense ->
            ( AuthModel
                { as_
                    | editingEntry = Just expense
                    , error        = Nothing
                    , pendingEntry = expenseToPending expense
                    , tab          = AddTab
                }
            , Nav.pushUrl as_.key (Routing.editEntryPath as_.basePath expense.tripId expense.id)
            )

        CancelEdit ->
            ( AuthModel
                { as_
                    | editingEntry     = Nothing
                    , pendingEditEntry = Nothing
                    , pendingEntry     = defaultPendingEntry as_.today
                    , tab              = LedgerTab
                }
            , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath as_.currentTripId LedgerTab)
            )

        TabChanged tab ->
            let
                geoCmd =
                    if tab == AddTab && not as_.geoBlocked then requestGeolocation () else Cmd.none

                basePending =
                    if tab == AddTab && as_.editingEntry /= Nothing then
                        defaultPendingEntry as_.today
                    else
                        as_.pendingEntry

                newPending =
                    if tab == AddTab && not as_.geoBlocked then
                        setLocation LocationFetching basePending
                    else
                        basePending
            in
            ( AuthModel
                { as_
                    | editingEntry     = Nothing
                    , pendingEditEntry = Nothing
                    , pendingEntry     = newPending
                    , tab              = tab
                    , tripForm         = Nothing
                }
            , Cmd.batch [ geoCmd, Nav.pushUrl as_.key (Routing.tabToPath as_.basePath as_.currentTripId tab) ]
            )

        RefreshClicked ->
            ( AuthModel { as_ | expensesState = Loading }
            , sendPouch (GetExpenses (TripId.toString as_.currentTripId))
            )

        ApiKeyChanged s ->
            let cfg = as_.config in
            ( AuthModel { as_ | config = { cfg | anthropicKey = s } }
            , saveStorage { key = "anthropic_key", value = s }
            )

        DismissError ->
            ( AuthModel { as_ | error = Nothing }, Cmd.none )

        GotGpsCoords lat lon ->
            authPending (setLocation (LocationGot lat lon BrowserGeo)) as_

        GeolocationDenied ->
            ( AuthModel { as_ | geoBlocked = True, pendingEntry = setLocation LocationIdle as_.pendingEntry }
            , Cmd.none
            )

        OpenMapPicker ->
            ( AuthModel { as_ | showMapPicker = True }, Cmd.none )

        MapPickerConfirmed lat lon ->
            ( AuthModel { as_ | pendingEntry = setLocation (LocationGot lat lon ManualPin) as_.pendingEntry, showMapPicker = False }
            , Cmd.none
            )

        DismissMapPicker ->
            ( AuthModel { as_ | showMapPicker = False }, Cmd.none )

        SkipLocation ->
            ( AuthModel { as_ | pendingEntry = setLocation LocationSkipped as_.pendingEntry, showMapPicker = False }
            , Cmd.none
            )

        ToggleLedgerMap ->
            ( AuthModel { as_ | showLedgerMap = not as_.showLedgerMap }, Cmd.none )

        ShowToast message ->
            ( AuthModel { as_ | toast = Just message }, toastFor message )

        ToastExpired ->
            ( AuthModel { as_ | toast = Nothing }, Cmd.none )

        GotExifCoords itemId (Just lat) (Just lon) _ ->
            ( AuthModel { as_ | scanQueue = Dict.update itemId (Maybe.map (\i -> { i | locationState = LocationGot lat lon ExifGps })) as_.scanQueue }
            , Cmd.none
            )

        GotExifCoords itemId _ _ debug ->
            ( AuthModel { as_ | scanQueue = Dict.update itemId (Maybe.map (\i -> { i | locationState = LocationNoExifGps, exifDebug = debug })) as_.scanQueue }
            , Cmd.none
            )

        ReviewScanItem itemId ->
            case Dict.get itemId as_.scanQueue of
                Nothing ->
                    ( AuthModel as_, Cmd.none )

                Just item ->
                    let
                        ocr =
                            Maybe.withDefault
                                { amount = Nothing, category = Nothing, date = Nothing, longNote = Nothing, merchant = Nothing, note = Nothing }
                                item.ocrData

                        newPending =
                            { amount        = ocr.amount |> Maybe.map String.fromFloat |> Maybe.withDefault ""
                            , category      = Maybe.withDefault Fuel ocr.category
                            , date          = Maybe.withDefault as_.today ocr.date
                            , locationState = item.locationState
                            , longNote      = Maybe.withDefault "" ocr.longNote
                            , merchant      = Maybe.withDefault "" ocr.merchant
                            , note          = Maybe.withDefault "" ocr.note
                            }
                    in
                    ( AuthModel
                        { as_
                            | activeScanItemId = Just itemId
                            , error            = Nothing
                            , pendingEntry     = newPending
                            , tab              = AddTab
                        }
                    , Cmd.none
                    )

        BackToQueue ->
            ( AuthModel
                { as_
                    | activeScanItemId = Nothing
                    , pendingEntry     = defaultPendingEntry as_.today
                    , tab              = ScanTab
                }
            , Cmd.none
            )

        ClearDoneItems ->
            ( AuthModel { as_ | scanQueue = Dict.filter (\_ i -> i.status /= ScanSubmitted) as_.scanQueue }
            , Cmd.none
            )

        SelectTrip tripId ->
            if Dict.member (TripId.toString tripId) as_.trips then
                ( AuthModel
                    { as_
                        | currentTripId = tripId
                        , editingEntry  = Nothing
                        , expensesState = Loading
                        , pendingEntry  = defaultPendingEntry as_.today
                        , tab           = LedgerTab
                    }
                , Cmd.batch
                    [ sendPouch (GetExpenses (TripId.toString tripId))
                    , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath tripId LedgerTab)
                    ]
                )

            else
                ( AuthModel as_, Cmd.none )

        OpenNewTripForm ->
            ( AuthModel
                { as_
                    | tripForm = Just
                        { budget        = ""
                        , coverPhotoUrl = ""
                        , description   = ""
                        , editing       = Nothing
                        , endDate       = ""
                        , errors        = []
                        , name          = ""
                        , startDate     = as_.today
                        }
                }
            , Cmd.none
            )

        OpenEditTripForm trip ->
            ( AuthModel
                { as_
                    | tripForm = Just
                        { budget        = if trip.budget > 0 then String.fromFloat trip.budget else ""
                        , coverPhotoUrl = trip.coverPhotoUrl
                        , description   = trip.description
                        , editing       = Just trip
                        , endDate       = trip.endDate
                        , errors        = []
                        , name          = trip.name
                        , startDate     = trip.startDate
                        }
                }
            , Cmd.none
            )

        TripFieldChanged field value ->
            let
                updateForm f =
                    case field of
                        TripBudget      -> { f | budget = value }
                        TripCoverPhoto  -> { f | coverPhotoUrl = value }
                        TripDescription -> { f | description = value }
                        TripEndDate     -> { f | endDate = value }
                        TripName        -> { f | name = value }
                        TripStartDate   -> { f | startDate = value }
            in
            ( AuthModel { as_ | tripForm = Maybe.map updateForm as_.tripForm }, Cmd.none )

        SaveTripForm ->
            case as_.tripForm of
                Nothing ->
                    ( AuthModel as_, Cmd.none )

                Just form ->
                    case Validate.validate Trip.validator form of
                        Err errs ->
                            ( AuthModel { as_ | tripForm = Just { form | errors = errs } }, Cmd.none )

                        Ok _ ->
                            case form.editing of
                                Just existing ->
                                    let
                                        updated =
                                            { existing
                                                | budget        = String.toFloat form.budget |> Maybe.withDefault 0
                                                , coverPhotoUrl = form.coverPhotoUrl
                                                , description   = form.description
                                                , endDate       = form.endDate
                                                , name          = form.name
                                                , startDate     = form.startDate
                                            }

                                        trips_ =
                                            Dict.insert (TripId.toString existing.id) updated as_.trips
                                    in
                                    ( AuthModel { as_ | tripForm = Nothing, trips = trips_ }
                                    , sendPouch (SaveTrip (Trip.encoder updated))
                                    )

                                Nothing ->
                                    ( AuthModel as_, Task.perform GotSaveTripTime Time.now )

        GotSaveTripTime posix ->
            case as_.tripForm of
                Nothing ->
                    ( AuthModel as_, Cmd.none )

                Just form ->
                    let
                        timestamp = String.fromInt (Time.posixToMillis posix)
                        tripId    = TripId.fromString ("trip::" ++ posixToIso posix ++ "::" ++ String.left 8 timestamp)

                        newTrip =
                            { id            = tripId
                            , budget        = String.toFloat form.budget |> Maybe.withDefault 0
                            , coverPhotoUrl = form.coverPhotoUrl
                            , description   = form.description
                            , endDate       = form.endDate
                            , name          = form.name
                            , startDate     = form.startDate
                            }

                        trips_ =
                            Dict.insert (TripId.toString tripId) newTrip as_.trips
                    in
                    ( AuthModel
                        { as_
                            | currentTripId = tripId
                            , editingEntry  = Nothing
                            , expensesState = Loading
                            , pendingEntry  = defaultPendingEntry as_.today
                            , tab           = LedgerTab
                            , tripForm      = Nothing
                            , trips         = trips_
                        }
                    , Cmd.batch
                        [ sendPouch (SaveTrip (Trip.encoder newTrip))
                        , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath tripId LedgerTab)
                        ]
                    )

        ConfirmDeleteTrip trip ->
            ( AuthModel { as_ | confirmDeleteTrip = Just trip }, Cmd.none )

        CancelDeleteTrip ->
            ( AuthModel { as_ | confirmDeleteTrip = Nothing }, Cmd.none )

        DeleteTrip trip ->
            let
                newTrips =
                    Dict.remove (TripId.toString trip.id) as_.trips
            in
            if Dict.isEmpty newTrips then
                ( AuthModel { as_ | confirmDeleteTrip = Nothing }, Cmd.none )

            else
                let
                    newCurrentId =
                        if as_.currentTripId == trip.id then
                            Dict.values newTrips
                                |> List.sortBy (TripId.toString << .id)
                                |> List.head
                                |> Maybe.map .id
                                |> Maybe.withDefault as_.currentTripId
                        else
                            as_.currentTripId

                    voidId =
                        "void::" ++ TripId.toString trip.id ++ "::del"
                in
                ( AuthModel
                    { as_
                        | confirmDeleteTrip = Nothing
                        , currentTripId     = newCurrentId
                        , expensesState     = Loading
                        , trips             = newTrips
                    }
                , Cmd.batch
                    [ sendPouch
                        (SaveVoid
                            (E.object
                                [ ( "_id",      E.string voidId )
                                , ( "targetId", E.string (TripId.toString trip.id) )
                                , ( "createdAt", E.string as_.today )
                                , ( "type",     E.string "void" )
                                ]
                            )
                        )
                    , sendPouch (GetExpenses (TripId.toString newCurrentId))
                    , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath newCurrentId LedgerTab)
                    ]
                )

        LinkClicked (Browser.Internal url) ->
            ( AuthModel as_, Nav.pushUrl as_.key (Url.toString url) )

        LinkClicked (Browser.External href) ->
            ( AuthModel as_, Nav.load href )

        UrlChanged url ->
            case Routing.routeFromUrl as_.basePath url of
                RouteEditEntry tripId entryId ->
                    if Maybe.map .id as_.editingEntry == Just entryId then
                        ( AuthModel { as_ | tab = AddTab }, Cmd.none )

                    else
                        let
                            maybeExpense =
                                Entry.resolve as_.rawExpenses as_.amendments as_.voids tripId
                                    |> List.filter (\e -> e.id == entryId)
                                    |> List.head
                                    |> Maybe.map Helpers.effectiveEntryToExpense
                        in
                        case maybeExpense of
                            Just expense ->
                                ( AuthModel
                                    { as_
                                        | editingEntry = Just expense
                                        , pendingEntry = expenseToPending expense
                                        , tab          = AddTab
                                    }
                                , Cmd.none
                                )

                            Nothing ->
                                let
                                    expCmd =
                                        if as_.currentTripId /= tripId then
                                            sendPouch (GetExpenses (TripId.toString tripId))
                                        else
                                            Cmd.none
                                in
                                ( AuthModel
                                    { as_
                                        | currentTripId    = tripId
                                        , pendingEditEntry = Just { entryId = entryId, tripId = tripId }
                                        , tab              = AddTab
                                    }
                                , expCmd
                                )

                route ->
                    let
                        tab =
                            Routing.routeToTab route

                        newCurrentTripId =
                            Routing.routeTripId route
                                |> Maybe.withDefault as_.currentTripId

                        tripChanged =
                            newCurrentTripId /= as_.currentTripId

                        tripLoadCmd =
                            if tripChanged then
                                sendPouch (GetExpenses (TripId.toString newCurrentTripId))
                            else
                                Cmd.none

                        geoCmd =
                            if tab == AddTab && not as_.geoBlocked then requestGeolocation () else Cmd.none

                        newPending =
                            if tab == AddTab && not as_.geoBlocked then
                                setLocation LocationFetching as_.pendingEntry
                            else
                                as_.pendingEntry
                    in
                    ( AuthModel
                        { as_
                            | currentTripId    = newCurrentTripId
                            , editingEntry     = if tab /= AddTab then Nothing else as_.editingEntry
                            , expensesState    = if tripChanged then Loading else as_.expensesState
                            , pendingEditEntry = Nothing
                            , pendingEntry     = newPending
                            , tab              = tab
                            , tripForm         = Nothing
                        }
                    , Cmd.batch [ geoCmd, tripLoadCmd ]
                    )

        _ ->
            ( AuthModel as_, Cmd.none )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "Ternpike"
    , body =
        [ Html.div
            [ Html.Attributes.class "bg-parchment text-ink min-h-screen font-body max-w-[480px] mx-auto relative" ]
            [ case model of
                GuestModel gs -> viewGuest gs
                AuthModel as_ -> viewAuth as_
            ]
        ]
    }


viewAuth : AuthState -> Html Msg
viewAuth as_ =
    let
        route =
            Routing.effectiveRoute as_

        tab =
            case route of
                RouteAdd _         -> Pages.Add.viewTab as_
                RouteAddReviewScan -> Pages.Add.viewTab as_
                RouteEditEntry _ _ -> Pages.Add.viewTab as_
                RouteLedger _      -> Pages.Ledger.viewTab as_
                RouteScan _        -> Pages.Scan.viewTab as_
                RouteSettings      -> Pages.Settings.viewTab as_
                RouteStats _       -> Pages.Stats.viewTab as_
                RouteTrips         -> Pages.Trips.viewTab as_
    in
    Html.div []
        [ UI.Layout.viewHeader as_
        , UI.Layout.viewErrorBanner as_.error
        , Html.div [ Html.Attributes.class "pb-20" ]
            [ UI.Layout.page
                { actions = tab.actions
                , body    = tab.body
                , hero    = tab.hero
                , route   = route
                }
            ]
        , UI.Layout.viewBottomNav as_.tab
        , case as_.confirmDeleteTrip of
            Just trip -> UI.Layout.viewDeleteConfirmModal trip
            Nothing   -> Html.text ""
        , UI.Layout.viewToast as_.toast
        ]



-- MAIN


main : Program D.Value Model Msg
main =
    Browser.application
        { init          = init
        , onUrlChange   = UrlChanged
        , onUrlRequest  = LinkClicked
        , subscriptions =
            \_ ->
                Sub.batch
                    [ pouchIn GotPouchMsg
                    , gotGpsCoords (\r -> if r.denied then GeolocationDenied else GotGpsCoords r.lat r.lon)
                    , gotExifResult (\r -> if r.hasGps then GotExifCoords r.id (Just r.lat) (Just r.lon) "" else GotExifCoords r.id Nothing Nothing r.debug)
                    ]
        , update        = update
        , view          = view
        }
