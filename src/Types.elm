module Types exposing
    ( AuthMsg_(..)
    , AuthState
    , GuestMsg_(..)
    , GuestScanState(..)
    , GuestState
    , Model(..)
    , Msg(..)
    , ShareMode(..)
    , SharedMsg_(..)
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
import Data.Location exposing (LocationState)
import Data.Me
import Data.Navigation exposing (Route)
import Data.NestPreview exposing (NestPreview)
import Data.Notifications exposing (NotificationPrefs, NotificationToggle, Permission, StandaloneState)
import Data.PaymentMethod exposing (PaymentMethod)
import Data.PendingEntry exposing (ParsedEntry, PendingForm)
import Data.Scan exposing (OcrData, ScanItem)
import Data.ScanItemId exposing (ScanItemId)
import Data.SharedTripId exposing (SharedTripId)
import Data.SharedTripUi exposing (SharedTripUiState)
import Data.SharedTrips
import Data.StatsGranularity exposing (Granularity)
import Data.StatsHover exposing (CumulativePoint, DailyDay, Hover)
import Data.SubscriptionStatus exposing (SubscriptionStatus)
import Data.Sync exposing (NetworkState, SyncState)
import Data.Tier exposing (Tier)
import Data.Trip exposing (Trip, TripField, TripForm)
import Data.TripId exposing (TripId)
import Data.Trips exposing (TripsState)
import Data.UserId
import Data.Void exposing (Void)
import Dict exposing (Dict)
import File exposing (File)
import Http
import Http.Billing
import Http.SharedTripApi
import Json.Decode
import Msg.Scan
import RemoteData exposing (RemoteData)
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
before signing in. `network` mirrors `navigator.onLine` as a tri-state
(`Unknown` until the first `networkStatus` report lands) so the guest UI
can surface a disconnected banner; `Unknown` is treated as offline-safe
(see `Data.Sync.isOffline`).

`nestPreview` holds the `RemoteData` lifecycle for the `/invite/resolve`
response on `RouteNestPreview`. `NotAsked` on every other route; transitions
to `Loading` → `Success NestPreview` or `Failure` as the resolve request
progresses. The `Pages.NestPreview` teaser card reads it in #337.

-}
type alias GuestState =
    { authError : Maybe String
    , basePath : String
    , codeInput : String
    , demoMode : Bool
    , emailInput : String
    , guestScan : GuestScanState
    , key : Nav.Key
    , magicLinkRequest : RemoteData Http.Error ()
    , nestPreview : RemoteData Http.Error NestPreview
    , network : NetworkState
    , pendingJoinToken : Maybe String
    , pendingRef : Maybe String
    , resendStatus : RemoteData Http.Error ()
    , route : Route
    , session : GuestSession
    , showConvert : Bool
    , showSettings : Bool
    , today : DateField
    , version : String
    }


