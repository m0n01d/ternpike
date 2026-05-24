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
import Data.Auth exposing (AppConfig, Creds)
import Data.Category as Category exposing (Category(..))
import Data.ColorScheme as ColorScheme
import Data.DateField as DateField exposing (DateField)
import Data.Entry as Entry
import Data.Expense as Expense
import Data.ExpenseId as ExpenseId
import Data.GeoPoint as GeoPoint
import Data.Guest exposing (GuestReason(..), GuestSession)
import Data.Iso8601 as Iso8601
import Data.Location exposing (LocationSource(..), LocationState(..))
import Data.Money as Money
import Data.Navigation exposing (Route(..), Tab(..))
import Data.PaymentMethod as PaymentMethod
import Data.PendingEntry as PendingEntry exposing (PendingEntry, PendingForm(..))
import Data.Pouch exposing (DocChange(..), ExpenseBundle, PouchInbound(..), PouchOutbound(..), TripBundle)
import Data.Scan as Scan exposing (OcrData, ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Data.SharedTrip as SharedTrip
import Data.SharedTripId
import Data.SharedTripUi as SharedTripUi
import Data.SharedTrips as SharedTrips
import Data.StatsHover as StatsHover
import Data.Sync exposing (SyncState(..))
import Data.Tier as Tier
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
import Http
import Http.SharedTripApi
import Json.Decode as D
import Json.Decode.Pipeline as Pipeline
import Json.Encode as E
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
import Routing
import Set
import Task
import Time
import Types exposing (AuthState, GuestState, Model(..), Msg(..))
import UI.BillingBanner
import UI.Layout
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


port gotGpsCoords : ({ lat : Float, lon : Float, denied : Bool } -> msg) -> Sub msg


port gotExifResult : ({ id : String, lat : Float, lon : Float, hasGps : Bool, debug : String } -> msg) -> Sub msg


port networkStatus : (Bool -> msg) -> Sub msg


port triggerInstallPrompt : () -> Cmd msg


port canInstall : (Bool -> msg) -> Sub msg



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
    , colorScheme = ColorScheme.Auto
    , config = gs.session.config
    , confirmDeleteTrip = Nothing
    , creds = creds
    , currentUser = UserId.fromString creds.email
    , error = Nothing
    , expenses = Dict.empty
    , sharedTripUi = SharedTripUi.empty
    , sharedTrips = SharedTrips.empty
    , form = FreshForm (defaultPendingEntry gs.today)
    , geoBlocked = False
    , key = gs.key
    , loadingExpenses = Set.empty
    , loadingTrips = Set.empty
    , movePicker = Nothing
    , networkOffline = gs.networkOffline
    , openLedgerMenu = Nothing
    , route = initialRoute
    , scanQueue = Dict.empty
    , showDayIntensity = True
    , showInstallPrompt = False
    , showLedgerMap = False
    , showMapPicker = False
    , statsGranularity = Nothing
    , statsHover = StatsHover.empty
    , submitting = False
    , syncState = NotEnabled
    , tier = Tier.Tern
    , toast = Nothing
    , today = gs.today
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
    , emailInput = ""
    , key = as_.key
    , networkOffline = as_.networkOffline
    , pendingJoinToken = Nothing
    , session = { config = as_.config, reason = reason }
    , showSettings = reason == SessionExpired
    , today = as_.today
    , version = as_.version
    }


credsDecoder : D.Decoder Creds
credsDecoder =
    D.map3 Creds
        (D.field "dbName" D.string)
        (D.field "email" D.string)
        (D.field "password" D.string)


encodeCreds : Creds -> D.Value
encodeCreds c =
    E.object
        [ ( "dbName", E.string c.dbName )
        , ( "email", E.string c.email )
        , ( "password", E.string c.password )
        ]



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
        |> D.andThen
            (\s ->
                case s of
                    "auth_error" ->
                        D.succeed AuthExpired

                    "error" ->
                        D.succeed SyncError

                    "synced" ->
                        D.succeed Synced

                    "syncing" ->
                        D.succeed Syncing

                    _ ->
                        D.succeed NotEnabled
            )



-- CACHE LOOKUPS
--
-- "Effective" means post-amendment, non-voided. See Data.Entry for the
-- definition. These two helpers are the only places in the app that go
-- from cached PouchDB documents → user-facing data.


{-| Every effective expense for one trip, sorted by date.

Pulls only that trip's expenses out of the outer `Dict` (single
`Dict.get`), then hands the rest to `Entry.resolve`. Amendments and voids
are passed in full — `resolve` builds its own indexes per call.

-}
resolveForTrip : TripId.TripId -> AuthState -> List Entry.EffectiveEntry
resolveForTrip tripId as_ =
    Entry.resolve
        (as_.expenses |> Dict.get (TripId.toString tripId) |> Maybe.withDefault Dict.empty |> Dict.values)
        (Dict.values as_.amendments)
        (Dict.values as_.voids)
        tripId


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
    in
    ( hydrateFormForRoute as2, Cmd.batch [ tripCmd, expenseCmd, geoCmd ] )


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
            , expect = Http.expectWhatever RequestCodeResult
            }
        )


