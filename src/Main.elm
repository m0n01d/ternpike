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

    expenses   : Dict String (Dict String Expense)
                   -- outer key = TripId.toString, inner key = ExpenseId.toString
    amendments : Dict String Amendment   -- keyed by amendment ID
    voids      : Dict String Void        -- keyed by void ID
    trips      : TripsState

Single-trip lookup is a `Dict.get` on the outer expenses dict.
`Data.Entry.resolve` folds amendments and applies voids to produce the
user-facing `EffectiveEntry` list.

# Flow

  1. `init` reads cached creds from JS flags and either constructs a
     `GuestModel` or jumps straight to `AuthModel` and starts CouchDB sync.
  2. The first time sync settles (`SyncStateMsg Synced`), we send
     `GetAllTrips`. We do **not** fetch on login — that would race with
     the initial sync pull.
  3. Each route transition runs `fetchesForRoute`, which fires only the
     PouchDB queries needed for that route (idempotent — guarded by
     `tripLoaded` / `loadingExpenses`).
  4. PouchDB's live-changes feed pushes every local or synced write
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
import Browser.Navigation as Nav
import Data.Amendment as Amendment
import Data.Category as Category exposing (Category(..))
import Data.Entry as Entry
import Data.Expense as Expense
import Data.ExpenseId as ExpenseId
import Data.PaymentMethod as PaymentMethod
import Data.Trip as Trip exposing (Trip, TripField(..))
import Data.TripId as TripId
import Data.Trips as Trips
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
import Set
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


port startSync : D.Value -> Cmd msg


port stopSync : () -> Cmd msg


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
    { activeScanItemId  = Nothing
    , amendments        = Dict.empty
    , basePath          = gs.basePath
    , config            = gs.session.config
    , confirmDeleteTrip = Nothing
    , creds             = creds
    , error             = Nothing
    , expenses          = Dict.empty
    , form              = FreshForm (defaultPendingEntry gs.today)
    , geoBlocked        = False
    , key               = gs.key
    , loadingExpenses   = Set.empty
    , loadingTrips      = Set.empty
    , route             = initialRoute
    , scanQueue         = Dict.empty
    , showLedgerMap     = False
    , showMapPicker     = False
    , submitting        = False
    , syncState         = NotEnabled
    , toast             = Nothing
    , today             = gs.today
    , tripForm          = Nothing
    , tripLoaded        = Set.empty
    , trips             = TripsLoading Dict.empty (Routing.routeTripId initialRoute)
    , version           = gs.version
    , voids             = Dict.empty
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

        GetExpense id ->
            E.object
                [ ( "tag", E.string "GetExpense" )
                , ( "expenseId", E.string (ExpenseId.toString id) )
                ]

        GetTripExpenses id ->
            E.object
                [ ( "tag", E.string "GetTripExpenses" )
                , ( "tripId", E.string (TripId.toString id) )
                ]

        SaveAmend doc   -> E.object [ ( "tag", E.string "SaveAmend" ),   ( "doc", doc ) ]
        SaveExpense doc -> E.object [ ( "tag", E.string "SaveExpense" ), ( "doc", doc ) ]
        SaveTrip doc    -> E.object [ ( "tag", E.string "SaveTrip" ),    ( "doc", doc ) ]
        SaveVoid doc    -> E.object [ ( "tag", E.string "SaveVoid" ),    ( "doc", doc ) ]


sendPouch : PouchOutbound -> Cmd Msg
sendPouch =
    pouchOut << encodePouchOut


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

                    "ExpenseLoaded" ->
                        D.map2 ExpenseFetched
                            (D.field "expenseId" ExpenseId.decode)
                            expenseBundleDecoder

                    "SyncState" ->
                        D.map SyncStateMsg (D.field "state" syncStateDecoder)

                    "TripExpensesLoaded" ->
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
                    "amend"   -> D.map AmendChanged   Amendment.decoder
                    "expense" -> D.map ExpenseChanged Expense.decoder
                    "trip"    -> D.map TripChanged    Trip.decoder
                    "void"    -> D.map VoidChanged    Void.decoder
                    _         -> D.fail ("Unknown doc type: " ++ t)
            )


tripBundleDecoder : D.Decoder TripBundle
tripBundleDecoder =
    D.map3 TripBundle
        (D.field "amendments" (D.dict Amendment.decoder))
        (D.field "expenses"   (D.dict Expense.decoder))
        (D.field "voids"      (D.dict Void.decoder))


