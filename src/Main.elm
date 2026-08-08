module Main exposing (main)

{-| Application entry point and the single source of truth for state.


# Big picture

The model is a sum type:

    type Model
        = AuthModel AuthState
        | GuestModel GuestState

The compiler enforces that auth-only pages (Add, Ledger, Scan, Stats, Trips)
cannot be reached while signed out. Any 401 from an HTTP call or the
CouchDB sync transitions the app to `GuestModel SessionExpired` —
there's no silent re-auth because tokens expire aggressively.


# Data shape

`AuthState` caches everything fetched from PouchDB:

    expenses : Dict String (Dict String Expense)

    -- outer key = TripId.toString, inner key = ExpenseId.toString
    amendments : Dict String Amendment

    -- keyed by amendment ID
    voids : Dict String Void

    -- keyed by void ID
    trips : TripsState

Single-trip lookup is a `Dict.get` on the outer expenses dict.
`Data.Entry.resolve` folds amendments and applies voids to produce the
user-facing `EffectiveEntry` list.


# Flow

1.  `init` reads cached creds from JS flags and either constructs a
    `GuestModel` or jumps straight to `AuthModel` and starts CouchDB sync.
2.  The first time sync settles (`SyncStateMsg Synced`), we send
    `GetAllTrips`. We do **not** fetch on login — that would race with
    the initial sync pull.
3.  Each route transition runs `fetchesForRoute`, which fires only the
    PouchDB queries needed for that route (idempotent — guarded by
    `tripLoaded` / `loadingExpenses`).
4.  PouchDB's live-changes feed pushes every local or synced write
    through `Ports.pouchIn`, where `handleDbChange` merges it into the right
    `Dict`.


# Ports

  - `Ports.pouchOut` / `Ports.pouchIn` — all PouchDB traffic (tagged JSON, see
    `src/pouch.js`).
  - `Ports.startSync` / `Ports.stopSync` — manage the live CouchDB sync handle.
  - `Ports.saveStorage` / `Ports.clearStorage` / `Ports.clearAllStorage` — IndexedDB-backed
    auth creds and API key.
  - `Ports.requestGeolocation` / `Ports.gotGpsCoords` — browser geolocation API.
  - `Ports.extractExifGps` / `Ports.gotExifResult` — EXIF GPS extraction from receipt
    photos.

For the full narrative and document ID conventions, see `docs/architecture.md`.

-}

