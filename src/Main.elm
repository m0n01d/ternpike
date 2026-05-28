port module Main exposing (main)

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
    through `pouchIn`, where `handleDbChange` merges it into the right
    `Dict`.


# Ports

  - `pouchOut` / `pouchIn` — all PouchDB traffic (tagged JSON, see
    `src/pouch.js`).
  - `startSync` / `stopSync` — manage the live CouchDB sync handle.
  - `saveStorage` / `clearStorage` / `clearAllStorage` — IndexedDB-backed
    auth creds and API key.
  - `requestGeolocation` / `gotGpsCoords` — browser geolocation API.
  - `extractExifGps` / `gotExifResult` — EXIF GPS extraction from receipt
    photos.

For the full narrative and document ID conventions, see `docs/architecture.md`.

-}

import Browser
import Browser.Dom
import Browser.Navigation as Nav
import Data.Amendment as Amendment
import Data.AmendmentId as AmendmentId
import Data.AnthropicKey as AnthropicKey
import Data.Auth exposing (AppConfig, Creds)
import Data.Category exposing (Category(..))
import Data.ColorScheme as ColorScheme
import Data.CsvExport as CsvExport
import Data.DateField as DateField exposing (DateField)
import Data.Entry as Entry
import Data.Expense as Expense exposing (Expense)
import Data.ExpenseId as ExpenseId
import Data.GeoPoint as GeoPoint
import Data.Guest exposing (GuestReason(..), GuestSession)
import Data.Iso8601 as Iso8601
import Data.Location exposing (LocationSource(..), LocationState(..))
import Data.Money as Money
import Data.Navigation exposing (Route(..), Tab(..))
import Data.Notifications as Notifications
import Data.OcrPath as OcrPath exposing (OcrPath(..))
import Data.PendingEntry as PendingEntry exposing (PendingEntry, PendingForm(..))
import Data.Pouch exposing (DocChange(..), ExpenseBundle, PouchInbound(..), PouchOutbound(..), TripBundle)
import Data.Scan as Scan exposing (ExifPhase(..), GeocodePhase(..), ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Data.SharedTrip as SharedTrip
import Data.SharedTripId
import Data.SharedTripUi as SharedTripUi
import Data.SharedTrips as SharedTrips
import Data.StatsHover as StatsHover
import Data.SubscriptionStatus as SubscriptionStatus exposing (SubscriptionStatus)
import Data.Sync exposing (SyncState(..))
import Data.Tier as Tier exposing (Tier)
import Data.Trip as Trip exposing (Trip, TripField(..))
import Data.TripId as TripId
import Data.Trips as Trips exposing (TripsState(..))
import Data.UserId as UserId
import Data.Void as Void
import Dict
import File
import Helpers
import Html exposing (Html)
import Html.Attributes
import Html.Extra
import Http
import Http.Billing
import Http.GeocodeApi
import Http.Me
import Http.SharedTripApi
import Json.Decode as D
import Json.Encode as E
import List.Extra
import Maybe.Extra
import Pages.Add
import Pages.Guest exposing (viewGuest)
import Pages.JoinSharedTrip
import Pages.Ledger
import Pages.Scan
import Pages.Settings
import Pages.Settings.SharedTrips
import Pages.Stats
import Pages.Trips
import Process
import RemoteData
import Routing
import Set
import Task
import Time
import Types exposing (AuthMsg_(..), AuthState, GuestMsg_(..), GuestState, Model(..), Msg(..), ShareMode(..), SharedMsg_(..))
import UI.BillingBanner
import UI.Layout
import UI.ShareModal
import UI.TripFormModal
import UI.TripPicker
import Url
import Validate



-- PORTS


port saveStorage : { key : String, value : String } -> Cmd msg


port clearStorage : () -> Cmd msg


port clearAllStorage : () -> Cmd msg


port pouchOut : D.Value -> Cmd msg


port pouchIn : (D.Value -> msg) -> Sub msg


port startSync : D.Value -> Cmd msg


port stopSync : () -> Cmd msg


port requestGeolocation : () -> Cmd msg


port extractExifGps : { id : String, dataUrl : String } -> Cmd msg


port prepareOcrImage : { dataUrl : String, id : String, maxBytes : Int } -> Cmd msg


port ocrImagePrepared : ({ dataUrl : String, error : String, finalBytes : Int, id : String, originalBytes : Int } -> msg) -> Sub msg


port gotGpsCoords : ({ lat : Float, lon : Float, denied : Bool } -> msg) -> Sub msg


port gotExifResult : ({ id : String, lat : Float, lon : Float, hasGps : Bool, debug : String } -> msg) -> Sub msg


port networkStatus : (Bool -> msg) -> Sub msg


port triggerInstallPrompt : () -> Cmd msg


port canInstall : (Bool -> msg) -> Sub msg


port scanProxyOut : { backendUrl : String, body : E.Value, itemId : String } -> Cmd msg


port scanProxyIn : ({ body : String, itemId : String, ok : Bool, status : Int } -> msg) -> Sub msg


port savePushPrefs : D.Value -> Cmd msg


port subscribePush : { prefs : D.Value, vapidPublicKey : String } -> Cmd msg


port unsubscribePush : () -> Cmd msg


port notificationState : ({ permission : String, prefs : D.Value, standalone : Bool, subscribed : Bool } -> msg) -> Sub msg


port pushSubscribeResult : ({ error : String, ok : Bool } -> msg) -> Sub msg


port downloadFile : { content : String, filename : String, mimeType : String } -> Cmd msg


port nativeShare : { mode : String, text : String, title : String, url : String } -> Cmd msg


port nativeShareResult : ({ ok : Bool, reason : String } -> msg) -> Sub msg



-- ROUTING
-- See src/Routing.elm
-- SESSION HELPERS


mapGuestConfig : (AppConfig -> AppConfig) -> GuestSession -> GuestSession
mapGuestConfig f gs =
    { gs | config = f gs.config }


{-| Transition from `GuestState` to `AuthState` after successful auth.

Everything starts empty — no expenses, no trips, no scan queue. The
caller is responsible for kicking off `startSync`; the trips list will
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
    , form = FreshForm (defaultPendingEntry gs.today)
    , geoBlocked = False
    , joinSharedTripRequest = RemoteData.NotAsked
    , key = gs.key
    , lastSyncedAt = Nothing
    , ledgerMapExpanded = False
    , loadingExpenses = Set.empty
    , loadingTrips = Set.empty
    , movePicker = Nothing
    , networkOffline = gs.networkOffline
    , notificationPermission = Notifications.Default
    , notificationPrefs = Notifications.defaultPrefs
    , openLedgerMenu = Nothing
    , pushSubscribed = False
    , route = initialRoute
    , scanQueue = Dict.empty
    , showByoKeyInput = gs.session.config.anthropicKey /= Nothing
    , showDayIntensity = True
    , showInstallPrompt = False
    , showLedgerMap = False
    , showMapPicker = False
    , standalone = Notifications.InBrowser
    , statsGranularity = Nothing
    , statsHover = StatsHover.empty
    , submitting = False
    , subscriptionStatus = creds.subscriptionStatus
    , syncState = NotEnabled
    , tier = creds.tier
    , toast = Nothing
    , today = gs.today
    , trailblazerNumber = creds.trailblazerNumber
    , trailblazerStatus = RemoteData.NotAsked
    , tripForm = Nothing
    , tripLoaded = Set.empty
    , trips = TripsLoading Dict.empty (Routing.routeTripId initialRoute)
    , version = gs.version
    , voids = Dict.empty
    }


toGuestState : GuestReason -> AuthState -> GuestState
toGuestState reason as_ =
    { authError = Nothing
    , basePath = as_.basePath
    , codeInput = ""
    , demoMode = as_.demoMode
    , emailInput = ""
    , key = as_.key
    , networkOffline = as_.networkOffline
    , pendingJoinToken = joinTokenFromRoute as_.route
    , pendingRef = Nothing
    , resendStatus = RemoteData.NotAsked
    , session = { config = as_.config, reason = reason }
    , showSettings = reason == SessionExpired
    , today = as_.today
    , version = as_.version
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


credsDecoder : D.Decoder Creds
credsDecoder =
    D.map6 Creds
        (D.field "dbName" D.string)
        (D.field "email" D.string)
        (D.field "password" D.string)
        subscriptionStatusField
        tierField
        trailblazerNumberField


{-| Decode tier from either the auth server's verify-code response or
the IndexedDB-stored `auth_creds` blob. Defaults to `Tern` when the
field is absent (legacy blobs persisted before tier was wired in) or
when the value is unrecognized — fails closed so an unknown tier never
silently grants paid features.
-}
tierField : D.Decoder Tier
tierField =
    D.oneOf
        [ D.field "tier" D.string
            |> D.map (Tier.fromString >> Maybe.withDefault Tier.Tern)
        , D.succeed Tier.Tern
        ]


{-| Decode `subscriptionStatus` from the verify-code response or the
IndexedDB blob. Absent / null / unrecognised → `Nothing` so legacy
`auth_creds` blobs persisted before this field was wired still
deserialise.
-}
subscriptionStatusField : D.Decoder (Maybe SubscriptionStatus)
subscriptionStatusField =
    D.oneOf
        [ D.field "subscriptionStatus" (D.nullable SubscriptionStatus.decoder)
        , D.succeed Nothing
        ]


{-| Decode `trailblazerNumber` from the verify-code response or the
IndexedDB blob. Absent / null → `Nothing`.
-}
trailblazerNumberField : D.Decoder (Maybe Int)
trailblazerNumberField =
    D.oneOf
        [ D.field "trailblazerNumber" (D.nullable D.int)
        , D.succeed Nothing
        ]


encodeCreds : Creds -> D.Value
encodeCreds c =
    E.object
        [ ( "dbName", E.string c.dbName )
        , ( "email", E.string c.email )
        , ( "password", E.string c.password )
        , ( "subscriptionStatus"
          , c.subscriptionStatus
                |> Maybe.map SubscriptionStatus.encoder
                |> Maybe.withDefault E.null
          )
        , ( "tier", E.string (Tier.toString c.tier) )
        , ( "trailblazerNumber"
          , c.trailblazerNumber
                |> Maybe.map E.int
                |> Maybe.withDefault E.null
          )
        ]


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



-- POUCHDB PROTOCOL


encodePouchOut : PouchOutbound -> D.Value
encodePouchOut msg =
    case msg of
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
    pouchOut << encodePouchOut


{-| Fire-and-forget push notification to co-travelers on a shared trip.

Calls `Http.SharedTripApi.notifyActivity` after PouchDB already accepted
the write — the HTTP response is handled by `SharedTripActivityNotified`
which is a no-op; any delivery failure is logged server-side and does
not affect UI state.

Returns `Cmd.none` for personal trips (no co-travelers to notify).

-}
notifySharedTripActivity :
    Creds
    -> Trip.TripTarget
    -> { action : String, amount : Float, note : Maybe String }
    -> Cmd Msg
notifySharedTripActivity creds target opts =
    case target of
        Trip.Personal ->
            Cmd.none

        Trip.InFlock sharedTripId ->
            Http.SharedTripApi.notifyActivity
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

                    "sharedtrip:meta" ->
                        -- Routed up as a top-level SharedTripMeta event by
                        -- pouch.js; ignored here.
                        D.fail "sharedtrip:meta routed as SharedTripMeta event"

                    "trip" ->
                        D.map TripChanged Trip.decoder

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


mapForm : (PendingEntry -> PendingEntry) -> PendingForm -> PendingForm
mapForm f form =
    case form of
        EditForm id p ->
            EditForm id (f p)

        FreshForm p ->
            FreshForm (f p)


formPending : PendingForm -> PendingEntry
formPending form =
    case form of
        EditForm _ p ->
            p

        FreshForm p ->
            p


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
                    { as_ | form = FreshForm (defaultPendingEntry as_.today) }

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
                requestGeolocation ()

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
        as1 =
            case change of
                AmendChanged a ->
                    { as_ | amendments = Dict.insert (AmendmentId.toString a.id) a as_.amendments }

                ExpenseChanged e ->
                    { as_
                        | expenses =
                            Dict.update (TripId.toString e.tripId)
                                (Just << Dict.insert (ExpenseId.toString e.id) e << Maybe.withDefault Dict.empty)
                                as_.expenses
                    }

                TripChanged t ->
                    { as_ | trips = upsertTripIntoState t as_.trips }

                VoidChanged v ->
                    { as_ | voids = Dict.insert v.id v as_.voids }
    in
    ( AuthModel (hydrateFormForRoute as1), Cmd.none )


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
                        { as1 | form = FreshForm (defaultPendingEntry as1.today) }

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
            , expect = Http.expectJson (GuestMsg << VerifyCodeResult) credsDecoder
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
            -- route needs an expenses fetch (will skip if already cached).
            fetchesForRoute { as_ | trips = TripsLoaded trips }
                |> (\( s, c ) -> ( AuthModel s, c ))

        Nothing ->
            case as_.route of
                -- A first-time invitee has zero personal trips but is mid
                -- invite-accept on `/sharedtrips/join?token=…`. Don't clobber
                -- their route — let them complete the Accept/Decline flow
                -- (which provisions a shared trip and resolves the empty
                -- state). Every other route falls back to the Trips empty
                -- state as before.
                RouteJoinSharedTrip _ ->
                    ( AuthModel { as_ | trips = NoTripsYet }
                    , Cmd.none
                    )

                _ ->
                    ( AuthModel { as_ | trips = NoTripsYet, route = RouteTrips }
                    , Nav.replaceUrl as_.key (as_.basePath ++ "trips")
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


{-| Build a blank Add-page form pre-seeded with the user's calendar
today. The `DateField` is rendered back to the legacy `YYYY-MM-DD`
String for `PendingEntry.date` because the form input remains a String
input (R7 will tighten that field).
-}
defaultPendingEntry : DateField -> PendingEntry
defaultPendingEntry today =
    { address = ""
    , amount = ""
    , category = Fuel
    , date = DateField.toIso today
    , locationState = LocationIdle
    , longNote = ""
    , merchant = ""
    , note = ""
    , paymentMethod = Nothing
    }


expenseToPending : Expense.Expense -> PendingEntry
expenseToPending e =
    { address = e.address
    , amount = Money.toDollarString e.amount
    , category = e.category
    , date = DateField.toIso e.date
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


setLocation : LocationState -> PendingEntry -> PendingEntry
setLocation ls p =
    { p | locationState = ls }


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


authPending : (PendingEntry -> PendingEntry) -> AuthState -> ( Model, Cmd Msg )
authPending f as_ =
    ( AuthModel { as_ | form = mapForm f as_.form }, Cmd.none )


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
                        (formPending as_.form).locationState

                    accept =
                        case formLs of
                            LocationGot _ ManualPin ->
                                False

                            LocationGot _ BrowserGeo ->
                                False

                            LocationSkipped ->
                                False

                            LocationIdle ->
                                False

                            LocationGot _ ExifGps ->
                                True

                            LocationGot _ Geocoded ->
                                True

                            LocationResolving ->
                                True

                            LocationNoExifGps ->
                                True
                in
                if accept then
                    { as_ | form = mapForm (setLocation (Scan.effectiveLocation item)) as_.form }

                else
                    as_

            else
                as_

        _ ->
            as_


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
    -> ( Dict.Dict String ScanItem, List (Cmd Msg) )
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
    -> ( Dict.Dict String ScanItem, List (Cmd Msg) )
    -> ( Dict.Dict String ScanItem, List (Cmd Msg) )
geocodeDispatchOne creds id ( queue, cmds ) =
    case Dict.get id queue |> Maybe.andThen (\item -> Maybe.andThen .address item.ocrData) of
        Just rawAddress ->
            if String.trim rawAddress /= "" then
                ( Dict.update id (Maybe.map (\item -> { item | geocode = GeocodeRequested })) queue
                , Http.GeocodeApi.geocode creds { address = rawAddress } (AuthMsg << GotGeocodeResult id) :: cmds
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


makeOcrCall : String -> OcrPath -> AppConfig -> String -> String -> Cmd Msg
makeOcrCall itemId path config base64Data mimeType =
    let
        body =
            E.object
                [ ( "model", E.string "claude-sonnet-4-6" )
                , ( "max_tokens", E.int 2048 )
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
                                        , ( "text", E.string "Extract expense info from every receipt visible in this image." )
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
                , expect = Http.expectStringResponse (AuthMsg << GotOcrResult itemId) ocrResponseToResult
                , timeout = Nothing
                , tracker = Nothing
                }

        HostedPath ->
            scanProxyOut { backendUrl = config.backendUrl, body = body, itemId = itemId }

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
    case D.decodeString (D.field "error" (D.field "message" D.string)) body of
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


claudeTextDecoder : D.Decoder String
claudeTextDecoder =
    D.field "content" (D.index 0 (D.field "text" D.string))


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
    case D.decodeString claudeTextDecoder responseBody of
        Err decodeErr ->
            Err
                ("Couldn't read Anthropic response: "
                    ++ D.errorToString decodeErr
                )

        Ok innerJson ->
            let
                stripped =
                    stripCodeFence innerJson
            in
            case D.decodeString Scan.ocrDataListDecoder stripped of
                Ok list ->
                    Ok list

                Err decodeErr ->
                    Err
                        ("Couldn't parse receipt JSON: "
                            ++ D.errorToString decodeErr
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



-- TRIP FORM PARSERS


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



-- INIT


init : D.Value -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flagsJson url key =
    let
        dec field_ =
            D.decodeValue (D.field field_ D.string) flagsJson
                |> Result.withDefault ""

        authCreds =
            D.decodeValue (D.field "authCreds" (D.nullable credsDecoder)) flagsJson
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
            , networkOffline = False
            , pendingJoinToken = joinTokenFromRoute initialRoute
            , pendingRef = pendingRef
            , resendStatus = RemoteData.NotAsked
            , session = { config = cfg, reason = NotLoggedIn }
            , showSettings = False
            , today = initialToday
            , version = dec "version"
            }
    in
    case authCreds of
        Nothing ->
            ( GuestModel gs, Cmd.none )

        Just creds ->
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
            ( AuthModel bootedFinal, Cmd.batch [ fetchMe bootedFinal, checkoutCmd ] )



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
                    , saveStorage { key = "anthropic_key", value = Maybe.Extra.unwrap "" AnthropicKey.toHeader newKey }
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
                    , saveStorage { key = "anthropic_key", value = Maybe.Extra.unwrap "" AnthropicKey.toHeader newKey }
                    )

        LinkClicked (Browser.Internal url) ->
            case model of
                GuestModel gs ->
                    ( GuestModel gs, Nav.pushUrl gs.key (Url.toString url) )

                AuthModel as_ ->
                    ( AuthModel as_, Nav.pushUrl as_.key (Url.toString url) )

        LinkClicked (Browser.External href) ->
            ( model, Nav.load href )

        NetworkStatusChanged isOnline ->
            case model of
                GuestModel gs ->
                    ( GuestModel { gs | networkOffline = not isOnline }, Cmd.none )

                AuthModel as_ ->
                    ( AuthModel { as_ | networkOffline = not isOnline }, Cmd.none )

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
                    , clearAllStorage ()
                    )

                AuthModel as_ ->
                    ( GuestModel
                        { authError = Nothing
                        , basePath = as_.basePath
                        , codeInput = ""
                        , demoMode = as_.demoMode
                        , emailInput = ""
                        , key = as_.key
                        , networkOffline = as_.networkOffline
                        , pendingJoinToken = Nothing
                        , pendingRef = Nothing
                        , resendStatus = RemoteData.NotAsked
                        , session = { config = { anthropicKey = Nothing, backendUrl = "", vapidPublicKey = "" }, reason = NotLoggedIn }
                        , showSettings = False
                        , today = as_.today
                        , version = as_.version
                        }
                    , Cmd.batch [ clearAllStorage (), stopSync () ]
                    )

        ScrolledToTop ->
            ( model, Cmd.none )

        SetColorScheme scheme ->
            case model of
                GuestModel gs ->
                    ( GuestModel gs, Cmd.none )

                AuthModel as_ ->
                    ( AuthModel { as_ | colorScheme = scheme }
                    , saveStorage { key = "color_scheme", value = ColorScheme.toString scheme }
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
                    ( GuestModel gs, scrollToTop )

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
                    in
                    ( AuthModel as2, Cmd.batch [ cmd, extraCmd, scrollToTop ] )


scrollToTop : Cmd Msg
scrollToTop =
    Task.perform (\_ -> SharedMsg ScrolledToTop) (Browser.Dom.setViewport 0 0)


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
                        [ saveStorage { key = "auth_creds", value = E.encode 0 (encodeCreds creds) }
                        , startSync (encodeCreds creds)
                        , Nav.replaceUrl gs.key landingUrl
                        , fetchMe as_
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
                    in
                    ( AuthModel (hydrateFormForRoute as1), Cmd.none )

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
                        -- Fire the initial trip load once sync has had its
                        -- first chance to settle — whether it succeeded
                        -- (Synced) or failed (SyncError, AuthExpired). The
                        -- app is local-first; we shouldn't wait on a working
                        -- remote before showing the user the data already in
                        -- their own PouchDB.
                        syncSettled s =
                            s == Synced || s == SyncError || s == AuthExpired

                        syncSettledEdge =
                            syncSettled state && not (syncSettled as_.syncState)

                        tripsStillLoading =
                            case as_.trips of
                                TripsLoading _ _ ->
                                    True

                                _ ->
                                    False

                        loadCmd =
                            if syncSettledEdge && tripsStillLoading then
                                sendPouch GetAllTrips

                            else
                                Cmd.none

                        capturedSyncedAt =
                            if state == Synced then
                                Task.perform (AuthMsg << GotSyncTime) Time.now

                            else
                                Cmd.none
                    in
                    ( AuthModel { as_ | syncState = state }, Cmd.batch [ loadCmd, capturedSyncedAt ] )

                Ok AuthExpiredMsg ->
                    ( GuestModel (toGuestState SessionExpired as_)
                    , Cmd.batch [ clearStorage (), stopSync () ]
                    )

                Err _ ->
                    ( AuthModel as_, Cmd.none )

        SignOutClicked ->
            ( GuestModel (toGuestState NotLoggedIn as_)
            , Cmd.batch [ clearStorage (), stopSync () ]
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
            , downloadFile
                { content = CsvExport.toCsv rows
                , filename = filename
                , mimeType = "text/csv"
                }
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
                    List.map (\( id, f ) -> Task.perform (AuthMsg << GotFileUrl id) (File.toUrl f)) indexed
            in
            ( AuthModel { as_ | scanQueue = newQueue }, Cmd.batch urlCmds )

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
            ( AuthModel { as_ | scanQueue = updatedQueue }
            , Cmd.batch
                [ if canScan then
                    -- Always route through the JS-side downscaler before
                    -- the OCR call. Anthropic's image limit is 5 MiB on
                    -- the base64 payload; modern phone JPEGs routinely
                    -- run 6–8 MB so we'd otherwise 400 on every photo.
                    -- We use the EXIF data URL for GPS extraction in
                    -- parallel because exifr needs the original bytes.
                    prepareOcrImage { dataUrl = dataUrl, id = itemId, maxBytes = ocrMaxBase64Bytes }

                  else
                    Cmd.none
                , extractExifGps { id = itemId, dataUrl = dataUrl }
                ]
            )

        OcrImagePrepared payload ->
            case Dict.get payload.id as_.scanQueue of
                Nothing ->
                    -- item was cleared/submitted while resize was in flight — no-op
                    ( AuthModel as_, Cmd.none )

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
                        ( AuthModel { as_ | scanQueue = updatedQueue }, Cmd.none )

                    else
                        let
                            updatedQueue =
                                Dict.update payload.id
                                    (Maybe.map (\i -> { i | imageUrl = payload.dataUrl }))
                                    as_.scanQueue
                        in
                        ( AuthModel { as_ | scanQueue = updatedQueue }
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
            ( AuthModel { as_ | scanQueue = afterGeocodeFlip }
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
            ( AuthModel { as_ | scanQueue = afterGeocodeFlip }
            , Cmd.batch geocodeCmds
            )

        AddressChanged s ->
            authPending (\p -> { p | address = s }) { as_ | duplicateWarning = Nothing }

        AmountChanged s ->
            authPending (\p -> { p | amount = s }) { as_ | duplicateWarning = Nothing }

        CategorySelected c ->
            authPending (\p -> { p | category = c }) as_

        DateChanged s ->
            authPending (\p -> { p | date = s }) { as_ | duplicateWarning = Nothing }

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
                    formPending as_.form

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
                                    , date = parsed.date
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
                                    , date =
                                        if parsed.date /= original.date then
                                            Just parsed.date

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
                                    , form = FreshForm (defaultPendingEntry as_.today)
                                    , route = nextRoute
                                    , scanQueue = updatedQueue
                                    , submitting = False
                                }
                            , Cmd.batch
                                [ sendPouch (SaveAmend editTarget (Amendment.encoder amend))
                                , notifySharedTripActivity as_.creds
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
                                    , date = parsed.date
                                    , geoPoint = parsed.geoPoint
                                    , longNote = parsed.longNote
                                    , merchant = parsed.merchant
                                    , note = parsed.note
                                    , paymentMethod = parsed.paymentMethod
                                    }

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
                                    , form = FreshForm (defaultPendingEntry as_.today)
                                    , route = nextRoute
                                    , scanQueue = updatedQueue
                                    , submitting = False
                                }
                            , Cmd.batch
                                [ sendPouch (SaveExpense addTarget (Expense.encoder expense))
                                , notifySharedTripActivity as_.creds
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
                , notifySharedTripActivity as_.creds
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
            , requestGeolocation ()
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
            , nativeShare
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
            ( AuthModel { as_ | form = mapForm (setLocation (LocationGot (GeoPoint.fromDegrees lat lon) ManualPin)) as_.form, showMapPicker = False }
            , Cmd.none
            )

        DismissMapPicker ->
            ( AuthModel { as_ | showMapPicker = False }, Cmd.none )

        SkipLocation ->
            ( AuthModel { as_ | form = mapForm (setLocation LocationSkipped) as_.form, showMapPicker = False }
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

        GotExifCoords itemId (Just lat) (Just lon) _ ->
            let
                point =
                    GeoPoint.fromDegrees lat lon

                newQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | exif = ExifFound point })) as_.scanQueue
            in
            ( AuthModel (syncScanLocationToForm itemId { as_ | scanQueue = newQueue })
            , Cmd.none
            )

        GotExifCoords itemId _ _ debug ->
            let
                newQueue =
                    Dict.update itemId (Maybe.map (\i -> { i | exif = ExifMissing, exifDebug = debug })) as_.scanQueue
            in
            ( AuthModel (syncScanLocationToForm itemId { as_ | scanQueue = newQueue })
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
            ( AuthModel (syncScanLocationToForm itemId { as_ | scanQueue = newQueue })
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
                                { address = Nothing, amount = Nothing, category = Nothing, date = Nothing, longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }
                                item.ocrData

                        newPending =
                            { address = Maybe.withDefault "" ocr.address
                            , amount =
                                ocr.amount
                                    |> Maybe.map Money.toDollarString
                                    |> Maybe.withDefault ""
                            , category = Maybe.withDefault Fuel ocr.category
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
                    ( AuthModel
                        { as_
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
            ( AuthModel
                { as_
                    | activeScanItemId = Nothing
                    , form = FreshForm (defaultPendingEntry as_.today)
                    , route = newRoute
                }
            , case Routing.routeTripId as_.route of
                Just tid ->
                    Nav.pushUrl as_.key (Routing.tabToPath as_.basePath tid ScanTab)

                Nothing ->
                    Cmd.none
            )

        ClearDoneItems ->
            ( AuthModel { as_ | scanQueue = Dict.filter (\_ i -> i.status /= ScanSubmitted) as_.scanQueue }
            , Cmd.none
            )

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
                                            , Http.SharedTripApi.createSharedTrip as_.creds { name = groupName } (AuthMsg << TripCreateSharedTripResult)
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
                            | form = FreshForm (defaultPendingEntry as_.today)
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

        CanInstall canIt ->
            ( AuthModel { as_ | showInstallPrompt = canIt }, Cmd.none )

        TriggerInstallPrompt ->
            ( AuthModel as_, triggerInstallPrompt () )

        TakeOverBilling flockId ->
            ( AuthModel as_
            , Http.SharedTripApi.transferOwnership
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

        OpenCreateSharedTripModal ->
            ( AuthModel (setSharedTripModal (SharedTripUi.CreateModal { name = "", request = RemoteData.NotAsked }) as_)
            , Cmd.none
            )

        CreateSharedTripNameChanged name ->
            let
                ui =
                    as_.sharedTripUi
            in
            case ui.modal of
                SharedTripUi.CreateModal m ->
                    ( AuthModel { as_ | sharedTripUi = { ui | modal = SharedTripUi.CreateModal { m | name = name } } }
                    , Cmd.none
                    )

                _ ->
                    ( AuthModel as_, Cmd.none )

        SubmitCreateSharedTrip ->
            case as_.sharedTripUi.modal of
                SharedTripUi.CreateModal { name } ->
                    let
                        trimmed =
                            String.trim name
                    in
                    if trimmed == "" then
                        ( AuthModel
                            (updateModalRequest
                                (\m ->
                                    case m of
                                        SharedTripUi.CreateModal data ->
                                            Just
                                                (SharedTripUi.CreateModal
                                                    { data | request = RemoteData.Failure (Http.BadBody "Name is required.") }
                                                )

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
                                        SharedTripUi.CreateModal data ->
                                            Just (SharedTripUi.CreateModal { data | request = RemoteData.Loading })

                                        _ ->
                                            Nothing
                                )
                                as_
                            )
                        , Http.SharedTripApi.createSharedTrip as_.creds { name = trimmed } (AuthMsg << CreateSharedTripResult)
                        )

                _ ->
                    ( AuthModel as_, Cmd.none )

        CreateSharedTripResult result ->
            case RemoteData.fromResult result of
                RemoteData.Success _ ->
                    ( AuthModel
                        (setSharedTripModal SharedTripUi.NoModal
                            { as_ | toast = Just "Shared trip created. It'll show up here once sync settles." }
                        )
                    , toastFor
                    )

                remote ->
                    ( AuthModel
                        (updateModalRequest
                            (\m ->
                                case m of
                                    SharedTripUi.CreateModal data ->
                                        Just (SharedTripUi.CreateModal { data | request = remote })

                                    _ ->
                                        Nothing
                            )
                            as_
                        )
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
                        , Http.SharedTripApi.createSharedTrip as_.creds { name = String.trim draft.groupName } (AuthMsg << ShareTripCreatedResult)
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
            , saveStorage { key = "auth_creds", value = E.encode 0 (encodeCreds refreshedCreds) }
            )

        MeFetched (Err _) ->
            -- Silent failure — /me is a refresh path, not a hard
            -- requirement. The next call (next startup, next post-
            -- checkout return) will retry. The cached `Creds` tier is
            -- already good enough to keep rendering until then.
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
                    , Http.SharedTripApi.inviteToSharedTrip as_.creds flockId { email = email } (AuthMsg << InviteToSharedTripResult)
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
            , Http.SharedTripApi.leaveSharedTrip as_.creds flockId (AuthMsg << LeaveSharedTripResult)
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
                    , Http.SharedTripApi.transferOwnership as_.creds flockId { newOwnerEmail = target } (AuthMsg << TransferToSharedTripResult)
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
            , Http.SharedTripApi.joinSharedTrip as_.creds { token = token } (AuthMsg << JoinSharedTripResult)
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
                    ( AuthModel
                        { as_
                            | joinSharedTripRequest = rd
                            , route = RouteSettings
                            , toast = Just ("Joined " ++ response.name ++ ".")
                        }
                    , Cmd.batch
                        [ Nav.pushUrl as_.key (as_.basePath ++ "settings")
                        , toastFor
                        ]
                    )

                RemoteData.Failure _ ->
                    ( AuthModel { as_ | joinSharedTripRequest = rd }, Cmd.none )

                RemoteData.NotAsked ->
                    ( AuthModel as_, Cmd.none )

                RemoteData.Loading ->
                    ( AuthModel as_, Cmd.none )

        -- PWA notifications (foundation #175): the `notificationState`
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
        -- emit `subscribePush` and let the JS handler request browser
        -- permission first (if needed) and then call
        -- `pushManager.subscribe` inside the same await chain. iOS
        -- Safari requires the entire flow to run within the user-gesture
        -- context AND requires permission to be Granted before
        -- subscribe is called — emitting permission + subscribe in
        -- parallel via Cmd.batch breaks both invariants. The JS handler
        -- re-emits `notificationState` + `pushSubscribeResult` so
        -- `NotificationStateChanged` / `PushSubscribeReceived` update
        -- AuthState.
        RequestPushPermission ->
            ( AuthModel as_
            , subscribePush
                { prefs = Notifications.encodePrefs as_.notificationPrefs
                , vapidPublicKey = as_.config.vapidPublicKey
                }
            )

        -- Optimistic flip of the local pref + fire-and-forget save to
        -- the server. The encoded prefs go to the JS port which PUTs
        -- them to `/notifications/preferences`; if the request fails
        -- we don't roll back (Elm state stays optimistic — the cron
        -- re-checks tier independently). New `NotificationToggle`
        -- variants get a new branch here and the compiler enforces it.
        -- When the last opt-in flips off we also call `unsubscribePush`
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
                [ savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    unsubscribePush ()
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
                [ savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    unsubscribePush ()
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
                [ savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    unsubscribePush ()
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
                [ savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    unsubscribePush ()
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
                [ savePushPrefs (Notifications.encodePrefs newPrefs)
                , if anyEnabled then
                    Cmd.none

                  else
                    unsubscribePush ()
                ]
            )



-- FLOCK HELPERS


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
            [ Html.Attributes.class "bg-parchment dark:bg-cream text-ink min-h-dvh font-body max-w-[480px] mx-auto relative sm:shadow-card sm:border-x sm:border-tan/40 sm:dark:border-moss/20" ]
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

                RouteLedger _ ->
                    Pages.Ledger.viewTab as_

                RouteScan _ ->
                    Pages.Scan.viewTab as_

                RouteSettings ->
                    Pages.Settings.viewTab as_

                RouteStats _ ->
                    Pages.Stats.viewTab as_

                RouteTrips ->
                    Pages.Trips.viewTab as_
    in
    Html.div []
        [ UI.Layout.viewHeader as_
        , UI.Layout.viewOfflineBanner as_.networkOffline
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
                    [ pouchIn (AuthMsg << GotPouchMsg)
                    , gotGpsCoords
                        (\r ->
                            if r.denied then
                                AuthMsg GeolocationDenied

                            else
                                AuthMsg (GotGpsCoords r.lat r.lon)
                        )
                    , gotExifResult
                        (\r ->
                            if r.hasGps then
                                AuthMsg (GotExifCoords r.id (Just r.lat) (Just r.lon) "")

                            else
                                AuthMsg (GotExifCoords r.id Nothing Nothing r.debug)
                        )
                    , networkStatus (SharedMsg << NetworkStatusChanged)
                    , canInstall (AuthMsg << CanInstall)
                    , ocrImagePrepared (AuthMsg << OcrImagePrepared)
                    , notificationState (AuthMsg << NotificationStateChanged)
                    , pushSubscribeResult (AuthMsg << PushSubscribeReceived)
                    , scanProxyIn (AuthMsg << ScanProxyResult)
                    , nativeShareResult (AuthMsg << ShareResultReceived)
                    ]
        , update = update
        , view = view
        }