expenseBundleDecoder : D.Decoder ExpenseBundle
expenseBundleDecoder =
    D.map3 ExpenseBundle
        (D.field "amendments" (D.dict Amendment.decoder))
        (D.field "expense"    (D.nullable Expense.decoder))
        (D.field "void"       (D.nullable Void.decoder))


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
        EditForm id p -> EditForm id (f p)
        FreshForm p   -> FreshForm (f p)


formPending : PendingForm -> PendingEntry
formPending form =
    case form of
        EditForm _ p -> p
        FreshForm p  -> p


{-| Build a `Route` from a `Tab` plus a tripId. Used for navigations
where the destination tab is known but the route needs the active
trip stitched in (post-submit redirect, scan-to-add handoff, etc.).
Tabs that aren't trip-scoped (Settings, Trips) ignore the tripId.
-}
routeForTab : Tab -> TripId.TripId -> Route
routeForTab tab tripId =
    case tab of
        AddTab      -> RouteAdd tripId
        LedgerTab   -> RouteLedger tripId
        ScanTab     -> RouteScan tripId
        SettingsTab -> RouteSettings
        StatsTab    -> RouteStats tripId
        TripsTab    -> RouteTrips


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
                        EditForm formId _ -> formId == id
                        FreshForm _       -> False
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
                        , sendPouch (GetTripExpenses tid)
                        )

                Nothing ->
                    ( as_, Cmd.none )

        ( as2, expenseCmd ) =
            case as1.route of
                RouteEditEntry _ eid ->
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
                        , sendPouch (GetExpense eid)
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
                    { as_ | amendments = Dict.insert a.id a as_.amendments }

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
                , expenses   = Dict.map (\_ inner -> Dict.remove id inner) as_.expenses
                , trips      = removeTripFromState (TripId.fromString id) as_.trips
                , voids      = Dict.remove id as_.voids
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
        email = String.trim gs.emailInput
    in
    if email == "" then
        ( GuestModel { gs | authError = Just "Enter your email address." }, Cmd.none )

    else
        ( GuestModel
            { gs
                | authError = Nothing
                , session   = { config = gs.session.config, reason = RequestingCode email }
            }
        , Http.post
            { url    = "/auth/request-code"
            , body   = Http.jsonBody (E.object [ ( "email", E.string email ) ])
            , expect = Http.expectWhatever RequestCodeResult
            }
        )


