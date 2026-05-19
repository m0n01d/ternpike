module Routing exposing
    ( editEntryPath
    , effectiveRoute
    , routeFromUrl
    , routeParser
    , routeTitle
    , routeToTab
    , tabToPath
    )

import Data.ExpenseId as ExpenseId
import Data.TripId as TripId
import Types exposing (AuthState, Route(..), Tab(..))
import Url
import Url.Parser as Parser exposing ((</>))


routeParser : Parser.Parser (Route -> a) a
routeParser =
    Parser.oneOf
        [ Parser.map RouteAdd (Parser.s "add")
        , Parser.map
            (\t e -> RouteEditEntry (TripId.fromString t) (ExpenseId.fromString e))
            (Parser.s "trip" </> Parser.string </> Parser.s "ledger" </> Parser.string </> Parser.s "edit")
        , Parser.map RouteLedger   (Parser.s "ledger")
        , Parser.map RouteScan     (Parser.s "scan")
        , Parser.map RouteSettings (Parser.s "settings")
        , Parser.map RouteStats    (Parser.s "stats")
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
        |> Maybe.withDefault RouteLedger


routeToTab : Route -> Tab
routeToTab route =
    case route of
        RouteAdd            -> AddTab
        RouteAddReviewScan  -> AddTab
        RouteEditEntry _ _  -> AddTab
        RouteLedger         -> LedgerTab
        RouteScan           -> ScanTab
        RouteSettings       -> SettingsTab
        RouteStats          -> StatsTab
        RouteTrips          -> TripsTab


routeTitle : Route -> String
routeTitle route =
    case route of
        RouteAdd            -> "ADD EXPENSE"
        RouteAddReviewScan  -> "REVIEW SCAN"
        RouteEditEntry _ _  -> "EDIT EXPENSE"
        RouteLedger         -> "LEDGER"
        RouteScan           -> "SCAN RECEIPTS"
        RouteSettings       -> "SETTINGS"
        RouteStats          -> "STATS"
        RouteTrips          -> "TRIPS"


effectiveRoute : AuthState -> Route
effectiveRoute as_ =
    case as_.tab of
        AddTab ->
            case as_.editingEntry of
                Just expense ->
                    RouteEditEntry expense.tripId expense.id

                Nothing ->
                    if as_.activeScanItemId /= Nothing then
                        RouteAddReviewScan

                    else
                        RouteAdd

        LedgerTab ->
            RouteLedger

        ScanTab ->
            RouteScan

        SettingsTab ->
            RouteSettings

        StatsTab ->
            RouteStats

        TripsTab ->
            RouteTrips


tabToPath : String -> Tab -> String
tabToPath basePath tab =
    basePath
        ++ (case tab of
                AddTab      -> "add"
                LedgerTab   -> "ledger"
                ScanTab     -> "scan"
                SettingsTab -> "settings"
                StatsTab    -> "stats"
                TripsTab    -> "trips"
           )


editEntryPath : String -> TripId.TripId -> ExpenseId.ExpenseId -> String
editEntryPath basePath tripId entryId =
    basePath
        ++ "trip/"
        ++ TripId.toString tripId
        ++ "/ledger/"
        ++ ExpenseId.toString entryId
        ++ "/edit"
