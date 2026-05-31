module Data.MilepostProgress exposing
    ( MilepostProgress
    , decoder
    , docId
    , encoder
    , reconcile
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
@docs reconcile

-}

import Data.Iso8601 as Iso8601
import Data.Milepost exposing (MarkerId)
import Dict exposing (Dict)
import Json.Decode
import Json.Encode
import Set exposing (Set)
import Time exposing (Posix)
import Types exposing (MilepostState(..))


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


{-| Decide what the milepost reconcile pass should do for one tick, given the
ids earned right now, the current time, and the loaded persistence state.

This is the pure heart of `Main.reconcileMileposts` (issue #408) — the orchestration
in `Main` is a thin wrapper that turns this decision into the actual
`SaveMilepostProgress` port call and toast-queue append. Three cases:

  - **First load (`NotLoaded`)** — seed the persisted map from whatever is
    earned now, stamping each id with `now`, but enqueue **nothing**. The
    pre-existing backlog must never trigger celebration toasts.

  - **Idempotent (`Loaded`, nothing new)** — when everything earned now is
    already persisted, there is nothing to write (`persist = Nothing`) and
    nothing to toast. No write churn on a steady-state pass.

  - **Fresh earn (`Loaded`, new ids)** — union the newly-earned ids (stamped
    `now`) into the existing map, persist the union, and enqueue the new ids
    in sorted order so each gets celebrated.

`rev` is the current PouchDB `_rev`, threaded straight back out so the caller
can build a conflict-free write. It is `Nothing` on the first-load seed (no
document exists yet) and carries the existing rev on the `Loaded` paths.

Markers never un-earn: an id present in the persisted map but absent from
`earnedNow` is preserved in `persist`, never removed.

    import Dict
    import Set
    import Time
    import Types exposing (MilepostState(..))

    reconcile
        { earnedNow = Set.fromList [ "first-trip" ]
        , now = Time.millisToPosix 0
        , state = NotLoaded
        }
    --> { persist = Just { earned = Dict.fromList [ ( "first-trip", "1970-01-01T00:00:00Z" ) ] }
    --> , rev = Nothing
    --> , toEnqueue = []
    --> }

    reconcile
        { earnedNow = Set.fromList [ "first-trip" ]
        , now = Time.millisToPosix 0
        , state = Loaded { earned = Dict.fromList [ ( "first-trip", "2024-01-01T00:00:00.000Z" ) ], rev = Just "3-abc" }
        }
    --> { persist = Nothing
    --> , rev = Just "3-abc"
    --> , toEnqueue = []
    --> }

-}
reconcile :
    { earnedNow : Set String
    , now : Posix
    , state : MilepostState
    }
    ->
        { persist : Maybe MilepostProgress
        , rev : Maybe String
        , toEnqueue : List String
        }
reconcile { earnedNow, now, state } =
    let
        nowIso : String
        nowIso =
            Iso8601.fromPosix now

        stamp : Set String -> Dict String String
        stamp ids =
            ids
                |> Set.toList
                |> List.map (\id -> ( id, nowIso ))
                |> Dict.fromList
    in
    case state of
        NotLoaded ->
            { persist = Just { earned = stamp earnedNow }
            , rev = Nothing
            , toEnqueue = []
            }

        Loaded { earned, rev } ->
            let
                newly : Set String
                newly =
                    Set.diff earnedNow (Set.fromList (Dict.keys earned))
            in
            if Set.isEmpty newly then
                { persist = Nothing
                , rev = rev
                , toEnqueue = []
                }

            else
                { persist = Just { earned = Dict.union (stamp newly) earned }
                , rev = rev
                , toEnqueue = Set.toList newly
                }
