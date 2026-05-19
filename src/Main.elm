port module Main exposing (main)

import Browser
import Dict exposing (Dict)
import File exposing (File)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Http
import Json.Decode as D
import Json.Decode.Pipeline as Pipeline
import Json.Encode as E
import Chart as C
import Chart.Attributes as CA
import List.NonEmpty.Zipper as Zipper exposing (Zipper)
import Process
import Task
import Time
import Validate exposing (Validator, ifBlank, ifTrue, validate)



-- PORTS


port saveStorage : { key : String, value : String } -> Cmd msg


port clearStorage : () -> Cmd msg


port clearAllStorage : () -> Cmd msg


-- Bool = force consent prompt (True when user explicitly clicks Sign In,
-- False for silent re-auth after a 401)
port requestOAuthToken : Bool -> Cmd msg


port gotNewToken : (String -> msg) -> Sub msg


port requestGeolocation : () -> Cmd msg


port extractExifGps : { id : String, dataUrl : String } -> Cmd msg


port gotGpsCoords : ({ lat : Float, lon : Float, denied : Bool } -> msg) -> Sub msg


port gotExifResult : ({ id : String, lat : Float, lon : Float, hasGps : Bool, debug : String } -> msg) -> Sub msg



-- TYPES


type Category
    = Fuel
    | Food
    | Camp
    | Ferry
    | Gear
    | Lodging
    | Activities
    | Shopping
    | Medical
    | Transport
    | Misc


type Tab
    = AddTab
    | LedgerTab
    | ScanTab
    | SettingsTab
    | StatsTab
    | TripsTab


type LocationSource
    = ExifGps
    | BrowserGeo
    | ManualPin


type LocationState
    = LocationIdle
    | LocationFetching
    | LocationCheckingExif
    | LocationNoExifGps
    | LocationGot Float Float LocationSource
    | LocationSkipped


type ScanStatus
    = ScanQueued
    | ScanProcessing
    | ScanReady
    | ScanSubmitted


type alias ScanItem =
    { id : String
    , imageUrl : String
    , status : ScanStatus
    , ocrData : Maybe OcrData
    , locationState : LocationState
    , exifDebug : String
    }


type alias Trip =
    { budget        : Float
    , coverPhotoUrl : String
    , description   : String
    , endDate       : String
    , name          : String
    , sheetGid      : Int
    , startDate     : String
    , tabName       : String
    }


type alias SheetProp =
    { gid   : Int
    , title : String
    }


type alias TripForm =
    { budget        : String
    , coverPhotoUrl : String
    , description   : String
    , editing       : Maybe Trip
    , endDate       : String
    , errors        : List String
    , name          : String
    , startDate     : String
    }


type TripField
    = TripBudget
    | TripCoverPhoto
    | TripDescription
    | TripEndDate
    | TripName
    | TripStartDate


type alias Entry =
    { id : String
    , date : String
    , amount : Float
    , category : Category
    , note : String
    , longNote : String
    , merchant : String
    , createdAt : String
    , rowIndex : Int
    , lat : Maybe Float
    , lon : Maybe Float
    }


type alias PendingEntry =
    { amount : String
    , category : Category
    , note : String
    , longNote : String
    , merchant : String
    , date : String
    , locationState : LocationState
    }


-- SESSION / AUTH TYPES

type alias Creds =
    { token : String }


type alias AppConfig =
    { anthropicKey   : String
    , googleClientId : String
    , sheetId        : String
    }


type GuestReason
    = FreshGuest
    | MetadataError String
    | MissingConfig
    | SessionExpired


type alias GuestSession =
    { config : AppConfig
    , reason : GuestReason
    }


type alias GuestState =
    { activeTripTab : String
    , pendingToken  : Maybe String
    , session       : GuestSession
    , showSettings  : Bool
    , storedTrips   : List Trip
    , today         : String
    , version       : String
    }


type alias AuthState =
    { activeScanItemId : Maybe String
    , config           : AppConfig
    , creds            : Creds
    , editingEntry     : Maybe Entry
    , entries          : List Entry
    , error            : Maybe String
    , geoBlocked       : Bool
    , loadingEntries   : Bool
    , pendingEntry     : PendingEntry
    , scanQueue        : Dict String ScanItem
    , showLedgerMap    : Bool
    , showMapPicker    : Bool
    , submitting       : Bool
    , tab              : Tab
    , toast            : Maybe String
    , today            : String
    , tripForm         : Maybe TripForm
    , trips            : Zipper Trip
    , version          : String
    }


type Model
    = GuestModel GuestState
    | AuthModel AuthState


type Msg
    = AmountChanged String
    | ApiKeyChanged String
    | BackToQueue
    | CancelEdit
    | CategorySelected Category
    | ClearDoneItems
    | DateChanged String
    | DeleteEntry Entry
    | DeleteTrip Trip
    | DismissError
    | DismissMapPicker
    | EditEntry Entry
    | EntriesFetched (Result Http.Error (List Entry))
    | EntryDeleted (Result Http.Error ())
    | EntrySubmitted (Result Http.Error ())
    | FilesSelected (List File)
    | GeolocationDenied
    | GoogleClientIdChanged String
    | GotExifCoords String (Maybe Float) (Maybe Float) String
    | GotFileUrl String String
    | GotGpsCoords Float Float
    | GotOAuthToken String
    | GotOcrResult String (Result Http.Error String)
    | GotSheetMeta (Result Http.Error (List SheetProp))
    | GotTripCreated (Result Http.Error SheetProp)
    | LongNoteChanged String
    | MapPickerConfirmed Float Float
    | MerchantChanged String
    | NoteChanged String
    | OpenEditTripForm Trip
    | OpenMapPicker
    | OpenNewTripForm
    | RefreshClicked
    | ResetSettingsClicked
    | ReviewScanItem String
    | SaveTripForm
    | SelectTrip String
    | SheetIdChanged String
    | ShowToast String
    | SignInClicked
    | SignOutClicked
    | SkipLocation
    | SubmitEntry
    | GotSubmitTime Time.Posix
    | TabChanged Tab
    | ToggleGuestSettings
    | ToggleLedgerMap
    | ToastExpired
    | TripFieldChanged TripField String



-- CATEGORY HELPERS


categoryColor : Category -> String
categoryColor cat =
    case cat of
        Fuel       -> "#e8a020"
        Food       -> "#3ecf6a"
        Camp       -> "#4090e0"
        Ferry      -> "#c060e0"
        Gear       -> "#e85030"
        Lodging    -> "#40c0b0"
        Activities -> "#f0b040"
        Shopping   -> "#e060a0"
        Medical    -> "#ff6060"
        Transport  -> "#a0a0e0"
        Misc       -> "#7a8a80"


categoryLabel : Category -> String
categoryLabel cat =
    case cat of
        Fuel       -> "fuel"
        Food       -> "food"
        Camp       -> "camp"
        Ferry      -> "ferry"
        Gear       -> "gear"
        Lodging    -> "lodging"
        Activities -> "activities"
        Shopping   -> "shopping"
        Medical    -> "medical"
        Transport  -> "transport"
        Misc       -> "misc"


categoryIcon : Category -> String
categoryIcon cat =
    case cat of
        Fuel       -> "⛽"
        Food       -> "🍔"
        Camp       -> "⛺"
        Ferry      -> "⛴"
        Gear       -> "🔧"
        Lodging    -> "🏨"
        Activities -> "🎯"
        Shopping   -> "🛍"
        Medical    -> "💊"
        Transport  -> "🚌"
        Misc       -> "📦"


categoryFromString : String -> Category
categoryFromString s =
    case s of
        "fuel"       -> Fuel
        "food"       -> Food
        "camp"       -> Camp
        "ferry"      -> Ferry
        "gear"       -> Gear
        "lodging"    -> Lodging
        "activities" -> Activities
        "shopping"   -> Shopping
        "medical"    -> Medical
        "transport"  -> Transport
        _            -> Misc


allCategories : List Category
allCategories =
    [ Fuel, Food, Camp, Lodging, Ferry, Activities, Shopping, Gear, Transport, Medical, Misc ]


-- SESSION HELPERS


guestMessage : GuestReason -> Maybe String
guestMessage reason =
    case reason of
        FreshGuest          -> Nothing
        MetadataError msg   -> Just ("Could not load sheet: " ++ msg)
        MissingConfig       -> Just "Enter your Google Client ID in Settings first."
        SessionExpired      -> Just "Session expired — tap Sign In to continue."


mapGuestConfig : (AppConfig -> AppConfig) -> GuestSession -> GuestSession
mapGuestConfig f gs =
    { gs | config = f gs.config }


toAuthState : Creds -> Zipper Trip -> GuestState -> AuthState
toAuthState creds tripsZipper gs =
    { activeScanItemId = Nothing
    , config           = gs.session.config
    , creds            = creds
    , editingEntry     = Nothing
    , entries          = []
    , error            = Nothing
    , geoBlocked       = False
    , loadingEntries   = gs.session.config.sheetId /= ""
    , pendingEntry     = defaultPendingEntry gs.today
    , scanQueue        = Dict.empty
    , showLedgerMap    = False
    , showMapPicker    = False
    , submitting       = False
    , tab              = LedgerTab
    , toast            = Nothing
    , today            = gs.today
    , tripForm         = Nothing
    , trips            = tripsZipper
    , version          = gs.version
    }


toGuestState : GuestReason -> AuthState -> GuestState
toGuestState reason as_ =
    { activeTripTab = (Zipper.current as_.trips).tabName
    , pendingToken  = Nothing
    , session       = { config = as_.config, reason = reason }
    , showSettings  = reason /= FreshGuest
    , storedTrips   = Zipper.toList as_.trips
    , today         = as_.today
    , version       = as_.version
    }


tripValidator : Validator String TripForm
tripValidator =
    Validate.all
        [ ifBlank .name "Trip name is required."
        , ifTrue (\f -> f.budget /= "" && String.toFloat f.budget == Nothing) "Budget must be a number."
        , ifTrue (\f -> f.endDate /= "" && f.endDate < f.startDate) "End date must be after start date."
        ]


slugify : String -> String
slugify s =
    s
        |> String.toLower
        |> String.map (\c -> if Char.isAlphaNum c then c else '-')
        |> String.split "-"
        |> List.filter ((/=) "")
        |> String.join "-"


encodeTrip : Trip -> E.Value
encodeTrip t =
    E.object
        [ ( "budget", E.float t.budget )
        , ( "coverPhotoUrl", E.string t.coverPhotoUrl )
        , ( "description", E.string t.description )
        , ( "endDate", E.string t.endDate )
        , ( "name", E.string t.name )
        , ( "sheetGid", E.int t.sheetGid )
        , ( "startDate", E.string t.startDate )
        , ( "tabName", E.string t.tabName )
        ]


tripDecoder : D.Decoder Trip
tripDecoder =
    D.succeed Trip
        |> Pipeline.required "budget" D.float
        |> Pipeline.required "coverPhotoUrl" D.string
        |> Pipeline.required "description" D.string
        |> Pipeline.required "endDate" D.string
        |> Pipeline.required "name" D.string
        |> Pipeline.required "sheetGid" D.int
        |> Pipeline.required "startDate" D.string
        |> Pipeline.required "tabName" D.string


tripsFromFlags : String -> List Trip
tripsFromFlags json =
    D.decodeString (D.list tripDecoder) json
        |> Result.withDefault []


sheetPropDecoder : D.Decoder SheetProp
sheetPropDecoder =
    D.map2 SheetProp
        (D.field "sheetId" D.int)
        (D.field "title" D.string)


sheetMetaDecoder : D.Decoder (List SheetProp)
sheetMetaDecoder =
    D.field "sheets"
        (D.list
            (D.field "properties" sheetPropDecoder)
        )


addSheetReplyDecoder : D.Decoder SheetProp
addSheetReplyDecoder =
    D.field "replies"
        (D.index 0
            (D.field "addSheet"
                (D.field "properties" sheetPropDecoder)
            )
        )