verifyCode : String -> GuestState -> ( Model, Cmd Msg )
verifyCode email gs =
    let
        code =
            String.trim gs.codeInput
    in
    if code == "" then
        ( GuestModel { gs | authError = Just "Enter the code from your email." }, Cmd.none )

    else
        ( GuestModel
            { gs
                | authError = Nothing
                , session = { config = gs.session.config, reason = VerifyingCode email code }
            }
        , Http.post
            { url = gs.session.config.backendUrl ++ "/auth/verify-code"
            , body = Http.jsonBody (E.object [ ( "email", E.string email ), ( "code", E.string code ) ])
            , expect = Http.expectJson VerifyCodeResult credsDecoder
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

        TripsFailed _ ->
            state


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

        TripsFailed _ ->
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


toastFor : String -> Cmd Msg
toastFor _ =
    Task.perform (\_ -> ToastExpired) (Process.sleep 4000)


setLocation : LocationState -> PendingEntry -> PendingEntry
setLocation ls p =
    { p | locationState = ls }


freshScanItem : String -> ScanItem
freshScanItem id =
    { exifDebug = ""
    , id = ScanItemId.fromString id
    , imageUrl = ""
    , locationState = LocationCheckingExif
    , ocrData = Nothing
    , status = ScanQueued
    }


authPending : (PendingEntry -> PendingEntry) -> AuthState -> ( Model, Cmd Msg )
authPending f as_ =
    ( AuthModel { as_ | form = mapForm f as_.form }, Cmd.none )



-- OCR


ocrSystemPrompt : String
ocrSystemPrompt =
    "You are a receipt parser. The image may contain one or many receipts (e.g. laid out on a table). Extract expense info for EVERY receipt visible and return ONLY a raw valid JSON array with no markdown, no code fences, no explanation. Each element of the array is one receipt, formatted exactly: {\"amount\": <number>, \"category\": \"<activities|camp|ferry|food|fuel|gear|lodging|medical|misc|parks|shopping|transport>\", \"note\": \"<brief description max 50 chars>\", \"longNote\": \"<detailed description max 560 chars, include what was purchased, where, any relevant context>\", \"merchant\": \"<store name>\", \"address\": \"<street address as printed on receipt, include city and state/region when visible, or null if not visible>\", \"date\": \"<YYYY-MM-DD or null if not visible on receipt>\", \"paymentMethod\": \"<cash|credit|null>\"}. If only one receipt is visible, still return a one-element array. For paymentMethod: use cash if receipt shows cash tendered/change; use credit if receipt shows card/credit/debit/visa/mastercard/chip; use null if unclear. Choose the best matching category. Use parks for national/state park entry fees. Use these note formats by category — fuel: \"$X.XX/gal Xgal Grade\" (e.g. \"$4.29/gal 12.3gal Regular\"); camp: \"$XX/night HookupType\" (e.g. \"$35/night Full\"); lodging: \"$XX/night Xnights\" (e.g. \"$89/night 2nights\"); ferry: \"Origin→Dest vehicle|foot\" (e.g. \"Juneau→Haines car\"); parks: \"PassType ParkName\" (e.g. \"Day Pass Denali\"); activities: \"Xppl Activity\" (e.g. \"2ppl Kayaking\"); food: \"Xppl MealType\" (e.g. \"3ppl Dinner\"); all others: brief description."


makeOcrCall : String -> String -> String -> String -> Cmd Msg
makeOcrCall itemId apiKey base64Data mimeType =
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

        -- Tier override from flags. Defaults to Tern. The auth server's
        -- `/me` endpoint is the long-term source of truth (see CLAUDE.md
        -- "Storage tiers"); this flag exists so the E2E harness can set the
        -- right tier on stub-auth boots without having to mount a fake
        -- session endpoint. Production main.js does not set the flag, so
        -- the default applies until /me is wired.
        initialColorScheme =
            D.decodeValue (D.field "colorScheme" D.string) flagsJson
                |> Result.toMaybe
                |> Maybe.andThen ColorScheme.fromString
                |> Maybe.withDefault ColorScheme.Auto

        initialTier =
            D.decodeValue (D.field "tier" D.string) flagsJson
                |> Result.toMaybe
                |> Maybe.andThen Tier.fromString
                |> Maybe.withDefault Tier.Tern

        initialToday =
            D.decodeValue (D.field "today" DateField.decoder) flagsJson
                |> Result.withDefault epochDate

        cfg =
            { anthropicKey = dec "anthropicKey"
            , backendUrl = dec "backendUrl"
            }

        basePath =
            dec "basePath"

        gs =
            { authError = Nothing
            , basePath = basePath
            , codeInput = ""
            , emailInput = ""
            , key = key
            , networkOffline = False
            , pendingJoinToken = Nothing
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
                initialRoute =
                    Routing.routeFromUrl basePath url

                as_ =
                    { tierBoot | colorScheme = initialColorScheme, tier = initialTier }

                tierBoot =
                    toAuthState creds initialRoute gs
            in
            -- Don't fire route-driven fetches here. Sync hasn't settled
            -- yet, so PouchDB queries would race with replication and
            -- return empty/stale. Wait for SyncStateMsg Synced, which
            -- triggers GetAllTrips; handleTripsFetched then runs
            -- fetchesForRoute once trip data is in hand.
            ( AuthModel as_, Cmd.none )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ( nextModel, cmd ) =
            case model of
                GuestModel gs ->
                    updateGuest msg gs

                AuthModel as_ ->
                    updateAuth msg as_
    in
    case msg of
        UrlChanged _ ->
            ( nextModel, Cmd.batch [ cmd, scrollToTop ] )

        AddressChanged _ ->
            ( nextModel, cmd )

        AmountChanged _ ->
            ( nextModel, cmd )

        ApiKeyChanged _ ->
            ( nextModel, cmd )

        BackToQueue ->
            ( nextModel, cmd )

        CanInstall _ ->
            ( nextModel, cmd )

        CancelDeleteTrip ->
            ( nextModel, cmd )

        CategorySelected _ ->
            ( nextModel, cmd )

        ClearDoneItems ->
            ( nextModel, cmd )

        CloseSharedTripModal ->
            ( nextModel, cmd )

        CloseLedgerMenu ->
            ( nextModel, cmd )

        CloseMovePicker ->
            ( nextModel, cmd )

        CloseTripForm ->
            ( nextModel, cmd )

        CodeInputChanged _ ->
            ( nextModel, cmd )

        ConfirmDeleteTrip _ ->
            ( nextModel, cmd )

        CreateSharedTripNameChanged _ ->
            ( nextModel, cmd )

        CreateSharedTripResult _ ->
            ( nextModel, cmd )

        DateChanged _ ->
            ( nextModel, cmd )

        DeleteTrip _ ->
            ( nextModel, cmd )

        DismissError ->
            ( nextModel, cmd )

        DismissMapPicker ->
            ( nextModel, cmd )

        DuplicateEntry _ ->
            ( nextModel, cmd )

        EmailInputChanged _ ->
            ( nextModel, cmd )

        FilesSelected _ ->
            ( nextModel, cmd )

        GeolocationDenied ->
            ( nextModel, cmd )

        GotDeleteTripTime _ _ ->
            ( nextModel, cmd )

        GotDuplicateTime _ _ ->
            ( nextModel, cmd )

        GotExifCoords _ _ _ _ ->
            ( nextModel, cmd )

        GotFileUrl _ _ ->
            ( nextModel, cmd )

        GotGpsCoords _ _ ->
            ( nextModel, cmd )

        GotMoveTime _ _ _ ->
            ( nextModel, cmd )

        GotOcrResult _ _ ->
            ( nextModel, cmd )

        GotPouchMsg _ ->
            ( nextModel, cmd )

        GotSaveTripTime _ ->
            ( nextModel, cmd )

        GotSubmitTime _ _ ->
            ( nextModel, cmd )

        GotVoidTime _ _ ->
            ( nextModel, cmd )

        HoverCumulativePoints _ ->
            ( nextModel, cmd )

        HoverDailyBars _ ->
            ( nextModel, cmd )

        InviteEmailChanged _ ->
            ( nextModel, cmd )

        InviteToSharedTripResult _ ->
            ( nextModel, cmd )

        JoinSharedTripAccepted _ ->
            ( nextModel, cmd )

        JoinSharedTripDeclined ->
            ( nextModel, cmd )

        JoinSharedTripResult _ ->
            ( nextModel, cmd )

        LeaveSharedTripConfirmed _ ->
            ( nextModel, cmd )

        LeaveSharedTripResult _ ->
            ( nextModel, cmd )

        LinkClicked _ ->
            ( nextModel, cmd )

        LongNoteChanged _ ->
            ( nextModel, cmd )

        MapPickerConfirmed _ _ ->
            ( nextModel, cmd )

        MerchantChanged _ ->
            ( nextModel, cmd )

        MoveEntry _ _ ->
            ( nextModel, cmd )

        NetworkStatusChanged _ ->
            ( nextModel, cmd )

        NoteChanged _ ->
            ( nextModel, cmd )

        OpenCreateSharedTripModal ->
            ( nextModel, cmd )

        OpenEditTripForm _ ->
            ( nextModel, cmd )

        OpenInviteModal _ ->
            ( nextModel, cmd )

        OpenLeaveConfirmModal _ ->
            ( nextModel, cmd )

        OpenLedgerMenu _ ->
            ( nextModel, cmd )

        OpenMapPicker ->
            ( nextModel, cmd )

        OpenMovePicker _ ->
            ( nextModel, cmd )

        OpenNewTripForm ->
            ( nextModel, cmd )

        OpenTransferModal _ ->
            ( nextModel, cmd )

        PaymentMethodChanged _ ->
            ( nextModel, cmd )

        RefreshClicked ->
            ( nextModel, cmd )

        RequestCodeResult _ ->
            ( nextModel, cmd )

        ResetSettingsClicked ->
            ( nextModel, cmd )

        ReviewScanItem _ ->
            ( nextModel, cmd )

        SaveTripForm ->
            ( nextModel, cmd )

        ScrolledToTop ->
            ( nextModel, cmd )

        SetColorScheme _ ->
            ( nextModel, cmd )

        SetStatsGranularity _ ->
            ( nextModel, cmd )

        ShowToast _ ->
            ( nextModel, cmd )

        SignOutClicked ->
            ( nextModel, cmd )

        SkipLocation ->
            ( nextModel, cmd )

        SubmitCode ->
            ( nextModel, cmd )

        SubmitCreateSharedTrip ->
            ( nextModel, cmd )

        SubmitEmail ->
            ( nextModel, cmd )

        SubmitEntry ->
            ( nextModel, cmd )

        SubmitInvite ->
            ( nextModel, cmd )

        SubmitTransfer ->
            ( nextModel, cmd )

        TakeOverBilling _ ->
            ( nextModel, cmd )

        ToastExpired ->
            ( nextModel, cmd )

        ToggleDayIntensity ->
            ( nextModel, cmd )

        ToggleSharedTripMembers _ ->
            ( nextModel, cmd )

        ToggleGuestSettings ->
            ( nextModel, cmd )

        ToggleLedgerMap ->
            ( nextModel, cmd )

        TransferTargetChanged _ ->
            ( nextModel, cmd )

        TransferToSharedTripResult _ ->
            ( nextModel, cmd )

        TriggerInstallPrompt ->
            ( nextModel, cmd )

        TripCreateSharedTripResult _ ->
            ( nextModel, cmd )

        TripFieldChanged _ _ ->
            ( nextModel, cmd )

        TripGroupNameChanged _ ->
            ( nextModel, cmd )

        TripInviteResult _ _ ->
            ( nextModel, cmd )

        TripInviteeAdded ->
            ( nextModel, cmd )

        TripInviteeDraftChanged _ ->
            ( nextModel, cmd )

        TripInviteeRemoved _ ->
            ( nextModel, cmd )

        TripTargetSelected _ ->
            ( nextModel, cmd )

        VerifyCodeResult _ ->
            ( nextModel, cmd )

        VoidEntry _ ->
            ( nextModel, cmd )


scrollToTop : Cmd Msg
scrollToTop =
    Task.perform (\_ -> ScrolledToTop) (Browser.Dom.setViewport 0 0)


updateGuest : Msg -> GuestState -> ( Model, Cmd Msg )
updateGuest msg gs =
    case msg of
        EmailInputChanged s ->
            ( GuestModel { gs | emailInput = s }, Cmd.none )

        SubmitEmail ->
            case gs.session.reason of
                NotLoggedIn ->
                    requestCode gs

                SessionExpired ->
                    requestCode gs

                _ ->
                    ( GuestModel gs, Cmd.none )

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

        CodeInputChanged s ->
            ( GuestModel { gs | codeInput = s }, Cmd.none )

        SubmitCode ->
            case gs.session.reason of
                AwaitingCode email ->
                    verifyCode email gs

                _ ->
                    ( GuestModel gs, Cmd.none )

        VerifyCodeResult result ->
            case ( gs.session.reason, result ) of
                ( VerifyingCode _ _, Ok creds ) ->
                    let
                        as_ =
                            toAuthState creds RouteTrips gs
                    in
                    ( AuthModel as_
                    , Cmd.batch
                        [ saveStorage { key = "auth_creds", value = E.encode 0 (encodeCreds creds) }
                        , startSync (encodeCreds creds)
                        , Nav.replaceUrl gs.key (gs.basePath ++ "trips")
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

        ToggleGuestSettings ->
            ( GuestModel { gs | showSettings = not gs.showSettings }, Cmd.none )

        ApiKeyChanged s ->
            ( GuestModel { gs | session = mapGuestConfig (\c -> { c | anthropicKey = s }) gs.session }
            , saveStorage { key = "anthropic_key", value = s }
            )

        ResetSettingsClicked ->
            ( GuestModel
                { gs
                    | authError = Nothing
                    , codeInput = ""
                    , emailInput = ""
                    , session = { config = { anthropicKey = "", backendUrl = "" }, reason = NotLoggedIn }
                    , showSettings = False
                }
            , clearAllStorage ()
            )

        GotPouchMsg _ ->
            ( GuestModel gs, Cmd.none )

        LinkClicked (Browser.Internal url) ->
            ( GuestModel gs, Nav.pushUrl gs.key (Url.toString url) )

        LinkClicked (Browser.External href) ->
            ( GuestModel gs, Nav.load href )

        NetworkStatusChanged isOnline ->
            ( GuestModel { gs | networkOffline = not isOnline }, Cmd.none )

        -- Messages that only apply to the authenticated state.
        -- They are no-ops here: the GuestModel has no corresponding fields.
        AddressChanged _ ->
            ( GuestModel gs, Cmd.none )

        AmountChanged _ ->
            ( GuestModel gs, Cmd.none )

        BackToQueue ->
            ( GuestModel gs, Cmd.none )

        CanInstall _ ->
            ( GuestModel gs, Cmd.none )

        CancelDeleteTrip ->
            ( GuestModel gs, Cmd.none )

        CategorySelected _ ->
            ( GuestModel gs, Cmd.none )

        ClearDoneItems ->
            ( GuestModel gs, Cmd.none )

        CloseSharedTripModal ->
            ( GuestModel gs, Cmd.none )

        CloseLedgerMenu ->
            ( GuestModel gs, Cmd.none )

        CloseMovePicker ->
            ( GuestModel gs, Cmd.none )

        CloseTripForm ->
            ( GuestModel gs, Cmd.none )

        ConfirmDeleteTrip _ ->
            ( GuestModel gs, Cmd.none )

        CreateSharedTripNameChanged _ ->
            ( GuestModel gs, Cmd.none )

        CreateSharedTripResult _ ->
            ( GuestModel gs, Cmd.none )

        DateChanged _ ->
            ( GuestModel gs, Cmd.none )

        DeleteTrip _ ->
            ( GuestModel gs, Cmd.none )

        DismissError ->
            ( GuestModel gs, Cmd.none )

        DismissMapPicker ->
            ( GuestModel gs, Cmd.none )

        DuplicateEntry _ ->
            ( GuestModel gs, Cmd.none )

        FilesSelected _ ->
            ( GuestModel gs, Cmd.none )

        GeolocationDenied ->
            ( GuestModel gs, Cmd.none )

        GotDeleteTripTime _ _ ->
            ( GuestModel gs, Cmd.none )

        GotDuplicateTime _ _ ->
            ( GuestModel gs, Cmd.none )

        GotExifCoords _ _ _ _ ->
            ( GuestModel gs, Cmd.none )

        GotFileUrl _ _ ->
            ( GuestModel gs, Cmd.none )

        GotGpsCoords _ _ ->
            ( GuestModel gs, Cmd.none )

        GotMoveTime _ _ _ ->
            ( GuestModel gs, Cmd.none )

        GotOcrResult _ _ ->
            ( GuestModel gs, Cmd.none )

        GotSaveTripTime _ ->
            ( GuestModel gs, Cmd.none )

        GotSubmitTime _ _ ->
            ( GuestModel gs, Cmd.none )

        GotVoidTime _ _ ->
            ( GuestModel gs, Cmd.none )

        HoverCumulativePoints _ ->
            ( GuestModel gs, Cmd.none )

        HoverDailyBars _ ->
            ( GuestModel gs, Cmd.none )

        InviteEmailChanged _ ->
            ( GuestModel gs, Cmd.none )

        InviteToSharedTripResult _ ->
            ( GuestModel gs, Cmd.none )

        JoinSharedTripAccepted _ ->
            ( GuestModel gs, Cmd.none )

        JoinSharedTripDeclined ->
            ( GuestModel gs, Cmd.none )

        JoinSharedTripResult _ ->
            ( GuestModel gs, Cmd.none )

        LeaveSharedTripConfirmed _ ->
            ( GuestModel gs, Cmd.none )

        LeaveSharedTripResult _ ->
            ( GuestModel gs, Cmd.none )

        LongNoteChanged _ ->
            ( GuestModel gs, Cmd.none )

        MapPickerConfirmed _ _ ->
            ( GuestModel gs, Cmd.none )

        MerchantChanged _ ->
            ( GuestModel gs, Cmd.none )

        MoveEntry _ _ ->
            ( GuestModel gs, Cmd.none )

        NoteChanged _ ->
            ( GuestModel gs, Cmd.none )

        OpenCreateSharedTripModal ->
            ( GuestModel gs, Cmd.none )

        OpenEditTripForm _ ->
            ( GuestModel gs, Cmd.none )

        OpenInviteModal _ ->
            ( GuestModel gs, Cmd.none )

        OpenLeaveConfirmModal _ ->
            ( GuestModel gs, Cmd.none )

        OpenLedgerMenu _ ->
            ( GuestModel gs, Cmd.none )

        OpenMapPicker ->
            ( GuestModel gs, Cmd.none )

        OpenMovePicker _ ->
            ( GuestModel gs, Cmd.none )

        OpenNewTripForm ->
            ( GuestModel gs, Cmd.none )

        OpenTransferModal _ ->
            ( GuestModel gs, Cmd.none )

        PaymentMethodChanged _ ->
            ( GuestModel gs, Cmd.none )

        RefreshClicked ->
            ( GuestModel gs, Cmd.none )

        ReviewScanItem _ ->
            ( GuestModel gs, Cmd.none )

        SaveTripForm ->
            ( GuestModel gs, Cmd.none )

        ScrolledToTop ->
            ( GuestModel gs, Cmd.none )

        SetColorScheme _ ->
            ( GuestModel gs, Cmd.none )

        SetStatsGranularity _ ->
            ( GuestModel gs, Cmd.none )

        ShowToast _ ->
            ( GuestModel gs, Cmd.none )

        SignOutClicked ->
            ( GuestModel gs, Cmd.none )

        SkipLocation ->
            ( GuestModel gs, Cmd.none )

        SubmitCreateSharedTrip ->
            ( GuestModel gs, Cmd.none )

        SubmitEntry ->
            ( GuestModel gs, Cmd.none )

        SubmitInvite ->
            ( GuestModel gs, Cmd.none )

        SubmitTransfer ->
            ( GuestModel gs, Cmd.none )

        TakeOverBilling _ ->
            ( GuestModel gs, Cmd.none )

        ToastExpired ->
            ( GuestModel gs, Cmd.none )

        ToggleDayIntensity ->
            ( GuestModel gs, Cmd.none )

        ToggleSharedTripMembers _ ->
            ( GuestModel gs, Cmd.none )

        ToggleLedgerMap ->
            ( GuestModel gs, Cmd.none )

        TransferTargetChanged _ ->
            ( GuestModel gs, Cmd.none )

        TransferToSharedTripResult _ ->
            ( GuestModel gs, Cmd.none )

        TriggerInstallPrompt ->
            ( GuestModel gs, Cmd.none )

        TripCreateSharedTripResult _ ->
            ( GuestModel gs, Cmd.none )

        TripFieldChanged _ _ ->
            ( GuestModel gs, Cmd.none )

        TripGroupNameChanged _ ->
            ( GuestModel gs, Cmd.none )

        TripInviteResult _ _ ->
            ( GuestModel gs, Cmd.none )

        TripInviteeAdded ->
            ( GuestModel gs, Cmd.none )

        TripInviteeDraftChanged _ ->
            ( GuestModel gs, Cmd.none )

        TripInviteeRemoved _ ->
            ( GuestModel gs, Cmd.none )

        TripTargetSelected _ ->
            ( GuestModel gs, Cmd.none )

        UrlChanged _ ->
            ( GuestModel gs, Cmd.none )

        VoidEntry _ ->
            ( GuestModel gs, Cmd.none )


updateAuth : Msg -> AuthState -> ( Model, Cmd Msg )
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

                        cmd =
                            if syncSettledEdge && tripsStillLoading then
                                sendPouch GetAllTrips

                            else
                                Cmd.none
                    in
                    ( AuthModel { as_ | syncState = state }, cmd )

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

        ResetSettingsClicked ->
            ( GuestModel
                { authError = Nothing
                , basePath = as_.basePath
                , codeInput = ""
                , emailInput = ""
                , key = as_.key
                , networkOffline = as_.networkOffline
                , pendingJoinToken = Nothing
                , session = { config = { anthropicKey = "", backendUrl = "" }, reason = NotLoggedIn }
                , showSettings = False
                , today = as_.today
                , version = as_.version
                }
            , Cmd.batch [ clearAllStorage (), stopSync () ]
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
                ocrList =
                    case result of
                        Ok responseBody ->
                            case D.decodeString claudeTextDecoder responseBody of
                                Ok innerJson ->
                                    case D.decodeString Scan.ocrDataListDecoder (stripCodeFence innerJson) of
                                        Ok list ->
                                            list

                                        Err _ ->
                                            []

                                Err _ ->
                                    []

                        Err _ ->
                            []

                updatedQueue =
                    case ( Dict.get itemId as_.scanQueue, ocrList ) of
                        ( Just source, first :: second :: rest ) ->
                            let
                                splits =
                                    first :: second :: rest

                                queueWithoutSource =
                                    Dict.remove itemId as_.scanQueue

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
                                            , { exifDebug = source.exifDebug
                                              , id = ScanItemId.fromString rawId
                                              , imageUrl = source.imageUrl
                                              , locationState = source.locationState
                                              , ocrData = Just data
                                              , status = ScanReady
                                              }
                                            )
                                        )
                                        splits
                            in
                            List.foldl (\( id, item ) d -> Dict.insert id item d) queueWithoutSource indexed

                        _ ->
                            let
                                singleData =
                                    List.head ocrList
                            in
                            Dict.update itemId (Maybe.map (\i -> { i | status = ScanReady, ocrData = singleData })) as_.scanQueue
            in
            ( AuthModel { as_ | scanQueue = updatedQueue }, Cmd.none )

        AddressChanged s ->
            authPending (\p -> { p | address = s }) as_

        AmountChanged s ->
            authPending (\p -> { p | amount = s }) as_

        CategorySelected c ->
            authPending (\p -> { p | category = c }) as_

        DateChanged s ->
            authPending (\p -> { p | date = s }) as_

        LongNoteChanged s ->
            authPending (\p -> { p | longNote = s }) as_

        MerchantChanged s ->
            authPending (\p -> { p | merchant = s }) as_

        NoteChanged s ->
            authPending (\p -> { p | note = s }) as_

        PaymentMethodChanged pm ->
            authPending (\p -> { p | paymentMethod = pm }) as_

        SubmitEntry ->
            case PendingEntry.parseEntry (formPending as_.form) of
                Ok parsed ->
                    ( AuthModel { as_ | submitting = True, error = Nothing }
                    , Task.perform (GotSubmitTime parsed) Time.now
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
                            in
                            ( AuthModel
                                { as_
                                    | activeScanItemId = Nothing
                                    , form = FreshForm (defaultPendingEntry as_.today)
                                    , route = nextRoute
                                    , scanQueue = updatedQueue
                                    , submitting = False
                                }
                            , Cmd.batch
                                [ sendPouch (SaveAmend (targetForTripId original.tripId as_) (Amendment.encoder amend))
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
                            in
                            ( AuthModel
                                { as_
                                    | activeScanItemId = Nothing
                                    , form = FreshForm (defaultPendingEntry as_.today)
                                    , route = nextRoute
                                    , scanQueue = updatedQueue
                                    , submitting = False
                                }
                            , Cmd.batch
                                [ sendPouch (SaveExpense (targetForTripId tripId as_) (Expense.encoder expense))
                                , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath tripId nextTab)
                                ]
                            )

                        _ ->
                            ( AuthModel { as_ | submitting = False }, Cmd.none )

        VoidEntry expense ->
            ( AuthModel { as_ | openLedgerMenu = Nothing }
            , Task.perform (GotVoidTime expense) Time.now
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
            in
            ( AuthModel { as_ | voids = Dict.insert voidId optimisticVoid as_.voids }
            , sendPouch
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
            )

        DuplicateEntry expense ->
            ( AuthModel { as_ | openLedgerMenu = Nothing }
            , Task.perform (GotDuplicateTime expense) Time.now
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
                , toastFor "Duplicated"
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

        MoveEntry expense newTripId ->
            if newTripId == expense.tripId then
                ( AuthModel { as_ | movePicker = Nothing }, Cmd.none )

            else
                ( AuthModel { as_ | movePicker = Nothing }
                , Task.perform (GotMoveTime expense newTripId) Time.now
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
                , toastFor "Moved"
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

        ApiKeyChanged s ->
            let
                cfg =
                    as_.config
            in
            ( AuthModel { as_ | config = { cfg | anthropicKey = s } }
            , saveStorage { key = "anthropic_key", value = s }
            )

        SetColorScheme scheme ->
            ( AuthModel { as_ | colorScheme = scheme }
            , saveStorage { key = "color_scheme", value = ColorScheme.toString scheme }
            )

        DismissError ->
            ( AuthModel { as_ | error = Nothing }, Cmd.none )

        GotGpsCoords lat lon ->
            authPending (setLocation (LocationGot (GeoPoint.fromDegrees lat lon) BrowserGeo)) as_

        GeolocationDenied ->
            ( AuthModel { as_ | geoBlocked = True, form = mapForm (setLocation LocationIdle) as_.form }
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
            ( AuthModel { as_ | showLedgerMap = not as_.showLedgerMap }, Cmd.none )

        SetStatsGranularity g ->
            ( AuthModel { as_ | statsGranularity = Just g }, Cmd.none )

        ShowToast message ->
            ( AuthModel { as_ | toast = Just message }, toastFor message )

        ToastExpired ->
            ( AuthModel { as_ | toast = Nothing }, Cmd.none )

        GotExifCoords itemId (Just lat) (Just lon) _ ->
            ( AuthModel { as_ | scanQueue = Dict.update itemId (Maybe.map (\i -> { i | locationState = LocationGot (GeoPoint.fromDegrees lat lon) ExifGps })) as_.scanQueue }
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
                            , locationState = item.locationState
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
            case ( as_.tripForm, result ) of
                ( Nothing, _ ) ->
                    ( AuthModel as_, Cmd.none )

                ( Just form, Err err ) ->
                    ( AuthModel
                        { as_
                            | tripForm =
                                Just
                                    { form
                                        | submitting = False
                                        , errors = [ flockErrorMessage err ]
                                    }
                        }
                    , Cmd.none
                    )

                ( Just form, Ok response ) ->
                    let
                        invitees =
                            case form.target of
                                Trip.ToNewFlock draft ->
                                    draft.invitees

                                _ ->
                                    []

                        inviteCmds =
                            List.indexedMap
                                (\i email ->
                                    Http.SharedTripApi.inviteToSharedTrip
                                        as_.creds
                                        response.sharedTripId
                                        { email = email }
                                        (TripInviteResult i)
                                )
                                invitees

                        updatedForm =
                            { form | target = Trip.ToExistingFlock response.sharedTripId }
                    in
                    ( AuthModel { as_ | tripForm = Just updatedForm }
                    , Cmd.batch
                        ([ sendPouch
                            (OpenSharedTrip
                                { flockId = response.sharedTripId
                                , dbName = "sharedtrip-" ++ Data.SharedTripId.toString response.sharedTripId
                                }
                            )
                         , Task.perform GotSaveTripTime Time.now
                         ]
                            ++ inviteCmds
                        )
                    )

        TripInviteResult _ _ ->
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
                                            ( AuthModel { as_ | tripForm = Just { form | submitting = True, errors = [] } }
                                            , Http.SharedTripApi.createSharedTrip as_.creds { name = groupName } TripCreateSharedTripResult
                                            )

                                        _ ->
                                            -- Personal / existing-flock: same path as before, get a
                                            -- timestamp then write the trip.
                                            ( AuthModel { as_ | tripForm = Just { form | submitting = True } }
                                            , Task.perform GotSaveTripTime Time.now
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
                        [ Task.perform (GotDeleteTripTime trip) Time.now
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
                        [ Task.perform (GotDeleteTripTime trip) Time.now
                        , Nav.pushUrl as_.key (as_.basePath ++ "trips")
                        ]
                    )

                other ->
                    ( AuthModel { as_ | confirmDeleteTrip = Nothing, trips = other }
                    , Task.perform (GotDeleteTripTime trip) Time.now
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

        LinkClicked (Browser.Internal url) ->
            ( AuthModel as_, Nav.pushUrl as_.key (Url.toString url) )

        LinkClicked (Browser.External href) ->
            ( AuthModel as_, Nav.load href )

        UrlChanged url ->
            let
                newRoute =
                    Routing.routeFromUrl as_.basePath url

                ( as1, cmd ) =
                    fetchesForRoute { as_ | route = newRoute, tripForm = Nothing }
            in
            ( AuthModel as1, cmd )

        NetworkStatusChanged isOnline ->
            ( AuthModel { as_ | networkOffline = not isOnline }, Cmd.none )

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
                TransferToSharedTripResult
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
            ( AuthModel (setSharedTripModal (SharedTripUi.CreateModal { error = Nothing, name = "" }) as_)
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
            let
                ui =
                    as_.sharedTripUi
            in
            case ui.modal of
                SharedTripUi.CreateModal { name } ->
                    let
                        trimmed =
                            String.trim name
                    in
                    if trimmed == "" then
                        let
                            newModal =
                                SharedTripUi.CreateModal { error = Just "Name is required.", name = name }
                        in
                        ( AuthModel { as_ | sharedTripUi = { ui | modal = newModal } }
                        , Cmd.none
                        )

                    else
                        ( AuthModel (setFlockInFlight True as_)
                        , Http.SharedTripApi.createSharedTrip as_.creds { name = trimmed } CreateSharedTripResult
                        )

                _ ->
                    ( AuthModel as_, Cmd.none )

        CreateSharedTripResult (Err err) ->
            ( AuthModel (storeFlockError err as_), Cmd.none )

        CreateSharedTripResult (Ok _) ->
            ( AuthModel
                (setSharedTripModal SharedTripUi.NoModal
                    { as_
                        | toast = Just "Shared trip created. It'll show up here once sync settles."
                    }
                )
            , toastFor "Shared trip created."
            )

        OpenInviteModal flockId ->
            ( AuthModel (setSharedTripModal (SharedTripUi.InviteModal flockId { email = "", error = Nothing }) as_)
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
                    ( AuthModel (setFlockInFlight True as_)
                    , Http.SharedTripApi.inviteToSharedTrip as_.creds flockId { email = email } InviteToSharedTripResult
                    )

                _ ->
                    ( AuthModel as_, Cmd.none )

        InviteToSharedTripResult (Err err) ->
            ( AuthModel (storeFlockError err as_), Cmd.none )

        InviteToSharedTripResult (Ok ()) ->
            ( AuthModel
                (setSharedTripModal SharedTripUi.NoModal
                    { as_
                        | toast = Just "Invite sent."
                    }
                )
            , toastFor "Invite sent."
            )

        OpenLeaveConfirmModal flockId ->
            ( AuthModel (setSharedTripModal (SharedTripUi.LeaveConfirmModal flockId { error = Nothing }) as_)
            , Cmd.none
            )

        LeaveSharedTripConfirmed flockId ->
            ( AuthModel (setFlockInFlight True as_)
            , Http.SharedTripApi.leaveSharedTrip as_.creds flockId LeaveSharedTripResult
            )

        LeaveSharedTripResult (Err err) ->
            ( AuthModel (storeFlockError err as_), Cmd.none )

        LeaveSharedTripResult (Ok ()) ->
            ( AuthModel (setSharedTripModal SharedTripUi.NoModal { as_ | toast = Just "Left shared trip." })
            , toastFor "Left shared trip."
            )

        OpenTransferModal flockId ->
            ( AuthModel (setSharedTripModal (SharedTripUi.TransferModal flockId { error = Nothing, target = "" }) as_)
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
                    ( AuthModel (setFlockInFlight True as_)
                    , Http.SharedTripApi.transferOwnership as_.creds flockId { newOwnerEmail = target } TransferToSharedTripResult
                    )

                _ ->
                    ( AuthModel as_, Cmd.none )

        TransferToSharedTripResult (Err err) ->
            ( AuthModel (storeFlockError err as_), Cmd.none )

        TransferToSharedTripResult (Ok ()) ->
            ( AuthModel (setSharedTripModal SharedTripUi.NoModal { as_ | toast = Just "Ownership transferred." })
            , toastFor "Ownership transferred."
            )

        JoinSharedTripAccepted token ->
            ( AuthModel as_
            , Http.SharedTripApi.joinSharedTrip as_.creds { token = token } JoinSharedTripResult
            )

        JoinSharedTripDeclined ->
            ( AuthModel { as_ | route = RouteTrips }
            , Nav.pushUrl as_.key (as_.basePath ++ "trips")
            )

        JoinSharedTripResult (Ok response) ->
            ( AuthModel
                { as_
                    | route = RouteSettings
                    , toast = Just ("Joined " ++ response.name ++ ".")
                }
            , Cmd.batch
                [ Nav.pushUrl as_.key (as_.basePath ++ "settings")
                , toastFor ("Joined " ++ response.name ++ ".")
                ]
            )

        JoinSharedTripResult (Err err) ->
            ( AuthModel { as_ | error = Just (joinErrorMessage err) }, Cmd.none )

        -- Messages that only apply to the guest (unauthenticated) state.
        -- They reach updateAuth when the top-level update dispatches before
        -- model state has been evaluated — return unchanged.
        CodeInputChanged _ ->
            ( AuthModel as_, Cmd.none )

        EmailInputChanged _ ->
            ( AuthModel as_, Cmd.none )

        RequestCodeResult _ ->
            ( AuthModel as_, Cmd.none )

        ScrolledToTop ->
            ( AuthModel as_, Cmd.none )

        SubmitCode ->
            ( AuthModel as_, Cmd.none )

        SubmitEmail ->
            ( AuthModel as_, Cmd.none )

        ToggleGuestSettings ->
            ( AuthModel as_, Cmd.none )

        VerifyCodeResult _ ->
            ( AuthModel as_, Cmd.none )



-- FLOCK HELPERS


setSharedTripModal : SharedTripUi.SharedTripModal -> AuthState -> AuthState
setSharedTripModal modal as_ =
    let
        ui =
            as_.sharedTripUi
    in
    { as_ | sharedTripUi = { ui | inFlight = False, modal = modal } }


setFlockInFlight : Bool -> AuthState -> AuthState
setFlockInFlight v as_ =
    let
        ui =
            as_.sharedTripUi
    in
    { as_ | sharedTripUi = { ui | inFlight = v } }


storeFlockError : Http.Error -> AuthState -> AuthState
storeFlockError err as_ =
    let
        message =
            flockErrorMessage err

        ui =
            as_.sharedTripUi

        newModal =
            case ui.modal of
                SharedTripUi.CreateModal m ->
                    SharedTripUi.CreateModal { m | error = Just message }

                SharedTripUi.InviteModal id m ->
                    SharedTripUi.InviteModal id { m | error = Just message }

                SharedTripUi.LeaveConfirmModal id _ ->
                    SharedTripUi.LeaveConfirmModal id { error = Just message }

                SharedTripUi.TransferModal id m ->
                    SharedTripUi.TransferModal id { m | error = Just message }

                SharedTripUi.NoModal ->
                    SharedTripUi.NoModal
    in
    { as_ | sharedTripUi = { ui | inFlight = False, modal = newModal } }


flockErrorMessage : Http.Error -> String
flockErrorMessage err =
    case err of
        Http.BadStatus 403 ->
            "Not allowed. Refresh and try again."

        Http.BadStatus 404 ->
            "That flock wasn't found."

        Http.BadStatus 409 ->
            "Already a member."

        Http.BadStatus 422 ->
            "Request rejected. Check the details and try again."

        Http.NetworkError ->
            "Network error. Try again."

        Http.Timeout ->
            "Took too long. Try again."

        _ ->
            "Something went wrong. Try again."


joinErrorMessage : Http.Error -> String
joinErrorMessage err =
    case err of
        Http.BadStatus 401 ->
            "This invite is no longer valid. Ask the inviter for a fresh link."

        Http.BadStatus 403 ->
            "This invite is for someone else."

        Http.BadStatus 404 ->
            "Invite expired or already used."

        Http.BadStatus 409 ->
            "You're already a member of that flock."

        Http.BadStatus 410 ->
            "This invite has expired. Ask the inviter for a fresh link."

        _ ->
            flockErrorMessage err



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "Ternpike"
    , body =
        [ Html.div
            [ Html.Attributes.class "bg-parchment dark:bg-cream text-ink min-h-screen font-body max-w-[480px] mx-auto relative" ]
            [ case model of
                GuestModel gs ->
                    viewGuest gs

                AuthModel as_ ->
                    viewAuth as_
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
        , Html.div [ Html.Attributes.class "pb-20" ]
            [ UI.Layout.page
                { actions = tab.actions
                , body = tab.body
                , hero = tab.hero
                , route = route
                }
            ]
        , UI.Layout.viewBottomNav as_
        , case as_.confirmDeleteTrip of
            Just trip ->
                UI.Layout.viewDeleteConfirmModal trip

            Nothing ->
                Html.text ""
        , case ( as_.movePicker, as_.trips ) of
            ( Just expense, TripsLoaded loadedTrips ) ->
                UI.TripPicker.viewMove
                    { expense = expense
                    , flocks = as_.sharedTrips
                    , trips = Trips.allTrips loadedTrips
                    }

            _ ->
                Html.text ""
        , Pages.Settings.SharedTrips.viewModal as_
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
                            Html.text ""

                Nothing ->
                    Html.text ""

        _ ->
            Html.text ""



-- MAIN


main : Program D.Value Model Msg
main =
    Browser.application
        { init = init
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        , subscriptions =
            \_ ->
                Sub.batch
                    [ pouchIn GotPouchMsg
                    , gotGpsCoords
                        (\r ->
                            if r.denied then
                                GeolocationDenied

                            else
                                GotGpsCoords r.lat r.lon
                        )
                    , gotExifResult
                        (\r ->
                            if r.hasGps then
                                GotExifCoords r.id (Just r.lat) (Just r.lon) ""

                            else
                                GotExifCoords r.id Nothing Nothing r.debug
                        )
                    , networkStatus NetworkStatusChanged
                    , canInstall CanInstall
                    ]
        , update = update
        , view = view
        }
