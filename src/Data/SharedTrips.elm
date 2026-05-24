module Data.SharedTrips exposing
    ( SharedTrips
    , empty
    , fromList
    , get
    , joinedBy
    , ownedBy
    )

{-| Collection of `SharedTrip` records keyed by `SharedTripId.toString`.

Thin wrapper around `Dict String SharedTrip` (exposed as a type alias so
callers can pattern-match on it as a dict directly). Lives on
`AuthState.sharedTrips` and is populated from `user:flocks` + per-flock
`flock:meta` documents during the startup sequence in `Main.elm`.

`ownedBy` filters to shared trips where the user is the billing owner — used
by Settings (#62) and the New Trip picker (#63) to surface "shared trips I
can create trips in." `joinedBy` filters to shared trips where the user
appears anywhere in the membership.

-}

import Data.SharedTrip exposing (SharedTrip)
import Data.SharedTripId exposing (SharedTripId)
import Data.UserId exposing (UserId)
import Dict exposing (Dict)


type alias SharedTrips =
    Dict String SharedTrip


{-| The empty `SharedTrips` dict — the initial value of `AuthState.sharedTrips`
for a solo user who hasn't joined any shared trip yet.
-}
empty : SharedTrips
empty =
    Dict.empty


{-| Build a `SharedTrips` dict from a list of `SharedTrip` records, keying each
by its `SharedTripId.toString`.
-}
fromList : List SharedTrip -> SharedTrips
fromList list =
    List.foldl
        (\sharedTrip acc -> Dict.insert (Data.SharedTripId.toString sharedTrip.id) sharedTrip acc)
        Dict.empty
        list


{-| Look up one shared trip by ID.
-}
get : SharedTripId -> SharedTrips -> Maybe SharedTrip
get id sharedTrips =
    Dict.get (Data.SharedTripId.toString id) sharedTrips


{-| Every shared trip where the given user is the billing owner. Used to
populate the "where does this trip live?" picker — only shared trips the
user can create trips in are eligible.
-}
ownedBy : UserId -> SharedTrips -> List SharedTrip
ownedBy user sharedTrips =
    Dict.values sharedTrips
        |> List.filter (Data.SharedTrip.isOwner user)


{-| Every shared trip where the given user appears anywhere in the
membership (owner or `otherMembers`).
-}
joinedBy : UserId -> SharedTrips -> List SharedTrip
joinedBy user sharedTrips =
    Dict.values sharedTrips
        |> List.filter (Data.SharedTrip.isMember user)
