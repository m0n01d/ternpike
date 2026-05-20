module Routing exposing
    ( editEntryPath
    , effectiveRoute
    , routeFromUrl
    , routeParser
    , routeTitle
    , routeToTab
    , routeTripId
    , tabToPath
    )

import Data.ExpenseId as ExpenseId
import Data.TripId as TripId
import Data.Trips as Trips
import Types exposing (AuthState, Route(..), Tab(..), TripsState(..))
import Url
import Url.Parser as Parser exposing ((</>))


routeParser : Parser.Parser (Route -> a) a
routeParser =
    Parser.oneOf
        [ Parser.map (\t e -> RouteEditEntry (TripId.fromString t) (ExpenseId.fromString e))
            (Parser.s "trip" </> Parser.string </> Parser.s "ledger" </> Parser.string </> Parser.s "edit")
        , Parser.map (\t -> RouteAdd (TripId.fromString t))
            (Parser.s "trip" </> Parser.string </> Parser.s "add")
        , Parser.map (\t -> RouteLedger (TripId.fromString t))
            (Parser.s "trip" </> Parser.string </> Parser.s "ledger")
        , Parser.map (\t -> RouteScan (TripId.fromString t))
            (Parser.s "trip" </> Parser.string </> Parser.s "scan")
        , Parser.map (\t -> RouteStats (TripId.fromString t))
            (Parser.s "trip" </> Parser.string </> Parser.s "stats")
        , Parser.map RouteSettings (Parser.s "settings")
        , Parser.map RouteTrips    (Parser.s "trips")
        ]


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
        RouteAdd _          -> AddTab
        RouteAddReviewScan  -> AddTab
        RouteEditEntry _ _  -> AddTab
        RouteLedger _       -> LedgerTab
        RouteScan _         -> ScanTab
        RouteSettings       -> SettingsTab
        RouteStats _        -> StatsTab
        RouteTrips          -> TripsTab


routeTitle : Route -> String
routeTitle route =
    case route of
        RouteAdd _          -> "ADD EXPENSE"
        RouteAddReviewScan  -> "REVIEW SCAN"
        RouteEditEntry _ _  -> "EDIT EXPENSE"
        RouteLedger _       -> "LEDGER"
        RouteScan _         -> "SCAN RECEIPTS"
        RouteSettings       -> "SETTINGS"
        RouteStats _        -> "STATS"
        RouteTrips          -> "TRIPS"


effectiveRoute : AuthState -> Route
effectiveRoute as_ =
    let
        withSelectedTrip toRoute =
            case as_.trips of
                TripsLoaded trips ->
                    toRoute (Trips.selectedTrip trips).id

                _ ->
                    RouteTrips
    in
    case as_.tab of
        AddTab ->
            case as_.editingEntry of
                Just expense ->
                    RouteEditEntry expense.tripId expense.id

                Nothing ->
                    if as_.activeScanItemId /= Nothing then
                        RouteAddReviewScan

                    else
                        withSelectedTrip RouteAdd

        LedgerTab ->
            withSelectedTrip RouteLedger

        ScanTab ->
            withSelectedTrip RouteScan

        SettingsTab ->
            RouteSettings

        StatsTab ->
            withSelectedTrip RouteStats

        TripsTab ->
            RouteTrips


tabToPath : String -> TripId.TripId -> Tab -> String
tabToPath basePath tripId tab =
    basePath
        ++ (case tab of
                AddTab      -> "trip/" ++ TripId.toString tripId ++ "/add"
                LedgerTab   -> "trip/" ++ TripId.toString tripId ++ "/ledger"
                ScanTab     -> "trip/" ++ TripId.toString tripId ++ "/scan"
                SettingsTab -> "settings"
                StatsTab    -> "trip/" ++ TripId.toString tripId ++ "/stats"
                TripsTab    -> "trips"
           )


routeTripId : Route -> Maybe TripId.TripId
routeTripId route =
    case route of
        RouteAdd tripId     -> Just tripId
        RouteEditEntry t _  -> Just t
        RouteLedger tripId  -> Just tripId
        RouteScan tripId    -> Just tripId
        RouteStats tripId   -> Just tripId
        _                   -> Nothing


editEntryPath : String -> TripId.TripId -> ExpenseId.ExpenseId -> String
editEntryPath basePath tripId entryId =
    basePath
        ++ "trip/"
        ++ TripId.toString tripId
        ++ "/ledger/"
        ++ ExpenseId.toString entryId
        ++ "/edit"