import Analytics
import Browser
import Browser.Dom
import Browser.Events
import Browser.Navigation as Nav
import Codec
import Data.Amendment as Amendment
import Data.AmendmentId as AmendmentId
import Data.AnthropicKey as AnthropicKey
import Data.Auth exposing (AppConfig, Creds)
import Data.ColorScheme as ColorScheme
import Data.CsvExport as CsvExport
import Data.Currency as Currency
import Data.DateField as DateField
import Data.Entry as Entry
import Data.ExchangeRate as ExchangeRate
import Data.Expense as Expense exposing (Expense)
import Data.ExpenseId as ExpenseId
import Data.FuelGrade as FuelGrade
import Data.Gallons as Gallons
import Data.GeoPoint as GeoPoint
import Data.Guest exposing (GuestReason(..), GuestSession)
import Data.Iso8601 as Iso8601
import Data.Liters as Liters
import Data.Location exposing (LocationSource(..), LocationState(..))
import Data.Milepost as Milepost
import Data.MilepostProgress as MilepostProgress exposing (MilepostProgress)
import Data.Money as Money
import Data.Navigation exposing (Route(..), Tab(..))
import Data.Notifications as Notifications
import Data.PendingEntry as PendingEntry exposing (PendingEntry, PendingForm(..))
import Data.Pouch exposing (DocChange(..), ExpenseBundle, PouchInbound(..), PouchOutbound(..), TripBundle)
import Data.PricePerGallon as PricePerGallon
import Data.PricePerLiter as PricePerLiter
import Data.Scan exposing (ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Data.SharedTrip as SharedTrip
import Data.SharedTripId
import Data.SharedTripUi as SharedTripUi
import Data.SharedTrips as SharedTrips
import Data.StatsHover as StatsHover
import Data.Sync exposing (NetworkState(..), SyncState(..))
import Data.Tier as Tier exposing (Tier)
import Data.Trip as Trip exposing (Trip, TripField(..))
import Data.TripId as TripId
import Data.Trips as Trips exposing (TripsState(..))
import Data.UserId as UserId
import Data.UserSettings as UserSettings
import Data.Void as Void
import Dict
import Effect
import File
import File.Select
import Helpers
import Html exposing (Html)
import Html.Attributes
import Html.Extra
import Http
import Http.Billing
import Http.Me
import Http.NestPreviewApi
import Http.RatesApi
import Http.SharedTripApi
import Json.Decode as D
import Json.Encode as E
import Maybe.Extra
import Msg.Scan
import Page.Scan
import Pages.Add
import Pages.Guest exposing (viewGuest)
import Pages.JoinSharedTrip
import Pages.Ledger
import Pages.Milepost
import Pages.Scan
import Pages.Settings
import Pages.Settings.SharedTrips
import Pages.Stats
import Pages.Trips
import Ports
import Process
import RemoteData
import Routing
import Set
import Task
import Time
import Types exposing (AuthMsg_(..), AuthState, GuestMsg_(..), GuestScanState(..), GuestState, MilepostState(..), Model(..), Msg(..), ShareMode(..), SharedMsg_(..), UserSettingsState(..))
import UI.BillingBanner
import UI.Layout
import UI.MilepostToast
import UI.ShareModal
import UI.TripFormModal
import UI.TripPicker
import Url
import Validate
import Verify.Core
import Verify.Registry
import Verify.Specs.JoinSharedTrip
import Verify.Specs.MilepostScreen
import Verify.Specs.NotificationsPaywall
import Verify.Specs.ScanQueueCard
import Verify.Specs.SharedTripCard



-- ROUTING
-- See src/Routing.elm
-- SESSION HELPERS


mapGuestConfig : (AppConfig -> AppConfig) -> GuestSession -> GuestSession
mapGuestConfig f gs =
    { gs | config = f gs.config }


{-| Transition from `GuestState` to `AuthState` after successful auth.

Everything starts empty — no expenses, no trips, no scan queue. The
caller is responsible for kicking off `Ports.startSync`; the trips list will
populate via `GetAllTrips` once the first sync settles.

`trips = TripsLoading ... initialRouteTripId` carries the pending
selection from the URL so that when trips arrive we can pick the right
one without a second navigation.

-}
toAuthState : Creds -> Route -> GuestState -> AuthState
toAuthState creds initialRoute gs =
    { activeScanItemId = Nothing
    , amendments = Dict.empty
    , basePath = gs.basePath
    , billingCheckout = RemoteData.NotAsked
    , billingPortal = RemoteData.NotAsked
    , colorScheme = ColorScheme.Auto
    , config = gs.session.config
    , confirmDeleteTrip = Nothing
    , confirmRemoveScan = Nothing
    , creds = creds
    , currentLocation = LocationIdle
    , currentUser = UserId.fromString creds.email
    , demoMode = gs.demoMode
    , duplicateWarning = Nothing
    , error = Nothing
    , expenses = Dict.empty
    , shareModalOpen = False
    , sharedTripUi = SharedTripUi.empty
    , sharedTrips = SharedTrips.empty
    , form = FreshForm (PendingEntry.defaultPendingEntry gs.today)
    , geoBlocked = False
    , isIosDevice = False
    , joinSharedTripRequest = RemoteData.NotAsked
    , key = gs.key
    , lastSyncedAt = Nothing
    , ledgerMapExpanded = False
    , loadingExpenses = Set.empty
    , loadingTrips = Set.empty
    , movePicker = Nothing
    , network = gs.network
    , notificationPermission = Notifications.Default
    , notificationPrefs = Notifications.defaultPrefs
    , ocrInFlight = Set.empty
    , openLedgerMenu = Nothing
    , postJoinPrompt = False
    , pwaInstalled = False
    , pushSubscribed = False
    , route = initialRoute
    , scanQueue = Dict.empty
    , scanSeq = 0
    , scanTombstones = Set.empty
    , showByoKeyInput = gs.session.config.anthropicKey /= Nothing
    , showDayIntensity = True
    , showInstallPrompt = False
    , showLedgerMap = False
    , showMapPicker = False
    , standalone = Notifications.InBrowser
    , statsGranularity = Nothing
    , statsHover = StatsHover.empty
    , storageAvailable = True
    , storagePersisted = False
    , submitting = False
    , subscriptionStatus = creds.subscriptionStatus
    , syncState = NotEnabled
    , tier = creds.tier
    , toast = Nothing
    , today = gs.today
    , trailblazerNumber = creds.trailblazerNumber
    , trailblazerStatus = RemoteData.NotAsked
    , milepost = NotLoaded
    , milepostStates = []
    , milepostToasts = []
    , tripForm = Nothing
    , tripLoaded = Set.empty
    , trips = TripsLoading Dict.empty (Routing.routeTripId initialRoute)
    , tripsHydrated = False
    , userSettings = SettingsNotLoaded
    , version = gs.version
    , voids = Dict.empty
    , zone = gs.zone
    }


toGuestState : GuestReason -> AuthState -> GuestState
toGuestState reason as_ =
    { authError = Nothing
    , basePath = as_.basePath
    , codeInput = ""
    , demoMode = as_.demoMode
    , emailInput = ""
    , key = as_.key
    , guestScan = NoScan
    , magicLinkRequest = RemoteData.NotAsked
    , showConvert = False
    , nestPreview = RemoteData.NotAsked
    , network = as_.network
    , pendingJoinToken = joinTokenFromRoute as_.route
    , pendingRef = Nothing
    , resendStatus = RemoteData.NotAsked
    , route = as_.route
    , session = { config = as_.config, reason = reason }
    , showSettings = reason == SessionExpired
    , today = as_.today
    , version = as_.version
    , zone = as_.zone
    }


{-| Extract the join JWT from a route so the sign-in flow can carry it
across re-auth. Returns `Just token` only for `RouteJoinSharedTrip`;
every other route resets to `Nothing` so a stale token from a prior
session doesn't trigger an unintended redirect after the user signs in
on an unrelated screen.

    joinTokenFromRoute (RouteJoinSharedTrip "abc")
    --> Just "abc"

    joinTokenFromRoute RouteTrips
    --> Nothing

-}
joinTokenFromRoute : Route -> Maybe String
joinTokenFromRoute route =
    case route of
        RouteJoinSharedTrip token ->
            Just token

        _ ->
            Nothing


{-| Outcome of parsing the URL's query string for the Stripe Checkout
return signals.

  - `CheckoutReturnSuccess` — `?checkout=success`; user just paid and
    is back on `/settings`. Fire `/me` to absorb the tier change and
    show a toast.
  - `CheckoutReturnCanceled` — `?checkout=canceled`; user clicked back
    on the Stripe page. No toast (the user deliberately cancelled), but
    strip the query so a refresh doesn't preserve it.
  - `CheckoutReturnNone` — neither marker present; ordinary navigation.

-}
type CheckoutReturn
    = CheckoutReturnCanceled
    | CheckoutReturnNone
    | CheckoutReturnSuccess


{-| Cheap substring scan for `checkout=success` / `checkout=canceled`
in the URL's query string. Bypasses the full `Url.Parser.Query` setup
because the rest of the routing layer already chose its `Route` from
the path + tripId/expenseId query params — this is purely the "did we
just come back from Stripe" sentinel.
-}
checkoutReturnFromUrl : Url.Url -> CheckoutReturn
checkoutReturnFromUrl url =
    case url.query of
        Just q ->
            if String.contains "checkout=success" q then
                CheckoutReturnSuccess

            else if String.contains "checkout=canceled" q then
                CheckoutReturnCanceled

            else
                CheckoutReturnNone

        Nothing ->
            CheckoutReturnNone


{-| `GET /me` refresh. Fired once per session immediately after the
auth model is constructed (whether from cached `auth_creds` on cold
boot or from a fresh `/auth/verify-code` response) so any tier change
the Stripe webhook applied between sessions is picked up. The Settings
billing UI (#21) will reuse this on `?checkout=success` return.

Errors are intentionally swallowed at the handler — `/me` is a
refresh path, not a hard requirement; the cached `Creds` tier is
already good enough to render until the next call retries.

-}
fetchMe : AuthState -> Cmd Msg
fetchMe as_ =
    Http.Me.fetch as_.config as_.creds (AuthMsg << MeFetched)


{-| `GET /rates` refresh for the spend estimate (#448). Fired on boot
alongside `fetchMe`; the fetched table is cached into the synced
`Data.UserSettings` doc. Errors are swallowed at the handler — the estimate
is a convenience and falls back to whatever rates are already cached
(possibly from another device, or a prior online session).
-}
fetchRates : AuthState -> Cmd Msg
fetchRates as_ =
    Http.RatesApi.fetch as_.config as_.creds (AuthMsg << RatesFetched)


{-| Persist a freshly-fetched rate table into the synced settings singleton,
threading the current `_rev` (milepost pattern) so the in-place update
doesn't 409, and optimistically updating the in-memory copy so the estimate
renders immediately rather than waiting for the change-feed echo.
-}
persistRates : ExchangeRate.RateTable -> AuthState -> ( AuthState, Cmd Msg )
persistRates table as_ =
    let
        currentRev : Maybe String
        currentRev =
            case as_.userSettings of
                SettingsLoaded loaded ->
                    loaded.rev

                SettingsNotLoaded ->
                    Nothing

        unchanged : Bool
        unchanged =
            case as_.userSettings of
                SettingsLoaded loaded ->
                    loaded.settings.exchangeRates == table

                SettingsNotLoaded ->
                    False

        settings : UserSettings.UserSettings
        settings =
            { exchangeRates = table }
    in
    if unchanged then
        -- Same rates already cached (the server day-caches, so a daily boot
        -- re-fetches an identical table). Skip the write to avoid a redundant
        -- synced rev on every device every boot — and to shrink the
        -- cross-device write-conflict window.
        ( as_, Cmd.none )

    else
        ( { as_ | userSettings = SettingsLoaded { rev = currentRev, settings = settings } }
        , sendPouch (SaveUserSettings (UserSettings.encoder currentRev settings))
        )



-- POUCHDB PROTOCOL


encodePouchOut : PouchOutbound -> D.Value
encodePouchOut msg =
    case msg of
        GetAllTripExpenses requests ->
            E.object
                [ ( "tag", E.string "GetAllTripExpenses" )
                , ( "requests"
                  , E.list
                        (\( target, tid ) ->
                            E.object
                                [ ( "target", Trip.encodeTarget target )
                                , ( "tripId", E.string (TripId.toString tid) )
                                ]
                        )
                        requests
                  )
                ]

        GetAllTrips ->
            E.object [ ( "tag", E.string "GetAllTrips" ) ]

        GetExpense target id ->
            E.object
                [ ( "tag", E.string "GetExpense" )
                , ( "target", Trip.encodeTarget target )
                , ( "expenseId", E.string (ExpenseId.toString id) )
                ]

        GetTripExpenses target id ->
            E.object
                [ ( "tag", E.string "GetTripExpenses" )
                , ( "target", Trip.encodeTarget target )
                , ( "tripId", E.string (TripId.toString id) )
                ]

        OpenSharedTrip { dbName, flockId } ->
            E.object
                [ ( "tag", E.string "OpenSharedTrip" )
                , ( "flockId", Data.SharedTripId.encode flockId )
                , ( "dbName", E.string dbName )
                ]

        SaveAmend target doc ->
            E.object
                [ ( "tag", E.string "SaveAmend" )
                , ( "target", Trip.encodeTarget target )
                , ( "doc", doc )
                ]

        SaveMilepostProgress doc ->
            -- Singleton in the personal DB; no TripTarget.
            E.object
                [ ( "tag", E.string "SaveMilepostProgress" )
                , ( "doc", doc )
                ]

        SaveUserSettings doc ->
            -- Singleton settings doc in the personal DB; no TripTarget.
            E.object
                [ ( "tag", E.string "SaveUserSettings" )
                , ( "doc", doc )
                ]

        SaveExpense target doc ->
            E.object
                [ ( "tag", E.string "SaveExpense" )
                , ( "target", Trip.encodeTarget target )
                , ( "doc", doc )
                ]

        SaveTrip target doc ->
            E.object
                [ ( "tag", E.string "SaveTrip" )
                , ( "target", Trip.encodeTarget target )
                , ( "doc", doc )
                ]

        SaveVoid target doc ->
            E.object
                [ ( "tag", E.string "SaveVoid" )
                , ( "target", Trip.encodeTarget target )
                , ( "doc", doc )
                ]


sendPouch : PouchOutbound -> Cmd Msg
sendPouch =
    Ports.pouchOut << encodePouchOut


{-| Fire-and-forget push notification to co-travelers on a shared trip.

Calls `Http.SharedTripApi.notifyActivity` after PouchDB already accepted
the write — the HTTP response is handled by `SharedTripActivityNotified`
which is a no-op; any delivery failure is logged server-side and does
not affect UI state.

Returns `Cmd.none` for personal trips (no co-travelers to notify).

-}
notifySharedTripActivity :
    AppConfig
    -> Creds
    -> Trip.TripTarget
    -> { action : String, amount : Float, note : Maybe String }
    -> Cmd Msg
notifySharedTripActivity config creds target opts =
    case target of
        Trip.Personal ->
            Cmd.none

        Trip.InFlock sharedTripId ->
            Http.SharedTripApi.notifyActivity
                config
                creds
                sharedTripId
                opts
                (\_ -> AuthMsg SharedTripActivityNotified)


{-| Resolve the `TripTarget` to use for an outbound `Save*` / `Get*`
command from a trip id. Looks up the trip in the loaded zipper and
asks `Trip.targetForTrip` to map it; falls back to `Personal` if the
trip isn't loaded (legacy / pre-flock callers).
-}
targetForTripId : TripId.TripId -> AuthState -> Trip.TripTarget
targetForTripId tripId as_ =
    case as_.trips of
        TripsLoaded loadedTrips ->
            case Trips.findTrip tripId loadedTrips of
                Just trip ->
                    Trip.targetForTrip trip

                Nothing ->
                    Trip.Personal

        _ ->
            Trip.Personal


{-| Project the live `AuthState` into the pure `Data.Milepost.Inputs` snapshot
that `Data.Milepost.evaluate` consumes.

Walks every loaded trip (`Trips.allTrips`); for each, resolves that trip's
cached expenses through `Data.Entry.resolve` (folding in amendments and
removing voids) so the facts handed to `evaluate` already reflect
post-amendment amounts/categories with voided expenses dropped. Flattens the
resulting `EffectiveEntry` values to `Data.Milepost.ExpenseFacts` and builds
`Data.Milepost.TripFacts` from `Trip.budget` / `Trip.id`.

`zone` is the device's current local zone (`as_.zone`), captured via
`Time.here` on boot and refreshed on every visibility change, so streak
day-bucketing happens on the user's _local_ midnights — correct for a
traveller crossing time zones. `now` is the caller-supplied time.

-}
milepostInputs : AuthState -> Time.Posix -> Milepost.Inputs
milepostInputs as_ now =
    let
        allTrips : List Trip
        allTrips =
            case as_.trips of
                TripsLoaded loadedTrips ->
                    Trips.allTrips loadedTrips

                _ ->
                    []

        allAmendments : List Amendment.Amendment
        allAmendments =
            Dict.values as_.amendments

        allVoids : List Void.Void
        allVoids =
            Dict.values as_.voids

        factsForTrip : Trip -> List Milepost.ExpenseFacts
        factsForTrip trip =
            let
                tripExpenses : List Expense
                tripExpenses =
                    Dict.get (TripId.toString trip.id) as_.expenses
                        |> Maybe.withDefault Dict.empty
                        |> Dict.values
            in
            Entry.resolve tripExpenses allAmendments allVoids trip.id
                |> List.map
                    (\entry ->
                        { amount = entry.amount
                        , category = entry.category
                        , createdAt = entry.createdAt
                        , fuelDetail = entry.fuelDetail
                        , isAmended = entry.isAmended
                        , tripId = TripId.toString entry.tripId
                        }
                    )
    in
    { expenses = List.concatMap factsForTrip allTrips
    , now = now
    , trips =
        List.map
            (\trip ->
                { budget = trip.budget
                , durationDays = tripDurationDays trip
                , id = TripId.toString trip.id
                }
            )
            allTrips
    , zone = as_.zone
    }


{-| Whole-day span of a trip's start→end dates for Milepost evaluation.

Guards the "unset" sentinel: `Trip.startDate`/`endDate` decode an empty legacy
value to the 1970-01-01 epoch (see `Data.Trip`), and `DateField.diffDays`
between two epochs (or an epoch and a real date) is meaningless — it would yield
a garbage multi-decade span. When either date is the epoch sentinel we report
`0` instead, so a trip with no dates set never spuriously earns a duration
marker.

-}
tripDurationDays : Trip -> Int
tripDurationDays trip =
    let
        epochSentinel : String
        epochSentinel =
            "1970-01-01"
    in
    if
        DateField.toIso trip.startDate
            == epochSentinel
            || DateField.toIso trip.endDate
            == epochSentinel
    then
        0

    else
        DateField.diffDays trip.startDate trip.endDate


{-| Like `milepostInputs` but scoped to a single trip.

Produces an `Inputs` snapshot that contains only the expenses and trip record
for `tripId`. Account-wide markers (Mile Marker 100, Seasoned Traveler) will
never earn from this projection — correct; they are not trip achievements.
Trip-scoped markers (Big Rig, Premium Unleaded, Cairn Builder, dollar
thresholds, etc.) will reflect this trip's reality.

`now` is passed as `Time.millisToPosix 0` by the Ledger call site; no current
marker uses `now` for per-trip evaluation, and the real `now` is not available
at view time (see `reconcileMileposts` for the write path that does have it).

-}
milepostInputsForTrip : TripId.TripId -> AuthState -> Milepost.Inputs
milepostInputsForTrip tripId as_ =
    let
        maybeTrip : Maybe Trip
        maybeTrip =
            case as_.trips of
                TripsLoaded loadedTrips ->
                    Trips.findTrip tripId loadedTrips

                _ ->
                    Nothing

        allAmendments : List Amendment.Amendment
        allAmendments =
            Dict.values as_.amendments

        allVoids : List Void.Void
        allVoids =
            Dict.values as_.voids
    in
    case maybeTrip of
        Nothing ->
            { expenses = []
            , now = Time.millisToPosix 0
            , trips = []
            , zone = as_.zone
            }

        Just trip ->
            let
                tripExpenses : List Expense
                tripExpenses =
                    Dict.get (TripId.toString trip.id) as_.expenses
                        |> Maybe.withDefault Dict.empty
                        |> Dict.values

                facts : List Milepost.ExpenseFacts
                facts =
                    Entry.resolve tripExpenses allAmendments allVoids trip.id
                        |> List.map
                            (\entry ->
                                { amount = entry.amount
                                , category = entry.category
                                , createdAt = entry.createdAt
                                , fuelDetail = entry.fuelDetail
                                , isAmended = entry.isAmended
                                , tripId = TripId.toString entry.tripId
                                }
                            )
            in
            { expenses = facts
            , now = Time.millisToPosix 0
            , trips =
                [ { budget = trip.budget
                  , durationDays = tripDurationDays trip
                  , id = TripId.toString trip.id
                  }
                ]
            , zone = as_.zone
            }


pouchInDecoder : D.Decoder PouchInbound
pouchInDecoder =
    D.field "tag" D.string
        |> D.andThen
            (\tag ->
                case tag of
                    "AuthExpired" ->
                        D.succeed AuthExpiredMsg

                    "DbChange" ->
                        D.map DbChange (D.field "doc" docChangeDecoder)

                    "DbDeleted" ->
                        D.map DbDeleted (D.field "id" D.string)

                    "DbError" ->
                        D.map DbError (D.field "message" D.string)

                    "ExpenseFetched" ->
                        D.map2 ExpenseFetched
                            (D.field "expenseId" ExpenseId.decode)
                            expenseBundleDecoder

                    "SharedTripMeta" ->
                        D.map SharedTripMetaChanged (D.field "doc" SharedTrip.decoder)

                    "SharedTripsReconciled" ->
                        D.map SharedTripsReconciled (D.field "flockIds" (D.list Data.SharedTripId.decoder))

                    "SyncState" ->
                        D.map SyncStateMsg (D.field "state" syncStateDecoder)

                    "TripExpensesFetched" ->
                        D.map2 TripExpensesFetched
                            (D.field "tripId" TripId.decode)
                            tripBundleDecoder

                    "TripsLoaded" ->
                        D.map TripsFetched (D.field "trips" (D.dict Trip.decoder))

                    "TripsPrefetched" ->
                        D.map TripsPrefetched (D.field "trips" (D.dict Trip.decoder))

                    _ ->
                        D.fail ("Unknown pouchIn tag: " ++ tag)
            )


docChangeDecoder : D.Decoder DocChange
docChangeDecoder =
    D.field "type" D.string
        |> D.andThen
            (\t ->
                case t of
                    "amend" ->
                        D.map AmendChanged Amendment.decoder

                    "expense" ->
                        D.map ExpenseChanged Expense.decoder

                    "milepostProgress" ->
                        D.map2 (\progress rev -> MilepostProgressChanged { progress = progress, rev = rev })
                            MilepostProgress.decoder
                            (D.maybe (D.field "_rev" D.string))

                    "sharedtrip:meta" ->
                        -- Routed up as a top-level SharedTripMeta event by
                        -- pouch.js; ignored here.
                        D.fail "sharedtrip:meta routed as SharedTripMeta event"

                    "trip" ->
                        D.map TripChanged Trip.decoder

                    "userSettings" ->
                        D.map2 (\settings rev -> UserSettingsChanged { rev = rev, settings = settings })
                            UserSettings.decoder
                            (D.maybe (D.field "_rev" D.string))

                    "void" ->
                        D.map VoidChanged Void.decoder

                    _ ->
                        D.fail ("Unknown doc type: " ++ t)
            )


tripBundleDecoder : D.Decoder TripBundle
tripBundleDecoder =
    D.map3 TripBundle
        (D.field "amendments" (D.dict Amendment.decoder))
        (D.field "expenses" (D.dict Expense.decoder))
        (D.field "voids" (D.dict Void.decoder))


expenseBundleDecoder : D.Decoder ExpenseBundle
expenseBundleDecoder =
    D.map3 ExpenseBundle
        (D.field "amendments" (D.dict Amendment.decoder))
        (D.field "expense" (D.nullable Expense.decoder))
        (D.field "void" (D.nullable Void.decoder))


syncStateDecoder : D.Decoder SyncState
syncStateDecoder =
    D.string
        |> D.map
            (\s ->
                case s of
                    "auth_error" ->
                        AuthExpired

                    "error" ->
                        SyncError

                    "synced" ->
                        Synced

                    "syncing" ->
                        Syncing

                    _ ->
                        NotEnabled
            )



-- CACHE LOOKUPS
--
-- "Effective" means post-amendment, non-voided. See Data.Entry for the
-- definition. These two helpers are the only places in the app that go
-- from cached PouchDB documents → user-facing data.


{-| Find one expense by ID, with its amendments folded in.

We don't know which trip the expense belongs to up front, so we scan
`Dict.values as_.expenses` — that's one `Dict.get` per loaded trip
(typically 1–3). Once we find the raw expense, we run a one-element
`Entry.resolve` to apply any amendments and detect voids.

Returns `Nothing` if the expense is unknown or has been voided. Used by
the edit page to hydrate the form.

-}
findEffective : ExpenseId.ExpenseId -> AuthState -> Maybe Expense.Expense
findEffective id as_ =
    as_.expenses
        |> Dict.values
        |> List.filterMap (Dict.get (ExpenseId.toString id))
        |> List.head
        |> Maybe.andThen
            (\raw ->
                Entry.resolve
                    [ raw ]
                    (Dict.values as_.amendments)
                    (Dict.values as_.voids)
                    raw.tripId
                    |> List.head
                    |> Maybe.map Helpers.effectiveEntryToExpense
            )


{-| Build a `Route` from a `Tab` plus a tripId. Used for navigations
where the destination tab is known but the route needs the active
trip stitched in (post-submit redirect, scan-to-add handoff, etc.).
Tabs that aren't trip-scoped (Settings, Trips) ignore the tripId.
-}
routeForTab : Tab -> TripId.TripId -> Route
routeForTab tab tripId =
    case tab of
        AddTab ->
            RouteAdd tripId

        LedgerTab ->
            RouteLedger tripId

        ScanTab ->
            RouteScan tripId

        SettingsTab ->
            RouteSettings

        StatsTab ->
            RouteStats tripId

        TripsTab ->
            RouteTrips



-- ROUTE-DRIVEN STATE TRANSITIONS
--
-- These two functions are what makes the URL the source of truth.
-- `fetchesForRoute` runs after every navigation and fires only the
-- PouchDB queries we don't already have an answer for. `hydrateFormForRoute`
-- keeps the edit form in lockstep with the route — entering an edit
-- route pulls the effective expense into the form; leaving it resets
-- the form.


{-| Sync the edit form to the current route.

On entering `RouteEditEntry`, hydrate the form from the cached effective
expense. If the expense isn't cached yet, leave the form alone and wait
— the data will arrive via PouchDB and `hydrateFormForRoute` will be
called again from the inbound-data handlers.

On leaving an edit route, reset to a fresh `defaultPendingEntry`.

Idempotent: if the form is already an `EditForm` for this expense, do
nothing — re-running this function on every state change is safe.

-}
hydrateFormForRoute : AuthState -> AuthState
hydrateFormForRoute as_ =
    case as_.route of
        RouteEditEntry _ id ->
            let
                alreadyHydrated =
                    case as_.form of
                        EditForm formId _ ->
                            formId == id

                        FreshForm _ ->
                            False
            in
            if alreadyHydrated then
                as_

            else
                case findEffective id as_ of
                    Just expense ->
                        { as_ | form = EditForm id (expenseToPending expense) }

                    Nothing ->
                        as_

        _ ->
            case as_.form of
                EditForm _ _ ->
                    { as_ | form = FreshForm (PendingEntry.defaultPendingEntry as_.today) }

                FreshForm _ ->
                    as_


{-| Fire the PouchDB queries needed to satisfy the current route.

Idempotent — every check guards against a duplicate fetch:

  - Trip-scoped routes (Ledger, Stats, Add, Scan, EditEntry): if the
    trip's expenses aren't yet in `tripLoaded` or `loadingTrips`,
    fire `GetTripExpenses` and mark the trip as loading.
  - `RouteEditEntry`: also fire `GetExpense` if the specific expense
    isn't already in any inner expenses dict or in `loadingExpenses`.

Side effects beyond fetching:

  - Selects the route's trip in the `Trips` zipper so pages can render
    the active trip without re-parsing the URL.
  - Requests browser geolocation when the route is the Add tab (so the
    new-expense form can stamp lat/lon).
  - Runs `hydrateFormForRoute` on the way out so the form is in sync
    whether the data was already cached or not.

-}
fetchesForRoute : AuthState -> ( AuthState, Cmd Msg )
fetchesForRoute as_ =
    let
        ( as1, tripCmd ) =
            case Routing.routeTripId as_.route of
                Just tid ->
                    let
                        key =
                            TripId.toString tid

                        withSelected =
                            case as_.trips of
                                TripsLoaded trips ->
                                    { as_ | trips = TripsLoaded (Trips.selectTrip tid trips) }

                                _ ->
                                    as_

                        alreadyHave =
                            Set.member key as_.tripLoaded
                                || Set.member key as_.loadingTrips
                    in
                    if alreadyHave then
                        ( withSelected, Cmd.none )

                    else
                        ( { withSelected | loadingTrips = Set.insert key as_.loadingTrips }
                        , sendPouch (GetTripExpenses (targetForTripId tid as_) tid)
                        )

                Nothing ->
                    ( as_, Cmd.none )

        ( as2, expenseCmd ) =
            case as1.route of
                RouteEditEntry tid eid ->
                    let
                        key =
                            ExpenseId.toString eid

                        alreadyHave =
                            (as1.expenses |> Dict.values |> List.any (Dict.member key))
                                || Set.member key as1.loadingExpenses
                    in
                    if alreadyHave then
                        ( as1, Cmd.none )

                    else
                        ( { as1 | loadingExpenses = Set.insert key as1.loadingExpenses }
                        , sendPouch (GetExpense (targetForTripId tid as1) eid)
                        )

                _ ->
                    ( as1, Cmd.none )

        geoCmd =
            if Routing.routeToTab as2.route == AddTab && not as2.geoBlocked then
                Ports.requestGeolocation ()

            else
                Cmd.none

        billingCmd =
            -- On Tern, the Plan section renders a Trailblazer button
            -- whose label needs the live "N of 500 left" countdown.
            -- Fetched lazily on navigation to Settings; cached on
            -- `as_.trailblazerStatus` so a tab-flick doesn't re-fetch.
            -- Paid users don't see the Trailblazer CTA at all so we skip
            -- the call for them.
            case ( as2.route, as2.tier, as2.trailblazerStatus ) of
                ( RouteSettings, Tier.Tern, RemoteData.NotAsked ) ->
                    Http.Billing.trailblazerStatus as2.config (AuthMsg << TrailblazerStatusFetched)

                _ ->
                    Cmd.none

        as3 =
            -- Reset the join-request RemoteData so the Accept button
            -- starts idle every time the user navigates to this page,
            -- whether arriving fresh or returning after a Decline.
            case as2.route of
                RouteJoinSharedTrip _ ->
                    { as2 | joinSharedTripRequest = RemoteData.NotAsked }

                _ ->
                    as2
    in
    ( hydrateFormForRoute as3, Cmd.batch [ tripCmd, expenseCmd, geoCmd, billingCmd ] )


{-| Insert a single document from PouchDB's live-changes feed into the
right cache.

Fires for every local write, every sync pull from CouchDB, and every
result of a `Save*` command — we don't need separate "save succeeded"
plumbing because the live feed is the confirmation. Always re-runs
`hydrateFormForRoute` afterwards so an in-flight edit picks up freshly
arrived data without a second navigation.

Expenses are routed into the right inner `Dict` by `expense.tripId`.

-}
handleDbChange : DocChange -> AuthState -> ( Model, Cmd Msg )
handleDbChange change as_ =
    let
        ( as1, dbCmd ) =
            case change of
                AmendChanged a ->
                    ( { as_ | amendments = Dict.insert (AmendmentId.toString a.id) a as_.amendments }
                    , Cmd.none
                    )

                ExpenseChanged e ->
                    let
                        withExpense =
                            { as_
                                | expenses =
                                    Dict.update (TripId.toString e.tripId)
                                        (Just << Dict.insert (ExpenseId.toString e.id) e << Maybe.withDefault Dict.empty)
                                        as_.expenses
                            }
                    in
                    clearSubmittedScanItem (ExpenseId.toString e.id) withExpense

                MilepostProgressChanged { progress, rev } ->
                    -- The earned-marker singleton arrived (our own write
                    -- confirming, or a sync pull from another device). Capture
                    -- the map + `_rev` so the next reconcile write threads the
                    -- right revision. We never shrink the map here — the
                    -- reconcile pass owns the union.
                    ( { as_ | milepost = Loaded { earned = progress.earned, rev = rev } }
                    , Cmd.none
                    )

                TripChanged t ->
                    ( { as_ | trips = upsertTripIntoState t as_.trips }, Cmd.none )

                UserSettingsChanged { rev, settings } ->
                    -- The settings singleton arrived (our own write echo, or a
                    -- sync pull from another device). Capture it + `_rev` so the
                    -- next write threads the right revision (milepost pattern).
                    ( { as_ | userSettings = SettingsLoaded { rev = rev, settings = settings } }
                    , Cmd.none
                    )

                VoidChanged v ->
                    ( { as_ | voids = Dict.insert v.id v as_.voids }, Cmd.none )
    in
    ( AuthModel (hydrateFormForRoute as1), dbCmd )


{-| The change-feed echo OWNS every submit-clear delete, idempotently.

When an expense arrives over the PouchDB change feed (the local save's own
echo, or a later CouchDB sync pull), match its `_id` against every scan
item's `expectedExpenseId` (stamped at `GotSubmitTime`). A match means the
expense the scan card produced has durably committed, so the card can be
retired: drop it from the in-memory queue, delete its durable row, and
tombstone its id (so a `loadScanQueue` mid-flight can't resurrect it).

Idempotent: a re-delivered echo finds no matching item (it was already
removed), so it's a clean no-op — `Dict.remove` and the IDB `delete` are
both no-ops on an absent key, and the id is harmlessly re-tombstoned.

-}
clearSubmittedScanItem : String -> AuthState -> ( AuthState, Cmd Msg )
clearSubmittedScanItem expenseId as_ =
    let
        matchingIds : List String
        matchingIds =
            Data.Scan.idsWithExpectedExpense expenseId as_.scanQueue
    in
    case matchingIds of
        [] ->
            ( as_, Cmd.none )

        _ ->
            ( { as_
                | scanQueue = List.foldl Dict.remove as_.scanQueue matchingIds
                , scanTombstones = List.foldl Set.insert as_.scanTombstones matchingIds
              }
            , Cmd.batch (List.map Ports.deleteScanItem matchingIds)
            )


{-| Remove a document from every cache it might live in.

Called on PouchDB `_deleted` revisions (rare — we soft-delete via `Void`
docs in normal flow). We don't know the doc's `type` here, so we attempt
removal from every cache. For expenses that means scanning every inner
dict, which is O(n trips) and fine in practice.

If the deleted doc was the one currently being edited, the form is
reset so the page doesn't end up showing stale data.

-}
handleDbDelete : String -> AuthState -> ( Model, Cmd Msg )
handleDbDelete id as_ =
    let
        as1 =
            { as_
                | amendments = Dict.remove id as_.amendments
                , expenses = Dict.map (\_ inner -> Dict.remove id inner) as_.expenses
                , trips = removeTripFromState (TripId.fromString id) as_.trips
                , voids = Dict.remove id as_.voids
            }

        -- If the deleted doc was the entry currently being edited, drop the
        -- hydrated form so the page falls back to AddPageLoading and (next
        -- nav) AddPageNew.
        as2 =
            case as1.form of
                EditForm fid _ ->
                    if ExpenseId.toString fid == id then
                        { as1 | form = FreshForm (PendingEntry.defaultPendingEntry as1.today) }

                    else
                        as1

                FreshForm _ ->
                    as1
    in
    ( AuthModel as2, Cmd.none )


requestCode : GuestState -> ( Model, Cmd Msg )
requestCode gs =
    let
        email =
            String.trim gs.emailInput
    in
    if email == "" then
        ( GuestModel { gs | authError = Just "Enter your email address." }, Cmd.none )

    else
        ( GuestModel
            { gs
                | authError = Nothing
                , session = { config = gs.session.config, reason = RequestingCode email }
            }
        , Http.post
            { url = gs.session.config.backendUrl ++ "/auth/request-code"
            , body = Http.jsonBody (E.object [ ( "email", E.string email ) ])
            , expect = Http.expectWhatever (GuestMsg << RequestCodeResult)
            }
        )


verifyCode : String -> GuestState -> ( Model, Cmd Msg )
verifyCode email gs =
    let
        code =
            String.trim gs.codeInput

        baseFields =
            [ ( "email", E.string email ), ( "code", E.string code ) ]

        bodyFields =
            case gs.pendingRef of
                Just ref ->
                    baseFields ++ [ ( "ref", E.string ref ) ]

                Nothing ->
                    baseFields
    in
    if code == "" then
        ( GuestModel { gs | authError = Just "Enter the code from your email." }, Cmd.none )

    else
        ( GuestModel
            { gs
                | authError = Nothing
                , resendStatus = RemoteData.NotAsked
                , session = { config = gs.session.config, reason = VerifyingCode email code }
            }
        , Http.post
            { url = gs.session.config.backendUrl ++ "/auth/verify-code"
            , body = Http.jsonBody (E.object bodyFields)
            , expect = Http.expectJson (GuestMsg << VerifyCodeResult) Codec.credsDecoder
            }
        )


{-| Request a passwordless magic link for the conversion wall (#337). Sends the
guest's email plus the share token (`next`, from the preview route) so the
emailed link can drive convert+join in one step. Mirrors `requestCode`.
-}
requestMagicLink : GuestState -> ( Model, Cmd Msg )
requestMagicLink gs =
    let
        email =
            String.trim gs.emailInput

        bodyFields =
            ( "email", E.string email )
                :: (case shareTokenFromRoute gs.route of
                        Just token ->
                            [ ( "next", E.string token ) ]

                        Nothing ->
                            []
                   )
    in
    if email == "" then
        ( GuestModel { gs | authError = Just "Enter your email address." }, Cmd.none )

    else
        ( GuestModel { gs | authError = Nothing, magicLinkRequest = RemoteData.Loading }
        , Http.post
            { url = gs.session.config.backendUrl ++ "/auth/request-magic-link"
            , body = Http.jsonBody (E.object bodyFields)
            , expect = Http.expectWhatever (GuestMsg << MagicLinkResult)
            }
        )


{-| Verify a magic-link token at the landing route (#337). The caller-confirmed
email (`gs.emailInput`) is enforced server-side against the token (forwarding
defense). `maybeNext` is the share token from the link, stashed in
`pendingJoinToken` so the post-sign-in redirect joins the trip. Mirrors
`verifyCode`.
-}
verifyMagicLink : String -> Maybe String -> GuestState -> ( Model, Cmd Msg )
verifyMagicLink token maybeNext gs =
    let
        email =
            String.trim gs.emailInput
    in
    if email == "" then
        ( GuestModel { gs | authError = Just "Enter the email this link was sent to." }, Cmd.none )

    else
        ( GuestModel
            { gs
                | authError = Nothing
                , magicLinkRequest = RemoteData.Loading
                , pendingJoinToken = maybeNext
            }
        , Http.post
            { url = gs.session.config.backendUrl ++ "/auth/verify-magic-link"
            , body = Http.jsonBody (E.object [ ( "token", E.string token ), ( "email", E.string email ) ])
            , expect = Http.expectJson (GuestMsg << MagicVerifyResult) Codec.credsDecoder
            }
        )


handleTripsFetched : Dict.Dict String Trip -> AuthState -> ( Model, Cmd Msg )
handleTripsFetched tripsDict as_ =
    let
        hint =
            Routing.routeTripId as_.route

        intendedTrip =
            hint |> Maybe.andThen (\id -> Dict.get (TripId.toString id) tripsDict)

        selectedTrips =
            case intendedTrip of
                Just trip ->
                    Just (Trips.selectTrip trip.id (Trips.fromDict tripsDict |> Maybe.withDefault (Trips.singleton trip)))

                Nothing ->
                    Trips.fromDict tripsDict
    in
    case selectedTrips of
        Just trips ->
            -- Trips loaded — let fetchesForRoute decide whether the current
            -- route needs an expenses fetch (will skip if already cached),
            -- then layer on a one-time full load of every other trip's
            -- expenses so milepost evaluation (count/dollar/streak markers)
            -- is correct from startup rather than waiting for the user to
            -- visit each trip (Decision 2). `loadAllTripExpenses` is
            -- idempotent: it skips trips already in `tripLoaded` /
            -- `loadingTrips`, so the lazy per-route fetch above is never
            -- duplicated.
            let
                ( routeState, routeCmd ) =
                    -- `tripsHydrated = True`: this is the authoritative
                    -- complete read, so the all-trips load + milepost
                    -- reconcile below (and the quiescence reconcile in the
                    -- `TripExpensesFetched` handler) are now allowed to run.
                    fetchesForRoute { as_ | trips = TripsLoaded trips, tripsHydrated = True }

                ( loadedState, loadAllCmd ) =
                    loadAllTripExpenses routeState

                -- If every trip's expenses were already cached (returning
                -- session, or a user with zero trips), no `TripExpensesFetched`
                -- will arrive to drive the reconcile — so trigger it here
                -- directly. When loads ARE pending, the quiescence check in the
                -- `TripExpensesFetched` handler fires it instead.
                reconcileCmd =
                    if Set.isEmpty loadedState.loadingTrips then
                        Task.perform (AuthMsg << ReconcileMileposts) Time.now

                    else
                        Cmd.none
            in
            ( AuthModel loadedState, Cmd.batch [ routeCmd, loadAllCmd, reconcileCmd ] )

        Nothing ->
            case as_.route of
                -- A first-time invitee has zero personal trips but is mid
                -- invite-accept on `/sharedtrips/join?token=…`. Don't clobber
                -- their route — let them complete the Accept/Decline flow
                -- (which provisions a shared trip and resolves the empty
                -- state). Every other route falls back to the Trips empty
                -- state as before.
                RouteJoinSharedTrip _ ->
                    ( AuthModel { as_ | trips = NoTripsYet, tripsHydrated = True }
                    , Cmd.none
                    )

                _ ->
                    ( AuthModel { as_ | trips = NoTripsYet, route = RouteTrips, tripsHydrated = True }
                    , Nav.replaceUrl as_.key (as_.basePath ++ "trips")
                    )


{-| Local-first early render of the trips list (`TripsPrefetched`).

The JS side reads whatever trips are already on disk the moment the personal
PouchDB handle opens — before the first sync round-trip settles — and hands
them here so the list renders immediately instead of blocking on the network
(the whole point of an offline-first app, and the fix for a multi-second
`TripsLoading` skeleton on a weak connection).

This is deliberately the LIGHT path. It resolves the skeleton and lazily
loads the current route's trip (so the Ledger/Stats you're looking at render
fast), but it does NOT:

  - fire `loadAllTripExpenses` / milepost reconcile — those wait for the
    authoritative `handleTripsFetched` (complete set) so milepost evaluation
    never seeds on a partial set (see `tripsHydrated` in `Types.elm`);
  - clobber the route to `/trips` on an empty read — a brand-new device whose
    trips haven't synced yet, or a deep link to a not-yet-pulled shared trip,
    must not lose its route. The empty-state decision belongs to the settled
    read.

It also no-ops if the authoritative read already populated `trips`
(`TripsLoaded`): the early read can only be a subset, so it must never
overwrite the complete set (e.g. when sync settles faster than the deferred
local read on a warm connection).

-}
handleTripsPrefetched : Dict.Dict String Trip -> AuthState -> ( Model, Cmd Msg )
handleTripsPrefetched tripsDict as_ =
    case as_.trips of
        TripsLoaded _ ->
            ( AuthModel as_, Cmd.none )

        _ ->
            let
                hint =
                    Routing.routeTripId as_.route

                intendedTrip =
                    hint |> Maybe.andThen (\id -> Dict.get (TripId.toString id) tripsDict)

                selectedTrips =
                    case intendedTrip of
                        Just trip ->
                            Just (Trips.selectTrip trip.id (Trips.fromDict tripsDict |> Maybe.withDefault (Trips.singleton trip)))

                        Nothing ->
                            Trips.fromDict tripsDict
            in
            case selectedTrips of
                Just trips ->
                    let
                        ( routeState, routeCmd ) =
                            fetchesForRoute { as_ | trips = TripsLoaded trips }
                    in
                    ( AuthModel routeState, routeCmd )

                Nothing ->
                    -- Empty local read: keep the skeleton, don't clobber the
                    -- route. The settled read owns the genuine empty state.
                    ( AuthModel as_, Cmd.none )


{-| Fire `GetTripExpenses` for every loaded trip whose expenses aren't already
cached (`tripLoaded`) or in flight (`loadingTrips`), marking each as loading.

This is the one-time full load that backs milepost evaluation (Decision 2 in
#408): the count/dollar/streak markers need every trip's resolved expenses, but
`fetchesForRoute` only loads the trip the user is currently looking at. We run
this once after `handleTripsFetched`. It is fully idempotent — a trip already
loaded or loading is skipped, so it never duplicates the lazy per-route fetch
and is safe to call repeatedly.

-}
loadAllTripExpenses : AuthState -> ( AuthState, Cmd Msg )
loadAllTripExpenses as_ =
    case as_.trips of
        TripsLoaded loadedTrips ->
            let
                toLoad : List Trip
                toLoad =
                    Trips.allTrips loadedTrips
                        |> List.filter
                            (\trip ->
                                let
                                    key =
                                        TripId.toString trip.id
                                in
                                not (Set.member key as_.tripLoaded)
                                    && not (Set.member key as_.loadingTrips)
                            )

                newLoading : Set.Set String
                newLoading =
                    toLoad
                        |> List.map (.id >> TripId.toString)
                        |> Set.fromList

                -- One bulk request instead of one `GetTripExpenses` per
                -- trip: the JS side scans each backing PouchDB once and
                -- buckets expenses by trip, then replies with one
                -- `TripExpensesFetched` per requested trip — so the
                -- per-trip quiescence accounting in `loadingTrips` is
                -- unchanged, but N full-database scans collapse to one
                -- scan per open handle.
                requests : List ( Trip.TripTarget, TripId.TripId )
                requests =
                    List.map (\trip -> ( targetForTripId trip.id as_, trip.id )) toLoad
            in
            if List.isEmpty requests then
                ( as_, Cmd.none )

            else
                ( { as_ | loadingTrips = Set.union newLoading as_.loadingTrips }
                , sendPouch (GetAllTripExpenses requests)
                )

        _ ->
            ( as_, Cmd.none )


{-| Re-evaluate the milepost catalog against the live state and persist any
newly-earned markers (Deliverable D, #408).

A thin wrapper over the pure decision `Data.MilepostProgress.reconcile` (#428):
this function evaluates the catalog, stashes the full state list onto
`as_.milepostStates` (Decision #409), asks the pure function what to do, then
turns that decision into the actual `SaveMilepostProgress` port write, the
`milepost` field update, and the earn-toast queue append (#410).

  - **First load** (`milepost == NotLoaded`): the pure function seeds the
    earned-marker map from everything earned right now, stamping each with
    `now`, and writes it silently. No toast — the pre-existing backlog
    shouldn't celebrate on first boot (`toEnqueue` is empty).
  - **Subsequent passes**: when the pure function reports new ids, write the
    union (markers never un-earn) and enqueue the newly-earned markers,
    arming the auto-advance timer only if the queue was previously empty.
    Idempotent — when nothing is new, no write is issued, so the oscillating
    `Synced` edge doesn't churn the doc.

This is pure local PouchDB; it is NOT gated on remote sync success (local-first
rule) — the caller fires it once expense loading is quiescent regardless of
whether sync reached the wire.

-}
reconcileMileposts : Time.Posix -> AuthState -> ( Model, Cmd Msg )
reconcileMileposts now as_ =
    let
        -- The full evaluated catalog. Stashed onto `as_.milepostStates` on
        -- every pass (Decision #409) so `Pages.Milepost` can render current
        -- locked/progress state without recomputing — there is no `now` on
        -- the model at view time.
        states : List Milepost.MarkerState
        states =
            Milepost.evaluate (milepostInputs as_ now)

        withStates : AuthState -> AuthState
        withStates next =
            { next | milepostStates = states }

        earnedNow : Set.Set String
        earnedNow =
            states
                |> List.filterMap
                    (\state ->
                        case state of
                            Milepost.Earned { marker } ->
                                Just marker.id

                            Milepost.Locked _ ->
                                Nothing
                    )
                |> Set.fromList

        -- The reconcile DECISION is a pure function (issue #428). It returns
        -- what to persist, the `_rev` to thread, and which ids to celebrate;
        -- this wrapper turns that decision into the actual port write and
        -- toast-queue append. See `Data.MilepostProgress.reconcile` for the
        -- branch logic (silent first-load, idempotent no-op, fresh-earn enqueue).
        decision : { persist : Maybe MilepostProgress, rev : Maybe String, toEnqueue : List String }
        decision =
            MilepostProgress.reconcile
                { earnedNow = earnedNow
                , now = now
                , state = as_.milepost
                }
    in
    case decision.persist of
        Nothing ->
            -- Idempotent no-op for persistence: nothing new earned since the
            -- last pass. Still refresh `milepostStates` so the screen reflects
            -- current locked/progress even when no doc is written.
            ( AuthModel (withStates as_), Cmd.none )

        Just progress ->
            let
                -- The newly-earned markers, in stable catalog order, mapped
                -- back from their ids. Appended to the earn-toast queue so
                -- `UI.MilepostToast` celebrates each one. The pure function
                -- returns an empty `toEnqueue` on the first-load seed, so the
                -- pre-existing backlog is silent (no celebrating it).
                newlyMarkers : List Milepost.Marker
                newlyMarkers =
                    Milepost.catalog
                        |> List.filter (\marker -> List.member marker.id decision.toEnqueue)

                queue : List Milepost.Marker
                queue =
                    as_.milepostToasts ++ newlyMarkers

                -- Schedule the auto-advance only when the queue was empty
                -- before this batch — `DismissMilepostToast` chains the next
                -- timer itself, so we never stack overlapping sleeps.
                autoAdvanceCmd : Cmd Msg
                autoAdvanceCmd =
                    if List.isEmpty as_.milepostToasts && not (List.isEmpty newlyMarkers) then
                        milepostToastFor

                    else
                        Cmd.none

                -- Thread the current `_rev` so PouchDB doesn't 409 on the
                -- second write. The JS upsert resolves the rev itself, but
                -- carrying it keeps the local model honest until the write
                -- confirms back on the change feed.
                doc : E.Value
                doc =
                    case decision.rev of
                        Just r ->
                            E.object
                                [ ( "_id", E.string MilepostProgress.docId )
                                , ( "_rev", E.string r )
                                , ( "type", E.string "milepostProgress" )
                                , ( "earned", E.dict identity E.string progress.earned )
                                ]

                        Nothing ->
                            MilepostProgress.encoder progress
            in
            ( AuthModel (withStates { as_ | milepost = Loaded { earned = progress.earned, rev = decision.rev }, milepostToasts = queue })
            , Cmd.batch
                [ sendPouch (SaveMilepostProgress doc)
                , autoAdvanceCmd
                ]
            )


upsertTripIntoState : Trip -> TripsState -> TripsState
upsertTripIntoState trip state =
    case state of
        TripsLoading dict hint ->
            TripsLoading (Dict.insert (TripId.toString trip.id) trip dict) hint

        TripsLoaded trips ->
            TripsLoaded (Trips.upsertTrip trip trips)

        NoTripsYet ->
            TripsLoaded (Trips.singleton trip)


removeTripFromState : TripId.TripId -> TripsState -> TripsState
removeTripFromState id state =
    case state of
        TripsLoading dict hint ->
            TripsLoading (Dict.remove (TripId.toString id) dict) hint

        TripsLoaded trips ->
            case Trips.removeTrip id trips of
                Just trips_ ->
                    TripsLoaded trips_

                Nothing ->
                    NoTripsYet

        NoTripsYet ->
            state



-- APP STATE HELPERS


expenseToPending : Expense.Expense -> PendingEntry
expenseToPending e =
    { address = e.address
    , amount = Money.toDollarString e.amount
    , category = e.category
    , currency = e.currency
    , date = DateField.toIso e.date

    -- The volume/price strings hold whichever unit the currency selects:
    -- gallons + price-per-gallon for a US fuel-up, liters + price-per-liter
    -- for any metric one (the Add form relabels the inputs to match).
    , fuelGallons =
        if Currency.usesGallons e.currency then
            e.fuelDetail |> Maybe.andThen .gallons |> Maybe.map Gallons.toInputString |> Maybe.withDefault ""

        else
            e.fuelDetail |> Maybe.andThen .liters |> Maybe.map Liters.toInputString |> Maybe.withDefault ""
    , fuelGrade =
        e.fuelDetail |> Maybe.andThen .grade |> Maybe.map FuelGrade.display |> Maybe.withDefault ""
    , fuelPricePerGallon =
        if Currency.usesGallons e.currency then
            e.fuelDetail |> Maybe.andThen .pricePerGallon |> Maybe.map PricePerGallon.toInputString |> Maybe.withDefault ""

        else
            e.fuelDetail |> Maybe.andThen .pricePerLiter |> Maybe.map PricePerLiter.toInputString |> Maybe.withDefault ""
    , locationState =
        case e.geoPoint of
            Just point ->
                LocationGot point ManualPin

            Nothing ->
                LocationIdle
    , longNote = e.longNote
    , merchant = e.merchant
    , note = e.note
    , paymentMethod = e.paymentMethod
    }


toastFor : Cmd Msg
toastFor =
    Task.perform (\_ -> AuthMsg ToastExpired) (Process.sleep 4000)


{-| Auto-advance the earn-toast queue after a few seconds by issuing a
`DismissMilepostToast`, which drops the head and re-arms this timer if more
markers remain. Mirrors `toastFor`, with a longer dwell so the celebration is
readable.
-}
milepostToastFor : Cmd Msg
milepostToastFor =
    Task.perform (\_ -> AuthMsg DismissMilepostToast) (Process.sleep 6000)


{-| Resolve the location that will actually be attached to the entry on
submit. Per-entry overrides (map picker, EXIF, "skip") win; otherwise we
fall back to the shared `currentLocation` broadcast — the device's live
GPS that the Add page and the Share modal both read from.

This keeps `pendingEntry.locationState` meaning "the user's deliberate
choice for THIS entry," and `as_.currentLocation` meaning "where the
device is right now." Single broadcast, single read path.

-}
effectiveLocation : AuthState -> PendingEntry -> LocationState
effectiveLocation as_ p =
    case p.locationState of
        LocationIdle ->
            as_.currentLocation

        other ->
            other


authPending : (PendingEntry -> PendingEntry) -> AuthState -> ( Model, Cmd Msg )
authPending f as_ =
    ( AuthModel { as_ | form = PendingEntry.mapForm f as_.form }, Cmd.none )


{-| Parse a trip-form budget input into a `Money`. An empty / unparseable
string falls back to `Money.zero`, mirroring the pre-R2 behaviour where
`String.toFloat form.budget |> Maybe.withDefault 0` stored a zero budget
for "no budget set". `Trip.validator` already rejects non-empty inputs
that don't parse, so the fallback is only reached for genuinely-empty
inputs.
-}
parseFormBudget : String -> Money.Money
parseFormBudget raw =
    Money.fromDollarString raw
        |> Maybe.withDefault Money.zero


{-| Parse a trip-form date input into a `DateField`. An empty /
unparseable string falls back to the epoch (`1970-01-01`), matching the
legacy `""` sentinel that the pre-R2 code stored for "date not set" —
downstream code asks `Trip.startDate /= ""` against the legacy shape;
post-R2 the equivalent is "is this exactly the epoch?", which the view
code in `Pages/Trips.elm` already handles via `DateField.compare`.

`Trip.validator` rejects out-of-order date pairs at the String level so
we never reach this code with a syntactically-valid but logically-bad
date.

-}
parseFormDate : String -> DateField.DateField
parseFormDate raw =
    DateField.fromIsoOr epochDate raw


{-| The DateField equivalent of the legacy `""` sentinel — used as the
fallback when a trip-form date input is empty or unparseable. The epoch
choice mirrors `Data.DateField.decoder`'s silent-default for malformed
wire values, and is what `DateField.fromIsoOr` falls back to inside the
module itself.
-}
epochDate : DateField.DateField
epochDate =
    DateField.fromIso "1970-01-01"
        |> Maybe.withDefault (DateField.today Time.utc (Time.millisToPosix 0))


{-| Capture the device's current local time zone and instant, then feed both
into `DateContextChanged`. Fired on boot and on every visibility change so the
app's notion of "today" (the default date for a new expense) and the zone used
for streak/Milepost day-bucketing track the user's real location — even after
they've travelled across zones or crossed local midnight with the app open.

`Time.here` re-reads the OS-configured zone each time it runs, so a westward
traveller whose device has switched zones gets the new zone on the next refresh.

-}
captureDateContext : Cmd Msg
captureDateContext =
    Task.map2 Tuple.pair Time.here Time.now
        |> Task.perform (\( zone, now ) -> SharedMsg (DateContextChanged zone now))



-- INIT


init : D.Value -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flagsJson url key =
    let
        dec field_ =
            D.decodeValue (D.field field_ D.string) flagsJson
                |> Result.withDefault ""

        authCreds =
            D.decodeValue (D.field "authCreds" (D.nullable Codec.credsDecoder)) flagsJson
                |> Result.withDefault Nothing

        demoMode =
            D.decodeValue (D.field "demoMode" D.bool) flagsJson
                |> Result.withDefault False

        initialColorScheme =
            D.decodeValue (D.field "colorScheme" D.string) flagsJson
                |> Result.toMaybe
                |> Maybe.andThen ColorScheme.fromString
                |> Maybe.withDefault ColorScheme.Auto

        initialToday =
            D.decodeValue (D.field "today" DateField.decoder) flagsJson
                |> Result.withDefault epochDate

        cfg =
            { anthropicKey =
                D.decodeValue (D.field "anthropicKey" AnthropicKey.decoder) flagsJson
                    |> Result.withDefault Nothing
            , backendUrl = dec "backendUrl"
            , vapidPublicKey = dec "vapidPublicKey"
            }

        basePath =
            dec "basePath"

        initialRoute =
            Routing.routeFromUrl basePath url

        pendingRef =
            D.decodeValue (D.field "pendingRef" (D.nullable D.string)) flagsJson
                |> Result.withDefault Nothing

        gs =
            { authError = Nothing
            , basePath = basePath
            , codeInput = ""
            , demoMode = demoMode
            , emailInput = ""
            , key = key
            , guestScan = NoScan
            , magicLinkRequest = RemoteData.NotAsked
            , showConvert = False
            , nestPreview = RemoteData.NotAsked
            , network = Unknown
            , pendingJoinToken = joinTokenFromRoute initialRoute
            , pendingRef = pendingRef
            , resendStatus = RemoteData.NotAsked
            , route = initialRoute
            , session = { config = cfg, reason = NotLoggedIn }
            , showSettings = False
            , today = initialToday
            , version = dec "version"
            , zone = Time.utc
            }
    in
    case ( initialRoute, authCreds ) of
        ( RouteVerify unit fixture, _ ) ->
            -- Verification routes mount a seeded fixture model and skip the
            -- normal boot entirely: no `fetchMe`, no sync, no PouchDB. JS also
            -- skips `attachPouch` for `/verify` paths, so nothing reaches the
            -- network. The mounted unit/fixture plus the full matrix are pushed
            -- to `window.__verify`.
            ( AuthModel (seedVerifyAuthState unit fixture initialColorScheme gs)
            , Ports.verifyResults
                (E.object
                    [ ( "mountedUnit", E.string unit )
                    , ( "mountedFixture", E.string fixture )
                    , ( "results", Verify.Registry.encode Verify.Registry.runAll )
                    ]
                )
            )

        ( RouteVerifyIndex, _ ) ->
            -- The human-browsable dashboard: lists every unit × fixture with its
            -- verdict + deep links. Same no-boot/no-network treatment as the
            -- per-fixture routes; the whole matrix is pushed to `window.__verify`.
            ( AuthModel (seedVerifyIndexModel initialColorScheme gs)
            , Ports.verifyResults
                (E.object
                    [ ( "mountedUnit", E.string "" )
                    , ( "mountedFixture", E.string "" )
                    , ( "results", Verify.Registry.encode Verify.Registry.runAll )
                    ]
                )
            )

        ( _, Nothing ) ->
            let
                bootFetchCmd =
                    case initialRoute of
                        RouteNestPreview token ->
                            Http.NestPreviewApi.resolve
                                gs.session.config.backendUrl
                                token
                                (GuestMsg << NestPreviewResult)

                        _ ->
                            Cmd.none
            in
            ( GuestModel
                { gs
                    | nestPreview =
                        case initialRoute of
                            RouteNestPreview _ ->
                                RemoteData.Loading

                            _ ->
                                RemoteData.NotAsked
                }
            , Cmd.batch [ bootFetchCmd, captureDateContext ]
            )

        ( _, Just creds ) ->
            let
                as_ =
                    { booted | colorScheme = initialColorScheme }

                booted =
                    toAuthState creds initialRoute gs

                ( bootedFinal, checkoutCmd ) =
                    -- Cold boot landing on `/settings?checkout=success`:
                    -- the user just paid and Stripe redirected here.
                    -- `fetchMe` is already firing below (it's the
                    -- server-authoritative refresh), so we only need to
                    -- (a) show the toast and (b) strip the query string
                    -- so a refresh doesn't re-toast. Same for the
                    -- `canceled` variant minus the toast.
                    case checkoutReturnFromUrl url of
                        CheckoutReturnSuccess ->
                            ( { as_ | toast = Just "Welcome aboard! Your plan is active." }
                            , Cmd.batch
                                [ Nav.replaceUrl key (basePath ++ "settings")
                                , toastFor
                                ]
                            )

                        CheckoutReturnCanceled ->
                            ( as_
                            , Nav.replaceUrl key (basePath ++ "settings")
                            )

                        CheckoutReturnNone ->
                            ( as_, Cmd.none )
            in
            -- Don't fire route-driven fetches here. Sync hasn't settled
            -- yet, so PouchDB queries would race with replication and
            -- return empty/stale. Wait for SyncStateMsg Synced, which
            -- triggers GetAllTrips; handleTripsFetched then runs
            -- fetchesForRoute once trip data is in hand.
            --
            -- `/me` IS fired here — it's the server-authoritative
            -- refresh path for tier + billing state, runs independently
            -- of PouchDB, and a stale tier from cached `Creds` would
            -- silently mis-gate paid features until the next login.
            -- `loadScanQueue` hydrates the durable offline scan queue from
            -- IndexedDB (#371). It runs independently of PouchDB sync — the
            -- queue is device-local, not synced — so it's safe to fire on the
            -- boot critical path alongside `/me`.
            ( AuthModel bootedFinal
            , Cmd.batch [ fetchMe bootedFinal, fetchRates bootedFinal, checkoutCmd, Ports.loadScanQueue (), captureDateContext ]
            )


{-| Build the seeded `AuthState` for a `/verify/:unit/:fixture` route. The
stored route is set to `RouteSettings` so the real Settings page (with its
tier-gated create-row and notifications panel) renders, then each unit applies
its fixture's state via `applyUnitSeed`. No effects fire — see the `init`
`RouteVerify` branch.
-}
seedVerifyAuthState : String -> String -> ColorScheme.ColorScheme -> GuestState -> AuthState
seedVerifyAuthState unit fixture colorScheme gs =
    let
        seedCreds : Creds
        seedCreds =
            { dbName = ""
            , email = "verify@ternpike.test"
            , password = ""
            , subscriptionStatus = Nothing
            , tier = Tier.Tern
            , trailblazerNumber = Nothing
            }

        booted : AuthState
        booted =
            toAuthState seedCreds RouteSettings gs
    in
    applyUnitSeed unit fixture { booted | colorScheme = colorScheme }


{-| Build the seeded `AuthState` for the `/verify` dashboard index. No fixture —
the dashboard just lists `Verify.Registry.runAll`. Route is `RouteVerifyIndex`
so `viewAuth` renders the dashboard. No effects fire.
-}
seedVerifyIndexModel : ColorScheme.ColorScheme -> GuestState -> AuthState
seedVerifyIndexModel colorScheme gs =
    let
        seedCreds : Creds
        seedCreds =
            { dbName = ""
            , email = "verify@ternpike.test"
            , password = ""
            , subscriptionStatus = Nothing
            , tier = Tier.Tern
            , trailblazerNumber = Nothing
            }

        booted : AuthState
        booted =
            toAuthState seedCreds RouteVerifyIndex gs
    in
    { booted | colorScheme = colorScheme }


{-| Apply a unit's fixture state onto the seeded model. Each unit owns its
fixture→state mapping (single-sourced with its `Verify.Specs` module); this just
dispatches by unit name. The default covers tier-only units like TierGating.
-}
applyUnitSeed : String -> String -> AuthState -> AuthState
applyUnitSeed unit fixture as_ =
    case unit of
        "NotificationsPaywall" ->
            let
                input : Verify.Specs.NotificationsPaywall.Input
                input =
                    Verify.Specs.NotificationsPaywall.inputForFixture fixture
            in
            { as_
                | notificationPermission = input.permission
                , pushSubscribed = input.subscribed
                , standalone = input.standalone
                , tier =
                    if input.isPaid then
                        Tier.Osprey

                    else
                        Tier.Tern
            }

        "JoinSharedTrip" ->
            let
                input : Verify.Specs.JoinSharedTrip.Input
                input =
                    Verify.Specs.JoinSharedTrip.honest (Verify.Specs.JoinSharedTrip.requestForFixture fixture)
            in
            { as_
                | joinSharedTripRequest = input.request
                , route = RouteJoinSharedTrip ""
            }

        "ScanQueueCard" ->
            let
                -- Fixed trip id for the verify seed — stable across fixture runs.
                verifyTripId : TripId.TripId
                verifyTripId =
                    TripId.fromString "trip::2024-01-01T00:00:00.000Z::verify"

                verifyTrip : Trip.Trip
                verifyTrip =
                    { budget = Money.zero
                    , coverPhotoUrl = ""
                    , description = ""
                    , endDate = epochDate
                    , flockId = Nothing
                    , id = verifyTripId
                    , name = "Verify Trip"
                    , startDate = epochDate
                    }

                seededItem : ScanItem
                seededItem =
                    Verify.Specs.ScanQueueCard.seededItem fixture

                -- The ocrPath is derived from tier + anthropicKey in the real
                -- view. Seed tier to produce the right path for this fixture:
                -- "unavailable" needs Unscannable → Tern with no key.
                -- Everything else needs HostedPath → Osprey with no key.
                seededTier : Tier.Tier
                seededTier =
                    if fixture == "unavailable" then
                        Tier.Tern

                    else
                        Tier.Osprey
            in
            { as_
                | route = RouteScan verifyTripId
                , scanQueue = Dict.singleton (ScanItemId.toString seededItem.id) seededItem
                , storageAvailable = Verify.Specs.ScanQueueCard.seededStorageAvailable fixture
                , tier = seededTier
                , trips = TripsLoaded (Trips.singleton verifyTrip)
            }

        "MilepostScreen" ->
            { as_
                | milepostStates = Verify.Specs.MilepostScreen.statesForFixture fixture
                , route = RouteMilepost
            }

        "SharedTripCard" ->
            { as_ | sharedTrips = Verify.Specs.SharedTripCard.seededTrips fixture }

        "TierGating" ->
            -- The tier gate on shared-trip CREATION now lives in the new-trip
            -- form's "+ New shared trip" target (UI.TripFormModal), not in
            -- Settings. Seed the form open on that target so the gated panel
            -- (invitee fields for paid, upgrade prompt for Tern) renders and
            -- carries the `TierGating` verify attrs.
            { as_
                | tier = verifyFixtureTier fixture
                , tripForm =
                    Just
                        { budget = ""
                        , coverPhotoUrl = ""
                        , description = ""
                        , editing = Nothing
                        , endDate = ""
                        , errors = []
                        , groupNameOverridden = False
                        , name = ""
                        , sharedTripRequest = RemoteData.NotAsked
                        , startDate = DateField.toIso as_.today
                        , submitting = False
                        , target = Trip.ToNewFlock Trip.defaultNewFlockDraft
                        }
            }

        _ ->
            { as_ | tier = verifyFixtureTier fixture }


{-| Map a verification fixture name to the tier it seeds. Unknown / `tern` /
probe fixtures fall back to the free tier.
-}
verifyFixtureTier : String -> Tier
verifyFixtureTier fixture =
    if String.contains "osprey" fixture then
        Tier.Osprey

    else if String.contains "trailblazer" fixture then
        Tier.Trailblazer

    else
        Tier.Tern



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model ) of
        ( SharedMsg s, _ ) ->
            updateShared s model

        ( GuestMsg g, GuestModel gs ) ->
            updateGuest g gs

        ( AuthMsg a, AuthModel as_ ) ->
            updateAuth a as_

        ( GuestMsg _, AuthModel as_ ) ->
            ( AuthModel as_, Cmd.none )

        ( AuthMsg _, GuestModel gs ) ->
            -- An AuthMsg arrived while the model is a GuestModel — the
            -- session was torn down (sign-out / 401) between dispatch and
            -- delivery. We have no AuthState to run updateAuth against, so
            -- the message is dropped. In-flight scan results are recovered
            -- on the next login from the IndexedDB row via
            -- reconcileHydratedQueue (see #343 / the offline-scan track);
            -- do NOT route an AuthMsg into updateAuth with no AuthState.
            ( GuestModel gs, Cmd.none )


updateShared : SharedMsg_ -> Model -> ( Model, Cmd Msg )
updateShared msg model =
    case msg of
        ApiKeyChanged s ->
            case model of
                GuestModel gs ->
                    let
                        newKey =
                            AnthropicKey.fromInput s
                    in
                    ( GuestModel { gs | session = mapGuestConfig (\c -> { c | anthropicKey = newKey }) gs.session }
                    , Ports.saveStorage { key = "anthropic_key", value = Maybe.Extra.unwrap "" AnthropicKey.toHeader newKey }
                    )

                AuthModel as_ ->
                    let
                        cfg =
                            as_.config

                        newKey =
                            AnthropicKey.fromInput s

                        newShowInput =
                            case newKey of
                                Just _ ->
                                    as_.showByoKeyInput

                                Nothing ->
                                    False
                    in
                    ( AuthModel { as_ | config = { cfg | anthropicKey = newKey }, showByoKeyInput = newShowInput }
                    , Ports.saveStorage { key = "anthropic_key", value = Maybe.Extra.unwrap "" AnthropicKey.toHeader newKey }
                    )

        DateContextChanged zone now ->
            -- Refreshed default "today" + streak-bucketing zone, captured from
            -- the device on boot and on every visibility change. Re-deriving
            -- `today` from the live zone keeps a new expense's default date
            -- pinned to the user's *local* day even after they've travelled
            -- across zones or crossed midnight with the app open.
            let
                refreshedToday : DateField.DateField
                refreshedToday =
                    DateField.today zone now
            in
            case model of
                GuestModel gs ->
                    ( GuestModel { gs | today = refreshedToday, zone = zone }, Cmd.none )

                AuthModel as_ ->
                    ( AuthModel { as_ | today = refreshedToday, zone = zone }, Cmd.none )

        LinkClicked (Browser.Internal url) ->
            let
                ( navKey, basePath ) =
                    case model of
                        GuestModel gs ->
                            ( gs.key, gs.basePath )

                        AuthModel as_ ->
                            ( as_.key, as_.basePath )

                isVerifyRoute : Bool
                isVerifyRoute =
                    case Routing.routeFromUrl basePath url of
                        RouteVerify _ _ ->
                            True

                        RouteVerifyIndex ->
                            True

                        _ ->
                            False
            in
            -- /verify routes seed their fixture model in `init`, so navigating
            -- to one (e.g. clicking a dashboard row) must do a full page load —
            -- client-side pushUrl wouldn't re-seed. A reload is fine for this
            -- dev/inspection surface.
            if isVerifyRoute then
                ( model, Nav.load (Url.toString url) )

            else
                ( model, Nav.pushUrl navKey (Url.toString url) )

        LinkClicked (Browser.External href) ->
            ( model, Nav.load href )

        NetworkStatusChanged isOnline ->
            case model of
                GuestModel gs ->
                    ( GuestModel { gs | network = networkStateFromOnline isOnline }, Cmd.none )

                AuthModel as_ ->
                    -- When the network comes back online in-session, kick the
                    -- deferred-scan retry so receipts OCR without an app
                    -- restart (#400). The live PouchDB sync doesn't reliably
                    -- re-emit a fresh `Synced` edge on an Airplane-mode flip,
                    -- so the `Synced`-edge trigger in `SyncStateMsg` alone
                    -- misses the in-session reconnect; the `navigator.onLine`
                    -- port drives the retry directly. Fired only on the
                    -- offline→online EDGE (`Data.Sync.becameOnline`) so a
                    -- redundant online report can't double-dispatch. Safe to
                    -- fire eagerly: `RetryDeferredScans` is idempotent and
                    -- tier-capped, and a reconnect-window transport/auth
                    -- failure requeues transiently (see
                    -- `Data.Scan.hostedFailureKind` / `byoFailureKind`), so a
                    -- premature attempt never strands a receipt.
                    ( AuthModel { as_ | network = networkStateFromOnline isOnline }
                    , if Data.Sync.becameOnline as_.network isOnline then
                        Task.perform
                            (\_ -> AuthMsg (ScanMsg Msg.Scan.RetryDeferredScans))
                            (Task.succeed ())

                      else
                        Cmd.none
                    )

        RefreshDateContext ->
            -- Visibility regained (or boot): re-capture the device zone + now.
            -- A no-op subscription can't run a Task, so this trigger fires the
            -- `Time.here`/`Time.now` read that lands as `DateContextChanged`.
            ( model, captureDateContext )

        ResetSettingsClicked ->
            case model of
                GuestModel gs ->
                    ( GuestModel
                        { gs
                            | authError = Nothing
                            , codeInput = ""
                            , emailInput = ""
                            , session = { config = { anthropicKey = Nothing, backendUrl = "", vapidPublicKey = "" }, reason = NotLoggedIn }
                            , showSettings = False
                        }
                    , Ports.clearAllStorage ()
                    )

                AuthModel as_ ->
                    ( GuestModel
                        { authError = Nothing
                        , basePath = as_.basePath
                        , codeInput = ""
                        , demoMode = as_.demoMode
                        , emailInput = ""
                        , key = as_.key
                        , guestScan = NoScan
                        , magicLinkRequest = RemoteData.NotAsked
                        , showConvert = False
                        , nestPreview = RemoteData.NotAsked
                        , network = as_.network
                        , pendingJoinToken = Nothing
                        , pendingRef = Nothing
                        , resendStatus = RemoteData.NotAsked
                        , route = as_.route
                        , session = { config = { anthropicKey = Nothing, backendUrl = "", vapidPublicKey = "" }, reason = NotLoggedIn }
                        , showSettings = False
                        , today = as_.today
                        , version = as_.version
                        , zone = as_.zone
                        }
                    , Cmd.batch [ Ports.clearAllStorage (), Ports.stopSync () ]
                    )

        ScrolledToTop ->
            ( model, Cmd.none )

        SetColorScheme scheme ->
            case model of
                GuestModel gs ->
                    ( GuestModel gs, Cmd.none )

                AuthModel as_ ->
                    ( AuthModel { as_ | colorScheme = scheme }
                    , Ports.saveStorage { key = "color_scheme", value = ColorScheme.toString scheme }
                    )

        ShowByoKeyInput ->
            case model of
                GuestModel gs ->
                    ( GuestModel gs, Cmd.none )

                AuthModel as_ ->
                    ( AuthModel { as_ | showByoKeyInput = True }, Cmd.none )

        UrlChanged url ->
            case model of
                GuestModel gs ->
                    let
                        newRoute =
                            Routing.routeFromUrl gs.basePath url

                        fetchCmd =
                            case newRoute of
                                RouteNestPreview token ->
                                    Http.NestPreviewApi.resolve
                                        gs.session.config.backendUrl
                                        token
                                        (GuestMsg << NestPreviewResult)

                                _ ->
                                    Cmd.none
                    in
                    -- Track the route so the guest view can branch on it
                    -- (the funnel's unauthenticated pages render off
                    -- `gs.route`). `pendingJoinToken` is left untouched —
                    -- it's parked at boot/re-auth from the original join
                    -- URL and must survive intra-guest navigation so the
                    -- post-sign-in redirect still fires.
                    ( GuestModel
                        { gs
                            | nestPreview =
                                case newRoute of
                                    RouteNestPreview _ ->
                                        RemoteData.Loading

                                    _ ->
                                        gs.nestPreview
                            , route = newRoute
                        }
                    , Cmd.batch [ scrollToTop, fetchCmd ]
                    )

                AuthModel as_ ->
                    let
                        newRoute =
                            Routing.routeFromUrl as_.basePath url

                        checkoutReturn =
                            checkoutReturnFromUrl url

                        ( as1, cmd ) =
                            fetchesForRoute { as_ | route = newRoute, tripForm = Nothing }

                        ( as2, extraCmd ) =
                            case checkoutReturn of
                                CheckoutReturnSuccess ->
                                    -- /me is the server-authoritative tier refresh
                                    -- — fire it so Stripe-just-set the tier change
                                    -- shows up on this page render. Strip the
                                    -- query string so a refresh doesn't re-toast.
                                    ( { as1 | toast = Just "Welcome aboard! Your plan is active." }
                                    , Cmd.batch
                                        [ fetchMe as1
                                        , Nav.replaceUrl as1.key (as1.basePath ++ "settings")
                                        , toastFor
                                        ]
                                    )

                                CheckoutReturnCanceled ->
                                    -- User clicked back from Stripe. Strip the
                                    -- query string so a refresh doesn't keep
                                    -- the ?checkout=canceled marker around.
                                    ( as1
                                    , Nav.replaceUrl as1.key (as1.basePath ++ "settings")
                                    )

                                CheckoutReturnNone ->
                                    ( as1, Cmd.none )

                        -- Navigating to The Milepost re-evaluates the catalog
                        -- so the screen reflects current locked/progress
                        -- (reconcile is idempotent for persistence).
                        milepostCmd =
                            case newRoute of
                                RouteMilepost ->
                                    Task.perform (AuthMsg << ReconcileMileposts) Time.now

                                _ ->
                                    Cmd.none
                    in
                    ( AuthModel as2, Cmd.batch [ cmd, extraCmd, milepostCmd, scrollToTop ] )


scrollToTop : Cmd Msg
scrollToTop =
    Task.perform (\_ -> SharedMsg ScrolledToTop) (Browser.Dom.setViewport 0 0)


{-| Split a `data:<mime>;base64,<payload>` URL into its mime type and base64
payload for the guest scan upload. Returns `Nothing` for a malformed URL.
-}
splitDataUrl : String -> Maybe { base64 : String, mimeType : String }
splitDataUrl dataUrl =
    case String.split ";base64," dataUrl of
        [ prefix, b64 ] ->
            Just { base64 = b64, mimeType = String.dropLeft 5 prefix }

        _ ->
            Nothing


{-| The share token carried by a `RouteNestPreview` URL, if the guest is on
the preview route — used to authorize the guest scan.
-}
shareTokenFromRoute : Route -> Maybe String
shareTokenFromRoute route =
    case route of
        RouteNestPreview token ->
            Just token

        _ ->
            Nothing


updateGuest : GuestMsg_ -> GuestState -> ( Model, Cmd Msg )
updateGuest msg gs =
    case msg of
        CodeInputChanged s ->
            ( GuestModel { gs | codeInput = s }, Cmd.none )

        EmailInputChanged s ->
            ( GuestModel { gs | emailInput = s }, Cmd.none )

        RequestCodeResult result ->
            case ( gs.session.reason, result ) of
                ( RequestingCode email, Ok () ) ->
                    ( GuestModel
                        { gs
                            | authError = Nothing
                            , session = { config = gs.session.config, reason = AwaitingCode email }
                        }
                    , Cmd.none
                    )

                ( RequestingCode _, Err _ ) ->
                    ( GuestModel
                        { gs
                            | authError = Just "Could not send code. Try again."
                            , session = { config = gs.session.config, reason = NotLoggedIn }
                        }
                    , Cmd.none
                    )

                _ ->
                    ( GuestModel gs, Cmd.none )

        ResendCode ->
            case ( gs.session.reason, gs.resendStatus ) of
                ( AwaitingCode _, RemoteData.Loading ) ->
                    ( GuestModel gs, Cmd.none )

                ( AwaitingCode email, _ ) ->
                    ( GuestModel
                        { gs
                            | authError = Nothing
                            , codeInput = ""
                            , resendStatus = RemoteData.Loading
                        }
                    , Http.post
                        { url = gs.session.config.backendUrl ++ "/auth/request-code"
                        , body = Http.jsonBody (E.object [ ( "email", E.string email ) ])
                        , expect = Http.expectWhatever (GuestMsg << ResendCodeResult)
                        }
                    )

                _ ->
                    ( GuestModel gs, Cmd.none )

        StartConversion ->
            ( GuestModel { gs | showConvert = True, magicLinkRequest = RemoteData.NotAsked, authError = Nothing }
            , Cmd.none
            )

        MagicLinkRequested ->
            requestMagicLink gs

        MagicLinkResult result ->
            ( GuestModel { gs | magicLinkRequest = RemoteData.fromResult result }
            , case result of
                Ok _ ->
                    Ports.trackFunnel
                        { flockId = Maybe.withDefault "" (shareTokenFromRoute gs.route)
                        , stage = Analytics.convertRequested
                        }

                Err _ ->
                    Cmd.none
            )

        ConfirmMagicEmail ->
            case gs.route of
                RouteMagicLink token next ->
                    verifyMagicLink token next gs

                _ ->
                    ( GuestModel gs, Cmd.none )

        MagicVerifyResult (Ok creds) ->
            let
                ( landingRoute, landingUrl ) =
                    case gs.pendingJoinToken of
                        Just token ->
                            ( RouteJoinSharedTrip token
                            , gs.basePath ++ "sharedtrips/join?token=" ++ token
                            )

                        Nothing ->
                            ( RouteTrips, gs.basePath ++ "trips" )

                as_ =
                    toAuthState creds landingRoute gs
            in
            ( AuthModel as_
            , Cmd.batch
                [ Ports.saveStorage { key = "auth_creds", value = E.encode 0 (Codec.encodeCreds creds) }
                , Ports.startSync (Codec.encodeCreds creds)
                , Nav.replaceUrl gs.key landingUrl
                , fetchMe as_

                -- `toAuthState` resets `scanQueue` to empty and `init` never
                -- re-runs after in-SPA re-login (token expired while the tab
                -- stayed open) — re-hydrate the durable queue here (#371).
                , Ports.loadScanQueue ()

                -- `init` won't re-run either, so re-capture the device zone +
                -- "today" so a re-login doesn't inherit a stale `gs.zone`.
                , captureDateContext
                ]
            )

        MagicVerifyResult (Err _) ->
            ( GuestModel
                { gs
                    | authError = Just "That link is invalid or expired. Ask for a fresh one."
                    , magicLinkRequest = RemoteData.NotAsked
                }
            , Cmd.none
            )

        GuestScanPick ->
            ( GuestModel gs
            , File.Select.file [ "image/*" ] (GuestMsg << GuestScanSelected)
            )

        GuestScanSelected file ->
            ( GuestModel { gs | guestScan = Scanning }
            , Task.perform (GuestMsg << GuestScanLoaded) (File.toUrl file)
            )

        GuestScanLoaded dataUrl ->
            case ( splitDataUrl dataUrl, shareTokenFromRoute gs.route ) of
                ( Just parts, Just token ) ->
                    ( GuestModel { gs | guestScan = Scanning }
                    , Http.NestPreviewApi.scanGuest gs.session.config.backendUrl
                        token
                        parts.base64
                        parts.mimeType
                        (GuestMsg << GuestScanResult)
                    )

                _ ->
                    ( GuestModel { gs | guestScan = NoScan }, Cmd.none )

        GuestScanResult (Ok ocr) ->
            ( GuestModel { gs | guestScan = Scanned ocr }
            , Ports.trackFunnel
                { flockId = Maybe.withDefault "" (shareTokenFromRoute gs.route)
                , stage = Analytics.scanTrySucceeded
                }
            )

        GuestScanResult (Err _) ->
            ( GuestModel { gs | guestScan = NoScan }, Cmd.none )

        NestPreviewResult result ->
            ( GuestModel { gs | nestPreview = RemoteData.fromResult result }
            , case result of
                Ok _ ->
                    Ports.trackFunnel
                        { flockId = Maybe.withDefault "" (shareTokenFromRoute gs.route)
                        , stage = Analytics.nestPreviewViewed
                        }

                Err _ ->
                    Cmd.none
            )

        ResendCodeResult result ->
            ( GuestModel { gs | resendStatus = RemoteData.fromResult result }
            , Cmd.none
            )

        SubmitCode ->
            case gs.session.reason of
                AwaitingCode email ->
                    verifyCode email gs

                _ ->
                    ( GuestModel gs, Cmd.none )

        SubmitEmail ->
            case gs.session.reason of
                NotLoggedIn ->
                    requestCode gs

                SessionExpired ->
                    requestCode gs

                _ ->
                    ( GuestModel gs, Cmd.none )

        ToggleGuestSettings ->
            ( GuestModel { gs | showSettings = not gs.showSettings }, Cmd.none )

        VerifyCodeResult result ->
            case ( gs.session.reason, result ) of
                ( VerifyingCode _ _, Ok creds ) ->
                    let
                        ( landingRoute, landingUrl ) =
                            case gs.pendingJoinToken of
                                Just token ->
                                    ( RouteJoinSharedTrip token
                                    , gs.basePath ++ "sharedtrips/join?token=" ++ token
                                    )

                                Nothing ->
                                    ( RouteTrips, gs.basePath ++ "trips" )

                        as_ =
                            toAuthState creds landingRoute gs
                    in
                    ( AuthModel as_
                    , Cmd.batch
                        [ Ports.saveStorage { key = "auth_creds", value = E.encode 0 (Codec.encodeCreds creds) }
                        , Ports.startSync (Codec.encodeCreds creds)
                        , Nav.replaceUrl gs.key landingUrl
                        , fetchMe as_

                        -- See `MagicVerifyResult` above: re-hydrate the durable
                        -- scan queue on in-SPA re-login since `toAuthState`
                        -- cleared it and `init` won't re-run (#371).
                        , Ports.loadScanQueue ()

                        -- Likewise re-capture the device zone + "today".
                        , captureDateContext
                        ]
                    )

                ( VerifyingCode email _, Err _ ) ->
                    ( GuestModel
                        { gs
                            | authError = Just "Wrong or expired code."
                            , session = { config = gs.session.config, reason = AwaitingCode email }
                        }
                    , Cmd.none
                    )

                _ ->
                    ( GuestModel gs, Cmd.none )


updateAuth : AuthMsg_ -> AuthState -> ( Model, Cmd Msg )
updateAuth msg as_ =
    case msg of
        GotPouchMsg raw ->
            case D.decodeValue pouchInDecoder raw of
                Ok (DbChange change) ->
                    handleDbChange change as_

                Ok (DbDeleted id) ->
                    handleDbDelete id as_

                Ok (TripsFetched tripsDict) ->
                    handleTripsFetched tripsDict as_

                Ok (TripsPrefetched tripsDict) ->
                    handleTripsPrefetched tripsDict as_

                Ok (TripExpensesFetched tripId bundle) ->
                    let
                        key =
                            TripId.toString tripId

                        as1 =
                            { as_
                                | amendments = Dict.union bundle.amendments as_.amendments
                                , expenses = Dict.insert key bundle.expenses as_.expenses
                                , loadingTrips = Set.remove key as_.loadingTrips
                                , tripLoaded = Set.insert key as_.tripLoaded
                                , voids = Dict.union bundle.voids as_.voids
                            }

                        -- Once the load-all wave (Decision 2) drains —
                        -- `loadingTrips` is empty — every trip's expenses are
                        -- in hand, so re-evaluate mileposts. Firing on
                        -- quiescence covers both the startup full-load and any
                        -- later lazy per-route fetch; the reconcile is
                        -- idempotent (writes only on a change) so the repeat is
                        -- harmless.
                        --
                        -- Gated on `tripsHydrated`: before the authoritative
                        -- settled read lands, the only thing in `loadingTrips`
                        -- is the current route's trip (loaded eagerly by the
                        -- local-first `TripsPrefetched` render). Reconciling
                        -- then would seed mileposts off that partial set, and
                        -- the next pass — once the full set loads — would treat
                        -- the rest of the backlog as freshly earned and fire
                        -- spurious celebration toasts. Wait for the complete set.
                        reconcileCmd =
                            if as_.tripsHydrated && Set.isEmpty as1.loadingTrips then
                                Task.perform (AuthMsg << ReconcileMileposts) Time.now

                            else
                                Cmd.none
                    in
                    ( AuthModel (hydrateFormForRoute as1), reconcileCmd )

                Ok (ExpenseFetched eid bundle) ->
                    let
                        as1 =
                            { as_
                                | amendments = Dict.union bundle.amendments as_.amendments
                                , expenses =
                                    case bundle.expense of
                                        Just e ->
                                            Dict.update (TripId.toString e.tripId)
                                                (Just << Dict.insert (ExpenseId.toString e.id) e << Maybe.withDefault Dict.empty)
                                                as_.expenses

                                        Nothing ->
                                            as_.expenses
                                , loadingExpenses = Set.remove (ExpenseId.toString eid) as_.loadingExpenses
                                , voids =
                                    case bundle.void of
                                        Just v ->
                                            Dict.insert v.id v as_.voids

                                        Nothing ->
                                            as_.voids
                            }
                    in
                    ( AuthModel (hydrateFormForRoute as1), Cmd.none )

                Ok (DbError msg_) ->
                    ( AuthModel { as_ | error = Just msg_ }, Cmd.none )

                Ok (SharedTripMetaChanged flock) ->
                    ( AuthModel
                        { as_
                            | sharedTrips =
                                Dict.insert
                                    (Data.SharedTripId.toString flock.id)
                                    flock
                                    as_.sharedTrips
                        }
                    , Cmd.none
                    )

                Ok (SharedTripsReconciled flockIds) ->
                    let
                        keep =
                            flockIds
                                |> List.map Data.SharedTripId.toString
                                |> Set.fromList
                    in
                    ( AuthModel
                        { as_
                            | sharedTrips = Dict.filter (\k _ -> Set.member k keep) as_.sharedTrips
                        }
                    , Cmd.none
                    )

                Ok (SyncStateMsg state) ->
                    let
                        -- Fire the authoritative trip load once sync has had
                        -- its first chance to settle — whether it succeeded
                        -- (Synced) or failed (SyncError, AuthExpired). This is
                        -- the COMPLETE read: it spans every open handle
                        -- (personal + shared) and reflects anything pulled from
                        -- remote, so it's the one that drives the all-trips
                        -- expense load + milepost reconcile. The local-first
                        -- `TripsPrefetched` early read has already rendered the
                        -- on-disk trips by now; this folds in the rest.
                        --
                        -- Gated on `tripsHydrated` (not "trips still loading")
                        -- because the early read flips `trips` to `TripsLoaded`
                        -- before this runs. `tripsHydrated` flips True in
                        -- `handleTripsFetched`, so the settled read fires
                        -- exactly once rather than on every `Synced` oscillation.
                        syncSettled s =
                            s == Synced || s == SyncError || s == AuthExpired

                        syncSettledEdge =
                            syncSettled state && not (syncSettled as_.syncState)

                        loadCmd =
                            if syncSettledEdge && not as_.tripsHydrated then
                                sendPouch GetAllTrips

                            else
                                Cmd.none

                        capturedSyncedAt =
                            if state == Synced then
                                Task.perform (AuthMsg << GotSyncTime) Time.now

                            else
                                Cmd.none

                        -- Reconnect orchestration (#373): on a genuine
                        -- transition INTO `Synced` — the proven CouchDB
                        -- round-trip, NOT `navigator.onLine` — kick the
                        -- deferred-scan retry. `Synced` oscillates
                        -- (Synced → Syncing → Synced per replication
                        -- cycle) so this fires repeatedly; the
                        -- `RetryDeferredScans` handler is idempotent (its
                        -- concurrency gate dispatches zero once the
                        -- in-flight set is at the tier cap), and routing it
                        -- through the normal `ScanMsg` path lets the
                        -- auth-expiry logout win the race when sync instead
                        -- reports `AuthExpired`.
                        syncedEdge =
                            state == Synced && as_.syncState /= Synced

                        retryDeferredCmd =
                            if syncedEdge then
                                Task.perform
                                    (\_ -> AuthMsg (ScanMsg Msg.Scan.RetryDeferredScans))
                                    (Task.succeed ())

                            else
                                Cmd.none
                    in
                    ( AuthModel { as_ | syncState = state }
                    , Cmd.batch [ loadCmd, capturedSyncedAt, retryDeferredCmd ]
                    )

                Ok AuthExpiredMsg ->
                    ( GuestModel (toGuestState SessionExpired as_)
                    , Cmd.batch [ Ports.clearStorage (), Ports.stopSync () ]
                    )

                Err _ ->
                    ( AuthModel as_, Cmd.none )

        SignOutClicked ->
            ( GuestModel (toGuestState NotLoggedIn as_)
            , Cmd.batch [ Ports.clearStorage (), Ports.stopSync () ]
            )

        ExportCsv tripId ->
            let
                rows =
                    Dict.get (TripId.toString tripId) as_.expenses
                        |> Maybe.withDefault Dict.empty
                        |> Dict.values

                filename =
                    "expenses-" ++ TripId.toString tripId ++ ".csv"
            in
            ( AuthModel as_
            , Ports.downloadFile
                { content = CsvExport.toCsv rows
                , filename = filename
                , mimeType = "text/csv"
                }
            )

        ScanMsg m ->
            let
                ( scanModel, effect ) =
                    Page.Scan.update m (scanModelFromAuth as_)
            in
            ( AuthModel (mergeScanModel scanModel as_)
            , Effect.perform as_.key effect
            )

        ScanQueueLoaded raw ->
            -- Hydrate the durable offline scan queue (#371). Decode the JSON
            -- array item-by-item so one corrupt doc can't sink the whole
            -- queue (bad docs are quarantined — dropped), normalize in-flight
            -- statuses via `reconcileHydratedQueue` (a reload can't keep an
            -- OCR request alive, so `ScanProcessing` parks back to
            -- `ScanDeferred`), then merge into the live queue.
            --
            -- The merge is `Dict.union inMemory (hydrated minus tombstones)`
            -- (#374): the in-memory item wins a key collision, AND any id
            -- tombstoned since the last load (submit-cleared, split source,
            -- or `ClearDoneItems`) is dropped from the hydrated side so a
            -- late `getAll` can't resurrect a just-removed card.
            let
                hydrated : Dict.Dict String Data.Scan.ScanItem
                hydrated =
                    decodeHydratedQueue raw

                reconciled : Dict.Dict String Data.Scan.ScanItem
                reconciled =
                    Data.Scan.reconcileHydratedQueue hydrated

                mergedQueue : Dict.Dict String Data.Scan.ScanItem
                mergedQueue =
                    Data.Scan.mergeHydratedQueue as_.scanTombstones as_.scanQueue reconciled

                -- Persist back any item whose status the reconcile flipped
                -- (`ScanProcessing` → `ScanDeferred`) so the durable store
                -- matches the normalized in-memory queue. This is the in-PR
                -- caller for `saveScanItem` / `scanItemSaved`. Tombstoned
                -- ids are skipped — re-persisting one would resurrect the
                -- durable row we just deleted.
                persistCmds : List (Cmd Msg)
                persistCmds =
                    reconciled
                        |> Dict.toList
                        |> List.filterMap
                            (\( key, item ) ->
                                if Set.member key as_.scanTombstones then
                                    Nothing

                                else
                                    case Dict.get key hydrated of
                                        Just before ->
                                            if before.status == item.status then
                                                Nothing

                                            else
                                                Just (Ports.saveScanItem (Data.Scan.scanItemEncoder item))

                                        Nothing ->
                                            Nothing
                            )
            in
            ( AuthModel { as_ | scanQueue = mergedQueue }
            , Cmd.batch persistCmds
            )

        ScanItemSaved ack ->
            -- Save-ack for `saveScanItem`. On failure (e.g. the JS `put` threw
            -- `QuotaExceededError`) flip `persistError` on the matching item so
            -- the capture UI never claims durability it didn't get (#371). The
            -- `id` keys off the current model, so a late ack can't act on a
            -- stale closure. A clean save clears any prior error. The `error`
            -- string is logged JS-side; Elm only needs the `ok` boolean.
            let
                updatedQueue : Dict.Dict String Data.Scan.ScanItem
                updatedQueue =
                    Dict.update ack.id
                        (Maybe.map (\item -> { item | persistError = not ack.ok }))
                        as_.scanQueue
            in
            ( AuthModel { as_ | scanQueue = updatedQueue }, Cmd.none )

        StorageStatusReceived status ->
            -- Boot storage probe + best-effort persistence result (#371/#377).
            -- `available` gates the durability promise under Private Browsing /
            -- Lockdown Mode. `persisted` is `navigator.storage.persist()` result
            -- — `True` only when the UA actually granted persistent storage
            -- (typically requires the installed-app heuristic on iOS/Safari).
            -- `installed` is `True` when running as a standalone PWA.
            -- `isIos` gates the manual Add-to-Home-Screen nudge (#377).
            ( AuthModel
                { as_
                    | isIosDevice = status.isIos
                    , pwaInstalled = status.installed
                    , storageAvailable = status.available
                    , storagePersisted = status.persisted
                }
            , Cmd.none
            )

        AddressChanged s ->
            authPending (\p -> { p | address = s }) { as_ | duplicateWarning = Nothing }

        AmountChanged s ->
            authPending (\p -> { p | amount = s }) { as_ | duplicateWarning = Nothing }

        CategorySelected c ->
            authPending (\p -> { p | category = c }) as_

        CurrencyChanged c ->
            authPending (\p -> { p | currency = c }) as_

        DateChanged s ->
            authPending (\p -> { p | date = s }) { as_ | duplicateWarning = Nothing }

        FuelGallonsChanged s ->
            authPending (\p -> { p | fuelGallons = s }) as_

        FuelGradeChanged s ->
            authPending (\p -> { p | fuelGrade = s }) as_

        FuelPricePerGallonChanged s ->
            authPending (\p -> { p | fuelPricePerGallon = s }) as_

        LongNoteChanged s ->
            authPending (\p -> { p | longNote = s }) as_

        MerchantChanged s ->
            authPending (\p -> { p | merchant = s }) { as_ | duplicateWarning = Nothing }

        NoteChanged s ->
            authPending (\p -> { p | note = s }) as_

        PaymentMethodChanged pm ->
            authPending (\p -> { p | paymentMethod = pm }) as_

        SubmitEntry ->
            let
                -- Resolve the entry's location through `effectiveLocation`
                -- so that an entry with no per-entry override picks up the
                -- broadcast `currentLocation` instead of submitting with
                -- LocationIdle (= no geoPoint).
                pendingNow =
                    PendingEntry.formPending as_.form

                pendingForSubmit =
                    { pendingNow | locationState = effectiveLocation as_ pendingNow }
            in
            case PendingEntry.parseEntry pendingForSubmit of
                Ok parsed ->
                    case as_.duplicateWarning of
                        Just _ ->
                            -- User has seen the warning and clicked "Add anyway" — proceed
                            ( AuthModel { as_ | duplicateWarning = Nothing, submitting = True, error = Nothing }
                            , Task.perform (AuthMsg << GotSubmitTime parsed) Time.now
                            )

                        Nothing ->
                            -- First submit attempt — check for duplicates before proceeding
                            let
                                tripExpenses : List Expense
                                tripExpenses =
                                    case Routing.routeTripId as_.route of
                                        Just tripId ->
                                            Dict.get (TripId.toString tripId) as_.expenses
                                                |> Maybe.withDefault Dict.empty
                                                |> Dict.values

                                        Nothing ->
                                            []

                                candidateExpense : Expense
                                candidateExpense =
                                    { address = parsed.address
                                    , amount = parsed.amount
                                    , category = parsed.category
                                    , createdAt = Time.millisToPosix 0
                                    , createdBy = as_.currentUser
                                    , currency = parsed.currency
                                    , date = parsed.date
                                    , fuelDetail = parsed.fuelDetail
                                    , geoPoint = parsed.geoPoint
                                    , id = ExpenseId.fromString ""
                                    , longNote = parsed.longNote
                                    , merchant = parsed.merchant
                                    , note = parsed.note
                                    , paymentMethod = parsed.paymentMethod
                                    , tripId = Maybe.withDefault (TripId.fromString "") (Routing.routeTripId as_.route)
                                    }
                            in
                            case Expense.findLikelyDuplicate candidateExpense tripExpenses of
                                Just match ->
                                    -- Soft warning: show the match, don't submit yet
                                    ( AuthModel { as_ | duplicateWarning = Just match, error = Nothing }
                                    , Cmd.none
                                    )

                                Nothing ->
                                    ( AuthModel { as_ | submitting = True, error = Nothing }
                                    , Task.perform (AuthMsg << GotSubmitTime parsed) Time.now
                                    )

                Err errs ->
                    ( AuthModel { as_ | error = Just (String.join " " errs) }, Cmd.none )

        GotSubmitTime parsed posix ->
            let
                timestamp =
                    String.fromInt (Time.posixToMillis posix)

                updatedQueue =
                    case as_.activeScanItemId of
                        Just id ->
                            Dict.update (ScanItemId.toString id) (Maybe.map (\i -> { i | status = ScanSubmitted })) as_.scanQueue

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
            case as_.form of
                EditForm editId _ ->
                    case findEffective editId as_ of
                        Just original ->
                            let
                                amendId =
                                    AmendmentId.fromString
                                        ("amend::" ++ ExpenseId.toString original.id ++ "::" ++ String.left 8 timestamp)

                                amend =
                                    { id = amendId
                                    , targetId = original.id
                                    , address =
                                        if parsed.address /= original.address then
                                            Just parsed.address

                                        else
                                            Nothing
                                    , amount =
                                        if parsed.amount /= original.amount then
                                            Just parsed.amount

                                        else
                                            Nothing
                                    , category =
                                        if parsed.category /= original.category then
                                            Just parsed.category

                                        else
                                            Nothing
                                    , createdAt = posix
                                    , createdBy = UserId.fromString as_.creds.email
                                    , currency =
                                        if parsed.currency /= original.currency then
                                            Just parsed.currency

                                        else
                                            Nothing
                                    , date =
                                        if parsed.date /= original.date then
                                            Just parsed.date

                                        else
                                            Nothing
                                    , fuelDetail =
                                        if parsed.fuelDetail /= original.fuelDetail then
                                            parsed.fuelDetail

                                        else
                                            Nothing
                                    , longNote =
                                        if parsed.longNote /= original.longNote then
                                            Just parsed.longNote

                                        else
                                            Nothing
                                    , merchant =
                                        if parsed.merchant /= original.merchant then
                                            Just parsed.merchant

                                        else
                                            Nothing
                                    , note =
                                        if parsed.note /= original.note then
                                            Just parsed.note

                                        else
                                            Nothing
                                    , paymentMethod =
                                        if parsed.paymentMethod /= original.paymentMethod then
                                            parsed.paymentMethod

                                        else
                                            Nothing
                                    }

                                nextRoute =
                                    routeForTab nextTab original.tripId

                                editTarget =
                                    targetForTripId original.tripId as_

                                editAmountCents =
                                    amend.amount
                                        |> Maybe.map Money.toCents
                                        |> Maybe.withDefault (Money.toCents parsed.amount)

                                editAmountFloat =
                                    toFloat editAmountCents / 100
                            in
                            ( AuthModel
                                { as_
                                    | activeScanItemId = Nothing
                                    , duplicateWarning = Nothing
                                    , form = FreshForm (PendingEntry.defaultPendingEntry as_.today)
                                    , route = nextRoute
                                    , scanQueue = updatedQueue
                                    , submitting = False
                                }
                            , Cmd.batch
                                [ sendPouch (SaveAmend editTarget (Amendment.encoder amend))
                                , notifySharedTripActivity as_.config
                                    as_.creds
                                    editTarget
                                    { action = "edit"
                                    , amount = editAmountFloat
                                    , note = Nothing
                                    }
                                , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath original.tripId nextTab)
                                ]
                            )

                        Nothing ->
                            ( AuthModel { as_ | submitting = False }, Cmd.none )

                FreshForm _ ->
                    case as_.trips of
                        TripsLoaded loadedTrips ->
                            let
                                tripId =
                                    (Trips.selectedTrip loadedTrips).id

                                expenseId =
                                    "expense::" ++ Iso8601.fromPosix posix ++ "::" ++ String.left 8 timestamp

                                expense =
                                    { id = ExpenseId.fromString expenseId
                                    , tripId = tripId
                                    , address = parsed.address
                                    , amount = parsed.amount
                                    , category = parsed.category
                                    , createdAt = posix
                                    , createdBy = UserId.fromString as_.creds.email
                                    , currency = parsed.currency
                                    , date = parsed.date
                                    , fuelDetail = parsed.fuelDetail
                                    , geoPoint = parsed.geoPoint
                                    , longNote = parsed.longNote
                                    , merchant = parsed.merchant
                                    , note = parsed.note
                                    , paymentMethod = parsed.paymentMethod
                                    }

                                -- Tag the just-submitted scan item with the
                                -- deterministic expense id it will write, so
                                -- the PouchDB `ExpenseChanged` change-feed echo
                                -- can match the saved expense back to its queue
                                -- card and clear it (the echo OWNS the delete —
                                -- see `handleDbChange`). The id is only
                                -- computable here (it needs `posix`), so the
                                -- tag is stamped at `GotSubmitTime`, not
                                -- `SubmitEntry`. Only the `FreshForm` path
                                -- produces an `ExpenseChanged`; the `EditForm`
                                -- path emits `SaveAmend` (no new expense doc),
                                -- so it is intentionally OUT of scope for the
                                -- echo-delete and never tags `expectedExpenseId`.
                                taggedQueue =
                                    case as_.activeScanItemId of
                                        Just id ->
                                            Dict.update (ScanItemId.toString id)
                                                (Maybe.map (\i -> { i | expectedExpenseId = Just expenseId }))
                                                updatedQueue

                                        Nothing ->
                                            updatedQueue

                                persistTagCmd : Cmd Msg
                                persistTagCmd =
                                    case as_.activeScanItemId of
                                        Just id ->
                                            Dict.get (ScanItemId.toString id) taggedQueue
                                                |> Maybe.map (Ports.saveScanItem << Data.Scan.scanItemEncoder)
                                                |> Maybe.withDefault Cmd.none

                                        Nothing ->
                                            Cmd.none

                                nextRoute =
                                    routeForTab nextTab tripId

                                addTarget =
                                    targetForTripId tripId as_

                                addAmountFloat =
                                    toFloat (Money.toCents expense.amount) / 100
                            in
                            ( AuthModel
                                { as_
                                    | activeScanItemId = Nothing
                                    , duplicateWarning = Nothing
                                    , form = FreshForm (PendingEntry.defaultPendingEntry as_.today)
                                    , route = nextRoute
                                    , scanQueue = taggedQueue
                                    , submitting = False
                                }
                            , Cmd.batch
                                [ sendPouch (SaveExpense addTarget (Expense.encoder expense))
                                , persistTagCmd
                                , notifySharedTripActivity as_.config
                                    as_.creds
                                    addTarget
                                    { action = "add"
                                    , amount = addAmountFloat
                                    , note = Just expense.note
                                    }
                                , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath tripId nextTab)
                                ]
                            )

                        _ ->
                            ( AuthModel { as_ | submitting = False }, Cmd.none )

        GotSyncTime posix ->
            ( AuthModel { as_ | lastSyncedAt = Just posix }, Cmd.none )

        VoidEntry expense ->
            ( AuthModel { as_ | openLedgerMenu = Nothing }
            , Task.perform (AuthMsg << GotVoidTime expense) Time.now
            )

        GotVoidTime expense posix ->
            let
                voidId =
                    "void::" ++ ExpenseId.toString expense.id ++ "::del"

                createdAtIso =
                    Iso8601.fromPosix posix

                createdBy =
                    UserId.fromString as_.creds.email

                -- Optimistic: insert the void into the cache locally so
                -- Entry.resolve filters out this expense immediately.
                -- Sync DbChange will be a no-op (same id).
                optimisticVoid =
                    { id = voidId
                    , targetId = ExpenseId.toString expense.id
                    , createdAt = createdAtIso
                    , createdBy = createdBy
                    }

                voidTarget =
                    targetForTripId expense.tripId as_

                voidAmountFloat =
                    toFloat (Money.toCents expense.amount) / 100
            in
            ( AuthModel { as_ | voids = Dict.insert voidId optimisticVoid as_.voids }
            , Cmd.batch
                [ sendPouch
                    (SaveVoid voidTarget
                        (E.object
                            [ ( "_id", E.string voidId )
                            , ( "targetId", E.string (ExpenseId.toString expense.id) )
                            , ( "createdAt", E.string createdAtIso )
                            , ( "createdBy", UserId.encode createdBy )
                            , ( "type", E.string "void" )
                            ]
                        )
                    )
                , notifySharedTripActivity as_.config
                    as_.creds
                    voidTarget
                    { action = "void"
                    , amount = voidAmountFloat
                    , note = Nothing
                    }
                ]
            )

        DuplicateEntry expense ->
            ( AuthModel { as_ | openLedgerMenu = Nothing }
            , Task.perform (AuthMsg << GotDuplicateTime expense) Time.now
            )

        GotDuplicateTime expense posix ->
            let
                timestamp =
                    String.fromInt (Time.posixToMillis posix)

                newId =
                    ExpenseId.fromString
                        ("expense::" ++ Iso8601.fromPosix posix ++ "::" ++ String.left 8 timestamp)

                duplicate =
                    Expense.snapshotWith
                        { id = newId
                        , createdAt = posix
                        , tripId = expense.tripId
                        }
                        expense

                tripKey =
                    TripId.toString expense.tripId

                tripBucket =
                    Dict.get tripKey as_.expenses |> Maybe.withDefault Dict.empty

                updatedExpenses =
                    Dict.insert tripKey
                        (Dict.insert (ExpenseId.toString newId) duplicate tripBucket)
                        as_.expenses
            in
            ( AuthModel
                { as_
                    | expenses = updatedExpenses
                    , toast = Just "Duplicated"
                }
            , Cmd.batch
                [ sendPouch (SaveExpense (targetForTripId duplicate.tripId as_) (Expense.encoder duplicate))
                , toastFor
                ]
            )

        OpenLedgerMenu expenseId ->
            ( AuthModel { as_ | openLedgerMenu = Just expenseId }, Cmd.none )

        CloseLedgerMenu ->
            ( AuthModel { as_ | openLedgerMenu = Nothing }, Cmd.none )

        OpenMovePicker expense ->
            ( AuthModel
                { as_
                    | movePicker = Just expense
                    , openLedgerMenu = Nothing
                }
            , Cmd.none
            )

        CloseMovePicker ->
            ( AuthModel { as_ | movePicker = Nothing }, Cmd.none )

        OpenShareModal ->
            -- Kick off a geolocation request so the printable sticker can
            -- stamp the user's actual GPS coords (not Cloudflare's IP geo,
            -- which can be states away on mobile data). GotGpsCoords
            -- writes to `as_.currentLocation` — the single broadcast for
            -- device location, shared by ShareModal and the Add/Edit
            -- form's location widget.
            --
            -- If we already have a cached fix, leave it visible (Add page
            -- is reading the same field and a flicker-to-Resolving would
            -- blink its widget); the fresh result will overlay when it
            -- arrives. Only flip to Resolving when we genuinely don't
            -- have anything yet.
            let
                nextLocation =
                    case as_.currentLocation of
                        LocationGot _ _ ->
                            as_.currentLocation

                        _ ->
                            LocationResolving
            in
            ( AuthModel { as_ | currentLocation = nextLocation, shareModalOpen = True }
            , Ports.requestGeolocation ()
            )

        CloseShareModal ->
            ( AuthModel { as_ | shareModalOpen = False }, Cmd.none )

        ShareViaNative mode ->
            let
                slug =
                    "user-" ++ UserId.shortHash as_.currentUser

                shareUrl =
                    as_.config.backendUrl ++ "/qr/" ++ slug ++ "?via=share"

                modeStr =
                    case mode of
                        AutoShare ->
                            "auto"

                        ForceCopy ->
                            "copy"
            in
            ( AuthModel as_
            , Ports.nativeShare
                { mode = modeStr
                , title = "Ternpike"
                , text = "I'm using Ternpike to track expenses on the road — it pays for itself. Check it out:"
                , url = shareUrl
                }
            )

        ShareResultReceived { reason } ->
            case reason of
                "native" ->
                    -- OS share sheet was its own feedback; no toast.
                    ( AuthModel as_, Cmd.none )

                "clipboard" ->
                    ( AuthModel { as_ | toast = Just "Link copied" }, toastFor )

                "cancelled" ->
                    ( AuthModel as_, Cmd.none )

                _ ->
                    ( AuthModel { as_ | toast = Just "Couldn't share — try the QR" }, toastFor )

        MoveEntry expense newTripId ->
            if newTripId == expense.tripId then
                ( AuthModel { as_ | movePicker = Nothing }, Cmd.none )

            else
                ( AuthModel { as_ | movePicker = Nothing }
                , Task.perform (AuthMsg << GotMoveTime expense newTripId) Time.now
                )

        GotMoveTime expense newTripId posix ->
            let
                timestamp =
                    String.fromInt (Time.posixToMillis posix)

                newExpenseId =
                    ExpenseId.fromString
                        ("expense::" ++ Iso8601.fromPosix posix ++ "::" ++ String.left 8 timestamp)

                moved =
                    Expense.snapshotWith
                        { id = newExpenseId
                        , createdAt = posix
                        , tripId = newTripId
                        }
                        expense

                voidId =
                    "void::" ++ ExpenseId.toString expense.id ++ "::del"

                createdAtIso =
                    Iso8601.fromPosix posix

                createdBy =
                    UserId.fromString as_.creds.email

                optimisticVoid =
                    { id = voidId
                    , targetId = ExpenseId.toString expense.id
                    , createdAt = createdAtIso
                    , createdBy = createdBy
                    }

                destKey =
                    TripId.toString newTripId

                destBucket =
                    Dict.get destKey as_.expenses |> Maybe.withDefault Dict.empty

                updatedExpenses =
                    Dict.insert destKey
                        (Dict.insert (ExpenseId.toString newExpenseId) moved destBucket)
                        as_.expenses

                destPath =
                    Routing.tabToPath as_.basePath newTripId LedgerTab
            in
            ( AuthModel
                { as_
                    | expenses = updatedExpenses
                    , toast = Just "Moved"
                    , voids = Dict.insert voidId optimisticVoid as_.voids
                }
            , Cmd.batch
                [ sendPouch
                    (SaveVoid (targetForTripId expense.tripId as_)
                        (E.object
                            [ ( "_id", E.string voidId )
                            , ( "targetId", E.string (ExpenseId.toString expense.id) )
                            , ( "createdAt", E.string createdAtIso )
                            , ( "createdBy", UserId.encode createdBy )
                            , ( "type", E.string "void" )
                            ]
                        )
                    )
                , sendPouch (SaveExpense (targetForTripId moved.tripId as_) (Expense.encoder moved))
                , Nav.pushUrl as_.key destPath
                , toastFor
                ]
            )

        CloseTripForm ->
            ( AuthModel { as_ | tripForm = Nothing }, Cmd.none )

        ReconcileMileposts now ->
            reconcileMileposts now as_

        RefreshClicked ->
            case Routing.routeTripId as_.route of
                Just tid ->
                    ( AuthModel
                        { as_
                            | loadingTrips = Set.insert (TripId.toString tid) as_.loadingTrips
                            , tripLoaded = Set.remove (TripId.toString tid) as_.tripLoaded
                        }
                    , sendPouch (GetTripExpenses (targetForTripId tid as_) tid)
                    )

                Nothing ->
                    ( AuthModel as_, Cmd.none )

        DismissError ->
            ( AuthModel { as_ | error = Nothing }, Cmd.none )

        GotGpsCoords lat lon ->
            -- Single broadcast: device location lives on `currentLocation`
            -- and is read by both consumers (the Add/Edit form's location
            -- widget via `effectiveLocation`, and the ShareModal's print
            -- URL builder). No per-consumer storage; the entry's own
            -- `locationState` only diverges from currentLocation when the
            -- user explicitly overrides via map picker, EXIF, or skip.
            ( AuthModel { as_ | currentLocation = LocationGot (GeoPoint.fromDegrees lat lon) BrowserGeo }
            , Cmd.none
            )

        GeolocationDenied ->
            -- `geoBlocked` gates whether to keep auto-requesting on every
            -- Add navigation; `currentLocation = LocationIdle` tells the
            -- view "no device location available, fall back to per-entry
            -- override UI (pin / skip)".
            ( AuthModel { as_ | currentLocation = LocationIdle, geoBlocked = True }
            , Cmd.none
            )

        OpenMapPicker ->
            ( AuthModel { as_ | showMapPicker = True }, Cmd.none )

        MapPickerConfirmed lat lon ->
            ( AuthModel { as_ | form = PendingEntry.mapForm (PendingEntry.setLocation (LocationGot (GeoPoint.fromDegrees lat lon) ManualPin)) as_.form, showMapPicker = False }
            , Cmd.none
            )

        DismissMapPicker ->
            ( AuthModel { as_ | showMapPicker = False }, Cmd.none )

        SkipLocation ->
            ( AuthModel { as_ | form = PendingEntry.mapForm (PendingEntry.setLocation LocationSkipped) as_.form, showMapPicker = False }
            , Cmd.none
            )

        ToggleDayIntensity ->
            ( AuthModel { as_ | showDayIntensity = not as_.showDayIntensity }, Cmd.none )

        ToggleLedgerMap ->
            let
                nextShow =
                    not as_.showLedgerMap
            in
            -- Always collapse back to small when the map is hidden, so
            -- the next time the user opens it they start at the
            -- compact 260-px size — discoverability beats remembering
            -- the previous expanded state.
            ( AuthModel
                { as_
                    | showLedgerMap = nextShow
                    , ledgerMapExpanded =
                        if nextShow then
                            as_.ledgerMapExpanded

                        else
                            False
                }
            , Cmd.none
            )

        ToggleLedgerMapExpanded ->
            ( AuthModel { as_ | ledgerMapExpanded = not as_.ledgerMapExpanded }, Cmd.none )

        SetStatsGranularity g ->
            ( AuthModel { as_ | statsGranularity = Just g }, Cmd.none )

        ToastExpired ->
            ( AuthModel { as_ | toast = Nothing }, Cmd.none )

        DismissMilepostToast ->
            let
                -- Drop the celebrated head. If markers remain, re-arm the
                -- auto-advance timer so the next one dismisses on its own too.
                remaining : List Milepost.Marker
                remaining =
                    List.drop 1 as_.milepostToasts

                cmd : Cmd Msg
                cmd =
                    if List.isEmpty remaining then
                        Cmd.none

                    else
                        milepostToastFor
            in
            ( AuthModel { as_ | milepostToasts = remaining }, cmd )

        OpenNewTripForm ->
            ( AuthModel
                { as_
                    | tripForm =
                        Just
                            { budget = ""
                            , coverPhotoUrl = ""
                            , description = ""
                            , editing = Nothing
                            , endDate = ""
                            , errors = []
                            , groupNameOverridden = False
                            , name = ""
                            , sharedTripRequest = RemoteData.NotAsked
                            , startDate = DateField.toIso as_.today
                            , submitting = False
                            , target = Trip.ToPersonal
                            }
                }
            , Cmd.none
            )

        OpenEditTripForm trip ->
            ( AuthModel
                { as_
                    | tripForm =
                        Just
                            { budget =
                                if Money.isZero trip.budget then
                                    ""

                                else
                                    Money.toDollarString trip.budget
                            , coverPhotoUrl = trip.coverPhotoUrl
                            , description = trip.description
                            , editing = Just trip
                            , endDate = DateField.toIso trip.endDate
                            , errors = []
                            , groupNameOverridden = False
                            , name = trip.name
                            , sharedTripRequest = RemoteData.NotAsked
                            , startDate = DateField.toIso trip.startDate
                            , submitting = False
                            , target =
                                case Trip.targetForTrip trip of
                                    Trip.InFlock fid ->
                                        Trip.ToExistingFlock fid

                                    Trip.Personal ->
                                        Trip.ToPersonal
                            }
                }
            , Cmd.none
            )

        TripFieldChanged field value ->
            let
                updateForm f =
                    case field of
                        TripBudget ->
                            { f | budget = value }

                        TripCoverPhoto ->
                            { f | coverPhotoUrl = value }

                        TripDescription ->
                            { f | description = value }

                        TripEndDate ->
                            { f | endDate = value }

                        TripName ->
                            { f | name = value }

                        TripStartDate ->
                            { f | startDate = value }
            in
            ( AuthModel { as_ | tripForm = Maybe.map updateForm as_.tripForm }, Cmd.none )

        TripTargetSelected target ->
            ( AuthModel
                { as_
                    | tripForm =
                        Maybe.map (\f -> { f | target = target }) as_.tripForm
                }
            , Cmd.none
            )

        TripGroupNameChanged value ->
            ( AuthModel
                { as_
                    | tripForm =
                        Maybe.map
                            (\f ->
                                case f.target of
                                    Trip.ToNewFlock draft ->
                                        { f
                                            | groupNameOverridden = True
                                            , target = Trip.ToNewFlock { draft | groupName = value }
                                        }

                                    _ ->
                                        f
                            )
                            as_.tripForm
                }
            , Cmd.none
            )

        TripInviteeDraftChanged value ->
            ( AuthModel
                { as_
                    | tripForm =
                        Maybe.map
                            (\f ->
                                case f.target of
                                    Trip.ToNewFlock draft ->
                                        { f | target = Trip.ToNewFlock { draft | inviteesDraft = value } }

                                    _ ->
                                        f
                            )
                            as_.tripForm
                }
            , Cmd.none
            )

        TripInviteeAdded ->
            ( AuthModel
                { as_
                    | tripForm =
                        Maybe.map
                            (\f ->
                                case f.target of
                                    Trip.ToNewFlock draft ->
                                        let
                                            trimmed =
                                                String.trim draft.inviteesDraft
                                        in
                                        if trimmed == "" || List.member trimmed draft.invitees then
                                            { f | target = Trip.ToNewFlock { draft | inviteesDraft = "" } }

                                        else
                                            { f
                                                | target =
                                                    Trip.ToNewFlock
                                                        { draft
                                                            | invitees = draft.invitees ++ [ trimmed ]
                                                            , inviteesDraft = ""
                                                        }
                                            }

                                    _ ->
                                        f
                            )
                            as_.tripForm
                }
            , Cmd.none
            )

        TripInviteeRemoved index ->
            ( AuthModel
                { as_
                    | tripForm =
                        Maybe.map
                            (\f ->
                                case f.target of
                                    Trip.ToNewFlock draft ->
                                        { f
                                            | target =
                                                Trip.ToNewFlock
                                                    { draft
                                                        | invitees =
                                                            List.indexedMap Tuple.pair draft.invitees
                                                                |> List.filter (\( i, _ ) -> i /= index)
                                                                |> List.map Tuple.second
                                                    }
                                        }

                                    _ ->
                                        f
                            )
                            as_.tripForm
                }
            , Cmd.none
            )

        TripCreateSharedTripResult result ->
            case as_.tripForm of
                Nothing ->
                    ( AuthModel as_, Cmd.none )

                Just form ->
                    case RemoteData.fromResult result of
                        RemoteData.NotAsked ->
                            ( AuthModel as_, Cmd.none )

                        RemoteData.Loading ->
                            ( AuthModel as_, Cmd.none )

                        RemoteData.Failure err ->
                            ( AuthModel
                                { as_
                                    | tripForm =
                                        Just
                                            { form
                                                | sharedTripRequest = RemoteData.Failure err
                                                , submitting = False
                                            }
                                }
                            , Cmd.none
                            )

                        RemoteData.Success response ->
                            let
                                invitees =
                                    case form.target of
                                        Trip.ToNewFlock draft ->
                                            draft.invitees

                                        _ ->
                                            []

                                inviteCmds =
                                    List.map
                                        (\email ->
                                            Http.SharedTripApi.inviteToSharedTrip
                                                as_.config
                                                as_.creds
                                                response.sharedTripId
                                                { email = email }
                                                (\_ -> AuthMsg TripInviteResult)
                                        )
                                        invitees

                                updatedForm =
                                    { form
                                        | sharedTripRequest = RemoteData.Success response
                                        , target = Trip.ToExistingFlock response.sharedTripId
                                    }
                            in
                            ( AuthModel { as_ | tripForm = Just updatedForm }
                            , Cmd.batch
                                ([ sendPouch
                                    (OpenSharedTrip
                                        { flockId = response.sharedTripId
                                        , dbName = "sharedtrip-" ++ Data.SharedTripId.toString response.sharedTripId
                                        }
                                    )
                                 , Task.perform (AuthMsg << GotSaveTripTime) Time.now
                                 ]
                                    ++ inviteCmds
                                )
                            )

        TripInviteResult ->
            -- Fire-and-forget. Invites can't block trip creation — partial
            -- success is OK (the user can re-invite from Settings on any
            -- specific failures). Failures get a console line for now;
            -- a follow-up could surface a small "1 of 3 invites failed"
            -- toast.
            ( AuthModel as_, Cmd.none )

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
                                                | budget = parseFormBudget form.budget
                                                , coverPhotoUrl = form.coverPhotoUrl
                                                , description = form.description
                                                , endDate = parseFormDate form.endDate
                                                , name = form.name
                                                , startDate = parseFormDate form.startDate
                                            }
                                    in
                                    ( AuthModel { as_ | tripForm = Nothing, trips = upsertTripIntoState updated as_.trips }
                                    , sendPouch (SaveTrip (Trip.targetForTrip updated) (Trip.encoder updated))
                                    )

                                Nothing ->
                                    case form.target of
                                        Trip.ToNewFlock draft ->
                                            -- New shared trip: create the flock server-side first,
                                            -- then the response handler chains invites + trip write.
                                            let
                                                groupName =
                                                    if form.groupNameOverridden && String.trim draft.groupName /= "" then
                                                        String.trim draft.groupName

                                                    else
                                                        String.trim form.name
                                            in
                                            ( AuthModel { as_ | tripForm = Just { form | errors = [], sharedTripRequest = RemoteData.Loading, submitting = True } }
                                            , Http.SharedTripApi.createSharedTrip as_.config as_.creds { name = groupName } (AuthMsg << TripCreateSharedTripResult)
                                            )

                                        _ ->
                                            -- Personal / existing-flock: same path as before, get a
                                            -- timestamp then write the trip.
                                            ( AuthModel { as_ | tripForm = Just { form | submitting = True } }
                                            , Task.perform (AuthMsg << GotSaveTripTime) Time.now
                                            )

        GotSaveTripTime posix ->
            case as_.tripForm of
                Nothing ->
                    ( AuthModel as_, Cmd.none )

                Just form ->
                    let
                        timestamp =
                            String.fromInt (Time.posixToMillis posix)

                        tripId =
                            TripId.fromString ("trip::" ++ Iso8601.fromPosix posix ++ "::" ++ String.left 8 timestamp)

                        ( newFlockId, target ) =
                            case form.target of
                                Trip.ToExistingFlock fid ->
                                    ( Just fid, Trip.InFlock fid )

                                Trip.ToPersonal ->
                                    ( Nothing, Trip.Personal )

                                Trip.ToNewFlock _ ->
                                    -- Should be impossible — SaveTripForm rewrites the target
                                    -- to ToExistingFlock before this code path runs. Defensive
                                    -- fallback to Personal so a coding regression doesn't crash.
                                    ( Nothing, Trip.Personal )

                        newTrip =
                            { budget = parseFormBudget form.budget
                            , coverPhotoUrl = form.coverPhotoUrl
                            , description = form.description
                            , endDate = parseFormDate form.endDate
                            , flockId = newFlockId
                            , id = tripId
                            , name = form.name
                            , startDate = parseFormDate form.startDate
                            }

                        newTrips =
                            case as_.trips of
                                TripsLoaded trips ->
                                    TripsLoaded (Trips.selectTrip tripId (Trips.upsertTrip newTrip trips))

                                _ ->
                                    TripsLoaded (Trips.singleton newTrip)
                    in
                    ( AuthModel
                        { as_
                            | form = FreshForm (PendingEntry.defaultPendingEntry as_.today)
                            , route = RouteLedger tripId
                            , tripForm = Nothing
                            , tripLoaded = Set.insert (TripId.toString tripId) as_.tripLoaded
                            , trips = newTrips
                        }
                    , Cmd.batch
                        [ sendPouch (SaveTrip target (Trip.encoder newTrip))
                        , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath tripId LedgerTab)
                        ]
                    )

        ConfirmDeleteTrip trip ->
            ( AuthModel { as_ | confirmDeleteTrip = Just trip }, Cmd.none )

        CancelDeleteTrip ->
            ( AuthModel { as_ | confirmDeleteTrip = Nothing }, Cmd.none )

        DeleteTrip trip ->
            -- Local-state transitions (selection / route) happen
            -- immediately; the void tombstone's `createdAt` is filled in
            -- by GotDeleteTripTime once the runtime hands us a real
            -- `Time.Posix` instant.
            case removeTripFromState trip.id as_.trips of
                TripsLoaded trips ->
                    let
                        nextHead =
                            Trips.selectedTrip trips
                    in
                    ( AuthModel
                        { as_
                            | confirmDeleteTrip = Nothing
                            , route = RouteLedger nextHead.id
                            , trips = TripsLoaded trips
                        }
                    , Cmd.batch
                        [ Task.perform (AuthMsg << GotDeleteTripTime trip) Time.now
                        , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath nextHead.id LedgerTab)
                        ]
                    )

                NoTripsYet ->
                    ( AuthModel
                        { as_
                            | confirmDeleteTrip = Nothing
                            , route = RouteTrips
                            , trips = NoTripsYet
                        }
                    , Cmd.batch
                        [ Task.perform (AuthMsg << GotDeleteTripTime trip) Time.now
                        , Nav.pushUrl as_.key (as_.basePath ++ "trips")
                        ]
                    )

                other ->
                    ( AuthModel { as_ | confirmDeleteTrip = Nothing, trips = other }
                    , Task.perform (AuthMsg << GotDeleteTripTime trip) Time.now
                    )

        GotDeleteTripTime trip posix ->
            let
                voidId =
                    "void::" ++ TripId.toString trip.id ++ "::del"

                createdAtIso =
                    Iso8601.fromPosix posix
            in
            ( AuthModel as_
            , sendPouch
                (SaveVoid (Trip.targetForTrip trip)
                    (E.object
                        [ ( "_id", E.string voidId )
                        , ( "targetId", E.string (TripId.toString trip.id) )
                        , ( "createdAt", E.string createdAtIso )
                        , ( "createdBy", UserId.encode (UserId.fromString as_.creds.email) )
                        , ( "type", E.string "void" )
                        ]
                    )
                )
            )

        HoverCumulativePoints items ->
            ( AuthModel { as_ | statsHover = StatsHover.setCumulative as_.statsHover items }
            , Cmd.none
            )

        HoverDailyBars items ->
            ( AuthModel { as_ | statsHover = StatsHover.setDaily as_.statsHover items }
            , Cmd.none
            )

        HoverPricePerGallonPoints items ->
            ( AuthModel { as_ | statsHover = StatsHover.setPricePerGallon as_.statsHover items }
            , Cmd.none
            )

        CanInstall canIt ->
            ( AuthModel { as_ | showInstallPrompt = canIt }, Cmd.none )

        TriggerInstallPrompt ->
            ( AuthModel as_, Ports.triggerInstallPrompt () )

        -- Post-join retention (#338). The one-time card on the member
        -- landing reuses the existing PWA plumbing: the "Add" button is
        -- `TriggerInstallPrompt` (the same outbound `Ports.triggerInstallPrompt`
        -- port Settings uses), "Not now" / "Got it" is
        -- `DismissPostJoinPrompt`, and "Turn on alerts" (offered only when
        -- the app is already standalone) is `EnableCrewPush`.
        DismissPostJoinPrompt ->
            ( AuthModel { as_ | postJoinPrompt = False }, Cmd.none )

        -- Default the `sharedTripActivity` pref on and request push.
        -- Reuses `Ports.subscribePush` (the JS handler requests browser
        -- permission first, then subscribes inside the same user-gesture
        -- chain — see RequestPushPermission for why we don't batch
        -- permission + subscribe). Mirrors the new pref optimistically so
        -- the toggle in Settings reflects it immediately. Dismisses the
        -- card so it never re-shows.
        EnableCrewPush ->
            let
                oldPrefs : Notifications.NotificationPrefs
                oldPrefs =
                    as_.notificationPrefs

                newPrefs : Notifications.NotificationPrefs
                newPrefs =
                    { oldPrefs | sharedTripActivity = True }
            in
            ( AuthModel { as_ | notificationPrefs = newPrefs, postJoinPrompt = False }
            , Ports.subscribePush
                { prefs = Notifications.encodePrefs newPrefs
                , vapidPublicKey = as_.config.vapidPublicKey
                }
            )

        TakeOverBilling flockId ->
            ( AuthModel as_
            , Http.SharedTripApi.transferOwnership
                as_.config
                as_.creds
                flockId
                { newOwnerEmail = as_.creds.email }
                (AuthMsg << TransferToSharedTripResult)
            )

        -- FLOCK MODAL MESSAGES
        CloseSharedTripModal ->
            ( AuthModel (setSharedTripModal SharedTripUi.NoModal as_), Cmd.none )

        ToggleSharedTripMembers flockId ->
            let
                ui =
                    as_.sharedTripUi
            in
            ( AuthModel { as_ | sharedTripUi = SharedTripUi.toggleExpanded flockId ui }
            , Cmd.none
            )

        OpenShareTripModal trip ->
            ( AuthModel { as_ | sharedTripUi = SharedTripUi.openShareTrip trip.id trip.name as_.sharedTripUi }
            , Cmd.none
            )

        ShareTripGroupNameChanged value ->
            ( AuthModel { as_ | sharedTripUi = SharedTripUi.mapShareDraft (\d -> { d | groupName = value }) as_.sharedTripUi }
            , Cmd.none
            )

        ShareTripInviteeDraftChanged value ->
            ( AuthModel { as_ | sharedTripUi = SharedTripUi.mapShareDraft (\d -> { d | inviteesDraft = value }) as_.sharedTripUi }
            , Cmd.none
            )

        ShareTripInviteeAdded ->
            ( AuthModel
                { as_
                    | sharedTripUi =
                        SharedTripUi.mapShareDraft
                            (\d ->
                                let
                                    trimmed =
                                        String.trim d.inviteesDraft
                                in
                                if trimmed == "" || List.member trimmed d.invitees then
                                    { d | inviteesDraft = "" }

                                else
                                    { d | invitees = d.invitees ++ [ trimmed ], inviteesDraft = "" }
                            )
                            as_.sharedTripUi
                }
            , Cmd.none
            )

        ShareTripInviteeRemoved index ->
            ( AuthModel
                { as_
                    | sharedTripUi =
                        SharedTripUi.mapShareDraft
                            (\d ->
                                { d
                                    | invitees =
                                        List.indexedMap Tuple.pair d.invitees
                                            |> List.filter (\( i, _ ) -> i /= index)
                                            |> List.map Tuple.second
                                }
                            )
                            as_.sharedTripUi
                }
            , Cmd.none
            )

        SubmitShareTrip ->
            case as_.sharedTripUi.modal of
                SharedTripUi.ShareTripModal _ { draft } ->
                    if not (Tier.isPaid as_.tier) then
                        -- Tern: the modal shows an upgrade prompt; submit is inert.
                        ( AuthModel as_, Cmd.none )

                    else if String.trim draft.groupName == "" then
                        ( AuthModel
                            (updateModalRequest
                                (\m ->
                                    case m of
                                        SharedTripUi.ShareTripModal tid data ->
                                            Just (SharedTripUi.ShareTripModal tid { data | request = RemoteData.Failure (Http.BadBody "Name is required.") })

                                        _ ->
                                            Nothing
                                )
                                as_
                            )
                        , Cmd.none
                        )

                    else
                        ( AuthModel
                            (updateModalRequest
                                (\m ->
                                    case m of
                                        SharedTripUi.ShareTripModal tid data ->
                                            Just (SharedTripUi.ShareTripModal tid { data | request = RemoteData.Loading })

                                        _ ->
                                            Nothing
                                )
                                as_
                            )
                        , Http.SharedTripApi.createSharedTrip as_.config as_.creds { name = String.trim draft.groupName } (AuthMsg << ShareTripCreatedResult)
                        )

                _ ->
                    ( AuthModel as_, Cmd.none )

        ShareTripCreatedResult result ->
            case as_.sharedTripUi.modal of
                SharedTripUi.ShareTripModal tripId { draft } ->
                    case RemoteData.fromResult result of
                        RemoteData.Success response ->
                            -- Shared trip created. Open its handle, move the existing
                            -- trip's docs into it (adopt), and fan out invites. The
                            -- modal stays in Loading until ShareTripAdoptResult lands.
                            let
                                inviteCmds =
                                    List.map
                                        (\email ->
                                            Http.SharedTripApi.inviteToSharedTrip
                                                as_.config
                                                as_.creds
                                                response.sharedTripId
                                                { email = email }
                                                (\_ -> AuthMsg TripInviteResult)
                                        )
                                        draft.invitees
                            in
                            ( AuthModel as_
                            , Cmd.batch
                                ([ sendPouch
                                    (OpenSharedTrip
                                        { flockId = response.sharedTripId
                                        , dbName = "sharedtrip-" ++ Data.SharedTripId.toString response.sharedTripId
                                        }
                                    )
                                 , Http.SharedTripApi.adoptTrip
                                    as_.config
                                    as_.creds
                                    response.sharedTripId
                                    { tripId = TripId.toString tripId }
                                    (AuthMsg << ShareTripAdoptResult)
                                 ]
                                    ++ inviteCmds
                                )
                            )

                        remote ->
                            ( AuthModel
                                (updateModalRequest
                                    (\m ->
                                        case m of
                                            SharedTripUi.ShareTripModal tid data ->
                                                Just (SharedTripUi.ShareTripModal tid { data | request = RemoteData.map (\_ -> ()) remote })

                                            _ ->
                                                Nothing
                                    )
                                    as_
                                )
                            , Cmd.none
                            )

                _ ->
                    ( AuthModel as_, Cmd.none )

        ShareTripAdoptResult result ->
            case result of
                Ok () ->
                    -- Don't optimistically touch the trip: the personal handle's
                    -- DbDeleted (server hard-deleted the originals) and the shared
                    -- handle's DbChange (re-adds tagged with the flockId) settle it.
                    ( AuthModel
                        (setSharedTripModal SharedTripUi.NoModal
                            { as_ | toast = Just "Trip shared. Syncing to everyone…" }
                        )
                    , toastFor
                    )

                Err err ->
                    ( AuthModel
                        (updateModalRequest
                            (\m ->
                                case m of
                                    SharedTripUi.ShareTripModal tid data ->
                                        Just (SharedTripUi.ShareTripModal tid { data | request = RemoteData.Failure err })

                                    _ ->
                                        Nothing
                            )
                            as_
                        )
                    , Cmd.none
                    )

        BillingCheckoutClicked plan ->
            ( AuthModel { as_ | billingCheckout = RemoteData.Loading }
            , Http.Billing.checkout as_.config as_.creds { plan = plan } (AuthMsg << BillingCheckoutResult)
            )

        BillingCheckoutResult result ->
            let
                existingTotal =
                    case as_.trailblazerStatus of
                        RemoteData.Success s ->
                            s.total

                        _ ->
                            500

                ( newCheckout, newTrailblazerStatus, cmd ) =
                    case result of
                        Ok { url } ->
                            ( RemoteData.NotAsked, as_.trailblazerStatus, Nav.load url )

                        Err Http.Billing.CheckoutSoldOut ->
                            ( RemoteData.Failure Http.Billing.CheckoutSoldOut
                            , RemoteData.Success { available = 0, total = existingTotal }
                            , Cmd.none
                            )

                        Err Http.Billing.CheckoutAlreadyTrailblazer ->
                            ( RemoteData.Failure Http.Billing.CheckoutAlreadyTrailblazer, as_.trailblazerStatus, Cmd.none )

                        Err (Http.Billing.CheckoutError detail) ->
                            -- `detail` is a short HTTP-status / network blurb from the
                            -- HTTP layer (e.g. "Checkout failed (HTTP 502)"). We render
                            -- the friendly preamble and append the technical detail so
                            -- a stuck user has something to copy-paste into a support
                            -- email without needing devtools.
                            ( RemoteData.Failure (Http.Billing.CheckoutError detail), as_.trailblazerStatus, Cmd.none )
            in
            ( AuthModel
                { as_
                    | billingCheckout = newCheckout
                    , trailblazerStatus = newTrailblazerStatus
                }
            , cmd
            )

        BillingPortalClicked ->
            ( AuthModel { as_ | billingPortal = RemoteData.Loading }
            , Http.Billing.portal as_.config as_.creds (AuthMsg << BillingPortalResult)
            )

        BillingPortalResult result ->
            let
                ( newPortal, cmd ) =
                    case result of
                        Ok { url } ->
                            ( RemoteData.NotAsked, Nav.load url )

                        Err err ->
                            ( RemoteData.Failure err, Cmd.none )
            in
            ( AuthModel { as_ | billingPortal = newPortal }
            , cmd
            )

        TrailblazerStatusFetched result ->
            ( AuthModel { as_ | trailblazerStatus = RemoteData.fromResult result }, Cmd.none )

        MeFetched (Ok me) ->
            let
                oldCreds =
                    as_.creds

                refreshedCreds =
                    { oldCreds
                        | subscriptionStatus = me.subscriptionStatus
                        , tier = me.tier
                        , trailblazerNumber = me.trailblazerNumber
                    }
            in
            ( AuthModel
                { as_
                    | creds = refreshedCreds
                    , subscriptionStatus = me.subscriptionStatus
                    , tier = me.tier
                    , trailblazerNumber = me.trailblazerNumber
                }
            , Ports.saveStorage { key = "auth_creds", value = E.encode 0 (Codec.encodeCreds refreshedCreds) }
            )

        MeFetched (Err _) ->
            -- Silent failure — /me is a refresh path, not a hard
            -- requirement. The next call (next startup, next post-
            -- checkout return) will retry. The cached `Creds` tier is
            -- already good enough to keep rendering until then.
            ( AuthModel as_, Cmd.none )

        RatesFetched (Ok table) ->
            persistRates table as_
                |> Tuple.mapFirst AuthModel

        RatesFetched (Err _) ->
            -- Silent — the estimate is a convenience. Fall back to whatever
            -- rates are already cached in the synced settings doc (possibly
            -- from another device or a prior online session); retry next boot.
            ( AuthModel as_, Cmd.none )

        OpenInviteModal flockId ->
            ( AuthModel (setSharedTripModal (SharedTripUi.InviteModal flockId { email = "", request = RemoteData.NotAsked }) as_)
            , Cmd.none
            )

        InviteEmailChanged email ->
            let
                ui =
                    as_.sharedTripUi
            in
            case ui.modal of
                SharedTripUi.InviteModal id m ->
                    ( AuthModel { as_ | sharedTripUi = { ui | modal = SharedTripUi.InviteModal id { m | email = email } } }
                    , Cmd.none
                    )

                _ ->
                    ( AuthModel as_, Cmd.none )

        SubmitInvite ->
            case as_.sharedTripUi.modal of
                SharedTripUi.InviteModal flockId { email } ->
                    ( AuthModel
                        (updateModalRequest
                            (\m ->
                                case m of
                                    SharedTripUi.InviteModal id data ->
                                        Just (SharedTripUi.InviteModal id { data | request = RemoteData.Loading })

                                    _ ->
                                        Nothing
                            )
                            as_
                        )
                    , Http.SharedTripApi.inviteToSharedTrip as_.config as_.creds flockId { email = email } (AuthMsg << InviteToSharedTripResult)
                    )

                _ ->
                    ( AuthModel as_, Cmd.none )

        InviteToSharedTripResult result ->
            case RemoteData.fromResult result of
                RemoteData.Success _ ->
                    ( AuthModel
                        (setSharedTripModal SharedTripUi.NoModal
                            { as_ | toast = Just "Invite sent." }
                        )
                    , toastFor
                    )

                remote ->
                    ( AuthModel
                        (updateModalRequest
                            (\m ->
                                case m of
                                    SharedTripUi.InviteModal id data ->
                                        Just (SharedTripUi.InviteModal id { data | request = remote })

                                    _ ->
                                        Nothing
                            )
                            as_
                        )
                    , Cmd.none
                    )

        OpenInviteCrewModal flockId ->
            -- Open the modal in NotAsked so its explanatory copy + confirm
            -- button are actually reachable; the request fires from the
            -- modal's "Get invite link" button (GetShareLinkClicked), matching
            -- the Reset-links / Email-invite flows.
            ( AuthModel
                (setSharedTripModal
                    (SharedTripUi.InviteCrewModal flockId { request = RemoteData.NotAsked })
                    as_
                )
            , Cmd.none
            )

        GetShareLinkClicked flockId ->
            ( AuthModel
                (setSharedTripModal
                    (SharedTripUi.InviteCrewModal flockId { request = RemoteData.Loading })
                    as_
                )
            , Http.SharedTripApi.getShareLink as_.config as_.creds flockId (AuthMsg << GetShareLinkResult)
            )

        GetShareLinkResult result ->
            case RemoteData.fromResult result of
                RemoteData.Success { url } ->
                    -- Close the modal and fire navigator.share (or clipboard fallback).
                    ( AuthModel (setSharedTripModal SharedTripUi.NoModal as_)
                    , Ports.nativeShare
                        { mode = "auto"
                        , title = "Join my trip on Ternpike"
                        , text = "I'm tracking expenses on Ternpike — join my trip."
                        , url = url
                        }
                    )

                remote ->
                    ( AuthModel
                        (updateModalRequest
                            (\m ->
                                case m of
                                    SharedTripUi.InviteCrewModal id _ ->
                                        Just (SharedTripUi.InviteCrewModal id { request = remote })

                                    _ ->
                                        Nothing
                            )
                            as_
                        )
                    , Cmd.none
                    )

        OpenLeaveConfirmModal flockId ->
            ( AuthModel (setSharedTripModal (SharedTripUi.LeaveConfirmModal flockId { request = RemoteData.NotAsked }) as_)
            , Cmd.none
            )

        LeaveSharedTripConfirmed flockId ->
            ( AuthModel
                (updateModalRequest
                    (\m ->
                        case m of
                            SharedTripUi.LeaveConfirmModal id _ ->
                                Just (SharedTripUi.LeaveConfirmModal id { request = RemoteData.Loading })

                            _ ->
                                Nothing
                    )
                    as_
                )
            , Http.SharedTripApi.leaveSharedTrip as_.config as_.creds flockId (AuthMsg << LeaveSharedTripResult)
            )

        LeaveSharedTripResult result ->
            case RemoteData.fromResult result of
                RemoteData.Success _ ->
                    ( AuthModel (setSharedTripModal SharedTripUi.NoModal { as_ | toast = Just "Left shared trip." })
                    , toastFor
                    )

                remote ->
                    ( AuthModel
                        (updateModalRequest
                            (\m ->
                                case m of
                                    SharedTripUi.LeaveConfirmModal id _ ->
                                        Just (SharedTripUi.LeaveConfirmModal id { request = remote })

                                    _ ->
                                        Nothing
                            )
                            as_
                        )
                    , Cmd.none
                    )

        OpenTransferModal flockId ->
            ( AuthModel (setSharedTripModal (SharedTripUi.TransferModal flockId { request = RemoteData.NotAsked, target = "" }) as_)
            , Cmd.none
            )

        TransferTargetChanged target ->
            let
                ui =
                    as_.sharedTripUi
            in
            case ui.modal of
                SharedTripUi.TransferModal id m ->
                    ( AuthModel { as_ | sharedTripUi = { ui | modal = SharedTripUi.TransferModal id { m | target = target } } }
                    , Cmd.none
                    )

                _ ->
                    ( AuthModel as_, Cmd.none )

        SubmitTransfer ->
            case as_.sharedTripUi.modal of
                SharedTripUi.TransferModal flockId { target } ->
                    ( AuthModel
                        (updateModalRequest
                            (\m ->
                                case m of
                                    SharedTripUi.TransferModal id data ->
                                        Just (SharedTripUi.TransferModal id { data | request = RemoteData.Loading })

                                    _ ->
                                        Nothing
                            )
                            as_
                        )
                    , Http.SharedTripApi.transferOwnership as_.config as_.creds flockId { newOwnerEmail = target } (AuthMsg << TransferToSharedTripResult)
                    )

                _ ->
                    ( AuthModel as_, Cmd.none )

        TransferToSharedTripResult result ->
            case RemoteData.fromResult result of
                RemoteData.Success _ ->
                    ( AuthModel (setSharedTripModal SharedTripUi.NoModal { as_ | toast = Just "Ownership transferred." })
                    , toastFor
                    )

                remote ->
                    ( AuthModel
                        (updateModalRequest
                            (\m ->
                                case m of
                                    SharedTripUi.TransferModal id data ->
                                        Just (SharedTripUi.TransferModal id { data | request = remote })

                                    _ ->
                                        Nothing
                            )
                            as_
                        )
                    , Cmd.none
                    )

        JoinSharedTripAccepted token ->
            ( AuthModel { as_ | joinSharedTripRequest = RemoteData.Loading }
            , Http.SharedTripApi.joinSharedTrip as_.config as_.creds { token = token } (AuthMsg << JoinSharedTripResult)
            )

        JoinSharedTripDeclined ->
            ( AuthModel { as_ | route = RouteTrips }
            , Nav.pushUrl as_.key (as_.basePath ++ "trips")
            )

        JoinSharedTripResult result ->
            let
                rd =
                    RemoteData.fromResult result
            in
            case rd of
                RemoteData.Success response ->
                    -- Post-join retention (#338): flip the one-time A2HS /
                    -- crew-push prompt on. The Settings landing renders the
                    -- post-join card (Add to Home Screen, then crew-activity
                    -- push once installed) while `postJoinPrompt` is True;
                    -- `DismissPostJoinPrompt` clears it. We never prompt during
                    -- the guest preview — only after a successful conversion.
                    ( AuthModel
                        { as_
                            | joinSharedTripRequest = rd
                            , postJoinPrompt = True
                            , route = RouteSettings
                            , toast = Just ("Joined " ++ response.name ++ ".")
                        }
                    , Cmd.batch
                        [ Nav.pushUrl as_.key (as_.basePath ++ "settings")
                        , toastFor
                        , Ports.trackFunnel
                            { flockId = Data.SharedTripId.toString response.sharedTripId
                            , stage = Analytics.joinSucceeded
                            }
                        ]
                    )

                RemoteData.Failure _ ->
                    ( AuthModel { as_ | joinSharedTripRequest = rd }, Cmd.none )

                RemoteData.NotAsked ->
                    ( AuthModel as_, Cmd.none )

                RemoteData.Loading ->
                    ( AuthModel as_, Cmd.none )

        -- PWA notifications (foundation #175): the `Ports.notificationState`
        -- port reports the browser's permission state, the subscribe
        -- flag, the standalone-PWA flag, and the persisted prefs blob
        -- on every relevant event. We mirror all four into AuthState
        -- here. Hydration via the JS handler + persistence via PouchDB
        -- land in the downstream port-wiring + Settings issues.
        NotificationStateChanged payload ->
            let
                prefs =
                    case D.decodeValue Notifications.decodePrefs payload.prefs of
                        Ok p ->
                            p

                        Err _ ->
                            as_.notificationPrefs

                standalone =
                    if payload.standalone then
                        Notifications.Standalone

                    else
                        Notifications.InBrowser
            in
            ( AuthModel
                { as_
                    | notificationPermission = Notifications.permissionFromString payload.permission
                    , notificationPrefs = prefs
                    , pushSubscribed = payload.subscribed
                    , standalone = standalone
                }
            , Cmd.none
            )

        -- Fire-and-forget: the push fan-out result does not affect UI
        -- state. Any delivery failures are logged server-side. The
        -- expense write has already landed in PouchDB by the time this
        -- returns, so we never need to roll back.
        SharedTripActivityNotified ->
            ( AuthModel as_, Cmd.none )

        -- Server-route handling (storing the subscription server-side,
        -- surfacing errors in the Settings UI) lands in later issues;
        -- for now we mirror the `ok` flag into AuthState.
        PushSubscribeReceived payload ->
            ( AuthModel { as_ | pushSubscribed = payload.ok }, Cmd.none )

        -- Fired by the Settings UI's "Enable notifications" button. We
        -- emit `Ports.subscribePush` and let the JS handler request browser
        -- permission first (if needed) and then call
        -- `pushManager.subscribe` inside the same await chain. iOS
        -- Safari requires the entire flow to run within the user-gesture
        -- context AND requires permission to be Granted before
        -- subscribe is called — emitting permission + subscribe in
        -- parallel via Cmd.batch breaks both invariants. The JS handler
        -- re-emits `Ports.notificationState` + `Ports.pushSubscribeResult` so
        -- `NotificationStateChanged` / `PushSubscribeReceived` update
        -- AuthState.
        RequestPushPermission ->
            ( AuthModel as_
            , Ports.subscribePush
                { prefs = Notifications.encodePrefs as_.notificationPrefs
                , vapidPublicKey = as_.config.vapidPublicKey
                }
            )

        ResetLinksClicked flockId ->
            ( AuthModel
                (setSharedTripModal
                    (SharedTripUi.ResetLinksConfirmModal flockId { request = RemoteData.NotAsked })
                    as_
                )
            , Cmd.none
            )

        ResetLinksConfirmed flockId ->
            ( AuthModel
                (updateModalRequest
                    (\m ->
                        case m of
                            SharedTripUi.ResetLinksConfirmModal id _ ->
                                Just (SharedTripUi.ResetLinksConfirmModal id { request = RemoteData.Loading })

                            _ ->
                                Nothing
                    )
                    as_
                )
            , Http.SharedTripApi.resetShareLinks as_.config as_.creds flockId (AuthMsg << ResetLinksResult)
            )

        ResetLinksResult result ->
            case RemoteData.fromResult result of
                RemoteData.Success _ ->
                    ( AuthModel
                        (setSharedTripModal SharedTripUi.NoModal
                            { as_ | toast = Just "All share links reset." }
                        )
                    , toastFor
                    )

                remote ->
                    ( AuthModel
                        (updateModalRequest
                            (\m ->
                                case m of
                                    SharedTripUi.ResetLinksConfirmModal id _ ->
                                        Just (SharedTripUi.ResetLinksConfirmModal id { request = remote })

                                    _ ->
                                        Nothing
                            )
                            as_
                        )
                    , Cmd.none
                    )

        -- Optimistic flip of the local pref + fire-and-forget save to
        -- the server. The encoded prefs go to the JS port which PUTs
        -- them to `/notifications/preferences`; if the request fails
        -- we don't roll back (Elm state stays optimistic — the cron
        -- re-checks tier independently). New `NotificationToggle`
        -- variants get a new branch here and the compiler enforces it.
        -- When the last opt-in flips off we also call `Ports.unsubscribePush`
        -- so the browser drops the registration entirely — no point
        -- keeping the endpoint live on the server if nothing will fire.
        ToggleNotificationPref Notifications.SharedTripAccessChange ->
            let
                oldPrefs : Notifications.NotificationPrefs
                oldPrefs =
                    as_.notificationPrefs

                newPrefs : Notifications.NotificationPrefs
                newPrefs =
                    { oldPrefs | sharedTripAccessChange = not oldPrefs.sharedTripAccessChange }

                anyEnabled : Bool
                anyEnabled =
                    newPrefs.sharedTripAccessChange || newPrefs.sharedTripActivity || newPrefs.sharedTripInvite || newPrefs.syncStalled || newPrefs.weeklyScanReminder
            in
            ( AuthModel { as_ | notificationPrefs = newPrefs }
            , Cmd.batch
                [ Ports.savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    Ports.unsubscribePush ()
                ]
            )

        ToggleNotificationPref Notifications.SharedTripActivity ->
            let
                oldPrefs : Notifications.NotificationPrefs
                oldPrefs =
                    as_.notificationPrefs

                newPrefs : Notifications.NotificationPrefs
                newPrefs =
                    { oldPrefs | sharedTripActivity = not oldPrefs.sharedTripActivity }

                anyEnabled : Bool
                anyEnabled =
                    newPrefs.sharedTripAccessChange || newPrefs.sharedTripActivity || newPrefs.sharedTripInvite || newPrefs.syncStalled || newPrefs.weeklyScanReminder
            in
            ( AuthModel { as_ | notificationPrefs = newPrefs }
            , Cmd.batch
                [ Ports.savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    Ports.unsubscribePush ()
                ]
            )

        ToggleNotificationPref Notifications.SharedTripInvite ->
            let
                oldPrefs : Notifications.NotificationPrefs
                oldPrefs =
                    as_.notificationPrefs

                newPrefs : Notifications.NotificationPrefs
                newPrefs =
                    { oldPrefs | sharedTripInvite = not oldPrefs.sharedTripInvite }

                anyEnabled : Bool
                anyEnabled =
                    newPrefs.sharedTripAccessChange || newPrefs.sharedTripActivity || newPrefs.sharedTripInvite || newPrefs.syncStalled || newPrefs.weeklyScanReminder
            in
            ( AuthModel { as_ | notificationPrefs = newPrefs }
            , Cmd.batch
                [ Ports.savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    Ports.unsubscribePush ()
                ]
            )

        ToggleNotificationPref Notifications.SyncStalled ->
            let
                oldPrefs : Notifications.NotificationPrefs
                oldPrefs =
                    as_.notificationPrefs

                newPrefs : Notifications.NotificationPrefs
                newPrefs =
                    { oldPrefs | syncStalled = not oldPrefs.syncStalled }

                anyEnabled : Bool
                anyEnabled =
                    newPrefs.sharedTripAccessChange || newPrefs.sharedTripActivity || newPrefs.sharedTripInvite || newPrefs.syncStalled || newPrefs.weeklyScanReminder
            in
            ( AuthModel { as_ | notificationPrefs = newPrefs }
            , Cmd.batch
                [ Ports.savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    Ports.unsubscribePush ()
                ]
            )

        ToggleNotificationPref Notifications.WeeklyScanReminder ->
            let
                oldPrefs : Notifications.NotificationPrefs
                oldPrefs =
                    as_.notificationPrefs

                newPrefs : Notifications.NotificationPrefs
                newPrefs =
                    { oldPrefs | weeklyScanReminder = not oldPrefs.weeklyScanReminder }

                anyEnabled : Bool
                anyEnabled =
                    newPrefs.sharedTripAccessChange || newPrefs.sharedTripActivity || newPrefs.sharedTripInvite || newPrefs.syncStalled || newPrefs.weeklyScanReminder
            in
            ( AuthModel { as_ | notificationPrefs = newPrefs }
            , Cmd.batch
                [ Ports.savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    Ports.unsubscribePush ()
                ]
            )



-- FLOCK HELPERS


{-| Map a `navigator.onLine` boolean (from the `networkStatus` port) to a
`NetworkState`. The `Unknown` third state only exists before the first
report; once a report lands we always know `Online` or `Offline`.
-}
networkStateFromOnline : Bool -> NetworkState
networkStateFromOnline isOnline =
    if isOnline then
        Online

    else
        Offline


{-| Project the narrow `Page.Scan.Model` slice out of `AuthState` for the
Scan-message router. The slice carries only the fields the Scan flows
touch, leaving the un-constructible `Nav.Key` (and everything else)
behind so the Scan slice stays drivable under `elm-program-test`.
-}
scanModelFromAuth : AuthState -> Page.Scan.Model
scanModelFromAuth as_ =
    { activeScanItemId = as_.activeScanItemId
    , basePath = as_.basePath
    , config = as_.config
    , confirmRemoveScan = as_.confirmRemoveScan
    , creds = as_.creds
    , currentUser = as_.currentUser
    , duplicateWarning = as_.duplicateWarning
    , error = as_.error
    , form = as_.form
    , network = as_.network
    , ocrInFlight = as_.ocrInFlight
    , route = as_.route
    , scanQueue = as_.scanQueue
    , scanSeq = as_.scanSeq
    , scanTombstones = as_.scanTombstones
    , sharedTrips = as_.sharedTrips
    , storageAvailable = as_.storageAvailable
    , tier = as_.tier
    , today = as_.today
    , trips = as_.trips
    }


{-| Merge a `Page.Scan.update` result back into the full `AuthState`,
writing through only the slice fields the Scan flows mutate.
-}
mergeScanModel : Page.Scan.Model -> AuthState -> AuthState
mergeScanModel scan as_ =
    { as_
        | activeScanItemId = scan.activeScanItemId
        , confirmRemoveScan = scan.confirmRemoveScan
        , duplicateWarning = scan.duplicateWarning
        , error = scan.error
        , form = scan.form
        , ocrInFlight = scan.ocrInFlight
        , route = scan.route
        , scanQueue = scan.scanQueue
        , scanSeq = scan.scanSeq
        , scanTombstones = scan.scanTombstones
    }


{-| Decode the `scanQueueLoaded` payload (a JSON array of
`scanItemEncoder`-shaped docs) into a `Dict String ScanItem` keyed by the
item's durable id, quarantining any doc that fails `scanItemDecoder` rather
than failing the whole hydration. A non-array payload (or a totally
undecodable one) yields an empty queue — boot/login then proceeds with no
hydrated items rather than erroring out (#371).
-}
decodeHydratedQueue : D.Value -> Dict.Dict String Data.Scan.ScanItem
decodeHydratedQueue raw =
    raw
        |> D.decodeValue (D.list D.value)
        |> Result.withDefault []
        |> List.filterMap
            (\itemValue ->
                case D.decodeValue Data.Scan.scanItemDecoder itemValue of
                    Ok item ->
                        Just ( ScanItemId.toString item.id, item )

                    Err _ ->
                        Nothing
            )
        |> Dict.fromList


setSharedTripModal : SharedTripUi.SharedTripModal -> AuthState -> AuthState
setSharedTripModal modal as_ =
    let
        ui =
            as_.sharedTripUi
    in
    { as_ | sharedTripUi = { ui | modal = modal } }


{-| Replace the currently-open modal's `request` field with a new
`RemoteData`. Used by both dispatch branches (flipping to `Loading`)
and result branches (storing `Failure`). No-op when no modal is open
or when the modal in scope isn't the one we expected (a stale message
arriving after the user closed the modal).
-}
updateModalRequest :
    (SharedTripUi.SharedTripModal -> Maybe SharedTripUi.SharedTripModal)
    -> AuthState
    -> AuthState
updateModalRequest f as_ =
    { as_ | sharedTripUi = SharedTripUi.setModalRequest f as_.sharedTripUi }



-- VIEW


view : Model -> Browser.Document Msg
view model =
    let
        demoMode =
            case model of
                GuestModel gs ->
                    gs.demoMode

                AuthModel as_ ->
                    as_.demoMode
    in
    { title = "Ternpike"
    , body =
        [ viewDemoBanner demoMode
        , Html.div
            [ Html.Attributes.class "bg-parchment dark:bg-cream text-ink min-h-screen min-h-[100lvh] font-body max-w-[480px] mx-auto relative sm:shadow-card sm:border-x sm:border-tan/40 sm:dark:border-moss/20" ]
            [ case model of
                GuestModel gs ->
                    viewGuest gs

                AuthModel as_ ->
                    viewAuth as_
            ]
        ]
    }


viewDemoBanner : Bool -> Html Msg
viewDemoBanner demoMode =
    if demoMode then
        Html.div
            [ Html.Attributes.class "bg-rust text-parchment text-xs font-display tracking-wide px-3 py-2 text-center" ]
            [ Html.text "DEMO MODE — fictional movie road trips. "
            , Html.a
                [ Html.Attributes.href "https://ternpike.com"
                , Html.Attributes.class "underline font-bold"
                ]
                [ Html.text "Sign up to track your own →" ]
            ]

    else
        Html.Extra.nothing


{-| The human-browsable verification dashboard at `/verify`. Renders every
registered unit × fixture from `Verify.Registry.runAll` with its verdict and a
deep link to the isolated `/verify/:unit/:fixture` route. The "third consumer"
of the one verdict taxonomy (alongside the elm-test matrix and `window.__verify`).
-}
viewVerifyDashboard : String -> Html Msg
viewVerifyDashboard basePath =
    let
        passCount : Int
        passCount =
            Verify.Registry.runAll
                |> List.filter (\r -> r.verdict == Verify.Core.Pass)
                |> List.length

        total : Int
        total =
            List.length Verify.Registry.runAll
    in
    Html.div [ Html.Attributes.class "max-w-2xl mx-auto p-6 flex flex-col gap-4" ]
        [ Html.h1 [ Html.Attributes.class "text-xl font-mono uppercase tracking-widest text-ink" ]
            [ Html.text "Verify" ]
        , Html.p [ Html.Attributes.class "text-xs text-muted" ]
            [ Html.text (String.fromInt passCount ++ " / " ++ String.fromInt total ++ " fixtures passing") ]
        , Html.div [ Html.Attributes.class "flex flex-col divide-y divide-tan" ]
            (List.map (viewVerifyRow basePath) Verify.Registry.runAll)
        ]


viewVerifyRow : String -> Verify.Core.RunResult -> Html Msg
viewVerifyRow basePath result =
    let
        ( badgeClass, badgeText ) =
            case result.verdict of
                Verify.Core.Pass ->
                    ( "bg-moss/15 text-moss", "PASS" )

                Verify.Core.Fail _ ->
                    ( "bg-rust/15 text-rust", "FAIL" )
    in
    Html.a
        [ Html.Attributes.href (basePath ++ "verify/" ++ result.unit ++ "/" ++ result.fixture)
        , Html.Attributes.class "flex items-center justify-between gap-3 py-2 hover:bg-cream-deep"
        ]
        [ Html.span [ Html.Attributes.class "text-sm text-ink" ]
            [ Html.span [ Html.Attributes.class "text-muted" ] [ Html.text (result.unit ++ " / ") ]
            , Html.text result.fixture
            ]
        , Html.span
            [ Html.Attributes.class ("shrink-0 px-2 py-0.5 rounded text-[11px] font-mono tracking-widest " ++ badgeClass) ]
            [ Html.text badgeText ]
        ]


viewAuth : AuthState -> Html Msg
viewAuth as_ =
    let
        route =
            Routing.effectiveRoute as_

        tab =
            case route of
                RouteAdd _ ->
                    Pages.Add.viewTab as_

                RouteAddReviewScan ->
                    Pages.Add.viewTab as_

                RouteEditEntry _ _ ->
                    Pages.Add.viewTab as_

                RouteJoinSharedTrip token ->
                    Pages.JoinSharedTrip.viewAuth as_ token

                RouteLedger tripId ->
                    let
                        earnedForTrip : List Milepost.MarkerState
                        earnedForTrip =
                            Milepost.evaluate (milepostInputsForTrip tripId as_)
                                |> List.filter
                                    (\s ->
                                        case s of
                                            Milepost.Earned { marker } ->
                                                Milepost.isTripScoped marker

                                            Milepost.Locked _ ->
                                                False
                                    )
                    in
                    Pages.Ledger.viewTab earnedForTrip as_

                RouteMagicLink _ _ ->
                    -- Magic-link landing is a guest-only route; an
                    -- authenticated user who somehow lands here sees
                    -- the Trips list (the real view lands in #335).
                    Pages.Trips.viewTab as_

                RouteNestPreview _ ->
                    -- Nest preview is a guest-only route; an
                    -- authenticated user who somehow lands here sees
                    -- the Trips list (the real view lands in #337).
                    Pages.Trips.viewTab as_

                RouteScan _ ->
                    Pages.Scan.viewTab as_

                RouteSettings ->
                    Pages.Settings.viewTab as_

                RouteStats _ ->
                    Pages.Stats.viewTab as_

                RouteTrips ->
                    Pages.Trips.viewTab as_

                RouteMilepost ->
                    Pages.Milepost.viewTab as_

                RouteVerify _ _ ->
                    -- Verification routes mount a seeded fixture model whose
                    -- stored `route` is rewritten to the unit's home page (e.g.
                    -- Settings), so this arm is only here for exhaustiveness.
                    Pages.Settings.viewTab as_

                RouteVerifyIndex ->
                    { actions = [], body = viewVerifyDashboard as_.basePath, hero = Html.Extra.nothing }
    in
    Html.div []
        [ UI.Layout.viewHeader as_
        , UI.Layout.viewOfflineBanner (Data.Sync.isOffline as_.network)
        , UI.Layout.viewErrorBanner as_.error
        , viewBillingBannerForRoute as_ route
        , Html.div [ Html.Attributes.class "pb-[calc(env(safe-area-inset-bottom)+5rem)]" ]
            [ UI.Layout.page
                { actions = tab.actions
                , body = tab.body
                , hero = tab.hero
                , route = route
                }
            ]
        , UI.Layout.viewBottomNav as_
        , Html.Extra.viewMaybe UI.Layout.viewDeleteConfirmModal as_.confirmDeleteTrip
        , case ( as_.movePicker, as_.trips ) of
            ( Just expense, TripsLoaded loadedTrips ) ->
                UI.TripPicker.viewMove
                    { expense = expense
                    , flocks = as_.sharedTrips
                    , trips = Trips.allTrips loadedTrips
                    }

            _ ->
                Html.Extra.nothing
        , Pages.Settings.SharedTrips.viewModal as_
        , UI.ShareModal.view as_
        , UI.TripFormModal.view as_
        , UI.Layout.viewToast as_.toast
        , UI.MilepostToast.view as_
        ]


{-| Resolve the active trip's flock from the route + loaded trips, and
render `UI.BillingBanner.view` when that flock is in `Grace` or
`Frozen`. Returns `Html.text ""` for personal trips, non-trip routes
(Settings, Trips list), and active flocks — see #64 for the matrix.
-}
viewBillingBannerForRoute : AuthState -> Route -> Html Msg
viewBillingBannerForRoute as_ route =
    case ( Routing.routeTripId route, as_.trips ) of
        ( Just tripId, TripsLoaded loadedTrips ) ->
            case Trips.findTrip tripId loadedTrips of
                Just trip ->
                    case Maybe.andThen (\fid -> SharedTrips.get fid as_.sharedTrips) trip.flockId of
                        Just flock ->
                            UI.BillingBanner.view
                                { currentUser = UserId.fromString as_.creds.email
                                , flock = flock
                                , tier = as_.tier
                                , today = as_.today
                                }

                        Nothing ->
                            Html.Extra.nothing

                Nothing ->
                    Html.Extra.nothing

        _ ->
            Html.Extra.nothing



-- MAIN


main : Program D.Value Model Msg
main =
    Browser.application
        { init = init
        , onUrlChange = SharedMsg << UrlChanged
        , onUrlRequest = SharedMsg << LinkClicked
        , subscriptions =
            \_ ->
                Sub.batch
                    [ -- Re-capture the device zone + "today" whenever visibility
                      -- flips. We fire on both edges (hide and show) rather than
                      -- filtering to `Visible`: `captureDateContext` is idempotent
                      -- (it just re-reads `Time.here`/`Time.now` and overwrites
                      -- `zone`/`today`), so the redundant hide-edge dispatch is
                      -- harmless, and skipping the filter avoids a no-op message
                      -- whose only job is to swallow the `Hidden` case.
                      Browser.Events.onVisibilityChange (\_ -> SharedMsg RefreshDateContext)
                    , Ports.pouchIn (AuthMsg << GotPouchMsg)
                    , Ports.gotGpsCoords
                        (\r ->
                            if r.denied then
                                AuthMsg GeolocationDenied

                            else
                                AuthMsg (GotGpsCoords r.lat r.lon)
                        )
                    , Ports.gotExifResult
                        (\r ->
                            if r.hasGps then
                                AuthMsg (ScanMsg (Msg.Scan.GotExifCoords r.id (Just r.lat) (Just r.lon) ""))

                            else
                                AuthMsg (ScanMsg (Msg.Scan.GotExifCoords r.id Nothing Nothing r.debug))
                        )
                    , Ports.networkStatus (SharedMsg << NetworkStatusChanged)
                    , Ports.canInstall (AuthMsg << CanInstall)
                    , Ports.ocrImagePrepared (AuthMsg << ScanMsg << Msg.Scan.OcrImagePrepared)
                    , Ports.notificationState (AuthMsg << NotificationStateChanged)
                    , Ports.pushSubscribeResult (AuthMsg << PushSubscribeReceived)
                    , Ports.scanProxyIn (AuthMsg << ScanMsg << Msg.Scan.ScanProxyResult)
                    , Ports.scanQueueLoaded (AuthMsg << ScanQueueLoaded)
                    , Ports.scanItemSaved (AuthMsg << ScanItemSaved)
                    , Ports.storageStatus (AuthMsg << StorageStatusReceived)
                    , Ports.nativeShareResult (AuthMsg << ShareResultReceived)
                    ]
        , update = update
        , view = view
        }
