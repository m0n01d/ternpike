module Data.Flocks exposing
    ( Flocks
    , empty
    , fromList
    , get
    , joinedBy
    , ownedBy
    )

{-| Collection of `Flock` records keyed by `FlockId.toString`.

Thin wrapper around `Dict String Flock` (exposed as a type alias so
callers can pattern-match on it as a dict directly). Lives on
`AuthState.flocks` and is populated from `user:flocks` + per-flock
`flock:meta` documents during the startup sequence in `Main.elm`.

`ownedBy` filters to flocks where the user is the billing owner — used
by Settings (#62) and the New Trip picker (#63) to surface "flocks I
can create trips in." `joinedBy` filters to flocks where the user
appears anywhere in the membership.

-}

import Data.Flock exposing (Flock)
import Data.FlockId exposing (FlockId)
import Data.UserId exposing (UserId)
import Dict exposing (Dict)


type alias Flocks =
    Dict String Flock


{-| The empty `Flocks` dict — the initial value of `AuthState.flocks`
for a solo user who hasn't joined any flock yet.
-}
empty : Flocks
empty =
    Dict.empty


{-| Build a `Flocks` dict from a list of `Flock` records, keying each
by its `FlockId.toString`.
-}
fromList : List Flock -> Flocks
fromList list =
    List.foldl
        (\flock acc -> Dict.insert (Data.FlockId.toString flock.id) flock acc)
        Dict.empty
        list


{-| Look up one flock by ID.
-}
get : FlockId -> Flocks -> Maybe Flock
get id flocks =
    Dict.get (Data.FlockId.toString id) flocks


{-| Every flock where the given user is the billing owner. Used to
populate the "where does this trip live?" picker — only flocks the
user can create trips in are eligible.
-}
ownedBy : UserId -> Flocks -> List Flock
ownedBy user flocks =
    Dict.values flocks
        |> List.filter (Data.Flock.isOwner user)


{-| Every flock where the given user appears anywhere in the
membership (owner or `otherMembers`).
-}
joinedBy : UserId -> Flocks -> List Flock
joinedBy user flocks =
    Dict.values flocks
        |> List.filter (Data.Flock.isMember user)
