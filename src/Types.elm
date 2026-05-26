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
import Data.ColorScheme exposing (ColorScheme)
import Data.DateField exposing (DateField)
import Data.Expense exposing (Expense)
import Data.ExpenseId exposing (ExpenseId)
import Data.Guest exposing (GuestSession)
import Data.Navigation exposing (Route)
import Data.Notifications exposing (NotificationPrefs, NotificationToggle, Permission, StandaloneState)
import Data.PaymentMethod exposing (PaymentMethod)
import Data.PendingEntry exposing (ParsedEntry, PendingForm)
import Data.Scan exposing (ScanItem)
import Data.ScanItemId exposing (ScanItemId)
import Data.SharedTripId exposing (SharedTripId)
import Data.SharedTripUi exposing (SharedTripUiState)
import Data.SharedTrips
import Data.StatsGranularity exposing (Granularity)
import Data.StatsHover exposing (CumulativePoint, DailyDay, Hover)
import Data.Sync exposing (SyncState)
import Data.Tier exposing (Tier)
import Data.Trip exposing (Trip, TripField, TripForm)
import Data.TripId exposing (TripId)
import Data.Trips exposing (TripsState)
import Data.UserId
import Data.Void exposing (Void)
import Dict exposing (Dict)
import File exposing (File)
import Http
import Http.GeocodeApi
import Http.SharedTripApi
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
before signing in. `networkOffline` mirrors `navigator.onLine`
(inverted) so the guest UI can surface a disconnected banner.

-}
type alias GuestState =
    { authError : Maybe String
    , basePath : String
    , codeInput : String
    , emailInput : String
    , key : Nav.Key
    , networkOffline : Bool
    , pendingJoinToken : Maybe String
    , session : GuestSession
    , showSettings : Bool
    , today : DateField
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
  - `networkOffline` — `True` while the browser reports no connection
    (driven by `navigator.onLine` + `online`/`offline` events via the
    `networkStatus` port). Used to gate the layout banner, sync-dot
    state, and the Scan page's network-dependent affordances.
  - `showInstallPrompt` — `True` once the browser has fired
    `beforeinstallprompt` and the deferred event is stashed on the JS
    side. Driven by the `canInstall` port; reset to `False` after the
    user accepts/dismisses the prompt or after `appinstalled` fires.
    The Settings page renders an "Install app" button only when this
    is `True` — browsers that don't fire `beforeinstallprompt` (e.g.
    Safari) never see the button.

Whenever fields here change, update `docs/architecture.md` per the
project memo.

