module Data.Trips exposing
    ( Trips
    , TripsState(..)
    , allTrips
    , findTrip
    , fromDict
    , otherTrips
    , removeTrip
    , selectTrip
    , selectedTrip
    , singleton
    , upsertTrip
    )

{-| A non-empty zipper-like collection of trips with one "selected" trip
at the head, plus the loading-state wrapper used by `AuthState`.

Why not `Dict TripId Trip` plus a separate `Maybe TripId` for selection?
Because every page that renders trip data needs the active trip — keeping
the selection as the head of the structure means `selectedTrip` returns a
`Trip` directly (no `Maybe` to unwrap) and the type guarantees we never
have "trips loaded but nothing selected" or "selection points at a
missing trip."

Sorting in `fromDict` is by `TripId.toString` descending, which works out
to newest-first because the ID starts with an ISO-8601 timestamp.

`TripsState` lives here too because it's the lifecycle around this
zipper: it's the type stored at `AuthState.trips` and every transition
ends in either `TripsLoaded Trips` or one of the empty/failed branches.

-}

import Data.Trip exposing (Trip)
import Data.TripId as TripId exposing (TripId)
import Dict exposing (Dict)
import List.Extra



-- TYPE


type Trips
    = Trips Trip (List Trip)


{-| Lifecycle around the trips list.

  - `TripsLoading dict hint` — `GetAllTrips` was sent but hasn't
    returned; `dict` collects any individual trips that arrive via the
    live-changes feed in the meantime, and `hint` is the route's
    intended selection (so we can pick the right trip the moment the
    bulk response lands).
  - `TripsLoaded trips` — the zipper is populated and selection is
    valid; this is the only state in which trip-scoped pages render
    real data.
  - `NoTripsYet` — the bulk fetch returned an empty dict; the Trips
    page shows the "create your first trip" hero.
  - `TripsFailed err` — the fetch errored; the Trips page surfaces the
    message and offers a refresh.

-}
type TripsState
    = NoTripsYet
    | TripsLoaded Trips
    | TripsLoading (Dict String Trip) (Maybe TripId)



-- CONSTRUCT


fromDict : Dict String Trip -> Maybe Trips
fromDict dict =
    let
        sorted =
            Dict.values dict
                |> List.sortBy (TripId.toString << .id)
                |> List.reverse
    in
    case sorted of
        head :: rest ->
            Just (Trips head rest)

        [] ->
            Nothing


singleton : Trip -> Trips
singleton trip =
    Trips trip []



-- ACCESS


selectedTrip : Trips -> Trip
selectedTrip (Trips head _) =
    head


otherTrips : Trips -> List Trip
otherTrips (Trips _ rest) =
    rest


allTrips : Trips -> List Trip
allTrips (Trips head rest) =
    head :: rest


findTrip : TripId -> Trips -> Maybe Trip
findTrip id trips =
    List.filter (\t -> t.id == id) (allTrips trips)
        |> List.head



-- MUTATE


selectTrip : TripId -> Trips -> Trips
selectTrip newId trips =
    let
        all =
            allTrips trips
    in
    case List.Extra.find (\t -> t.id == newId) all of
        Just chosen ->
            Trips chosen (List.filter (\t -> t.id /= newId) all)

        Nothing ->
            trips


upsertTrip : Trip -> Trips -> Trips
upsertTrip trip (Trips head rest) =
    if trip.id == head.id then
        Trips trip rest

    else
        let
            replaced =
                List.map
                    (\t ->
                        if t.id == trip.id then
                            trip

                        else
                            t
                    )
                    rest

            exists =
                List.any (\t -> t.id == trip.id) rest
        in
        if exists then
            Trips head replaced

        else
            Trips head (trip :: rest)


removeTrip : TripId -> Trips -> Maybe Trips
removeTrip id (Trips head rest) =
    if head.id == id then
        case rest of
            next :: more ->
                Just (Trips next more)

            [] ->
                Nothing

    else
        Just (Trips head (List.filter (\t -> t.id /= id) rest))
