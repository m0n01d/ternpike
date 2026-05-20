module Data.Trips exposing
    ( Trips
    , allTrips
    , findTrip
    , fromDict
    , mostRecent
    , otherTrips
    , removeTrip
    , selectTrip
    , selectedTrip
    , singleton
    , upsertTrip
    )

import Data.Trip exposing (Trip)
import Data.TripId as TripId exposing (TripId)
import Dict exposing (Dict)



-- TYPE


type Trips
    = Trips Trip (List Trip)



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


mostRecent : Dict String Trip -> Maybe Trips
mostRecent =
    fromDict


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
    case List.filter (\t -> t.id == newId) all |> List.head of
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