buildTripsZipper : List Trip -> String -> List SheetProp -> Maybe String -> Maybe String -> Zipper Trip
buildTripsZipper storedTrips activeTripTab props migrationStartDate activeTripTabFlag =
    let
        tripsWithGid =
            List.filterMap
                (\p ->
                    let
                        existing =
                            List.filter (\t -> t.tabName == p.title) storedTrips
                    in
                    case existing of
                        t :: _ ->
                            Just { t | sheetGid = p.gid }

                        [] ->
                            Nothing
                )
                props

        allTrips =
            if List.isEmpty tripsWithGid then
                case props of
                    firstProp :: _ ->
                        [ { budget        = 0
                          , coverPhotoUrl = ""
                          , description   = ""
                          , endDate       = ""
                          , name          = "Trip 1"
                          , sheetGid      = firstProp.gid
                          , startDate     = Maybe.withDefault "" migrationStartDate
                          , tabName       = firstProp.title
                          }
                        ]

                    [] ->
                        [ { budget        = 0
                          , coverPhotoUrl = ""
                          , description   = ""
                          , endDate       = ""
                          , name          = "Trip 1"
                          , sheetGid      = 0
                          , startDate     = Maybe.withDefault "" migrationStartDate
                          , tabName       = "Expenses"
                          }
                        ]

            else
                tripsWithGid

        activeTab =
            if activeTripTab /= "" then activeTripTab
            else Maybe.withDefault "" activeTripTabFlag

        zipper =
            case allTrips of
                h :: t ->
                    Zipper.fromCons h t

                [] ->
                    Zipper.fromCons
                        { budget = 0, coverPhotoUrl = "", description = "", endDate = ""
                        , name = "Trip 1", sheetGid = 0, startDate = "", tabName = "Expenses"
                        }
                        []

        focused =
            if activeTab /= "" then
                Zipper.focus (\tr -> tr.tabName == activeTab) zipper
                    |> Maybe.withDefault zipper
            else
                zipper
    in
    focused


ocrSystemPrompt : String
ocrSystemPrompt =
    "You are a receipt parser. Extract expense info and return ONLY raw valid JSON with no markdown, no code fences, no explanation. Format exactly: {\"amount\": <number>, \"category\": \"<fuel|food|camp|ferry|gear|lodging|activities|shopping|medical|transport|misc>\", \"note\": \"<brief description max 50 chars>\", \"longNote\": \"<detailed description max 280 chars, include what was purchased, where, any relevant context>\", \"merchant\": \"<store name>\", \"date\": \"<YYYY-MM-DD or null if not visible on receipt>\"}. Choose the best matching category."



-- INIT


defaultPendingEntry : String -> PendingEntry
defaultPendingEntry today =
    { amount = "", category = Fuel, note = "", longNote = "", merchant = "", date = today
    , locationState = LocationIdle
    }


entryToPending : Entry -> PendingEntry
entryToPending e =
    { amount = String.fromFloat e.amount
    , category = e.category
    , note = e.note
    , longNote = e.longNote
    , merchant = e.merchant
    , date = e.date
    , locationState =
        case ( e.lat, e.lon ) of
            ( Just la, Just lo ) ->
                LocationGot la lo ManualPin

            _ ->
                LocationIdle
    }


toastFor : String -> Cmd Msg
toastFor _ =
    Task.perform (\_ -> ToastExpired) (Process.sleep 4000)


setLocation : LocationState -> PendingEntry -> PendingEntry
setLocation ls p =
    { p | locationState = ls }


freshScanItem : String -> ScanItem
freshScanItem id =
    { id = id
    , imageUrl = ""
    , status = ScanQueued
    , ocrData = Nothing
    , locationState = LocationCheckingExif
    , exifDebug = ""
    }



init : D.Value -> ( Model, Cmd Msg )
init flagsJson =
    let
        dec field_ =
            D.decodeValue (D.field field_ D.string) flagsJson
                |> Result.withDefault ""

        token =
            D.decodeValue (D.maybe (D.field "token" D.string)) flagsJson
                |> Result.withDefault Nothing
                |> Maybe.andThen (\t -> if t == "" then Nothing else Just t)

        cfg =
            { anthropicKey   = dec "anthropicKey"
            , googleClientId = dec "googleClientId"
            , sheetId        = dec "sheetId"
            }

        storedTrips =
            tripsFromFlags (dec "trips")

        activeTripTab =
            dec "activeTripTab"

        gs =
            { activeTripTab = activeTripTab
            , pendingToken  = Nothing
            , session       = { config = cfg, reason = FreshGuest }
            , showSettings  = False
            , storedTrips   = storedTrips
            , today         = dec "today"
            , version       = dec "version"
            }
    in
    case token of
        Nothing ->
            ( GuestModel gs, Cmd.none )

        Just t ->
            if cfg.sheetId /= "" then
                ( GuestModel { gs | pendingToken = Just t }
                , fetchSheetMeta { token = t } cfg.sheetId
                )
            else
                let
                    defaultTrip =
                        { budget = 0, coverPhotoUrl = "", description = "", endDate = ""
                        , name = "Trip 1", sheetGid = 0, startDate = "", tabName = "Expenses"
                        }

                    tripsZipper =
                        case storedTrips of
                            h :: rest ->
                                let z = Zipper.fromCons h rest
                                in if activeTripTab /= "" then
                                    Zipper.focus (\t2 -> t2.tabName == activeTripTab) z
                                        |> Maybe.withDefault z
                                   else
                                    z

                            [] ->
                                Zipper.fromCons defaultTrip []
                in
                ( AuthModel (toAuthState { token = t } tripsZipper gs)
                , Cmd.none
                )



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
        SignInClicked ->
            if gs.session.config.googleClientId == "" then
                ( GuestModel { gs | session = { config = gs.session.config, reason = MissingConfig } }
                , Cmd.none
                )
            else
                ( GuestModel gs, requestOAuthToken True )

        GotOAuthToken token ->
            if gs.session.config.sheetId /= "" then
                ( GuestModel { gs | pendingToken = Just token }
                , Cmd.batch
                    [ saveStorage { key = "oauth_token", value = token }
                    , fetchSheetMeta { token = token } gs.session.config.sheetId
                    ]
                )
            else
                let
                    defaultTrip =
                        { budget = 0, coverPhotoUrl = "", description = "", endDate = ""
                        , name = "Trip 1", sheetGid = 0, startDate = "", tabName = "Expenses"
                        }
                    as_ = toAuthState { token = token } (Zipper.fromCons defaultTrip []) gs
                in
                ( AuthModel as_
                , saveStorage { key = "oauth_token", value = token }
                )

        GotSheetMeta result ->
            case gs.pendingToken of
                Nothing ->
                    ( GuestModel gs, Cmd.none )

                Just token ->
                    case result of
                        Err (Http.BadStatus 401) ->
                            ( GuestModel
                                { gs
                                    | pendingToken = Nothing
                                    , session = { config = gs.session.config, reason = SessionExpired }
                                }
                            , Cmd.none
                            )

                        Err e ->
                            ( GuestModel
                                { gs
                                    | pendingToken = Nothing
                                    , session = { config = gs.session.config, reason = MetadataError (httpErrString e) }
                                }
                            , Cmd.none
                            )

                        Ok props ->
                            let
                                tripsZipper =
                                    buildTripsZipper
                                        gs.storedTrips
                                        gs.activeTripTab
                                        props
                                        Nothing
                                        Nothing

                                as_ =
                                    toAuthState { token = token } tripsZipper gs

                                activeTrip =
                                    Zipper.current tripsZipper
                            in
                            ( AuthModel as_
                            , fetchEntries { token = token } gs.session.config.sheetId activeTrip.tabName
                            )

        ToggleGuestSettings ->
            ( GuestModel { gs | showSettings = not gs.showSettings }, Cmd.none )

        ApiKeyChanged s ->
            ( GuestModel { gs | session = mapGuestConfig (\c -> { c | anthropicKey = s }) gs.session }
            , saveStorage { key = "anthropic_key", value = s }
            )

        SheetIdChanged s ->
            ( GuestModel { gs | session = mapGuestConfig (\c -> { c | sheetId = s }) gs.session }
            , saveStorage { key = "sheet_id", value = s }
            )

        GoogleClientIdChanged s ->
            ( GuestModel { gs | session = mapGuestConfig (\c -> { c | googleClientId = s }) gs.session }
            , saveStorage { key = "google_client_id", value = s }
            )

        ResetSettingsClicked ->
            let
                emptyCfg = { anthropicKey = "", googleClientId = "", sheetId = "" }
            in
            ( GuestModel
                { gs
                    | activeTripTab = ""
                    , session       = { config = emptyCfg, reason = FreshGuest }
                    , showSettings  = False
                    , storedTrips   = []
                }
            , clearAllStorage ()
            )

        _ ->
            ( GuestModel gs, Cmd.none )


