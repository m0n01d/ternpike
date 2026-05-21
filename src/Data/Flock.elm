module Data.Flock exposing
    ( BillingStatus(..)
    , Flock
    , addMember
    , decoder
    , encode
    , isMember
    , isOwner
    , members
    , removeMember
    , transferOwnership
    )

{-| A flock — a shared expense space with one billing owner and zero or
more other members.

The members list is modelled as `billingOwner :: otherMembers` rather
than a single flat list so that "the owner is always a member" is a
structural invariant: there is no value of `Flock` for which the owner
isn't in the members set. `members` derives the flat list on demand,
which is provably non-empty by construction.

On the wire (PouchDB `flock:meta`) the field is flat: a single
`members` array containing every member including the billing owner.
The decoder picks the owner out and assembles `otherMembers = members ∖
{billingOwner}`. The decoder hard-rejects (`Json.Decode.fail`) any
document where `billingOwner` is not in `members` — we don't try to
recover from server-side data integrity bugs by silently fixing them.
The encoder mirrors the decoder by flattening back to `members =
billingOwner :: otherMembers`.

The mutating helpers (`addMember`, `removeMember`, `transferOwnership`)
preserve the same invariant at the value-construction layer:
`addMember` is idempotent, `removeMember` refuses to drop the owner,
and `transferOwnership` is a no-op when the target isn't already in
`otherMembers`.

-}

import Data.FlockId
import Data.UserId exposing (UserId)
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode


type alias Flock =
    { billingLapsedAt : Maybe String
    , billingOwner : UserId
    , billingStatus : BillingStatus
    , createdAt : String
    , createdBy : UserId
    , id : Data.FlockId.FlockId
    , name : String
    , otherMembers : List UserId
    }


type BillingStatus
    = Active
    | Frozen
    | Grace



-- DERIVED


{-| Every member of the flock, with the billing owner at the head.
Provably non-empty by construction.
-}
members : Flock -> List UserId
members flock =
    flock.billingOwner :: flock.otherMembers


{-| True if the given user is the billing owner of the flock.
-}
isOwner : UserId -> Flock -> Bool
isOwner user flock =
    flock.billingOwner == user


{-| True if the given user appears anywhere in the flock's membership
(owner or otherwise).
-}
isMember : UserId -> Flock -> Bool
isMember user flock =
    flock.billingOwner == user || List.member user flock.otherMembers



-- MUTATE


{-| Add a user as a non-owner member. Idempotent — if the user is
already the owner or already in `otherMembers`, the flock is returned
unchanged.
-}
addMember : UserId -> Flock -> Flock
addMember user flock =
    if isMember user flock then
        flock

    else
        { flock | otherMembers = user :: flock.otherMembers }


{-| Remove a user from `otherMembers`. Refuses to remove the billing
owner — that's a different operation (`transferOwnership` followed by
`removeMember`). Returns the flock unchanged if the user wasn't in
`otherMembers` either.
-}
removeMember : UserId -> Flock -> Flock
removeMember user flock =
    if user == flock.billingOwner then
        flock

    else
        { flock | otherMembers = List.filter ((/=) user) flock.otherMembers }


{-| Promote one of the `otherMembers` to billing owner, demoting the
current owner into `otherMembers`. No-op if the target isn't already in
`otherMembers` — we never silently add a user as part of this
operation.

The resulting `members` set is identical to the original, just with a
different head.

-}
transferOwnership : UserId -> Flock -> Flock
transferOwnership newOwner flock =
    if List.member newOwner flock.otherMembers then
        { flock
            | billingOwner = newOwner
            , otherMembers =
                flock.billingOwner
                    :: List.filter ((/=) newOwner) flock.otherMembers
        }

    else
        flock



-- JSON


{-| Encode a `Flock` to the on-disk `flock:meta` wire format. Flattens
the structural `billingOwner :: otherMembers` split back to a single
`members` array.
-}
encode : Flock -> Json.Encode.Value
encode flock =
    Json.Encode.object
        [ ( "_id", Data.FlockId.encode flock.id )
        , ( "billingLapsedAt"
          , flock.billingLapsedAt
                |> Maybe.map Json.Encode.string
                |> Maybe.withDefault Json.Encode.null
          )
        , ( "billingOwner", Data.UserId.encode flock.billingOwner )
        , ( "billingStatus", Json.Encode.string (billingStatusToString flock.billingStatus) )
        , ( "createdAt", Json.Encode.string flock.createdAt )
        , ( "createdBy", Data.UserId.encode flock.createdBy )
        , ( "members", Json.Encode.list Data.UserId.encode (members flock) )
        , ( "name", Json.Encode.string flock.name )
        , ( "type", Json.Encode.string "flock:meta" )
        ]


{-| Decode a `flock:meta` document. Hard-rejects via `Json.Decode.fail`
when `billingOwner` is not in the flat `members` array — that doc is
malformed and we'd rather see the error than silently paper over it.
-}
decoder : Json.Decode.Decoder Flock
decoder =
    Json.Decode.succeed RawFlock
        |> Pipeline.optional "billingLapsedAt" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.required "billingOwner" Data.UserId.decoder
        |> Pipeline.required "billingStatus" billingStatusDecoder
        |> Pipeline.required "createdAt" Json.Decode.string
        |> Pipeline.required "createdBy" Data.UserId.decoder
        |> Pipeline.required "_id" Data.FlockId.decoder
        |> Pipeline.required "members" (Json.Decode.list Data.UserId.decoder)
        |> Pipeline.required "name" Json.Decode.string
        |> Json.Decode.andThen
            (\raw ->
                if List.member raw.billingOwner raw.memberList then
                    Json.Decode.succeed
                        { billingLapsedAt = raw.billingLapsedAt
                        , billingOwner = raw.billingOwner
                        , billingStatus = raw.billingStatus
                        , createdAt = raw.createdAt
                        , createdBy = raw.createdBy
                        , id = raw.id
                        , name = raw.name
                        , otherMembers = List.filter ((/=) raw.billingOwner) raw.memberList
                        }

                else
                    Json.Decode.fail "Flock: billingOwner is not in members"
            )


type alias RawFlock =
    { billingLapsedAt : Maybe String
    , billingOwner : UserId
    , billingStatus : BillingStatus
    , createdAt : String
    , createdBy : UserId
    , id : Data.FlockId.FlockId
    , memberList : List UserId
    , name : String
    }


billingStatusDecoder : Json.Decode.Decoder BillingStatus
billingStatusDecoder =
    Json.Decode.string
        |> Json.Decode.andThen
            (\s ->
                case s of
                    "active" ->
                        Json.Decode.succeed Active

                    "frozen" ->
                        Json.Decode.succeed Frozen

                    "grace" ->
                        Json.Decode.succeed Grace

                    _ ->
                        Json.Decode.fail ("Unknown billingStatus: " ++ s)
            )


billingStatusToString : BillingStatus -> String
billingStatusToString status =
    case status of
        Active ->
            "active"

        Frozen ->
            "frozen"

        Grace ->
            "grace"
