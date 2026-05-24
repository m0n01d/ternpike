module Data.SharedTrip exposing
    ( BillingStatus(..)
    , SharedTrip
    , decoder
    , isMember
    , isOwner
    , isReadOnly
    , members
    )

{-| A shared trip — a shared expense space with one billing owner and zero or
more other members.

The members list is modelled as `billingOwner :: otherMembers` rather
than a single flat list so that "the owner is always a member" is a
structural invariant: there is no value of `SharedTrip` for which the owner
isn't in the members set. `members` derives the flat list on demand,
which is provably non-empty by construction.

On the wire (PouchDB `sharedtrip:meta`) the field is flat: a single
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

import Data.SharedTripId
import Data.UserId exposing (UserId)
import Json.Decode
import Json.Decode.Pipeline as Pipeline


type alias SharedTrip =
    { billingLapsedAt : Maybe String
    , billingOwner : UserId
    , billingStatus : BillingStatus
    , createdAt : String
    , createdBy : UserId
    , id : Data.SharedTripId.SharedTripId
    , name : String
    , otherMembers : List UserId
    }


type BillingStatus
    = Active
    | Frozen
    | Grace



-- DERIVED


{-| Every member of the shared trip, with the billing owner at the head.
Provably non-empty by construction.
-}
members : SharedTrip -> List UserId
members sharedTrip =
    sharedTrip.billingOwner :: sharedTrip.otherMembers


{-| True if the given user is the billing owner of the shared trip.
-}
isOwner : UserId -> SharedTrip -> Bool
isOwner user sharedTrip =
    sharedTrip.billingOwner == user


{-| True if the given user appears anywhere in the shared trip's membership
(owner or otherwise).
-}
isMember : UserId -> SharedTrip -> Bool
isMember user sharedTrip =
    sharedTrip.billingOwner == user || List.member user sharedTrip.otherMembers


{-| True when the shared trip's billing lapse means writes should be
pre-disabled in the UI. `Grace` and `Frozen` are both read-only on the
client; `Active` is writable. Single source of truth for the predicate
— every disable site (Add submit, Ledger row menu, Scan trigger)
consults this so the rule stays in one place.

The server enforces the same gate at the CouchDB `validate_doc_update`
layer (#57); this is purely the UX side so users don't submit and then
see a 403.

-}
isReadOnly : SharedTrip -> Bool
isReadOnly sharedTrip =
    case sharedTrip.billingStatus of
        Active ->
            False

        Grace ->
            True

        Frozen ->
            True



-- MUTATE
-- JSON


{-| Decode a `sharedtrip:meta` document. Hard-rejects via `Json.Decode.fail`
when `billingOwner` is not in the flat `members` array — that doc is
malformed and we'd rather see the error than silently paper over it.
-}
decoder : Json.Decode.Decoder SharedTrip
decoder =
    -- `_id` on the PouchDB doc is the literal `"sharedtrip:meta"` (one meta
    -- doc per per-sharedtrip DB), not the SharedTripId — so we read the per-sharedtrip
    -- identifier off the `flockId` field the server writes alongside it.
    Json.Decode.succeed RawSharedTrip
        |> Pipeline.optional "billingLapsedAt" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.required "billingOwner" Data.UserId.decoder
        |> Pipeline.required "billingStatus" billingStatusDecoder
        |> Pipeline.required "createdAt" Json.Decode.string
        |> Pipeline.required "createdBy" Data.UserId.decoder
        |> Pipeline.required "flockId" Data.SharedTripId.decoder
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
                    Json.Decode.fail "SharedTrip: billingOwner is not in members"
            )


type alias RawSharedTrip =
    { billingLapsedAt : Maybe String
    , billingOwner : UserId
    , billingStatus : BillingStatus
    , createdAt : String
    , createdBy : UserId
    , id : Data.SharedTripId.SharedTripId
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
