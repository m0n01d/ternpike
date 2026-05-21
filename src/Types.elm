module Types exposing (..)

import Browser
import Browser.Navigation as Nav
import Data.Amendment exposing (Amendment)
import Data.Category exposing (Category(..))
import Data.Entry exposing (EffectiveEntry)
import Data.Expense exposing (Expense)
import Data.ExpenseId exposing (ExpenseId)
import Data.PaymentMethod exposing (PaymentMethod)
import Data.Trip exposing (Trip, TripField, TripForm)
import Data.TripId exposing (TripId)
import Data.Trips exposing (Trips)
import Data.Void exposing (Void)
import Dict exposing (Dict)
import File exposing (File)
import Http
import Json.Decode as D
import Set exposing (Set)
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
    { amount        : Maybe Float
    , category      : Maybe Category
    , date          : Maybe String
    , longNote      : Maybe String
    , merchant      : Maybe String
    , note          : Maybe String
    , paymentMethod : Maybe PaymentMethod
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
    , paymentMethod : Maybe PaymentMethod
    }


-- AUTH / SESSION


type alias Creds =
    { dbName   : String
    , email    : String
    , password : String
    }


type alias AppConfig =
    { anthropicKey : String
    , backendUrl   : String
    }


type AddPageMode
    = AddPageEditing ExpenseId
    | AddPageLoading ExpenseId
    | AddPageNew


type LedgerMode
    = LedgerLoading
    | LedgerReady (List EffectiveEntry)


type PendingForm
    = EditForm ExpenseId PendingEntry
    | FreshForm PendingEntry


type TripsState
    = NoTripsYet
    | TripsFailed String
    | TripsLoaded Trips
    | TripsLoading (Dict String Trip) (Maybe TripId)


type SyncState
    = AuthExpired
    | NotEnabled
    | SyncError
    | Synced
    | Syncing


type GuestReason
    = AwaitingCode String
    | NotLoggedIn
    | RequestingCode String
    | SessionExpired
    | VerifyingCode String String


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
    , amendments        : Dict String Amendment
    , basePath          : String
    , config            : AppConfig
    , confirmDeleteTrip : Maybe Trip
    , creds             : Creds
    , error             : Maybe String
    , expenses          : Dict String (Dict String Expense)
    , form              : PendingForm
    , geoBlocked        : Bool
    , key               : Nav.Key
    , loadingExpenses   : Set String
    , loadingTrips      : Set String
    , route             : Route
    , scanQueue         : Dict String ScanItem
    , showLedgerMap     : Bool
    , showMapPicker     : Bool
    , submitting        : Bool
    , syncState         : SyncState
    , toast             : Maybe String
    , today             : String
    , tripForm          : Maybe TripForm
    , tripLoaded        : Set String
    , trips             : TripsState
    , version           : String
    , voids             : Dict String Void
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
    | CategorySelected Category
    | ClearDoneItems
    | CloseTripForm
    | CodeInputChanged String
    | ConfirmDeleteTrip Trip
    | DateChanged String
    | DeleteTrip Trip
    | DismissError
    | DismissMapPicker
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
    | PaymentMethodChanged (Maybe PaymentMethod)
    | RefreshClicked
    | RequestCodeResult (Result Http.Error ())
    | ResetSettingsClicked
    | ReviewScanItem String
    | SaveTripForm
    | ShowToast String
    | SignOutClicked
    | SkipLocation
    | SubmitCode
    | SubmitEmail
    | SubmitEntry
    | ToastExpired
    | ToggleGuestSettings
    | ToggleLedgerMap
    | TripFieldChanged TripField String
    | UrlChanged Url.Url
    | VerifyCodeResult (Result Http.Error Creds)
    | VoidEntry Expense


-- POUCHDB PROTOCOL


type PouchOutbound
    = GetAllTrips
    | GetExpense     ExpenseId
    | GetTripExpenses TripId
    | SaveAmend      D.Value
    | SaveExpense    D.Value
    | SaveTrip       D.Value
    | SaveVoid       D.Value


type PouchInbound
    = AuthExpiredMsg
    | DbChange DocChange
    | DbDeleted String
    | DbError String
    | ExpenseFetched ExpenseId ExpenseBundle
    | SyncStateMsg SyncState
    | TripExpensesFetched TripId TripBundle
    | TripsFetched (Dict String Trip)


type DocChange
    = AmendChanged Amendment
    | ExpenseChanged Expense
    | TripChanged Trip
    | VoidChanged Void


type alias TripBundle =
    { amendments : Dict String Amendment
    , expenses   : Dict String Expense
    , voids      : Dict String Void
    }


type alias ExpenseBundle =
    { amendments : Dict String Amendment
    , expense    : Maybe Expense
    , void       : Maybe Void
    }