updateAuth : Msg -> AuthState -> ( Model, Cmd Msg )
updateAuth msg as_ =
    case msg of
        GotOAuthToken token ->
            ( AuthModel { as_ | creds = { token = token } }
            , saveStorage { key = "oauth_token", value = token }
            )

        SignOutClicked ->
            ( GuestModel (toGuestState FreshGuest as_), clearStorage () )

        ResetSettingsClicked ->
            ( GuestModel
                { activeTripTab = ""
                , pendingToken  = Nothing
                , session       = { config = { anthropicKey = "", googleClientId = "", sheetId = "" }, reason = FreshGuest }
                , showSettings  = False
                , storedTrips   = []
                , today         = as_.today
                , version       = as_.version
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
            ( AuthModel { as_ | scanQueue = newQueue }
            , Cmd.batch urlCmds
            )

        GotFileUrl itemId dataUrl ->
            let
                newStatus =
                    if as_.config.anthropicKey /= "" then
                        ScanProcessing
                    else
                        ScanReady

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
                                        Err _ -> Nothing
                                Err _ -> Nothing
                        Err _ -> Nothing

                updatedQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | status = ScanReady, ocrData = ocrData })) as_.scanQueue
            in
            ( AuthModel { as_ | scanQueue = updatedQueue }, Cmd.none )

        AmountChanged s ->
            authPending (\p -> { p | amount = s }) as_

        CategorySelected cat ->
            authPending (\p -> { p | category = cat }) as_

        NoteChanged s ->
            authPending (\p -> { p | note = s }) as_

        LongNoteChanged s ->
            authPending (\p -> { p | longNote = s }) as_

        MerchantChanged s ->
            authPending (\p -> { p | merchant = s }) as_

        DateChanged s ->
            authPending (\p -> { p | date = s }) as_

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
                p = as_.pendingEntry
            in
            case as_.editingEntry of
                Just original ->
                    let
                        updated =
                            { original
                                | date = p.date
                                , amount = String.toFloat p.amount |> Maybe.withDefault 0
                                , category = p.category
                                , note = p.note
                                , longNote = p.longNote
                                , merchant = p.merchant
                                , lat =
                                    case p.locationState of
                                        LocationGot la _ _ -> Just la
                                        LocationSkipped -> Nothing
                                        _ -> original.lat
                                , lon =
                                    case p.locationState of
                                        LocationGot _ lo _ -> Just lo
                                        LocationSkipped -> Nothing
                                        _ -> original.lon
                            }
                    in
                    ( AuthModel as_, updateEntry as_.creds as_.config.sheetId (Zipper.current as_.trips).tabName updated )

                Nothing ->
                    let
                        ( eLat, eLon ) =
                            case p.locationState of
                                LocationGot la lo _ -> ( Just la, Just lo )
                                _ -> ( Nothing, Nothing )

                        entry =
                            { id = "e-" ++ String.fromInt (Time.posixToMillis posix)
                            , date = p.date
                            , amount = String.toFloat p.amount |> Maybe.withDefault 0
                            , category = p.category
                            , note = p.note
                            , longNote = p.longNote
                            , merchant = p.merchant
                            , createdAt = posixToIso posix
                            , rowIndex = 0
                            , lat = eLat
                            , lon = eLon
                            }
                    in
                    ( AuthModel as_, appendEntry as_.creds as_.config.sheetId (Zipper.current as_.trips).tabName entry )

        EntrySubmitted result ->
            case result of
                Ok () ->
                    let
                        updatedQueue =
                            case as_.activeScanItemId of
                                Just id ->
                                    Dict.update id (Maybe.map (\i -> { i | status = ScanSubmitted })) as_.scanQueue
                                Nothing ->
                                    as_.scanQueue

                        hasRemaining =
                            Dict.values updatedQueue |> List.any (\i -> i.status /= ScanSubmitted)

                        nextTab =
                            if as_.activeScanItemId /= Nothing && hasRemaining then
                                ScanTab
                            else
                                LedgerTab
                    in
                    ( AuthModel
                        { as_
                            | submitting = False
                            , pendingEntry = defaultPendingEntry as_.today
                            , editingEntry = Nothing
                            , activeScanItemId = Nothing
                            , scanQueue = updatedQueue
                            , tab = nextTab
                            , loadingEntries = True
                        }
                    , fetchEntries as_.creds as_.config.sheetId (Zipper.current as_.trips).tabName
                    )

                Err (Http.BadStatus 401) ->
                    ( GuestModel (toGuestState SessionExpired as_), clearStorage () )

                Err e ->
                    let toastMsg = "Save failed: " ++ httpErrString e
                    in ( AuthModel { as_ | submitting = False, toast = Just toastMsg }, toastFor toastMsg )

        EntriesFetched result ->
            case result of
                Ok entries ->
                    ( AuthModel { as_ | entries = entries, loadingEntries = False }, Cmd.none )

                Err (Http.BadStatus 401) ->
                    ( GuestModel (toGuestState SessionExpired as_), clearStorage () )

                Err e ->
                    ( AuthModel { as_ | loadingEntries = False, error = Just ("Load failed: " ++ httpErrString e) }
                    , Cmd.none
                    )

        DeleteEntry entry ->
            ( AuthModel { as_ | entries = List.filter (\e -> e.id /= entry.id) as_.entries }
            , deleteEntry as_.creds as_.config.sheetId (Zipper.current as_.trips).sheetGid entry.rowIndex
            )

        EntryDeleted result ->
            case result of
                Ok () ->
                    ( AuthModel as_, fetchEntries as_.creds as_.config.sheetId (Zipper.current as_.trips).tabName )

                Err (Http.BadStatus 401) ->
                    ( GuestModel (toGuestState SessionExpired as_), clearStorage () )

                Err e ->
                    ( AuthModel { as_ | error = Just ("Delete failed: " ++ httpErrString e) }, Cmd.none )

        EditEntry entry ->
            ( AuthModel
                { as_
                    | editingEntry = Just entry
                    , pendingEntry = entryToPending entry
                    , tab = AddTab
                    , error = Nothing
                }
            , Cmd.none
            )

        CancelEdit ->
            ( AuthModel
                { as_
                    | editingEntry = Nothing
                    , pendingEntry = defaultPendingEntry as_.today
                    , tab = LedgerTab
                }
            , Cmd.none
            )

        TabChanged tab ->
            let
                shouldFetch =
                    tab == LedgerTab && as_.config.sheetId /= ""

                geoCmd =
                    if tab == AddTab && not as_.geoBlocked then
                        requestGeolocation ()
                    else
                        Cmd.none

                newPending =
                    if tab == AddTab && not as_.geoBlocked then
                        setLocation LocationFetching as_.pendingEntry
                    else
                        as_.pendingEntry
            in
            ( AuthModel
                { as_
                    | tab = tab
                    , loadingEntries = shouldFetch
                    , pendingEntry = newPending
                    , editingEntry = if tab /= AddTab then Nothing else as_.editingEntry
                    , tripForm = Nothing
                }
            , Cmd.batch
                [ if shouldFetch then fetchEntries as_.creds as_.config.sheetId (Zipper.current as_.trips).tabName else Cmd.none
                , geoCmd
                ]
            )

        RefreshClicked ->
            ( AuthModel { as_ | loadingEntries = True }
            , fetchEntries as_.creds as_.config.sheetId (Zipper.current as_.trips).tabName
            )

        ApiKeyChanged s ->
            let cfg = as_.config
            in ( AuthModel { as_ | config = { cfg | anthropicKey = s } }
               , saveStorage { key = "anthropic_key", value = s }
               )

        SheetIdChanged s ->
            let cfg = as_.config
            in ( AuthModel { as_ | config = { cfg | sheetId = s } }
               , saveStorage { key = "sheet_id", value = s }
               )

        GoogleClientIdChanged s ->
            let cfg = as_.config
            in ( AuthModel { as_ | config = { cfg | googleClientId = s } }
               , saveStorage { key = "google_client_id", value = s }
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
            ( AuthModel { as_ | showMapPicker = False, pendingEntry = setLocation (LocationGot lat lon ManualPin) as_.pendingEntry }
            , Cmd.none
            )

        DismissMapPicker ->
            ( AuthModel { as_ | showMapPicker = False }, Cmd.none )

        SkipLocation ->
            ( AuthModel { as_ | showMapPicker = False, pendingEntry = setLocation LocationSkipped as_.pendingEntry }
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
                                { amount = Nothing, category = Nothing, note = Nothing, merchant = Nothing, date = Nothing, longNote = Nothing }
                                item.ocrData

                        newPending =
                            { amount = ocr.amount |> Maybe.map String.fromFloat |> Maybe.withDefault ""
                            , category = Maybe.withDefault Fuel ocr.category
                            , note = Maybe.withDefault "" ocr.note
                            , longNote = Maybe.withDefault "" ocr.longNote
                            , merchant = Maybe.withDefault "" ocr.merchant
                            , date = Maybe.withDefault as_.today ocr.date
                            , locationState = item.locationState
                            }
                    in
                    ( AuthModel
                        { as_
                            | activeScanItemId = Just itemId
                            , pendingEntry = newPending
                            , tab = AddTab
                            , error = Nothing
                        }
                    , Cmd.none
                    )

        BackToQueue ->
            ( AuthModel
                { as_
                    | activeScanItemId = Nothing
                    , pendingEntry = defaultPendingEntry as_.today
                    , tab = ScanTab
                }
            , Cmd.none
            )

        ClearDoneItems ->
            ( AuthModel { as_ | scanQueue = Dict.filter (\_ i -> i.status /= ScanSubmitted) as_.scanQueue }
            , Cmd.none
            )

        SelectTrip tabName ->
            let
                trips_ =
                    Zipper.focus (\t -> t.tabName == tabName) as_.trips
                        |> Maybe.withDefault as_.trips
            in
            ( AuthModel { as_ | trips = trips_, loadingEntries = True, tab = LedgerTab }
            , Cmd.batch
                [ saveStorage { key = "active_trip", value = tabName }
                , fetchEntries as_.creds as_.config.sheetId (Zipper.current trips_).tabName
                ]
            )

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
                    case validate tripValidator form of
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
                                            Zipper.map
                                                (\t -> if t.tabName == existing.tabName then updated else t)
                                                as_.trips
                                    in
                                    ( AuthModel { as_ | trips = trips_, tripForm = Nothing }
                                    , saveStorage { key = "trips", value = E.encode 0 (E.list encodeTrip (Zipper.toList trips_)) }
                                    )

                                Nothing ->
                                    let
                                        tabName =
                                            slugify form.name
                                    in
                                    ( AuthModel as_
                                    , createTripSheet as_.creds as_.config.sheetId tabName
                                    )

        GotTripCreated result ->
            case result of
                Err e ->
                    ( AuthModel { as_ | error = Just ("Failed to create trip: " ++ httpErrString e) }, Cmd.none )

                Ok prop ->
                    case as_.tripForm of
                        Nothing ->
                            ( AuthModel as_, Cmd.none )

                        Just form ->
                            let
                                newTrip =
                                    { budget        = String.toFloat form.budget |> Maybe.withDefault 0
                                    , coverPhotoUrl = form.coverPhotoUrl
                                    , description   = form.description
                                    , endDate       = form.endDate
                                    , name          = form.name
                                    , sheetGid      = prop.gid
                                    , startDate     = form.startDate
                                    , tabName       = prop.title
                                    }

                                trips_ =
                                    Zipper.consBefore newTrip as_.trips
                                        |> Zipper.focus (\t -> t.tabName == prop.title)
                                        |> Maybe.withDefault as_.trips
                            in
                            ( AuthModel
                                { as_
                                    | trips = trips_
                                    , tripForm = Nothing
                                    , loadingEntries = True
                                    , tab = LedgerTab
                                }
                            , Cmd.batch
                                [ saveStorage { key = "trips", value = E.encode 0 (E.list encodeTrip (Zipper.toList trips_)) }
                                , saveStorage { key = "active_trip", value = prop.title }
                                , fetchEntries as_.creds as_.config.sheetId prop.title
                                ]
                            )

        DeleteTrip trip ->
            let
                remaining =
                    Zipper.toList as_.trips
                        |> List.filter (\t -> t.tabName /= trip.tabName)
            in
            case remaining of
                [] ->
                    ( AuthModel as_, Cmd.none )

                h :: t ->
                    let
                        trips_ =
                            Zipper.fromCons h t
                                |> Zipper.focus (\tr -> tr.tabName /= trip.tabName)
                                |> Maybe.withDefault (Zipper.fromCons h t)
                    in
                    ( AuthModel { as_ | trips = trips_ }
                    , saveStorage { key = "trips", value = E.encode 0 (E.list encodeTrip (Zipper.toList trips_)) }
                    )

        _ ->
            ( AuthModel as_, Cmd.none )


authPending : (PendingEntry -> PendingEntry) -> AuthState -> ( Model, Cmd Msg )
authPending f as_ =
    ( AuthModel { as_ | pendingEntry = f as_.pendingEntry }, Cmd.none )



-- HTTP


fetchEntries : Creds -> String -> String -> Cmd Msg
fetchEntries creds sheetId tabName =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ creds.token) ]
        , url = "https://sheets.googleapis.com/v4/spreadsheets/" ++ sheetId ++ "/values/" ++ tabName ++ "!A2:J"
        , body = Http.emptyBody
        , expect = expectJsonBody EntriesFetched entriesDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


appendEntry : Creds -> String -> String -> Entry -> Cmd Msg
appendEntry creds sheetId tabName entry =
    let
        body =
            E.object
                [ ( "values"
                  , E.list identity
                        [ E.list identity
                            [ E.string entry.id
                            , E.string entry.date
                            , E.float entry.amount
                            , E.string (categoryLabel entry.category)
                            , E.string entry.note
                            , E.string entry.merchant
                            , E.string entry.createdAt
                            , entry.lat |> Maybe.map (\v -> E.string (String.fromFloat v)) |> Maybe.withDefault (E.string "")
                            , entry.lon |> Maybe.map (\v -> E.string (String.fromFloat v)) |> Maybe.withDefault (E.string "")
                            , E.string entry.longNote
                            ]
                        ]
                  )
                ]
    in
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ creds.token) ]
        , url = "https://sheets.googleapis.com/v4/spreadsheets/" ++ sheetId ++ "/values/" ++ tabName ++ "!A:J:append?valueInputOption=RAW"
        , body = Http.jsonBody body
        , expect = expectWhateverBody EntrySubmitted
        , timeout = Nothing
        , tracker = Nothing
        }