verifyCode : String -> GuestState -> ( Model, Cmd Msg )
verifyCode email gs =
    let
        code = String.trim gs.codeInput
    in
    if code == "" then
        ( GuestModel { gs | authError = Just "Enter the code from your email." }, Cmd.none )

    else
        ( GuestModel
            { gs
                | authError = Nothing
                , session   = { config = gs.session.config, reason = VerifyingCode email code }
            }
        , Http.post
            { url    = "/auth/verify-code"
            , body   = Http.jsonBody (E.object [ ( "email", E.string email ), ( "code", E.string code ) ])
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


defaultPendingEntry : String -> PendingEntry
defaultPendingEntry today =
    { amount        = ""
    , category      = Fuel
    , date          = today
    , locationState = LocationIdle
    , longNote      = ""
    , merchant      = ""
    , note          = ""
    , paymentMethod = Nothing
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
    { exifDebug     = ""
    , id            = id
    , imageUrl      = ""
    , locationState = LocationCheckingExif
    , ocrData       = Nothing
    , status        = ScanQueued
    }


authPending : (PendingEntry -> PendingEntry) -> AuthState -> ( Model, Cmd Msg )
authPending f as_ =
    ( AuthModel { as_ | form = mapForm f as_.form }, Cmd.none )



-- OCR


ocrSystemPrompt : String
ocrSystemPrompt =
    "You are a receipt parser. Extract expense info and return ONLY raw valid JSON with no markdown, no code fences, no explanation. Format exactly: {\"amount\": <number>, \"category\": \"<activities|camp|ferry|food|fuel|gear|lodging|medical|misc|parks|shopping|transport>\", \"note\": \"<brief description max 50 chars>\", \"longNote\": \"<detailed description max 560 chars, include what was purchased, where, any relevant context>\", \"merchant\": \"<store name>\", \"date\": \"<YYYY-MM-DD or null if not visible on receipt>\", \"paymentMethod\": \"<cash|credit|null>\"}. For paymentMethod: use cash if receipt shows cash tendered/change; use credit if receipt shows card/credit/debit/visa/mastercard/chip; use null if unclear. Choose the best matching category. Use parks for national/state park entry fees. Use these note formats by category — fuel: \"$X.XX/gal Xgal Grade\" (e.g. \"$4.29/gal 12.3gal Regular\"); camp: \"$XX/night HookupType\" (e.g. \"$35/night Full\"); lodging: \"$XX/night Xnights\" (e.g. \"$89/night 2nights\"); ferry: \"Origin→Dest vehicle|foot\" (e.g. \"Juneau→Haines car\"); parks: \"PassType ParkName\" (e.g. \"Day Pass Denali\"); activities: \"Xppl Activity\" (e.g. \"2ppl Kayaking\"); food: \"Xppl MealType\" (e.g. \"3ppl Dinner\"); all others: brief description."


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
        |> Pipeline.optional "amount"        (D.map Just D.float) Nothing
        |> Pipeline.optional "category"      (D.map Just (D.map Category.fromString D.string)) Nothing
        |> Pipeline.optional "date"          (D.map Just D.string) Nothing
        |> Pipeline.optional "longNote"      (D.map Just D.string) Nothing
        |> Pipeline.optional "merchant"      (D.map Just D.string) Nothing
        |> Pipeline.optional "note"          (D.map Just D.string) Nothing
        |> Pipeline.optional "paymentMethod"
            (D.nullable
                (D.string
                    |> D.andThen
                        (\s ->
                            case PaymentMethod.fromString s of
                                Just pm -> D.succeed pm
                                Nothing -> D.fail ("Unknown paymentMethod: " ++ s)
                        )
                )
            )
            Nothing


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

        authCreds =
            D.decodeValue (D.field "authCreds" (D.nullable credsDecoder)) flagsJson
                |> Result.withDefault Nothing

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
    case authCreds of
        Nothing ->
            ( GuestModel gs, Cmd.none )

        Just creds ->
            let
                initialRoute =
                    Routing.routeFromUrl basePath url

                as_ =
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
                            , session   = { config = gs.session.config, reason = AwaitingCode email }
                        }
                    , Cmd.none
                    )

                ( RequestingCode _, Err _ ) ->
                    ( GuestModel
                        { gs
                            | authError = Just "Could not send code. Try again."
                            , session   = { config = gs.session.config, reason = NotLoggedIn }
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
                        as_ = toAuthState creds RouteTrips gs
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
                            , session   = { config = gs.session.config, reason = AwaitingCode email }
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
                    | authError    = Nothing
                    , codeInput    = ""
                    , emailInput   = ""
                    , session      = { config = { anthropicKey = "", backendUrl = "" }, reason = NotLoggedIn }
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

        _ ->
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
                                | amendments   = Dict.union bundle.amendments as_.amendments
                                , expenses     = Dict.insert key bundle.expenses as_.expenses
                                , loadingTrips = Set.remove key as_.loadingTrips
                                , tripLoaded   = Set.insert key as_.tripLoaded
                                , voids        = Dict.union bundle.voids as_.voids
                            }
                    in
                    ( AuthModel (hydrateFormForRoute as1), Cmd.none )

                Ok (ExpenseFetched eid bundle) ->
                    let
                        as1 =
                            { as_
                                | amendments      = Dict.union bundle.amendments as_.amendments
                                , expenses        =
                                    case bundle.expense of
                                        Just e ->
                                            Dict.update (TripId.toString e.tripId)
                                                (Just << Dict.insert (ExpenseId.toString e.id) e << Maybe.withDefault Dict.empty)
                                                as_.expenses

                                        Nothing ->
                                            as_.expenses
                                , loadingExpenses = Set.remove (ExpenseId.toString eid) as_.loadingExpenses
                                , voids           =
                                    case bundle.void of
                                        Just v  -> Dict.insert v.id v as_.voids
                                        Nothing -> as_.voids
                            }
                    in
                    ( AuthModel (hydrateFormForRoute as1), Cmd.none )

                Ok (DbError msg_) ->
                    ( AuthModel { as_ | error = Just msg_ }, Cmd.none )

                Ok (SyncStateMsg state) ->
                    let
                        syncSettledEdge =
                            state == Synced && as_.syncState /= Synced

                        tripsStillLoading =
                            case as_.trips of
                                TripsLoading _ _ -> True
                                _                -> False

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

        AmountChanged s        -> authPending (\p -> { p | amount = s }) as_
        CategorySelected c     -> authPending (\p -> { p | category = c }) as_
        DateChanged s          -> authPending (\p -> { p | date = s }) as_
        LongNoteChanged s      -> authPending (\p -> { p | longNote = s }) as_
        MerchantChanged s      -> authPending (\p -> { p | merchant = s }) as_
        NoteChanged s          -> authPending (\p -> { p | note = s }) as_
        PaymentMethodChanged pm -> authPending (\p -> { p | paymentMethod = pm }) as_

        SubmitEntry ->
            case String.toFloat (formPending as_.form).amount of
                Just _ ->
                    ( AuthModel { as_ | submitting = True, error = Nothing }
                    , Task.perform GotSubmitTime Time.now
                    )
                Nothing ->
                    ( AuthModel { as_ | error = Just "Enter a valid amount." }, Cmd.none )

        GotSubmitTime posix ->
            let
                p         = formPending as_.form
                timestamp = String.fromInt (Time.posixToMillis posix)

                ( eLat, eLon ) =
                    case p.locationState of
                        LocationGot la lo _ -> ( Just la, Just lo )
                        _                   -> ( Nothing, Nothing )

                updatedQueue =
                    case as_.activeScanItemId of
                        Just id -> Dict.update id (Maybe.map (\i -> { i | status = ScanSubmitted })) as_.scanQueue
                        Nothing -> as_.scanQueue

                hasRemaining =
                    Dict.values updatedQueue |> List.any (\i -> i.status /= ScanSubmitted)

                nextTab =
                    if as_.activeScanItemId /= Nothing && hasRemaining then ScanTab else LedgerTab
            in
            case as_.form of
                EditForm editId _ ->
                    case findEffective editId as_ of
                        Just original ->
                            let
                                amendId =
                                    "amend::" ++ ExpenseId.toString original.id ++ "::" ++ String.left 8 timestamp

                                amend =
                                    { id            = amendId
                                    , targetId      = original.id
                                    , amount        = if p.amount /= String.fromFloat original.amount then String.toFloat p.amount else Nothing
                                    , category      = if p.category /= original.category then Just p.category else Nothing
                                    , createdAt     = posixToIso posix
                                    , date          = if p.date /= original.date then Just p.date else Nothing
                                    , longNote      = if p.longNote /= original.longNote then Just p.longNote else Nothing
                                    , merchant      = if p.merchant /= original.merchant then Just p.merchant else Nothing
                                    , note          = if p.note /= original.note then Just p.note else Nothing
                                    , paymentMethod = if p.paymentMethod /= original.paymentMethod then p.paymentMethod else Nothing
                                    }

                                nextRoute =
                                    routeForTab nextTab original.tripId
                            in
                            ( AuthModel
                                { as_
                                    | activeScanItemId = Nothing
                                    , form             = FreshForm (defaultPendingEntry as_.today)
                                    , route            = nextRoute
                                    , scanQueue        = updatedQueue
                                    , submitting       = False
                                }
                            , Cmd.batch
                                [ sendPouch (SaveAmend (Amendment.encoder amend))
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
                                    "expense::" ++ posixToIso posix ++ "::" ++ String.left 8 timestamp

                                expense =
                                    { id            = ExpenseId.fromString expenseId
                                    , tripId        = tripId
                                    , amount        = String.toFloat p.amount |> Maybe.withDefault 0
                                    , category      = p.category
                                    , createdAt     = posixToIso posix
                                    , date          = p.date
                                    , lat           = eLat
                                    , lon           = eLon
                                    , longNote      = p.longNote
                                    , merchant      = p.merchant
                                    , note          = p.note
                                    , paymentMethod = p.paymentMethod
                                    }

                                nextRoute =
                                    routeForTab nextTab tripId
                            in
                            ( AuthModel
                                { as_
                                    | activeScanItemId = Nothing
                                    , form             = FreshForm (defaultPendingEntry as_.today)
                                    , route            = nextRoute
                                    , scanQueue        = updatedQueue
                                    , submitting       = False
                                }
                            , Cmd.batch
                                [ sendPouch (SaveExpense (Expense.encoder expense))
                                , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath tripId nextTab)
                                ]
                            )

                        _ ->
                            ( AuthModel { as_ | submitting = False }, Cmd.none )

        VoidEntry expense ->
            let
                voidId =
                    "void::" ++ ExpenseId.toString expense.id ++ "::del"

                -- Optimistic: insert the void into the cache locally so
                -- Entry.resolve filters out this expense immediately.
                -- Sync DbChange will be a no-op (same id).
                optimisticVoid =
                    { id        = voidId
                    , targetId  = ExpenseId.toString expense.id
                    , createdAt = as_.today
                    }
            in
            ( AuthModel { as_ | voids = Dict.insert voidId optimisticVoid as_.voids }
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

        CloseTripForm ->
            ( AuthModel { as_ | tripForm = Nothing }, Cmd.none )

        RefreshClicked ->
            case Routing.routeTripId as_.route of
                Just tid ->
                    ( AuthModel
                        { as_
                            | loadingTrips = Set.insert (TripId.toString tid) as_.loadingTrips
                            , tripLoaded   = Set.remove (TripId.toString tid) as_.tripLoaded
                        }
                    , sendPouch (GetTripExpenses tid)
                    )

                Nothing ->
                    ( AuthModel as_, Cmd.none )

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
            ( AuthModel { as_ | geoBlocked = True, form = mapForm (setLocation LocationIdle) as_.form }
            , Cmd.none
            )

        OpenMapPicker ->
            ( AuthModel { as_ | showMapPicker = True }, Cmd.none )

        MapPickerConfirmed lat lon ->
            ( AuthModel { as_ | form = mapForm (setLocation (LocationGot lat lon ManualPin)) as_.form, showMapPicker = False }
            , Cmd.none
            )

        DismissMapPicker ->
            ( AuthModel { as_ | showMapPicker = False }, Cmd.none )

        SkipLocation ->
            ( AuthModel { as_ | form = mapForm (setLocation LocationSkipped) as_.form, showMapPicker = False }
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
                                { amount = Nothing, category = Nothing, date = Nothing, longNote = Nothing, merchant = Nothing, note = Nothing, paymentMethod = Nothing }
                                item.ocrData

                        newPending =
                            { amount        = ocr.amount |> Maybe.map String.fromFloat |> Maybe.withDefault ""
                            , category      = Maybe.withDefault Fuel ocr.category
                            , date          = Maybe.withDefault as_.today ocr.date
                            , locationState = item.locationState
                            , longNote      = Maybe.withDefault "" ocr.longNote
                            , merchant      = Maybe.withDefault "" ocr.merchant
                            , note          = Maybe.withDefault "" ocr.note
                            , paymentMethod = ocr.paymentMethod
                            }

                        newRoute =
                            case Routing.routeTripId as_.route of
                                Just tid -> RouteAdd tid
                                Nothing  -> as_.route
                    in
                    ( AuthModel
                        { as_
                            | activeScanItemId = Just itemId
                            , error            = Nothing
                            , form             = FreshForm newPending
                            , route            = newRoute
                        }
                    , Cmd.none
                    )

        BackToQueue ->
            let
                newRoute =
                    case Routing.routeTripId as_.route of
                        Just tid -> RouteScan tid
                        Nothing  -> as_.route
            in
            ( AuthModel
                { as_
                    | activeScanItemId = Nothing
                    , form             = FreshForm (defaultPendingEntry as_.today)
                    , route            = newRoute
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

                                    in
                                    ( AuthModel { as_ | tripForm = Nothing, trips = upsertTripIntoState updated as_.trips }
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

                        newTrips =
                            case as_.trips of
                                TripsLoaded trips ->
                                    TripsLoaded (Trips.selectTrip tripId (Trips.upsertTrip newTrip trips))

                                _ ->
                                    TripsLoaded (Trips.singleton newTrip)
                    in
                    ( AuthModel
                        { as_
                            | form       = FreshForm (defaultPendingEntry as_.today)
                            , route      = RouteLedger tripId
                            , tripForm   = Nothing
                            , tripLoaded = Set.insert (TripId.toString tripId) as_.tripLoaded
                            , trips      = newTrips
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
                voidId =
                    "void::" ++ TripId.toString trip.id ++ "::del"

                voidCmd =
                    sendPouch
                        (SaveVoid
                            (E.object
                                [ ( "_id",      E.string voidId )
                                , ( "targetId", E.string (TripId.toString trip.id) )
                                , ( "createdAt", E.string as_.today )
                                , ( "type",     E.string "void" )
                                ]
                            )
                        )
            in
            case removeTripFromState trip.id as_.trips of
                TripsLoaded trips ->
                    let
                        nextHead =
                            Trips.selectedTrip trips
                    in
                    ( AuthModel
                        { as_
                            | confirmDeleteTrip = Nothing
                            , route             = RouteLedger nextHead.id
                            , trips             = TripsLoaded trips
                        }
                    , Cmd.batch
                        [ voidCmd
                        , Nav.pushUrl as_.key (Routing.tabToPath as_.basePath nextHead.id LedgerTab)
                        ]
                    )

                NoTripsYet ->
                    ( AuthModel
                        { as_
                            | confirmDeleteTrip = Nothing
                            , route             = RouteTrips
                            , trips             = NoTripsYet
                        }
                    , Cmd.batch [ voidCmd, Nav.pushUrl as_.key (as_.basePath ++ "trips") ]
                    )

                other ->
                    ( AuthModel { as_ | confirmDeleteTrip = Nothing, trips = other }
                    , voidCmd
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
        , UI.Layout.viewBottomNav as_
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
