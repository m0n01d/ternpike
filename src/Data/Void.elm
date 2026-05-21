module Data.Void exposing (Void, decoder)

{-| Tombstone marker — a soft delete.

Hard-deleting from PouchDB is awkward to sync (it produces a deletion
revision that has to propagate before the doc disappears everywhere, and
conflicts can resurrect deleted docs). Instead, "deleting" an expense or
trip writes a `Void` document keyed `void::<targetId>::del`. The void
propagates exactly like any other write, and `Data.Entry.resolve` filters
out any expense whose ID is in the set of void targets.

`targetId` is stored as a plain `String` (not `ExpenseId` or `TripId`)
because the same Void type covers both expense and trip deletions.

`createdBy` records which signed-in user wrote the tombstone — populated for
every new void; legacy voids without the field decode to `UserId.unknown`.

-}

import Data.UserId as UserId exposing (UserId)
import Json.Decode as D
import Json.Decode.Pipeline as Pipeline


type alias Void =
    { createdAt : String
    , createdBy : UserId
    , id : String
    , targetId : String
    }


decoder : D.Decoder Void
decoder =
    D.succeed Void
        |> Pipeline.required "createdAt" D.string
        |> Pipeline.optional "createdBy" UserId.decoder UserId.unknown
        |> Pipeline.required "_id" D.string
        |> Pipeline.required "targetId" D.string