deleteEntry : Creds -> String -> Int -> Int -> Cmd Msg
deleteEntry creds sheetId sheetGid rowIndex =
    let
        body =
            E.object
                [ ( "requests"
                  , E.list identity
                        [ E.object
                            [ ( "deleteDimension"
                              , E.object
                                    [ ( "range"
                                      , E.object
                                            [ ( "sheetId", E.int sheetGid )
                                            , ( "dimension", E.string "ROWS" )
                                            , ( "startIndex", E.int (rowIndex - 1) )
                                            , ( "endIndex", E.int rowIndex )
                                            ]
                                      )
                                    ]
                              )
                            ]
                        ]
                  )
                ]
    in
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ creds.token) ]
        , url = "https://sheets.googleapis.com/v4/spreadsheets/" ++ sheetId ++ ":batchUpdate"
        , body = Http.jsonBody body
        , expect = expectWhateverBody EntryDeleted
        , timeout = Nothing
        , tracker = Nothing
        }


updateEntry : Creds -> String -> String -> Entry -> Cmd Msg
updateEntry creds sheetId tabName entry =
    let
        range =
            tabName ++ "!A" ++ String.fromInt entry.rowIndex ++ ":J" ++ String.fromInt entry.rowIndex

        body =
            E.object
                [ ( "values"
                  , E.list identity
                        [ E.list identity
                            [ E.string entry.id
                            , E.string entry.date
                            , E.float entry.amount
                            , E.string (categoryLabel entry.category)
                            , E.string entry.note
                            , E.string entry.merchant
                            , E.string entry.createdAt
                            , entry.lat |> Maybe.map (\v -> E.string (String.fromFloat v)) |> Maybe.withDefault (E.string "")
                            , entry.lon |> Maybe.map (\v -> E.string (String.fromFloat v)) |> Maybe.withDefault (E.string "")
                            , E.string entry.longNote
                            ]
                        ]
                  )
                ]
    in
    Http.request
        { method = "PUT"
        , headers = [ Http.header "Authorization" ("Bearer " ++ creds.token) ]
        , url = "https://sheets.googleapis.com/v4/spreadsheets/" ++ sheetId ++ "/values/" ++ range ++ "?valueInputOption=RAW"
        , body = Http.jsonBody body
        , expect = expectWhateverBody EntrySubmitted
        , timeout = Nothing
        , tracker = Nothing
        }


fetchSheetMeta : Creds -> String -> Cmd Msg
fetchSheetMeta creds sheetId =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ creds.token) ]
        , url = "https://sheets.googleapis.com/v4/spreadsheets/" ++ sheetId ++ "?fields=sheets.properties"
        , body = Http.emptyBody
        , expect = expectJsonBody GotSheetMeta sheetMetaDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


createTripSheet : Creds -> String -> String -> Cmd Msg
createTripSheet creds sheetId tabName =
    let
        body =
            E.object
                [ ( "requests"
                  , E.list identity
                        [ E.object
                            [ ( "addSheet"
                              , E.object
                                    [ ( "properties"
                                      , E.object [ ( "title", E.string tabName ) ]
                                      )
                                    ]
                              )
                            ]
                        ]
                  )
                ]
    in
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ creds.token) ]
        , url = "https://sheets.googleapis.com/v4/spreadsheets/" ++ sheetId ++ ":batchUpdate"
        , body = Http.jsonBody body
        , expect = expectJsonBody GotTripCreated addSheetReplyDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


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



-- CUSTOM HTTP EXPECT HELPERS
-- Both preserve 401 as Http.BadStatus 401 (so Elm can trigger silent re-auth)
-- and fold all other errors into Http.BadBody with the response body included.


expectJsonBody : (Result Http.Error a -> msg) -> D.Decoder a -> Http.Expect msg
expectJsonBody toMsg decoder =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ u ->
                    Err (Http.BadUrl u)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ meta body ->
                    if meta.statusCode == 401 then
                        Err (Http.BadStatus 401)

                    else
                        Err (Http.BadBody (String.fromInt meta.statusCode ++ " " ++ body))

                Http.GoodStatus_ _ body ->
                    case D.decodeString decoder body of
                        Ok v ->
                            Ok v

                        Err e ->
                            Err (Http.BadBody (D.errorToString e))


expectWhateverBody : (Result Http.Error () -> msg) -> Http.Expect msg
expectWhateverBody toMsg =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ u ->
                    Err (Http.BadUrl u)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ meta body ->
                    if meta.statusCode == 401 then
                        Err (Http.BadStatus 401)

                    else
                        Err (Http.BadBody (String.fromInt meta.statusCode ++ " " ++ body))

                Http.GoodStatus_ _ _ ->
                    Ok ()


-- DECODERS


entriesDecoder : D.Decoder (List Entry)
entriesDecoder =
    D.oneOf
        [ D.field "values" (D.list rowDecoder)
            |> D.map (List.indexedMap (\i e -> { e | rowIndex = i + 2 }))
        , D.succeed []
        ]


rowDecoder : D.Decoder Entry
rowDecoder =
    D.succeed
        (\id date amount category note merchant createdAt lat lon longNote ->
            { id = id
            , date = date
            , amount = amount
            , category = category
            , note = note
            , longNote = longNote
            , merchant = merchant
            , createdAt = createdAt
            , rowIndex = 0
            , lat = lat
            , lon = lon
            }
        )
        |> Pipeline.custom (D.index 0 D.string)
        |> Pipeline.custom (D.index 1 D.string)
        |> Pipeline.custom (D.index 2 (D.string |> D.andThen parseAmountStr))
        |> Pipeline.custom (D.index 3 (D.string |> D.map categoryFromString))
        |> Pipeline.custom (optIndex 4 D.string "")
        |> Pipeline.custom (optIndex 5 D.string "")
        |> Pipeline.custom (optIndex 6 D.string "")
        |> Pipeline.custom (optMaybeFloat 7)
        |> Pipeline.custom (optMaybeFloat 8)
        |> Pipeline.custom (optIndex 9 D.string "")


optIndex : Int -> D.Decoder a -> a -> D.Decoder a
optIndex i decoder fallback =
    D.oneOf
        [ D.index i decoder
        , D.succeed fallback
        ]


optMaybeFloat : Int -> D.Decoder (Maybe Float)
optMaybeFloat i =
    D.oneOf
        [ D.index i
            (D.string
                |> D.andThen
                    (\s ->
                        if s == "" then
                            D.succeed Nothing

                        else
                            D.succeed (String.toFloat s)
                    )
            )
        , D.succeed Nothing
        ]


parseAmountStr : String -> D.Decoder Float
parseAmountStr s =
    case String.toFloat s of
        Just f ->
            D.succeed f

        Nothing ->
            D.succeed 0.0


claudeTextDecoder : D.Decoder String
claudeTextDecoder =
    D.field "content" (D.index 0 (D.field "text" D.string))


type alias OcrData =
    { amount   : Maybe Float
    , category : Maybe Category
    , note     : Maybe String
    , merchant : Maybe String
    , date     : Maybe String
    , longNote : Maybe String
    }


ocrDataDecoder : D.Decoder OcrData
ocrDataDecoder =
    D.succeed OcrData
        |> Pipeline.optional "amount"   (D.map Just D.float) Nothing
        |> Pipeline.optional "category" (D.map Just (D.map categoryFromString D.string)) Nothing
        |> Pipeline.optional "note"     (D.map Just D.string) Nothing
        |> Pipeline.optional "merchant" (D.map Just D.string) Nothing
        |> Pipeline.optional "date"     (D.map Just D.string) Nothing
        |> Pipeline.optional "longNote" (D.map Just D.string) Nothing


fileListDecoder : D.Decoder (List File)
fileListDecoder =
    D.field "length" D.int
        |> D.andThen
            (\n ->
                List.range 0 (n - 1)
                    |> List.map (\i -> D.field (String.fromInt i) File.decoder)
                    |> List.foldr (D.map2 (::)) (D.succeed [])
            )



-- TIME / URL HELPERS


posixToIso : Time.Posix -> String
posixToIso posix =
    let
        y =
            String.fromInt (Time.toYear Time.utc posix)

        m =
            String.fromInt (monthNum (Time.toMonth Time.utc posix)) |> String.padLeft 2 '0'

        d =
            String.fromInt (Time.toDay Time.utc posix) |> String.padLeft 2 '0'

        h =
            String.fromInt (Time.toHour Time.utc posix) |> String.padLeft 2 '0'

        mi =
            String.fromInt (Time.toMinute Time.utc posix) |> String.padLeft 2 '0'

        s =
            String.fromInt (Time.toSecond Time.utc posix) |> String.padLeft 2 '0'
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


formatDateDisplay : String -> String
formatDateDisplay iso =
    case String.split "-" iso of
        [ y, m, d ] ->
            let
                mn =
                    case m of
                        "01" -> "Jan"
                        "02" -> "Feb"
                        "03" -> "Mar"
                        "04" -> "Apr"
                        "05" -> "May"
                        "06" -> "Jun"
                        "07" -> "Jul"
                        "08" -> "Aug"
                        "09" -> "Sep"
                        "10" -> "Oct"
                        "11" -> "Nov"
                        "12" -> "Dec"
                        _ -> m

                day =
                    String.toInt d |> Maybe.withDefault 0 |> String.fromInt
            in
            mn ++ " " ++ day ++ ", " ++ y

        _ ->
            iso



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


httpErrString : Http.Error -> String
httpErrString err =
    case err of
        Http.BadUrl u ->
            "Bad URL: " ++ u

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "No network connection"

        Http.BadStatus 401 ->
            "Session expired — re-authenticating…"

        Http.BadStatus code ->
            "HTTP " ++ String.fromInt code

        Http.BadBody body ->
            -- body is "NNN <json>"; try to extract Google's message field
            let
                jsonPart =
                    body |> String.dropLeft 4 |> String.trimLeft
            in
            D.decodeString (D.at [ "error", "message" ] D.string) jsonPart
                |> Result.withDefault (String.left 160 body)


formatAmount : Float -> String
formatAmount amount =
    let
        cents =
            round (amount * 100)

        dollars =
            cents // 100

        centsRem =
            remainderBy 100 (abs cents)
    in
    "$" ++ String.fromInt dollars ++ "." ++ String.padLeft 2 '0' (String.fromInt centsRem)


formatCoord : Float -> Float -> String
formatCoord lat lon =
    String.left 9 (String.fromFloat lat) ++ ", " ++ String.left 9 (String.fromFloat lon)


encodeWaypoints : List Entry -> String
encodeWaypoints entries =
    let
        withCoords =
            List.filterMap
                (\e ->
                    case ( e.lat, e.lon ) of
                        ( Just la, Just lo ) ->
                            Just
                                (E.object
                                    [ ( "lat", E.float la )
                                    , ( "lon", E.float lo )
                                    , ( "label"
                                      , E.string
                                            ((if e.merchant /= "" then e.merchant else categoryLabel e.category)
                                                ++ " "
                                                ++ formatAmount e.amount
                                            )
                                      )
                                    ]
                                )

                        _ ->
                            Nothing
                )
                entries
    in
    E.encode 0 (E.list identity withCoords)


uniqueDates : List Entry -> List String
uniqueDates entries =
    entries
        |> List.map .date
        |> List.foldr
            (\d acc ->
                if List.member d acc then
                    acc

                else
                    d :: acc
            )
            []
        |> List.sort
        |> List.reverse


isoToDayCount : String -> Int
isoToDayCount s =
    case List.filterMap String.toInt (String.split "-" s) of
        [ y, m, d ] ->
            let
                monthOffsets =
                    [ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 ]

                offset =
                    List.drop (m - 1) monthOffsets |> List.head |> Maybe.withDefault 0
            in
            y * 365 + offset + d

        _ ->
            0


medianAmount : List Entry -> Float
medianAmount entries =
    let
        amounts =
            List.sort (List.map .amount entries)

        n =
            List.length amounts

        mid =
            n // 2
    in
    if n == 0 then
        0

    else if remainderBy 2 n == 1 then
        amounts |> List.drop mid |> List.head |> Maybe.withDefault 0

    else
        let
            a =
                amounts |> List.drop (mid - 1) |> List.head |> Maybe.withDefault 0

            b =
                amounts |> List.drop mid |> List.head |> Maybe.withDefault 0
        in
        (a + b) / 2