-}
type alias AuthState =
    { activeScanItemId : Maybe ScanItemId
    , amendments : Dict String Amendment
    , basePath : String
    , colorScheme : ColorScheme
    , config : AppConfig
    , confirmDeleteTrip : Maybe Trip
    , creds : Creds
    , currentUser : Data.UserId.UserId
    , duplicateWarning : Maybe Expense
    , error : Maybe String
    , expenses : Dict String (Dict String Expense)
    , sharedTripUi : SharedTripUiState
    , sharedTrips : Data.SharedTrips.SharedTrips
    , form : PendingForm
    , geoBlocked : Bool
    , key : Nav.Key
    , lastSyncedAt : Maybe Time.Posix
    , ledgerMapExpanded : Bool
    , loadingExpenses : Set String
    , loadingTrips : Set String
    , movePicker : Maybe Expense
    , networkOffline : Bool
    , notificationPermission : Permission
    , notificationPrefs : NotificationPrefs
    , openLedgerMenu : Maybe ExpenseId
    , pushSubscribed : Bool
    , route : Route
    , scanQueue : Dict String ScanItem
    , showByoKeyInput : Bool
    , showDayIntensity : Bool
    , showInstallPrompt : Bool
    , showLedgerMap : Bool
    , showMapPicker : Bool
    , standalone : StandaloneState
    , statsGranularity : Maybe Granularity
    , statsHover : Hover
    , submitting : Bool
    , syncState : SyncState
    , tier : Tier
    , toast : Maybe String
    , today : DateField
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

Form inputs (Add page): `AddressChanged`, `AmountChanged`,
`CategorySelected`, `DateChanged`, `LongNoteChanged`, `MerchantChanged`,
`NoteChanged`, `PaymentMethodChanged`.

Scan flow: `FilesSelected`, `GotFileUrl`, `GotExifCoords`,
`GotGeocodeResult`, `GotOcrResult`, `ReviewScanItem`, `BackToQueue`,
`ClearDoneItems`.

Location: `GotGpsCoords`, `GeolocationDenied`, `OpenMapPicker`,
`MapPickerConfirmed`, `DismissMapPicker`, `SkipLocation`.

Trip CRUD: `OpenNewTripForm`, `OpenEditTripForm`, `TripFieldChanged`,
`SaveTripForm`, `GotSaveTripTime`, `CloseTripForm`,
`ConfirmDeleteTrip`, `CancelDeleteTrip`, `DeleteTrip`,
`GotDeleteTripTime` — `DeleteTrip` fires a `Time.now` task so the void
tombstone's `createdAt` is the actual instant, not the calendar day.

Expense submit/void: `SubmitEntry`, `GotSubmitTime`, `VoidEntry`,
`GotVoidTime` — same `Time.now` pattern for the void tombstone.

Expense duplicate: `DuplicateEntry`, `GotDuplicateTime` — snapshot the
effective state into a brand-new expense doc in the same trip.

Expense move: `OpenMovePicker`, `CloseMovePicker`, `MoveEntry`,
`GotMoveTime` — snapshot the effective state into a new expense in the
destination trip and void the original. The expense's ID changes.

Ledger row menu: `OpenLedgerMenu`, `CloseLedgerMenu` — toggle the kebab
popover holding secondary row actions (Duplicate, Move to trip…,
Delete).

Guest auth: `EmailInputChanged`, `SubmitEmail`, `CodeInputChanged`,
`SubmitCode`, `RequestCodeResult`, `VerifyCodeResult`,
`ToggleGuestSettings`.

Session: `SignOutClicked`, `ResetSettingsClicked`, `ApiKeyChanged`.

PouchDB / navigation / chrome: `GotPouchMsg`, `LinkClicked`,
`NetworkStatusChanged`, `UrlChanged`, `RefreshClicked`,
`ToggleDayIntensity`, `ToggleLedgerMap`, `ShowToast`, `ToastExpired`,
`DismissError`.

PWA install: `CanInstall` (JS reports the deferred
`beforeinstallprompt` event is/isn't stashed), `TriggerInstallPrompt`
(user tapped the Settings "Install app" button — JS replays the
stashed event).

Stats hover: `HoverDailyBars`, `HoverCumulativePoints` — UI-only,
records the chart datapoint(s) the pointer is currently over so the
Stats page can render a tooltip overlay.

Stats granularity: `SetStatsGranularity` — switches the Daily Spending
chart between `Auto`, `Daily`, `Weekly`, and `Monthly` bins from the
chip selector.

-}
type Msg
    = AddressChanged String
    | AmountChanged String
    | ApiKeyChanged String
    | BackToQueue
    | CanInstall Bool
    | CancelDeleteTrip
    | CategorySelected Category
    | ClearDoneItems
    | CloseSharedTripModal
    | CreateSharedTripNameChanged String
    | CreateSharedTripResult (Result Http.Error Http.SharedTripApi.CreateSharedTripResponse)
    | CloseLedgerMenu
    | CloseMovePicker
    | CloseTripForm
    | CodeInputChanged String
    | ConfirmDeleteTrip Trip
    | DateChanged String
    | DeleteTrip Trip
    | DismissError
    | DismissMapPicker
    | DuplicateEntry Expense
    | EmailInputChanged String
    | ExportCsv Data.TripId.TripId
    | FilesSelected (List File)
    | GeolocationDenied
    | GotDeleteTripTime Trip Time.Posix
    | GotDuplicateTime Expense Time.Posix
    | GotExifCoords String (Maybe Float) (Maybe Float) String
    | GotFileUrl String String
    | GotGeocodeResult String (Result Http.Error Http.GeocodeApi.GeocodeResponse)
    | GotGpsCoords Float Float
    | GotMoveTime Expense TripId Time.Posix
    | GotOcrResult String (Result String String)
    | GotPouchMsg Json.Decode.Value
    | GotSaveTripTime Time.Posix
    | GotSubmitTime ParsedEntry Time.Posix
    | GotSyncTime Time.Posix
    | GotVoidTime Expense Time.Posix
    | HoverCumulativePoints (List (CI.One CumulativePoint CI.Dot))
    | HoverDailyBars (List (CI.One DailyDay CI.Bar))
    | InviteEmailChanged String
    | InviteToSharedTripResult (Result Http.Error ())
    | JoinSharedTripAccepted String
    | JoinSharedTripDeclined
    | JoinSharedTripResult (Result Http.Error Http.SharedTripApi.JoinSharedTripResponse)
    | LeaveSharedTripConfirmed SharedTripId
    | LeaveSharedTripResult (Result Http.Error ())
    | LinkClicked Browser.UrlRequest
    | LongNoteChanged String
    | MapPickerConfirmed Float Float
    | MerchantChanged String
    | MoveEntry Expense TripId
    | NetworkStatusChanged Bool
    | NoteChanged String
    | NotificationStateChanged { permission : String, prefs : Json.Decode.Value, standalone : Bool, subscribed : Bool }
    | OcrImagePrepared { dataUrl : String, error : String, finalBytes : Int, id : String, originalBytes : Int }
    | OpenEditTripForm Trip
    | OpenCreateSharedTripModal
    | OpenInviteModal SharedTripId
    | OpenLeaveConfirmModal SharedTripId
    | OpenLedgerMenu ExpenseId
    | OpenMapPicker
    | OpenMovePicker Expense
    | OpenNewTripForm
    | OpenTransferModal SharedTripId
    | PaymentMethodChanged (Maybe PaymentMethod)
    | PushSubscribeReceived { error : String, ok : Bool }
    | RefreshClicked
    | RequestCodeResult (Result Http.Error ())
    | RequestPushPermission
    | SharedTripActivityNotified
    | ResetSettingsClicked
    | ReviewScanItem String
    | SaveTripForm
    | ScanProxyResult { body : String, itemId : String, ok : Bool, status : Int }
    | ScrolledToTop
    | SetColorScheme ColorScheme
    | SetStatsGranularity Granularity
    | ShowByoKeyInput
    | SignOutClicked
    | SkipLocation
    | SubmitCode
    | SubmitEmail
    | SubmitEntry
    | SubmitCreateSharedTrip
    | SubmitInvite
    | SubmitTransfer
    | TakeOverBilling SharedTripId
    | ToastExpired
    | ToggleDayIntensity
    | ToggleSharedTripMembers SharedTripId
    | ToggleGuestSettings
    | ToggleLedgerMap
    | ToggleLedgerMapExpanded
    | ToggleNotificationPref NotificationToggle
    | TransferTargetChanged String
    | TransferToSharedTripResult (Result Http.Error ())
    | TriggerInstallPrompt
    | TripCreateSharedTripResult (Result Http.Error Http.SharedTripApi.CreateSharedTripResponse)
    | TripFieldChanged TripField String
    | TripGroupNameChanged String
    | TripInviteResult
    | TripInviteeAdded
    | TripInviteeDraftChanged String
    | TripInviteeRemoved Int
    | TripTargetSelected Data.Trip.CreateTarget
    | UrlChanged Url.Url
    | VerifyCodeResult (Result Http.Error Creds)
    | VoidEntry Expense