{-| Guest receipt-scan state for the Nest preview (#336).

  - `NoScan` — the guest hasn't tried a scan yet.
  - `Scanning` — the image is being read and the `/scan-guest` request is in
    flight.
  - `Scanned` — the parsed receipt is shown (S3). Under the default
    `view_scan_preview` gate it is discarded on conversion, never saved.

-}
type GuestScanState
    = NoScan
    | Scanned OcrData
    | Scanning


{-| Where a `ShareViaNative` Msg should route on the JS side.

  - `AutoShare` — try `navigator.share` first; fall back to clipboard if
    unavailable or rejected. Used by the primary "Share with a friend"
    CTA.
  - `ForceCopy` — skip the share sheet and write to clipboard directly.
    Used by the explicit "Copy link" button.

-}
type ShareMode
    = AutoShare
    | ForceCopy


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
  - `scanTombstones` — in-memory set of scan-item ids deleted since the
    last `loadScanQueue` (submit-cleared via the `ExpenseChanged` echo,
    multi-receipt split sources, or `ClearDoneItems`). The
    `scanQueueLoaded` merge subtracts these from the hydrated queue so a
    late `getAll` can't resurrect a just-removed item. Never persisted —
    a fresh boot starts with an empty set because the durable store no
    longer holds the deleted docs.
  - `error`, `toast`, `submitting` — banner, transient toast, submit
    spinner.
  - `network` — connectivity as a tri-state (`Unknown` until the first
    `networkStatus` report, then `Online` / `Offline` from
    `navigator.onLine` + `online`/`offline` events). Used to gate the
    layout banner, sync-dot state, and the Scan page's capture routing.
    `Unknown` is treated as offline-safe — see `Data.Sync.isOffline` —
    so the boot window defers OCR rather than firing a doomed call.
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
    , billingCheckout : RemoteData Http.Billing.CheckoutFailure Http.Billing.CheckoutOk
    , billingPortal : RemoteData Http.Error ()
    , colorScheme : ColorScheme
    , config : AppConfig
    , confirmDeleteTrip : Maybe Trip
    , creds : Creds
    , currentUser : Data.UserId.UserId
    , demoMode : Bool
    , duplicateWarning : Maybe Expense
    , error : Maybe String
    , currentLocation : LocationState
    , expenses : Dict String (Dict String Expense)
    , shareModalOpen : Bool
    , sharedTripUi : SharedTripUiState
    , sharedTrips : Data.SharedTrips.SharedTrips
    , form : PendingForm
    , geoBlocked : Bool
    , isIosDevice : Bool
    , joinSharedTripRequest : RemoteData Http.Error Http.SharedTripApi.JoinSharedTripResponse
    , key : Nav.Key
    , lastSyncedAt : Maybe Time.Posix
    , ledgerMapExpanded : Bool
    , loadingExpenses : Set String
    , loadingTrips : Set String
    , movePicker : Maybe Expense
    , network : NetworkState
    , notificationPermission : Permission
    , notificationPrefs : NotificationPrefs
    , ocrInFlight : Set String
    , openLedgerMenu : Maybe ExpenseId
    , postJoinPrompt : Bool
    , pwaInstalled : Bool
    , pushSubscribed : Bool
    , route : Route
    , scanQueue : Dict String ScanItem
    , scanSeq : Int
    , scanTombstones : Set String
    , showByoKeyInput : Bool
    , showDayIntensity : Bool
    , showInstallPrompt : Bool
    , showLedgerMap : Bool
    , showMapPicker : Bool
    , standalone : StandaloneState
    , statsGranularity : Maybe Granularity
    , statsHover : Hover
    , storageAvailable : Bool
    , storagePersisted : Bool
    , submitting : Bool
    , subscriptionStatus : Maybe SubscriptionStatus
    , syncState : SyncState
    , tier : Tier
    , toast : Maybe String
    , today : DateField
    , trailblazerNumber : Maybe Int
    , trailblazerStatus : RemoteData Http.Error Http.Billing.TrailblazerStatus
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

Guest auth: wrapped under `GuestMsg GuestMsg_`. See `GuestMsg_` for
the 7 constructors that fire only in the guest state.

Session: `SignOutClicked`, `ResetSettingsClicked`, `ApiKeyChanged`.

PouchDB / navigation / chrome: `GotPouchMsg`, `LinkClicked`,
`NetworkStatusChanged`, `UrlChanged`, `RefreshClicked`,
`ToggleDayIntensity`, `ToggleLedgerMap`, `ShowToast`, `ToastExpired`,
`DismissError`.

Shared (guest + auth): wrapped under `SharedMsg SharedMsg_`. See
`SharedMsg_` for the 8 constructors that fire in both states.

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
    = AuthMsg AuthMsg_
    | GuestMsg GuestMsg_
    | SharedMsg SharedMsg_


{-| Messages that fire in both guest and authenticated states.

These are bucketed here so the compiler can verify that `updateShared`
handles them without any per-state no-ops leaking into `updateGuest` or
`updateAuth`.

-}
type SharedMsg_
    = ApiKeyChanged String
    | LinkClicked Browser.UrlRequest
    | NetworkStatusChanged Bool
    | ResetSettingsClicked
    | ScrolledToTop
    | SetColorScheme ColorScheme
    | ShowByoKeyInput
    | UrlChanged Url.Url


{-| Messages that fire only in the guest (unauthenticated) state.

These are bucketed here so the compiler can verify that `updateGuest`
handles them without any per-state no-ops leaking into `updateAuth`.

-}
type GuestMsg_
    = CodeInputChanged String
    | ConfirmMagicEmail
    | EmailInputChanged String
    | GuestScanLoaded String
    | GuestScanPick
    | GuestScanResult (Result Http.Error OcrData)
    | GuestScanSelected File
    | MagicLinkRequested
    | MagicLinkResult (Result Http.Error ())
    | MagicVerifyResult (Result Http.Error Creds)
    | NestPreviewResult (Result Http.Error NestPreview)
    | RequestCodeResult (Result Http.Error ())
    | ResendCode
    | ResendCodeResult (Result Http.Error ())
    | StartConversion
    | SubmitCode
    | SubmitEmail
    | ToggleGuestSettings
    | VerifyCodeResult (Result Http.Error Creds)


{-| Messages that fire only in the authenticated state.

These are bucketed here so the compiler can verify that `updateAuth`
handles them without any per-state no-ops leaking into `updateGuest`.

-}
type AuthMsg_
    = AddressChanged String
    | AmountChanged String
    | BillingCheckoutClicked String
    | BillingCheckoutResult (Result Http.Billing.CheckoutFailure Http.Billing.CheckoutOk)
    | BillingPortalClicked
    | BillingPortalResult (Result Http.Error Http.Billing.PortalResponse)
    | CanInstall Bool
    | CancelDeleteTrip
    | CategorySelected Category
    | CloseLedgerMenu
    | CloseMovePicker
    | CloseShareModal
    | CloseSharedTripModal
    | CloseTripForm
    | ConfirmDeleteTrip Trip
    | DateChanged String
    | DeleteTrip Trip
    | DismissError
    | DismissMapPicker
    | DismissPostJoinPrompt
    | DuplicateEntry Expense
    | EnableCrewPush
    | ExportCsv Data.TripId.TripId
    | GeolocationDenied
    | GotDeleteTripTime Trip Time.Posix
    | GotDuplicateTime Expense Time.Posix
    | GotGpsCoords Float Float
    | GotMoveTime Expense TripId Time.Posix
    | GotPouchMsg Json.Decode.Value
    | GotSaveTripTime Time.Posix
    | GotSubmitTime ParsedEntry Time.Posix
    | GotSyncTime Time.Posix
    | GetShareLinkClicked SharedTripId
    | GetShareLinkResult (Result Http.Error Http.SharedTripApi.ShareLinkResponse)
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
    | LongNoteChanged String
    | MapPickerConfirmed Float Float
    | MeFetched (Result Http.Error Data.Me.MeResponse)
    | MerchantChanged String
    | MoveEntry Expense TripId
    | NoteChanged String
    | NotificationStateChanged { permission : String, prefs : Json.Decode.Value, standalone : Bool, subscribed : Bool }
    | OpenEditTripForm Trip
    | OpenInviteCrewModal SharedTripId
    | OpenInviteModal SharedTripId
    | OpenLeaveConfirmModal SharedTripId
    | OpenLedgerMenu ExpenseId
    | OpenMapPicker
    | OpenMovePicker Expense
    | OpenNewTripForm
    | OpenShareModal
    | OpenShareTripModal Trip
    | OpenTransferModal SharedTripId
    | PaymentMethodChanged (Maybe PaymentMethod)
    | PushSubscribeReceived { error : String, ok : Bool }
    | RefreshClicked
    | RequestPushPermission
    | ResetLinksClicked SharedTripId
    | ResetLinksConfirmed SharedTripId
    | ResetLinksResult (Result Http.Error ())
    | SaveTripForm
    | ScanItemSaved { error : String, id : String, ok : Bool }
    | ScanMsg Msg.Scan.Msg
    | ScanQueueLoaded Json.Decode.Value
    | SetStatsGranularity Granularity
    | ShareResultReceived { ok : Bool, reason : String }
    | ShareTripAdoptResult (Result Http.Error ())
    | ShareTripCreatedResult (Result Http.Error Http.SharedTripApi.CreateSharedTripResponse)
    | ShareTripGroupNameChanged String
    | ShareTripInviteeAdded
    | ShareTripInviteeDraftChanged String
    | ShareTripInviteeRemoved Int
    | ShareViaNative ShareMode
    | SharedTripActivityNotified
    | SignOutClicked
    | SkipLocation
    | StorageStatusReceived { available : Bool, installed : Bool, isIos : Bool, persisted : Bool }
    | SubmitEntry
    | SubmitInvite
    | SubmitShareTrip
    | SubmitTransfer
    | TakeOverBilling SharedTripId
    | ToastExpired
    | ToggleDayIntensity
    | ToggleLedgerMap
    | ToggleLedgerMapExpanded
    | ToggleNotificationPref NotificationToggle
    | ToggleSharedTripMembers SharedTripId
    | TrailblazerStatusFetched (Result Http.Error Http.Billing.TrailblazerStatus)
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
    | VoidEntry Expense