topCategory : List Entry -> Maybe Category
topCategory entries =
    allCategories
        |> List.map
            (\cat ->
                ( cat
                , entries
                    |> List.filter (\e -> e.category == cat)
                    |> List.map .amount
                    |> List.sum
                )
            )
        |> List.sortBy (negate << Tuple.second)
        |> List.head
        |> Maybe.andThen
            (\( cat, total ) ->
                if total > 0 then
                    Just cat

                else
                    Nothing
            )


biggestDay : List Entry -> Maybe ( String, Float )
biggestDay entries =
    uniqueDates entries
        |> List.map
            (\date ->
                ( date
                , entries
                    |> List.filter (\e -> e.date == date)
                    |> List.map .amount
                    |> List.sum
                )
            )
        |> List.sortBy (negate << Tuple.second)
        |> List.head



-- VIEW


view : Model -> Html Msg
view model =
    div
        [ style "background" "#0d0f0e"
        , style "color" "#c8d0c8"
        , style "min-height" "100vh"
        , style "font-family" "'Barlow Condensed', system-ui, sans-serif"
        , style "max-width" "480px"
        , style "margin" "0 auto"
        , style "position" "relative"
        ]
        [ case model of
            GuestModel gs -> viewGuest gs
            AuthModel as_ -> viewAuth as_
        ]


viewGuest : GuestState -> Html Msg
viewGuest gs =
    div
        [ style "display" "flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "justify-content" "center"
        , style "min-height" "100vh"
        , style "padding" "32px 24px"
        , style "text-align" "center"
        ]
        [ div [ style "font-size" "48px", style "margin-bottom" "16px" ] [ text "🏔" ]
        , h1
            [ style "font-size" "32px"
            , style "font-weight" "700"
            , style "color" "#e8a020"
            , style "letter-spacing" "0.05em"
            , style "margin-bottom" "8px"
            ]
            [ text "ALASKA TRACKER" ]
        , p [ style "color" "#7a8a80", style "margin-bottom" "24px", style "font-size" "16px" ]
            [ text "Road log for the long way north" ]
        , case guestMessage gs.session.reason of
            Just msg ->
                div
                    [ class "w-full mb-4 px-4 py-3 rounded-lg bg-[#2a1510] border border-[#e85030] text-[#e8a020] text-sm text-left" ]
                    [ text msg ]
            Nothing ->
                text ""
        , if gs.pendingToken /= Nothing then
            p [ style "color" "#7a8a80", style "font-size" "14px", style "padding" "16px" ]
                [ text "Loading…" ]
          else
            button
                [ onClick SignInClicked
                , style "background" "#e8a020"
                , style "color" "#0d0f0e"
                , style "border" "none"
                , style "border-radius" "8px"
                , style "padding" "16px 32px"
                , style "font-size" "16px"
                , style "font-weight" "700"
                , style "cursor" "pointer"
                , style "letter-spacing" "0.05em"
                , style "min-height" "52px"
                ]
                [ text "SIGN IN WITH GOOGLE" ]
        , p [ style "color" "#4a5a50", style "margin-top" "24px", style "font-size" "13px" ]
            [ text "Need a Google Client ID? Enter it in Settings below." ]
        , div [ style "margin-top" "48px", style "width" "100%" ]
            [ button
                [ onClick ToggleGuestSettings
                , style "background" "none"
                , style "border" "1px solid #3a4240"
                , style "color" "#7a8a80"
                , style "border-radius" "6px"
                , style "padding" "10px 20px"
                , style "font-size" "14px"
                , style "cursor" "pointer"
                ]
                [ text "⚙ Settings" ]
            , if gs.showSettings then
                viewSettingsPanel gs.session.config False gs.version
              else
                text ""
            ]
        ]


viewAuth : AuthState -> Html Msg
viewAuth as_ =
    div []
        [ viewHeader as_
        , viewErrorBanner as_.error
        , div [ style "padding-bottom" "80px" ]
            [ case as_.tab of
                ScanTab ->
                    viewScanTab as_

                AddTab ->
                    viewAddTab as_

                LedgerTab ->
                    viewLedgerTab as_

                StatsTab ->
                    viewStatsTab as_

                SettingsTab ->
                    viewSettingsPanel as_.config True as_.version

                TripsTab ->
                    viewTripsTab as_
            ]
        , viewBottomNav as_.tab
        , viewToast as_.toast
        ]


viewToast : Maybe String -> Html Msg
viewToast toast =
    case toast of
        Nothing ->
            text ""

        Just message ->
            div [ class "fixed bottom-16 left-4 right-4 z-50 flex items-center gap-3 rounded-xl px-4 py-3 bg-[#1e2220] border border-[#e85030] shadow-lg" ]
                [ span [ class "text-[#e8c080] text-sm flex-1" ] [ text message ]
                , button
                    [ onClick ToastExpired
                    , class "bg-transparent border-none text-[#7a8a80] text-lg leading-none cursor-pointer p-0 flex-shrink-0"
                    ]
                    [ text "✕" ]
                ]


viewHeader : AuthState -> Html Msg
viewHeader as_ =
    div
        [ style "background" "#161918"
        , style "border-bottom" "1px solid #2a3230"
        , style "padding" "12px 20px"
        , style "display" "flex"
        , style "align-items" "center"
        , style "justify-content" "space-between"
        , style "position" "sticky"
        , style "top" "0"
        , style "z-index" "10"
        ]
        [ div []
            [ span
                [ style "font-size" "18px"
                , style "font-weight" "700"
                , style "color" "#e8a020"
                , style "letter-spacing" "0.08em"
                ]
                [ text "ALASKA" ]
            , span
                [ style "font-size" "11px"
                , style "color" "#7a8a80"
                , style "margin-left" "8px"
                ]
                [ text (Zipper.current as_.trips).name ]
            ]
        , button
            [ onClick
                (if as_.tab == SettingsTab then
                    TabChanged LedgerTab
                 else
                    TabChanged SettingsTab
                )
            , style "background" "none"
            , style "border" "none"
            , style "font-size" "22px"
            , style "cursor" "pointer"
            , style "padding" "4px 8px"
            , style "color" (if as_.tab == SettingsTab then "#e8a020" else "#7a8a80")
            ]
            [ text "⚙" ]
        ]


viewBottomNav : Tab -> Html Msg
viewBottomNav currentTab =
    nav
        [ style "position" "fixed"
        , style "bottom" "0"
        , style "left" "50%"
        , style "transform" "translateX(-50%)"
        , style "width" "100%"
        , style "max-width" "480px"
        , style "background" "#161918"
        , style "border-top" "1px solid #2a3230"
        , style "display" "flex"
        , style "z-index" "10"
        ]
        (List.map (viewNavTab currentTab)
            [ ( ScanTab, "📷", "Scan" )
            , ( AddTab, "+", "Add" )
            , ( LedgerTab, "☰", "Ledger" )
            , ( StatsTab, "▦", "Stats" )
            , ( TripsTab, "🗺", "Trips" )
            ]
        )


viewNavTab : Tab -> ( Tab, String, String ) -> Html Msg
viewNavTab currentTab ( tab, icon, label_ ) =
    let
        active =
            currentTab == tab
    in
    button
        [ onClick (TabChanged tab)
        , style "flex" "1"
        , style "background" "none"
        , style "border" "none"
        , style "padding" "10px 4px"
        , style "display" "flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "gap" "2px"
        , style "cursor" "pointer"
        , style "color" (if active then "#e8a020" else "#7a8a80")
        , style "min-height" "56px"
        ]
        [ span [ style "font-size" "20px" ] [ text icon ]
        , span [ style "font-size" "10px", style "letter-spacing" "0.05em" ] [ text label_ ]
        ]



-- SCAN TAB


viewScanTab : AuthState -> Html Msg
viewScanTab model =
    div [ class "px-5 pt-6 pb-4" ]
        [ h2 [ sectionHead ] [ text "SCAN RECEIPTS" ]
        , label [ class "flex flex-col items-center justify-center bg-[#1e2220] border-2 border-dashed border-[#3a4240] rounded-xl py-10 px-6 cursor-pointer mb-5" ]
            [ div [ class "text-5xl mb-3" ] [ text "📷" ]
            , p [ class "text-[#7a8a80] text-base text-center" ] [ text "Tap to add photos" ]
            , p [ class "text-[#4a5a50] text-xs mt-1 text-center" ] [ text "Select multiple for batch upload" ]
            , input
                [ type_ "file"
                , accept "image/*"
                , attribute "multiple" "true"
                , class "hidden"
                , on "change" (D.map FilesSelected (D.at [ "target", "files" ] fileListDecoder))
                ]
                []
            ]
        , if Dict.isEmpty model.scanQueue then
            button
                [ onClick (TabChanged AddTab)
                , class "w-full py-3.5 rounded-lg border border-[#3a4240] text-[#7a8a80] text-sm cursor-pointer bg-transparent font-[inherit]"
                ]
                [ text "Fill in manually →" ]

          else
            div []
                [ div [ class "grid grid-cols-2 gap-3 mb-4" ]
                    (Dict.values model.scanQueue |> List.map viewScanCard)
                , if Dict.values model.scanQueue |> List.any (\i -> i.status == ScanSubmitted) then
                    button
                        [ onClick ClearDoneItems
                        , class "w-full py-2 rounded-lg border border-[#3a4240] text-[#4a5a50] text-xs cursor-pointer bg-transparent font-[inherit] mb-4"
                        ]
                        [ text "Clear submitted" ]

                  else
                    text ""
                , let
                    debugItems =
                        Dict.values model.scanQueue |> List.filter (\i -> i.exifDebug /= "")
                  in
                  if List.isEmpty debugItems then
                    text ""

                  else
                    div [ class "mt-2" ]
                        (List.indexedMap
                            (\idx item ->
                                div [ class "mb-3 rounded-lg bg-[#161918] p-3" ]
                                    [ div [ class "text-[#4a5a50] text-xs mb-1" ]
                                        [ text ("EXIF dump — photo " ++ String.fromInt (idx + 1)) ]
                                    , div
                                        [ class "font-mono text-[10px] text-[#7a8a80] break-all whitespace-pre-wrap max-h-40 overflow-y-auto"
                                        ]
                                        [ text item.exifDebug ]
                                    ]
                            )
                            debugItems
                        )
                ]
        ]


viewScanCard : ScanItem -> Html Msg
viewScanCard item =
    div [ class "bg-[#161918] rounded-xl overflow-hidden" ]
        [ if item.imageUrl /= "" then
            img [ src item.imageUrl, class "w-full h-28 object-cover" ] []

          else
            div [ class "w-full h-28 bg-[#1e2220] flex items-center justify-center text-3xl text-[#3a4240]" ]
                [ text "📷" ]
        , div [ class "p-2" ]
            [ viewScanCardStatus item ]
        ]


viewScanCardStatus : ScanItem -> Html Msg
viewScanCardStatus item =
    case item.status of
        ScanQueued ->
            div [ class "text-[#4a5a50] text-xs py-1" ] [ text "Queued…" ]

        ScanProcessing ->
            div [ class "text-[#e8a020] text-xs py-1" ] [ text "⏳ Reading…" ]

        ScanReady ->
            div []
                [ case item.ocrData of
                    Just ocr ->
                        div [ class "mb-2" ]
                            [ div [ class "text-[#e8a020] font-mono text-sm font-bold" ]
                                [ text (ocr.amount |> Maybe.map (\a -> "$" ++ String.fromFloat a) |> Maybe.withDefault "—") ]
                            , div [ class "text-[#7a8a80] text-xs truncate" ]
                                [ text
                                    (ocr.merchant
                                        |> Maybe.withDefault
                                            (ocr.category |> Maybe.map categoryLabel |> Maybe.withDefault "receipt")
                                    )
                                ]
                            ]

                    Nothing ->
                        div [ class "text-[#7a8a80] text-xs mb-2" ] [ text "Fill manually" ]
                , button
                    [ onClick (ReviewScanItem item.id)
                    , class "w-full py-1.5 rounded-lg bg-[#e8a020] text-[#0d0f0e] text-xs font-bold cursor-pointer border-none font-[inherit]"
                    ]
                    [ text "Review →" ]
                ]

        ScanSubmitted ->
            div [ class "text-[#4a5a50] text-xs text-center py-1" ] [ text "✓ Submitted" ]



