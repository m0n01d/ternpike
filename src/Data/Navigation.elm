module Data.Navigation exposing (Route(..), Tab(..))

{-| URL routes and bottom-nav tabs.

`Tab` is the set of bottom-nav destinations the user can tap. `Route` is
the parsed-URL state — most routes map 1:1 to a tab, but `RouteEditEntry`
and `RouteAddReviewScan` are sub-states of the Add tab that don't have
their own nav slot. The mapping from `Route` to `Tab` (used to highlight
the active nav item) lives in `Routing.routeToTab`.

These types are deliberately small and exhaustive — pattern matches over
them are the compiler's way of forcing us to handle every page when we
add a new one.

-}

import Data.ExpenseId exposing (ExpenseId)
import Data.TripId exposing (TripId)


{-| Which bottom-nav slot is highlighted.
-}
type Tab
    = AddTab
    | LedgerTab
    | ScanTab
    | SettingsTab
    | StatsTab
    | TripsTab


{-| Parsed URL state.

Trip-scoped routes carry a `TripId` because every page below the Trips
list needs to know which trip it's rendering. `RouteEditEntry` also
carries the `ExpenseId` so the edit form can hydrate from the cached
expense. `RouteAddReviewScan` is the effective route when an OCR'd scan
item is being reviewed on the Add tab — `Routing.effectiveRoute` derives
it from `AuthState.activeScanItemId`, so it never appears in a URL.

-}
type Route
    = RouteAdd TripId
    | RouteAddReviewScan
    | RouteEditEntry TripId ExpenseId
    | RouteJoinSharedTrip String
    | RouteLedger TripId
    | RouteScan TripId
    | RouteSettings
    | RouteStats TripId
    | RouteTrips
