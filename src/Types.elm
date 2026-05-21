module Types exposing
    ( AuthState
    , GuestState
    , Model(..)
    , Msg(..)
    )

{-| Top-level state and message types — the spine of the Elm
architecture for this app.

Everything else lives in `src/Data/*` modules: navigation
(`Data.Navigation`), location capture (`Data.Location`), receipt
scanning (`Data.Scan`), form state (`Data.PendingEntry`, `Data.Ledger`),
auth/config (`Data.Auth`, `Data.Guest`), sync (`Data.Sync`), PouchDB
ports (`Data.Pouch`), and trip loading (`Data.Trips`).

What stays here:

  - `Model = GuestModel | AuthModel` — the union that lets the
    compiler enforce "auth-only pages cannot be reached while signed
    out" (see `CLAUDE.md`).
  - `AuthState` — the giant signed-in state record.
  - `GuestState` — the signed-out state record.
  - `Msg` — every action the runtime dispatches. Centralised because
    every page produces and every handler consumes it; splitting it
    would just churn imports without buying anything.

These records and the message union are exported by name (not `(..)`)
per the style guide; constructors of `Msg` are exposed via `Msg(..)`
because every consumer pattern-matches them.

-}

import Browser
import Browser.Navigation as Nav
import Chart.Item as CI
import Data.Amendment exposing (Amendment)
import Data.Auth exposing (AppConfig, Creds)
import Data.Category exposing (Category)
import Data.Expense exposing (Expense)
import Data.Guest exposing (GuestSession)
import Data.Navigation exposing (Route)
import Data.PaymentMethod exposing (PaymentMethod)
import Data.PendingEntry exposing (PendingForm)
import Data.Scan exposing (ScanItem)
import Data.StatsGranularity exposing (Granularity)
import Data.StatsHover exposing (CumulativePoint, DailyDay, Hover)
import Data.Sync exposing (SyncState)
import Data.Trip exposing (Trip, TripField, TripForm)
import Data.Trips exposing (TripsState)
import Data.Void exposing (Void)
import Dict exposing (Dict)
import File exposing (File)
import Http
import Json.Decode
import Set exposing (Set)
import Time
import Url



-- MODEL


{-| The two-tree model. `AuthModel` is the signed-in app; `GuestModel`
is the sign-in flow. The compiler ensures auth-only pages can only be
reached through `AuthModel`.
-}
type Model
    = AuthModel AuthState
    | GuestModel GuestState


{-| Signed-out state.

Holds the email/code form inputs plus the pre-login `GuestSession`
(config + flow step). `authError` carries transient error chips that
clear on the next transition. `showSettings` lets the user open the
settings panel from the guest screen to set their Anthropic key
before signing in.

-}
type alias GuestState =
    { authError : Maybe String
    , basePath : String
    , codeInput : String
    , emailInput : String
    , key : Nav.Key
    , session : GuestSession
    , showSettings : Bool
    , today : String
    , version : String
    }


{-| Signed-in state — the cache for every PouchDB-backed document plus
the page-level UI state for the current route.

Document caches (all keyed by stringified ID):

  - `amendments`, `voids` — flat dicts, used by `Data.Entry.resolve`.
  - `expenses` — `Dict (TripId.toString) (Dict (ExpenseId.toString)
    Expense)`. Nested so single-trip lookup is one `Dict.get` and
    cross-trip lookup (e.g. `Main.findEffective`) scans only the loaded
    trips.
  - `trips` — `TripsState`, the loading-aware zipper wrapper.

Loading bookkeeping:

  - `loadingTrips` / `tripLoaded` — guards against duplicate
    `GetTripExpenses` queries. A trip moves from
    `loadingTrips`→`tripLoaded` when its bundle arrives.
  - `loadingExpenses` — same idea for single-expense fetches on the
    edit route.

Form state:

  - `form` — `PendingForm`, the in-progress Add page.
  - `tripForm` — `Just` when the new/edit-trip modal is open.

Ephemeral UI:

  - `confirmDeleteTrip`, `showLedgerMap`, `showMapPicker` — modal/toggle
    state for the corresponding pages.
  - `activeScanItemId` — set while the user is reviewing one scan-queue
    item on the Add tab; flipping the effective route to
    `RouteAddReviewScan`.
  - `error`, `toast`, `submitting` — banner, transient toast, submit
    spinner.

Whenever fields here change, update `docs/architecture.md` per the
project memo.

-}
type alias AuthState =
    { activeScanItemId : Maybe String
    , amendments : Dict String Amendment
    , basePath : String
    , config : AppConfig
    , confirmDeleteTrip : Maybe Trip
    , creds : Creds
    , error : Maybe String
    , expenses : Dict String (Dict String Expense)
    , form : PendingForm
    , geoBlocked : Bool
    , key : Nav.Key
    , loadingExpenses : Set String
    , loadingTrips : Set String
    , route : Route
    , scanQueue : Dict String ScanItem
    , showLedgerMap : Bool
    , showMapPicker : Bool
    , statsGranularity : Maybe Granularity
    , statsHover : Hover
    , submitting : Bool
    , syncState : SyncState
    , toast : Maybe String
    , today : String
    , tripForm : Maybe TripForm
    , tripLoaded : Set String
    , trips : TripsState
    , version : String
    , voids : Dict String Void
    }



-- MSG


{-| Every action the runtime can dispatch.

Variants are grouped by area below; the type itself is alphabetised per
the style guide.

Form inputs (Add page): `AmountChanged`, `CategorySelected`,
`DateChanged`, `LongNoteChanged`, `MerchantChanged`, `NoteChanged`,
`PaymentMethodChanged`.

Scan flow: `FilesSelected`, `GotFileUrl`, `GotExifCoords`,
`GotOcrResult`, `ReviewScanItem`, `BackToQueue`, `ClearDoneItems`.

Location: `GotGpsCoords`, `GeolocationDenied`, `OpenMapPicker`,
`MapPickerConfirmed`, `DismissMapPicker`, `SkipLocation`.

Trip CRUD: `OpenNewTripForm`, `OpenEditTripForm`, `TripFieldChanged`,
`SaveTripForm`, `GotSaveTripTime`, `CloseTripForm`,
`ConfirmDeleteTrip`, `CancelDeleteTrip`, `DeleteTrip`.

Expense submit/void: `SubmitEntry`, `GotSubmitTime`, `VoidEntry`.

Guest auth: `EmailInputChanged`, `SubmitEmail`, `CodeInputChanged`,
`SubmitCode`, `RequestCodeResult`, `VerifyCodeResult`,
`ToggleGuestSettings`.

Session: `SignOutClicked`, `ResetSettingsClicked`, `ApiKeyChanged`.

PouchDB / navigation / chrome: `GotPouchMsg`, `LinkClicked`,
`UrlChanged`, `RefreshClicked`, `ToggleLedgerMap`, `ShowToast`,
`ToastExpired`, `DismissError`.

Stats hover: `HoverDailyBars`, `HoverCumulativePoints` — UI-only,
records the chart datapoint(s) the pointer is currently over so the
Stats page can render a tooltip overlay.

Stats granularity: `SetStatsGranularity` — switches the Daily Spending
chart between `Auto`, `Daily`, `Weekly`, and `Monthly` bins from the
chip selector.

-}
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
    | GotPouchMsg Json.Decode.Value
    | GotSaveTripTime Time.Posix
    | GotSubmitTime Time.Posix
    | HoverCumulativePoints (List (CI.One CumulativePoint CI.Dot))
    | HoverDailyBars (List (CI.One DailyDay CI.Bar))
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
    | ScrolledToTop
    | SetStatsGranularity Granularity
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