-- ADD TAB


viewAddTab : AuthState -> Html Msg
viewAddTab model =
    let
        p =
            model.pendingEntry

        isEditing =
            model.editingEntry /= Nothing
    in
    div [ style "padding" "24px 20px" ]
        [ div
            [ style "display" "flex"
            , style "align-items" "center"
            , style "justify-content" "space-between"
            , style "margin-bottom" "20px"
            ]
            [ h2 [ sectionHead ]
                [ text
                    (if isEditing then
                        "EDIT EXPENSE"

                     else if model.activeScanItemId /= Nothing then
                        "REVIEW SCAN"

                     else
                        "ADD EXPENSE"
                    )
                ]
            , if model.activeScanItemId /= Nothing then
                button
                    [ onClick BackToQueue
                    , class "bg-transparent border-none text-[#7a8a80] text-sm cursor-pointer p-1 font-[inherit]"
                    ]
                    [ text "← queue" ]

              else if isEditing then
                button
                    [ onClick CancelEdit
                    , class "bg-transparent border-none text-[#7a8a80] text-sm cursor-pointer p-1 font-[inherit]"
                    ]
                    [ text "← cancel" ]

              else
                text ""
            ]
        , case model.activeScanItemId of
            Nothing ->
                text ""

            Just id ->
                case Dict.get id model.scanQueue of
                    Just item ->
                        img
                            [ src item.imageUrl
                            , class "w-full rounded-xl object-contain mb-4"
                            , style "max-height" "240px"
                            , style "background" "#1a2420"
                            ]
                            []

                    Nothing ->
                        text ""
        , formField "AMOUNT"
            (div [ style "position" "relative" ]
                [ span
                    [ style "position" "absolute"
                    , style "left" "14px"
                    , style "top" "50%"
                    , style "transform" "translateY(-50%)"
                    , style "color" "#e8a020"
                    , style "font-size" "20px"
                    , style "font-family" "monospace"
                    ]
                    [ text "$" ]
                , input
                    [ type_ "number"
                    , attribute "inputmode" "decimal"
                    , value p.amount
                    , onInput AmountChanged
                    , placeholder "0.00"
                    , style "width" "100%"
                    , style "background" "#1e2220"
                    , style "border" "1px solid #3a4240"
                    , style "color" "#c8d0c8"
                    , style "border-radius" "8px"
                    , style "padding" "16px 14px 16px 36px"
                    , style "font-size" "24px"
                    , style "font-family" "monospace"
                    ]
                    []
                ]
            )
        , formField "CATEGORY"
            (div
                [ class "grid grid-cols-4 gap-2"
                ]
                (List.map (viewCategoryBtn p.category) allCategories)
            )
        , formField "NOTE"
            (input
                [ type_ "text"
                , value p.note
                , onInput NoteChanged
                , placeholder "brief (50 chars)"
                , attribute "maxlength" "50"
                , textInputStyle
                ]
                []
            )
        , formField "DETAILS"
            (textarea
                [ value p.longNote
                , onInput LongNoteChanged
                , placeholder "optional — what happened, where, any context (280 chars)"
                , attribute "maxlength" "280"
                , attribute "rows" "3"
                , class "w-full p-3 bg-[#1e2220] border border-[#3a4240] text-[#c8d0c8] rounded-lg font-[inherit] text-base resize-none leading-snug"
                , style "outline" "none"
                ]
                []
            )
        , formField "MERCHANT"
            (input
                [ type_ "text"
                , value p.merchant
                , onInput MerchantChanged
                , placeholder "optional"
                , textInputStyle
                ]
                []
            )
        , formField "DATE"
            (input
                [ type_ "date"
                , value p.date
                , onInput DateChanged
                , textInputStyle
                ]
                []
            )
        , viewLocationWidget model
        , button
            [ onClick SubmitEntry
            , disabled model.submitting
            , style "width" "100%"
            , style "background" "#e8a020"
            , style "color" "#0d0f0e"
            , style "border" "none"
            , style "border-radius" "8px"
            , style "padding" "18px"
            , style "font-size" "18px"
            , style "font-weight" "700"
            , style "letter-spacing" "0.05em"
            , style "cursor" (if model.submitting then "not-allowed" else "pointer")
            , style "margin-top" "8px"
            , style "min-height" "56px"
            , style "opacity" (if model.submitting then "0.6" else "1")
            ]
            [ text
                (if model.submitting then
                    "SAVING..."

                 else if isEditing then
                    "UPDATE EXPENSE"

                 else
                    "SAVE EXPENSE"
                )
            ]
        ]


viewLocationWidget : AuthState -> Html Msg
viewLocationWidget model =
    div [ style "margin-bottom" "16px" ]
        [ viewLocationStatus model.pendingEntry.locationState
        , if model.showMapPicker then
            Html.node "map-picker"
                [ attribute "lat"
                    (case model.pendingEntry.locationState of
                        LocationGot la _ _ ->
                            String.fromFloat la

                        _ ->
                            "64.2008"
                    )
                , attribute "lon"
                    (case model.pendingEntry.locationState of
                        LocationGot _ lo _ ->
                            String.fromFloat lo

                        _ ->
                            "-153.4937"
                    )
                , on "confirm"
                    (D.map2 MapPickerConfirmed
                        (D.at [ "detail", "lat" ] D.float)
                        (D.at [ "detail", "lon" ] D.float)
                    )
                , on "dismiss" (D.succeed DismissMapPicker)
                ]
                []

          else
            text ""
        ]


viewLocationStatus : LocationState -> Html Msg
viewLocationStatus ls =
    case ls of
        LocationFetching ->
            div
                [ style "color" "#4a5a50"
                , style "font-size" "13px"
                , style "padding" "8px 0"
                ]
                [ text "📍 Getting location…" ]

        LocationCheckingExif ->
            div [ class "text-[#4a5a50] text-sm py-2" ]
                [ text "📍 Reading photo…" ]

        LocationNoExifGps ->
            div [ class "flex items-center gap-3 py-2" ]
                [ span [ class "text-[#4a5a50] text-sm" ] [ text "No GPS in photo" ]
                , button [ onClick OpenMapPicker
                         , class "bg-transparent border-none text-[#4a5a50] text-xs cursor-pointer p-0 font-[inherit]" ]
                    [ text "pin manually" ]
                ]

        LocationGot lat lon source ->
            let
                sourceLabel =
                    case source of
                        ExifGps    -> "📍 from photo"
                        BrowserGeo -> "📍 GPS"
                        ManualPin  -> "📍 pinned"
            in
            div [ class "flex items-center gap-3 py-2" ]
                [ span [ class "text-[#4090e0] text-sm" ]
                    [ text (sourceLabel ++ " — " ++ formatCoord lat lon) ]
                , button
                    [ onClick OpenMapPicker
                    , class "bg-transparent border-none text-[#4a5a50] text-xs cursor-pointer p-0 font-[inherit]"
                    ]
                    [ text "adjust" ]
                , button
                    [ onClick SkipLocation
                    , class "bg-transparent border-none text-[#4a5a50] text-xs cursor-pointer p-0 font-[inherit]"
                    ]
                    [ text "remove" ]
                ]

        LocationSkipped ->
            div
                [ style "display" "flex"
                , style "align-items" "center"
                , style "gap" "12px"
                , style "padding" "8px 0"
                ]
                [ span [ style "color" "#4a5a50", style "font-size" "13px" ] [ text "no location" ]
                , button
                    [ onClick OpenMapPicker
                    , style "background" "none"
                    , style "border" "none"
                    , style "color" "#4a5a50"
                    , style "font-size" "12px"
                    , style "cursor" "pointer"
                    , style "padding" "0"
                    , style "font-family" "inherit"
                    ]
                    [ text "pin manually" ]
                ]

        LocationIdle ->
            div
                [ style "display" "flex"
                , style "gap" "12px"
                , style "align-items" "center"
                ]
                [ button
                    [ onClick OpenMapPicker
                    , style "background" "#1e2220"
                    , style "border" "1px solid #3a4240"
                    , style "color" "#c8d0c8"
                    , style "border-radius" "8px"
                    , style "padding" "12px 16px"
                    , style "font-size" "14px"
                    , style "cursor" "pointer"
                    , style "flex" "1"
                    , style "font-family" "inherit"
                    ]
                    [ text "📍 Pin manually" ]
                , button
                    [ onClick SkipLocation
                    , style "background" "none"
                    , style "border" "none"
                    , style "color" "#4a5a50"
                    , style "font-size" "13px"
                    , style "cursor" "pointer"
                    , style "padding" "8px"
                    , style "font-family" "inherit"
                    ]
                    [ text "Skip location" ]
                ]


viewCategoryBtn : Category -> Category -> Html Msg
viewCategoryBtn selected cat =
    let
        active =
            selected == cat
    in
    button
        [ onClick (CategorySelected cat)
        , style "background" (if active then categoryColor cat else "#1e2220")
        , style "color" (if active then "#0d0f0e" else "#c8d0c8")
        , style "border" ("1px solid " ++ (if active then categoryColor cat else "#3a4240"))
        , style "border-radius" "8px"
        , style "padding" "12px 8px"
        , style "font-size" "14px"
        , style "font-weight" (if active then "700" else "400")
        , style "cursor" "pointer"
        , style "display" "flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "gap" "4px"
        , style "min-height" "64px"
        ]
        [ span [ style "font-size" "20px" ] [ text (categoryIcon cat) ]
        , text (categoryLabel cat)
        ]



-- LEDGER TAB


viewLedgerMap : AuthState -> Html Msg
viewLedgerMap model =
    if model.showLedgerMap then
        Html.node "waypoint-map"
            [ attribute "points" (encodeWaypoints model.entries)
            , class "block w-full rounded-xl overflow-hidden mb-5"
            , style "height" "260px"
            ]
            []

    else
        text ""


viewLedgerSummary : List Entry -> Html Msg
viewLedgerSummary entries =
    let
        total =
            List.sum (List.map .amount entries)

        catRow =
            allCategories
                |> List.filterMap
                    (\cat ->
                        let
                            t =
                                entries
                                    |> List.filter (\e -> e.category == cat)
                                    |> List.map .amount
                                    |> List.sum
                        in
                        if t > 0 then
                            Just ( cat, t )
                        else
                            Nothing
                    )
    in
    div
        [ style "background" "#161918"
        , style "border-radius" "10px"
        , style "padding" "14px 16px"
        , style "margin-bottom" "20px"
        ]
        [ div
            [ style "font-family" "monospace"
            , style "font-size" "22px"
            , style "color" "#e8a020"
            , style "margin-bottom" "12px"
            ]
            [ text (formatAmount total) ]
        , div
            [ style "display" "flex"
            , style "flex-wrap" "wrap"
            , style "gap" "10px"
            ]
            (List.map
                (\( cat, t ) ->
                    div
                        [ style "display" "flex"
                        , style "align-items" "center"
                        , style "gap" "4px"
                        ]
                        [ span [ style "font-size" "15px" ] [ text (categoryIcon cat) ]
                        , span
                            [ style "font-family" "monospace"
                            , style "font-size" "13px"
                            , style "color" "#7a8a80"
                            ]
                            [ text (formatAmount t) ]
                        ]
                )
                catRow
            )
        ]


