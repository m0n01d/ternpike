module Types exposing (..)

import Browser
import Browser.Navigation as Nav
import Data.Amendment exposing (Amendment)
import Data.Category exposing (Category(..))
import Data.Entry exposing (EffectiveEntry)
import Data.Expense exposing (Expense)
import Data.ExpenseId exposing (ExpenseId)
import Data.Trip exposing (Trip, TripField, TripForm)
import Data.TripId exposing (TripId)
import Data.Void exposing (Void)
import Dict exposing (Dict)
import File exposing (File)
import Http
import Json.Decode as D
import Time
import Url


-- NAVIGATION


type Tab
    = AddTab
    | LedgerTab
    | ScanTab
    | SettingsTab
    | StatsTab
    | TripsTab


type Route
    = RouteAdd TripId
    | RouteAddReviewScan
    | RouteEditEntry TripId ExpenseId
    | RouteLedger TripId
    | RouteScan TripId
    | RouteSettings
    | RouteStats TripId
    | RouteTrips


-- LOCATION


type LocationSource
    = BrowserGeo
    | ExifGps
    | ManualPin


type LocationState
    = LocationCheckingExif
    | LocationFetching
    | LocationGot Float Float LocationSource
    | LocationIdle
    | LocationNoExifGps
    | LocationSkipped


-- SCAN


type ScanStatus
    = ScanProcessing
    | ScanQueued
    | ScanReady
    | ScanSubmitted


type alias OcrData =
    { amount   : Maybe Float
    , category : Maybe Category
    , date     : Maybe String
    , longNote : Maybe String
    , merchant : Maybe String
    , note     : Maybe String
    }


type alias ScanItem =
    { exifDebug    : String
    , id           : String
    , imageUrl     : String
    , locationState: LocationState
    , ocrData      : Maybe OcrData
    , status       : ScanStatus
    }


-- FORM STATE


type alias PendingEntry =
    { amount        : String
    , category      : Category
    , date          : String
    , locationState : LocationState
    , longNote      : String
    , merchant      : String
    , note          : String
    }


-- AUTH / SESSION


type alias Creds =
    { userId : String }


type alias AppConfig =
    { anthropicKey : String
    , backendUrl   : String
    }


type ExpensesState
    = Loaded (List EffectiveEntry)
    | Loading
    | NotAsked


type SyncState
    = AuthExpired
    | NotEnabled
    | SyncError
    | Synced
    | Syncing


type GuestReason
    = AwaitingCode String
    | NotLoggedIn
    | SessionExpired


type alias GuestSession =
    { config : AppConfig
    , reason : GuestReason
    }


type alias GuestState =
    { authError    : Maybe String
    , basePath     : String
    , codeInput    : String
    , emailInput   : String
    , key          : Nav.Key
    , session      : GuestSession
    , showSettings : Bool
    , today        : String
    , version      : String
    }


type alias AuthState =
    { activeScanItemId  : Maybe String
    , amendments        : List Amendment
    , basePath          : String
    , config            : AppConfig
    , confirmDeleteTrip : Maybe Trip
    , creds             : Creds
    , currentTripId     : TripId
    , editingEntry      : Maybe Expense
    , error             : Maybe String
    , expensesState     : ExpensesState
    , geoBlocked        : Bool
    , key               : Nav.Key
    , pendingEditEntry  : Maybe { entryId : ExpenseId, tripId : TripId }
    , pendingEntry      : PendingEntry
    , rawExpenses       : List Expense
    , scanQueue         : Dict String ScanItem
    , showLedgerMap     : Bool
    , showMapPicker     : Bool
    , submitting        : Bool
    , syncState         : SyncState
    , tab               : Tab
    , toast             : Maybe String
    , today             : String
    , tripForm          : Maybe TripForm
    , trips             : Dict String Trip
    , version           : String
    , voids             : List Void
    }


type Model
    = AuthModel AuthState
    | GuestModel GuestState


-- MSG


type Msg
    = AmountChanged String
    | ApiKeyChanged String
    | BackToQueue
    | CancelDeleteTrip
    | CancelEdit
    | CategorySelected Category
    | ClearDoneItems
    | CodeInputChanged String
    | ConfirmDeleteTrip Trip
    | DateChanged String
    | DeleteTrip Trip
    | DismissError
    | DismissMapPicker
    | EditEntry Expense
    | EmailInputChanged String
    | FilesSelected (List File)
    | GeolocationDenied
    | GotExifCoords String (Maybe Float) (Maybe Float) String
    | GotFileUrl String String
    | GotGpsCoords Float Float
    | GotOcrResult String (Result Http.Error String)
    | GotPouchMsg D.Value
    | GotSaveTripTime Time.Posix
    | GotSubmitTime Time.Posix
    | LinkClicked Browser.UrlRequest
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
    | SelectTrip TripId
    | ShowToast String
    | SignOutClicked
    | SkipLocation
    | SubmitCode
    | SubmitEmail
    | SubmitEntry
    | TabChanged Tab
    | ToggleGuestSettings
    | ToggleLedgerMap
    | ToastExpired
    | TripFieldChanged TripField String
    | UrlChanged Url.Url
    | VoidEntry Expense


-- POUCHDB PROTOCOL


type PouchOutbound
    = GetAllTrips
    | GetExpenses String
    | SaveAmend   D.Value
    | SaveExpense D.Value
    | SaveTrip    D.Value
    | SaveVoid    D.Value


type PouchInbound
    = AuthExpiredMsg
    | DbChange DbChangeData
    | DbError  String
    | QueryComplete String
    | SyncStateMsg SyncState


type alias DbChangeData =
    { deleted : Bool
    , doc     : D.Value
    , id      : String
    }
