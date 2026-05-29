module Routing exposing
    ( editEntryPath
    , effectiveRoute
    , pathForCurrentTab
    , routeFromUrl
    , routeTitle
    , routeToTab
    , routeTripId
    , tabToPath
    )

import Data.ExpenseId as ExpenseId
import Data.Navigation exposing (Route(..), Tab(..))
import Data.TripId as TripId
import Data.Trips as Trips exposing (TripsState(..))
import Types exposing (AuthState)
import Url
import Url.Parser as Parser exposing ((</>), (<?>))
import Url.Parser.Query as Query



-- See `effectiveRoute` below for the one piece of derived state: when the
-- stored route is `RouteAdd _` AND a scan-queue item is being reviewed, the
-- *effective* route is `RouteAddReviewScan` (no URL pattern for it).
--
-- IDs live in the query string (`?tripId=...&expenseId=...`) rather than in
-- the path. Putting them in the path collides with Cloudflare URL
-- Normalization, which percent-encodes `:` in path segments (the IDs are
-- `trip::<iso>::<nonce>`). Query values are left alone, and
-- `Url.Parser.Query.string` percent-decodes either way.


routeParser : Parser.Parser (Route -> a) a
routeParser =
    Parser.oneOf
        [ Parser.map (withTripAndExpense RouteEditEntry)
            (Parser.s "trip"
                </> Parser.s "ledger"
                </> Parser.s "edit"
                <?> Query.string "tripId"
                <?> Query.string "expenseId"
            )
        , Parser.map (withTrip RouteAdd)
            (Parser.s "trip" </> Parser.s "add" <?> Query.string "tripId")
        , Parser.map (withTrip RouteLedger)
            (Parser.s "trip" </> Parser.s "ledger" <?> Query.string "tripId")
        , Parser.map (withTrip RouteScan)
            (Parser.s "trip" </> Parser.s "scan" <?> Query.string "tripId")
        , Parser.map (withTrip RouteStats)
            (Parser.s "trip" </> Parser.s "stats" <?> Query.string "tripId")
        , Parser.map withJoinToken
            (Parser.s "sharedtrips" </> Parser.s "join" <?> Query.string "token")
        , Parser.map withMagicToken
            (Parser.s "auth" </> Parser.s "magic" <?> Query.string "token" <?> Query.string "next")
        , Parser.map withNestToken
            (Parser.s "nest" <?> Query.string "token")
        , Parser.map RouteSettings (Parser.s "settings")
        , Parser.map RouteTrips (Parser.s "trips")
        ]


withJoinToken : Maybe String -> Route
withJoinToken maybeToken =
    case maybeToken of
        Just token ->
            RouteJoinSharedTrip token

        Nothing ->
            RouteTrips


withMagicToken : Maybe String -> Maybe String -> Route
withMagicToken maybeToken maybeNext =
    case maybeToken of
        Just token ->
            RouteMagicLink token maybeNext

        Nothing ->
            RouteTrips


withNestToken : Maybe String -> Route
withNestToken maybeToken =
    case maybeToken of
        Just token ->
            RouteNestPreview token

        Nothing ->
            RouteTrips


withTrip : (TripId.TripId -> Route) -> Maybe String -> Route
withTrip ctor maybeTripId =
    case maybeTripId of
        Just s ->
            ctor (TripId.fromString s)

        Nothing ->
            RouteTrips


withTripAndExpense :
    (TripId.TripId -> ExpenseId.ExpenseId -> Route)
    -> Maybe String
    -> Maybe String
    -> Route
withTripAndExpense ctor maybeTripId maybeExpenseId =
    Maybe.map2
        (\t e -> ctor (TripId.fromString t) (ExpenseId.fromString e))
        maybeTripId
        maybeExpenseId
        |> Maybe.withDefault RouteTrips


routeFromUrl : String -> Url.Url -> Route
routeFromUrl basePath url =
    let
        stripped =
            if String.startsWith basePath url.path then
                "/" ++ String.dropLeft (String.length basePath) url.path

            else
                url.path
    in
    Parser.parse routeParser { url | path = stripped }
        |> Maybe.withDefault RouteTrips


routeToTab : Route -> Tab
routeToTab route =
    case route of
        RouteAdd _ ->
            AddTab

        RouteAddReviewScan ->
            AddTab

        RouteEditEntry _ _ ->
            AddTab

        RouteJoinSharedTrip _ ->
            SettingsTab

        RouteLedger _ ->
            LedgerTab

        RouteMagicLink _ _ ->
            SettingsTab

        RouteNestPreview _ ->
            SettingsTab

        RouteScan _ ->
            ScanTab

        RouteSettings ->
            SettingsTab

        RouteStats _ ->
            StatsTab

        RouteTrips ->
            TripsTab


routeTitle : Route -> String
routeTitle route =
    case route of
        RouteAdd _ ->
            "ADD EXPENSE"

        RouteAddReviewScan ->
            "REVIEW SCAN"

        RouteEditEntry _ _ ->
            "EDIT EXPENSE"

        RouteJoinSharedTrip _ ->
            "JOIN SHARED TRIP"

        RouteLedger _ ->
            "LEDGER"

        RouteMagicLink _ _ ->
            "SIGN IN"

        RouteNestPreview _ ->
            "TRIP PREVIEW"

        RouteScan _ ->
            "SCAN RECEIPTS"

        RouteSettings ->
            "SETTINGS"

        RouteStats _ ->
            "STATS"

        RouteTrips ->
            "TRIPS"


effectiveRoute : AuthState -> Route
effectiveRoute as_ =
    case ( as_.route, as_.activeScanItemId ) of
        ( RouteAdd _, Just _ ) ->
            RouteAddReviewScan

        _ ->
            as_.route


tabToPath : String -> TripId.TripId -> Tab -> String
tabToPath basePath tripId tab =
    let
        withTripId path =
            path ++ "?tripId=" ++ TripId.toString tripId
    in
    basePath
        ++ (case tab of
                AddTab ->
                    withTripId "trip/add"

                LedgerTab ->
                    withTripId "trip/ledger"

                ScanTab ->
                    withTripId "trip/scan"

                SettingsTab ->
                    "settings"

                StatsTab ->
                    withTripId "trip/stats"

                TripsTab ->
                    "trips"
           )


routeTripId : Route -> Maybe TripId.TripId
routeTripId route =
    case route of
        RouteAdd tripId ->
            Just tripId

        RouteEditEntry t _ ->
            Just t

        RouteLedger tripId ->
            Just tripId

        RouteScan tripId ->
            Just tripId

        RouteStats tripId ->
            Just tripId

        _ ->
            Nothing


editEntryPath : String -> TripId.TripId -> ExpenseId.ExpenseId -> String
editEntryPath basePath tripId entryId =
    basePath
        ++ "trip/ledger/edit?tripId="
        ++ TripId.toString tripId
        ++ "&expenseId="
        ++ ExpenseId.toString entryId


pathForCurrentTab : AuthState -> Tab -> String
pathForCurrentTab as_ tab =
    case as_.trips of
        TripsLoaded trips ->
            tabToPath as_.basePath (Trips.selectedTrip trips).id tab

        _ ->
            as_.basePath ++ "trips"