viewLedgerTab : AuthState -> Html Msg
viewLedgerTab model =
    div [ style "padding" "20px" ]
        [ div [ class "flex items-center justify-between mb-5" ]
            [ h2 [ sectionHead ] [ text "LEDGER" ]
            , div [ class "flex gap-2" ]
                [ button
                    [ onClick ToggleLedgerMap
                    , class
                        (if model.showLedgerMap then
                            "px-3 py-1.5 rounded border border-[#3a4240] bg-[#1e3a50] text-[#4090e0] text-sm cursor-pointer font-[inherit]"

                         else
                            "px-3 py-1.5 rounded border border-[#3a4240] bg-transparent text-[#7a8a80] text-sm cursor-pointer font-[inherit]"
                        )
                    ]
                    [ text "🗺 map" ]
                , button
                    [ onClick RefreshClicked
                    , class "px-3 py-1.5 rounded border border-[#3a4240] bg-transparent text-[#7a8a80] text-sm cursor-pointer font-[inherit]"
                    ]
                    [ text "↻ refresh" ]
                ]
            ]
        , if not (List.isEmpty model.entries) then
            viewLedgerSummary model.entries

          else
            text ""
        , viewLedgerMap model
        , if model.config.sheetId == "" then
            p [ style "color" "#7a8a80", style "text-align" "center", style "padding" "32px 0" ]
                [ text "Enter your Sheet ID in Settings to get started." ]

          else if model.loadingEntries then
            viewSkeleton

          else if List.isEmpty model.entries then
            p [ style "color" "#7a8a80", style "text-align" "center", style "padding" "32px 0" ]
                [ text "No expenses yet. Add your first one!" ]

          else
            Keyed.node "div"
                []
                (uniqueDates model.entries
                    |> List.map
                        (\date ->
                            let
                                dayEntries =
                                    List.filter (\e -> e.date == date) model.entries
                            in
                            ( date
                            , div [ style "margin-bottom" "24px" ]
                                [ div
                                    [ style "font-size" "11px"
                                    , style "letter-spacing" "0.1em"
                                    , style "color" "#7a8a80"
                                    , style "margin-bottom" "8px"
                                    , style "padding-bottom" "6px"
                                    , style "border-bottom" "1px solid #2a3230"
                                    , style "display" "flex"
                                    , style "justify-content" "space-between"
                                    , style "align-items" "center"
                                    ]
                                    [ text (String.toUpper (formatDateDisplay date))
                                    , span
                                        [ style "font-family" "monospace"
                                        , style "color" "#e8a020"
                                        , style "letter-spacing" "0"
                                        ]
                                        [ text (formatAmount (List.sum (List.map .amount dayEntries))) ]
                                    ]
                                , Keyed.node "div" [] (List.map (\e -> ( e.id, viewEntryRow e )) dayEntries)
                                ]
                            )
                        )
                )
        ]


viewEntryRow : Entry -> Html Msg
viewEntryRow entry =
    div
        [ onClick (EditEntry entry)
        , style "background" "#161918"
        , style "border-radius" "8px"
        , style "padding" "14px 16px"
        , style "margin-bottom" "8px"
        , style "display" "flex"
        , style "align-items" "center"
        , style "gap" "12px"
        , style "cursor" "pointer"
        ]
        [ div
            [ style "width" "10px"
            , style "height" "10px"
            , style "border-radius" "50%"
            , style "background" (categoryColor entry.category)
            , style "flex-shrink" "0"
            ]
            []
        , span [ style "font-size" "20px", style "flex-shrink" "0" ] [ text (categoryIcon entry.category) ]
        , div [ style "flex" "1", style "min-width" "0" ]
            [ div
                [ style "font-size" "15px"
                , style "color" "#c8d0c8"
                , style "white-space" "nowrap"
                , style "overflow" "hidden"
                , style "text-overflow" "ellipsis"
                ]
                [ text
                    (if entry.note /= "" then
                        entry.note

                     else if entry.merchant /= "" then
                        entry.merchant

                     else
                        categoryLabel entry.category
                    )
                ]
            , if entry.merchant /= "" && entry.note /= "" then
                div [ style "font-size" "12px", style "color" "#4a5a50" ] [ text entry.merchant ]

              else
                text ""
            , if entry.longNote /= "" then
                div [ class "text-xs text-[#4a5a50] mt-1 leading-snug line-clamp-2" ] [ text entry.longNote ]

              else
                text ""
            ]
        , span
            [ style "font-family" "monospace"
            , style "font-size" "17px"
            , style "color" "#c8d0c8"
            , style "flex-shrink" "0"
            ]
            [ text (formatAmount entry.amount) ]
        , case entry.lat of
            Just _ ->
                span
                    [ style "font-size" "14px"
                    , style "color" "#4090e0"
                    , style "flex-shrink" "0"
                    , title "Has GPS coordinates"
                    ]
                    [ text "📍" ]

            Nothing ->
                text ""
        , button
            [ Html.Events.stopPropagationOn "click" (D.succeed ( DeleteEntry entry, True ))
            , style "background" "none"
            , style "border" "none"
            , style "color" "#e85030"
            , style "font-size" "18px"
            , style "cursor" "pointer"
            , style "padding" "4px 8px"
            , style "flex-shrink" "0"
            , style "min-width" "44px"
            , style "min-height" "44px"
            , style "display" "flex"
            , style "align-items" "center"
            , style "justify-content" "center"
            ]
            [ text "✕" ]
        ]


viewSkeleton : Html Msg
viewSkeleton =
    div []
        (List.repeat 5
            (div
                [ style "background" "#161918"
                , style "border-radius" "8px"
                , style "padding" "18px 16px"
                , style "margin-bottom" "8px"
                , style "display" "flex"
                , style "gap" "12px"
                ]
                [ div [ style "width" "10px", style "height" "10px", style "border-radius" "50%", style "background" "#2a3230" ] []
                , div [ style "flex" "1", style "height" "16px", style "background" "#2a3230", style "border-radius" "4px" ] []
                , div [ style "width" "60px", style "height" "16px", style "background" "#2a3230", style "border-radius" "4px" ] []
                ]
            )
        )



-- STATS TAB


viewStatsTab : AuthState -> Html Msg
viewStatsTab model =
    let
        entries =
            model.entries

        total =
            List.sum (List.map .amount entries)

        numDays =
            List.length (uniqueDates entries)

        numEntries =
            List.length entries

        avgPerDay =
            if numDays > 0 then
                total / toFloat numDays

            else
                0

        avgPerEntry =
            if numEntries > 0 then
                total / toFloat numEntries

            else
                0

        median =
            medianAmount entries

        topCat =
            topCategory entries

        bigDay =
            biggestDay entries

        top5 =
            entries
                |> List.sortBy (\e -> negate e.amount)
                |> List.take 5

        tripStart =
            (Zipper.current model.trips).startDate

        daysIn =
            if tripStart /= "" && model.today /= "" then
                isoToDayCount model.today - isoToDayCount tripStart + 1

            else
                0
    in
    div [ style "padding" "20px" ]
        [ h2 [ sectionHead ] [ text "STATS" ]
        , div
            [ style "display" "grid"
            , style "grid-template-columns" "1fr 1fr"
            , style "gap" "12px"
            , style "margin-bottom" "24px"
            ]
            [ statCard "TOTAL SPENT" (formatAmount total)
            , statCard "ENTRIES" (String.fromInt numEntries)
            , statCard "DAYS ON ROAD" (String.fromInt numDays)
            , statCard "AVG / DAY" (formatAmount avgPerDay)
            , statCard "AVG / ENTRY" (formatAmount avgPerEntry)
            , statCard "MEDIAN" (formatAmount median)
            , statCard "TOP CATEGORY"
                (topCat
                    |> Maybe.map (\c -> categoryIcon c ++ " " ++ categoryLabel c)
                    |> Maybe.withDefault "—"
                )
            , if numDays > 1 then
                statCard "BIGGEST DAY"
                    (bigDay
                        |> Maybe.map (\( d, t ) -> String.slice 5 10 d ++ "  " ++ formatAmount t)
                        |> Maybe.withDefault "—"
                    )
              else
                statCard "ENTRIES TODAY" (String.fromInt numEntries)
            , statCard "DAYS INTO TRIP"
                (if daysIn > 0 then String.fromInt daysIn else "—")
            , statCard "PROJ / 30 DAYS"
                (if avgPerDay > 0 then formatAmount (avgPerDay * 30) else "—")
            ]
        , if List.isEmpty entries then
            text ""

          else
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                , style "margin-bottom" "16px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                    [ text "BY CATEGORY" ]
                , viewCategoryChart entries
                ]
        , if numDays > 1 then
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                , style "margin-bottom" "16px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                    [ text "DAILY SPENDING" ]
                , viewDailyChart entries
                ]

          else
            text ""
        , if numDays > 1 then
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                , style "margin-bottom" "16px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                    [ text "CUMULATIVE SPEND" ]
                , viewCumulativeChart entries
                ]

          else
            text ""
        , if List.isEmpty top5 then
            text ""

          else
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "12px" ]
                    [ text "TOP 5 LARGEST" ]
                , div []
                    (List.indexedMap
                        (\i entry ->
                            div
                                [ style "display" "flex"
                                , style "align-items" "center"
                                , style "gap" "12px"
                                , style "padding" "10px 0"
                                , style "border-bottom" (if i < List.length top5 - 1 then "1px solid #2a3230" else "none")
                                ]
                                [ span [ style "color" "#4a5a50", style "font-family" "monospace", style "width" "20px" ]
                                    [ text (String.fromInt (i + 1) ++ ".") ]
                                , span [ style "font-size" "18px" ] [ text (categoryIcon entry.category) ]
                                , div [ style "flex" "1" ]
                                    [ div [ style "font-size" "14px" ] [ text (if entry.note /= "" then entry.note else categoryLabel entry.category) ]
                                    , div [ style "font-size" "11px", style "color" "#7a8a80" ] [ text entry.date ]
                                    ]
                                , span [ style "font-family" "monospace", style "color" "#e8a020", style "font-size" "16px" ]
                                    [ text (formatAmount entry.amount) ]
                                ]
                        )
                        top5
                    )
                ]
        ]


statCard : String -> String -> Html Msg
statCard label_ value =
    div
        [ style "background" "#161918"
        , style "border-radius" "10px"
        , style "padding" "16px"
        ]
        [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "6px" ]
            [ text label_ ]
        , div [ style "font-size" "22px", style "font-family" "monospace", style "color" "#e8a020" ]
            [ text value ]
        ]


viewCategoryChart : List Entry -> Html Msg
viewCategoryChart entries =
    let
        rows =
            allCategories
                |> List.map
                    (\cat ->
                        { color = categoryColor cat
                        , label = categoryLabel cat
                        , total =
                            entries
                                |> List.filter (\e -> e.category == cat)
                                |> List.map .amount
                                |> List.sum
                        }
                    )
    in
    C.chart
        [ CA.height 140
        , CA.margin { top = 10, bottom = 28, left = 0, right = 0 }
        ]
        [ C.bars []
            [ C.bar .total []
                |> C.variation (\_ d -> [ CA.color d.color ])
            ]
            rows
        , C.binLabels .label [ CA.moveDown 16, CA.color "#7a8a80", CA.fontSize 9 ]
        ]


viewDailyChart : List Entry -> Html Msg
viewDailyChart entries =
    let
        days =
            uniqueDates entries
                |> List.reverse
                |> List.map
                    (\date ->
                        { date = String.slice 5 10 date
                        , total =
                            entries
                                |> List.filter (\e -> e.date == date)
                                |> List.map .amount
                                |> List.sum
                        }
                    )
    in
    C.chart
        [ CA.height 140
        , CA.margin { top = 10, bottom = 28, left = 0, right = 0 }
        ]
        [ C.bars []
            [ C.bar .total [ CA.color "#e8a020" ] ]
            days
        , C.binLabels .date [ CA.moveDown 16, CA.color "#7a8a80", CA.fontSize 8 ]
        ]


