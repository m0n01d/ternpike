module Data.MilepostProgress exposing
    ( MilepostProgress
    , decoder
    , docId
    , encoder
    )

{-| The persisted record of which mileposts the user has earned, and when.

A single PouchDB document (`_id = "milepost::progress"`, `type =
"milepostProgress"`) holds a map from `MarkerId` to the ISO-8601 timestamp at
which that marker was first earned. The reconcile pass in `Main` (issue #408)
reads this document, unions in any newly-earned markers, and writes it back.

Markers never un-earn — once an id is in the map it stays there even if the
underlying expenses change. The reconcile pass only ever adds keys.

This module owns the wire shape only. It is deliberately kept out of
`Data.Milepost` (the pure catalog + evaluator) so the catalog edits in #412
don't collide with the persistence layer.

@docs MilepostProgress
@docs decoder
@docs docId
@docs encoder

-}

import Data.Milepost exposing (MarkerId)
import Dict exposing (Dict)
import Json.Decode
import Json.Encode


{-| The earned-marker map.

`earned` maps a `MarkerId` to the ISO-8601 timestamp at which it was first
earned. Keys are stable marker ids from `Data.Milepost.catalog`.

-}
type alias MilepostProgress =
    { earned : Dict MarkerId String
    }


{-| The fixed singleton document id this record lives at in the personal
PouchDB.

    docId
    --> "milepost::progress"

-}
docId : String
docId =
    "milepost::progress"


{-| Decode a `milepostProgress` document.

Reads the `earned` object as a `Dict MarkerId String`. A document missing the
`earned` field (or carrying a malformed one) decodes to an empty map rather
than failing, so a partially-written or legacy document never blocks
evaluation.

-}
decoder : Json.Decode.Decoder MilepostProgress
decoder =
    Json.Decode.map MilepostProgress
        (Json.Decode.oneOf
            [ Json.Decode.field "earned" (Json.Decode.dict Json.Decode.string)
            , Json.Decode.succeed Dict.empty
            ]
        )


{-| Encode a `milepostProgress` document body, including the `_id` and `type`
fields PouchDB needs. Callers thread the current `_rev` separately on the JS
side (PouchDB rejects a second write without it).
-}
encoder : MilepostProgress -> Json.Encode.Value
encoder progress =
    Json.Encode.object
        [ ( "_id", Json.Encode.string docId )
        , ( "type", Json.Encode.string "milepostProgress" )
        , ( "earned", Json.Encode.dict identity Json.Encode.string progress.earned )
        ]