viewCumulativeChart : List Entry -> Html Msg
viewCumulativeChart entries =
    let
        sorted =
            uniqueDates entries |> List.reverse

        points =
            List.indexedMap
                (\i date ->
                    { x = toFloat (i + 1)
                    , y =
                        entries
                            |> List.filter (\e -> e.date <= date)
                            |> List.map .amount
                            |> List.sum
                    }
                )
                sorted
    in
    C.chart
        [ CA.height 160
        , CA.margin { top = 10, bottom = 10, left = 0, right = 0 }
        ]
        [ C.series .x
            [ C.interpolated .y [ CA.color "#4090e0", CA.width 2 ] [] ]
            points
        ]



-- TRIPS TAB


viewTripsTab : AuthState -> Html Msg
viewTripsTab as_ =
    let
        activeTrip =
            Zipper.current as_.trips

        allTrips =
            Zipper.toList as_.trips

        otherTrips =
            List.filter (\t -> t.tabName /= activeTrip.tabName) allTrips

        totalSpent =
            List.sum (List.map .amount as_.entries)
    in
    div [ style "padding" "20px" ]
        [ h2 [ sectionHead ] [ text "TRIPS" ]
        , div
            [ style "background" "#161918"
            , style "border" "1px solid #2a3230"
            , style "border-radius" "12px"
            , style "padding" "16px"
            , style "margin-bottom" "20px"
            ]
            [ div [ style "display" "flex", style "justify-content" "space-between", style "align-items" "flex-start" ]
                [ div []
                    [ p
                        [ style "font-size" "18px"
                        , style "font-weight" "700"
                        , style "color" "#e8a020"
                        , style "margin-bottom" "4px"
                        ]
                        [ text activeTrip.name ]
                    , if activeTrip.description /= "" then
                        p [ style "font-size" "13px", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                            [ text activeTrip.description ]
                      else
                        text ""
                    , if activeTrip.startDate /= "" then
                        p [ style "font-size" "12px", style "color" "#4a5a50" ]
                            [ text (activeTrip.startDate ++ (if activeTrip.endDate /= "" then " → " ++ activeTrip.endDate else "")) ]
                      else
                        text ""
                    ]
                , button
                    [ onClick (OpenEditTripForm activeTrip)
                    , style "background" "none"
                    , style "border" "1px solid #2a3230"
                    , style "color" "#7a8a80"
                    , style "border-radius" "6px"
                    , style "padding" "6px 10px"
                    , style "font-size" "12px"
                    , style "cursor" "pointer"
                    ]
                    [ text "Edit" ]
                ]
            , if activeTrip.budget > 0 then
                let
                    pct =
                        Basics.min 1.0 (totalSpent / activeTrip.budget)
                in
                div [ style "margin-top" "12px" ]
                    [ div [ style "display" "flex", style "justify-content" "space-between", style "font-size" "12px", style "color" "#7a8a80", style "margin-bottom" "4px" ]
                        [ text ("$" ++ String.fromInt (round totalSpent) ++ " spent")
                        , text ("Budget: $" ++ String.fromInt (round activeTrip.budget))
                        ]
                    , div [ style "background" "#2a3230", style "border-radius" "4px", style "height" "6px" ]
                        [ div
                            [ style "background" (if pct >= 1.0 then "#e85030" else "#e8a020")
                            , style "border-radius" "4px"
                            , style "height" "6px"
                            , style "width" (String.fromFloat (pct * 100) ++ "%")
                            ]
                            []
                        ]
                    ]
              else
                text ""
            ]
        , if not (List.isEmpty otherTrips) then
            div [ style "margin-bottom" "20px" ]
                (List.map
                    (\trip ->
                        button
                            [ onClick (SelectTrip trip.tabName)
                            , style "width" "100%"
                            , style "background" "#161918"
                            , style "border" "1px solid #2a3230"
                            , style "border-radius" "10px"
                            , style "padding" "14px 16px"
                            , style "margin-bottom" "8px"
                            , style "display" "flex"
                            , style "justify-content" "space-between"
                            , style "align-items" "center"
                            , style "cursor" "pointer"
                            , style "color" "#c8d0c8"
                            , style "font-family" "inherit"
                            ]
                            [ div [ style "text-align" "left" ]
                                [ p [ style "font-size" "15px", style "font-weight" "600", style "margin-bottom" "2px" ] [ text trip.name ]
                                , if trip.startDate /= "" then
                                    p [ style "font-size" "11px", style "color" "#4a5a50" ] [ text trip.startDate ]
                                  else
                                    text ""
                                ]
                            , span [ style "color" "#7a8a80", style "font-size" "16px" ] [ text "›" ]
                            ]
                    )
                    otherTrips
                )
          else
            text ""
        , case as_.tripForm of
            Nothing ->
                button
                    [ onClick OpenNewTripForm
                    , style "width" "100%"
                    , style "background" "none"
                    , style "border" "1px dashed #3a4240"
                    , style "border-radius" "10px"
                    , style "padding" "14px"
                    , style "color" "#7a8a80"
                    , style "font-size" "15px"
                    , style "cursor" "pointer"
                    , style "font-family" "inherit"
                    ]
                    [ text "+ New Trip" ]

            Just form ->
                viewTripForm form
        ]


viewTripForm : TripForm -> Html Msg
viewTripForm form =
    div
        [ style "background" "#161918"
        , style "border" "1px solid #2a3230"
        , style "border-radius" "12px"
        , style "padding" "16px"
        ]
        [ p [ style "font-size" "15px", style "font-weight" "700", style "color" "#e8a020", style "margin-bottom" "16px" ]
            [ text (if form.editing == Nothing then "New Trip" else "Edit Trip") ]
        , if not (List.isEmpty form.errors) then
            div [ style "background" "#2a1510", style "border" "1px solid #e85030", style "border-radius" "8px", style "padding" "10px", style "margin-bottom" "12px" ]
                (List.map (\e -> p [ style "font-size" "13px", style "color" "#e8a020" ] [ text e ]) form.errors)
          else
            text ""
        , formField "TRIP NAME"
            (input
                [ type_ "text"
                , value form.name
                , onInput (TripFieldChanged TripName)
                , placeholder "Alaska 2026"
                , textInputStyle
                ]
                []
            )
        , formField "DESCRIPTION"
            (input
                [ type_ "text"
                , value form.description
                , onInput (TripFieldChanged TripDescription)
                , placeholder "Optional"
                , textInputStyle
                ]
                []
            )
        , formField "START DATE"
            (input
                [ type_ "date"
                , value form.startDate
                , onInput (TripFieldChanged TripStartDate)
                , textInputStyle
                ]
                []
            )
        , formField "END DATE"
            (input
                [ type_ "date"
                , value form.endDate
                , onInput (TripFieldChanged TripEndDate)
                , textInputStyle
                ]
                []
            )
        , formField "BUDGET ($)"
            (input
                [ type_ "number"
                , value form.budget
                , onInput (TripFieldChanged TripBudget)
                , placeholder "0 = no budget"
                , textInputStyle
                ]
                []
            )
        , formField "COVER PHOTO URL"
            (input
                [ type_ "url"
                , value form.coverPhotoUrl
                , onInput (TripFieldChanged TripCoverPhoto)
                , placeholder "https://..."
                , textInputStyle
                ]
                []
            )
        , div [ style "display" "flex", style "gap" "10px", style "margin-top" "16px" ]
            [ button
                [ onClick SaveTripForm
                , style "flex" "1"
                , style "background" "#e8a020"
                , style "color" "#0d0f0e"
                , style "border" "none"
                , style "border-radius" "8px"
                , style "padding" "12px"
                , style "font-size" "15px"
                , style "font-weight" "700"
                , style "cursor" "pointer"
                ]
                [ text "Save" ]
            , button
                [ onClick (TabChanged TripsTab)
                , style "flex" "1"
                , style "background" "none"
                , style "color" "#7a8a80"
                , style "border" "1px solid #2a3230"
                , style "border-radius" "8px"
                , style "padding" "12px"
                , style "font-size" "15px"
                , style "cursor" "pointer"
                ]
                [ text "Cancel" ]
            ]
        ]



-- SETTINGS TAB


viewSettingsPanel : AppConfig -> Bool -> String -> Html Msg
viewSettingsPanel cfg isSignedIn version =
    div [ style "padding" "24px 20px" ]
        [ h2 [ sectionHead ] [ text "SETTINGS" ]
        , formField "GOOGLE CLIENT ID"
            (input
                [ type_ "text"
                , value cfg.googleClientId
                , onInput GoogleClientIdChanged
                , placeholder "123456789-abc...apps.googleusercontent.com"
                , textInputStyle
                ]
                []
            )
        , formField "GOOGLE SHEET ID"
            (input
                [ type_ "text"
                , value cfg.sheetId
                , onInput SheetIdChanged
                , placeholder "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms"
                , textInputStyle
                ]
                []
            )
        , formField "ANTHROPIC API KEY"
            (input
                [ type_ "password"
                , value cfg.anthropicKey
                , onInput ApiKeyChanged
                , placeholder "sk-ant-..."
                , textInputStyle
                ]
                []
            )
        , if isSignedIn then
            div [ style "margin-top" "32px" ]
                [ button
                    [ onClick SignOutClicked
                    , style "width" "100%"
                    , style "background" "none"
                    , style "border" "1px solid #e85030"
                    , style "color" "#e85030"
                    , style "border-radius" "8px"
                    , style "padding" "14px"
                    , style "font-size" "15px"
                    , style "cursor" "pointer"
                    ]
                    [ text "SIGN OUT" ]
                ]
          else
            text ""
        , div [ style "margin-top" "8px" ]
            [ button
                [ onClick ResetSettingsClicked
                , Html.Attributes.class "w-full py-3.5 rounded-lg border border-red-900/60 text-red-400/80 text-sm cursor-pointer bg-transparent font-[inherit] hover:border-red-700 hover:text-red-300 transition-colors"
                ]
                [ text "Reset all settings" ]
            ]
        , if version /= "" then
            p [ Html.Attributes.class "text-[#3a4a40] text-xs text-center mt-6 font-mono" ]
                [ text version ]
          else
            text ""
        ]



-- SHARED VIEW HELPERS


viewErrorBanner : Maybe String -> Html Msg
viewErrorBanner maybeErr =
    case maybeErr of
        Nothing ->
            text ""

        Just err ->
            div
                [ style "background" "#2a1510"
                , style "border-left" "4px solid #e85030"
                , style "color" "#e8a020"
                , style "padding" "12px 16px"
                , style "margin" "0 20px 16px"
                , style "border-radius" "0 6px 6px 0"
                , style "font-size" "14px"
                , style "display" "flex"
                , style "justify-content" "space-between"
                , style "align-items" "center"
                ]
                [ text err
                , button
                    [ onClick DismissError
                    , style "background" "none"
                    , style "border" "none"
                    , style "color" "#e85030"
                    , style "cursor" "pointer"
                    , style "font-size" "18px"
                    , style "padding" "0 0 0 12px"
                    ]
                    [ text "✕" ]
                ]


formField : String -> Html Msg -> Html Msg
formField label_ input_ =
    div [ style "margin-bottom" "20px" ]
        [ div
            [ style "font-size" "11px"
            , style "letter-spacing" "0.1em"
            , style "color" "#7a8a80"
            , style "margin-bottom" "8px"
            ]
            [ text label_ ]
        , input_
        ]


sectionHead : Attribute Msg
sectionHead =
    style "font-size" "13px"


textInputStyle : Attribute Msg
textInputStyle =
    style "width" "100%"



-- MAIN


main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions =
            \_ ->
                Sub.batch
                    [ gotNewToken GotOAuthToken
                    , gotGpsCoords (\r -> if r.denied then GeolocationDenied else GotGpsCoords r.lat r.lon)
                    , gotExifResult (\r -> if r.hasGps then GotExifCoords r.id (Just r.lat) (Just r.lon) "" else GotExifCoords r.id Nothing Nothing r.debug)
                    ]
        }
