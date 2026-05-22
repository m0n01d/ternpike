module Data.Expense exposing (Expense, decoder, encoder, snapshotWith)

{-| One expense as originally saved.

`Expense` is **immutable after creation**. Edits never overwrite an expense —
they produce an `Amendment` instead (see `Data.Amendment`). Deletes produce a
`Void`. The user-facing view is built by `Data.Entry.resolve`, which folds
amendments onto the raw expense to produce an `EffectiveEntry`.

The encoder adds `"type": "expense"` so the live-changes feed in `pouch.js`
can route incoming docs to the right decoder. `_id` is the PouchDB document
key and comes from `ExpenseId.encode`.

Unknown categories decode to `Misc` rather than failing — receipts older than
the current category list still load. `createdBy` is decoded with a
`UserId.unknown` fallback so documents written before the field existed still
load cleanly.

Field types reflect the typed-primitives refactor (#92):

  - `amount : Data.Money.Money` — was `Float`. Encoder still emits `Float`
    dollars so the wire format is unchanged.
  - `createdAt : Time.Posix` — was `String`. Wire format remains the ISO
    `"YYYY-MM-DDTHH:MM:SSZ"` string for backward compatibility.
  - `date : Data.DateField.DateField` — was `String`. Wire format remains
    ISO `"YYYY-MM-DD"`.
  - `geoPoint : Maybe Data.GeoPoint.GeoPoint` — replaces the parallel
    `lat : Maybe Float, lon : Maybe Float` pair. Encoder still emits the
    sibling `"lat"` / `"lon"` fields when present.

-}

import Data.Category as Category exposing (Category)
import Data.DateField as DateField exposing (DateField)
import Data.ExpenseId as ExpenseId exposing (ExpenseId)
import Data.GeoPoint as GeoPoint exposing (GeoPoint)
import Data.Iso8601 as Iso8601
import Data.Money as Money exposing (Money)
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod)
import Data.TripId as TripId exposing (TripId)
import Data.UserId as UserId exposing (UserId)
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode
import Time


type alias Expense =
    { amount : Money
    , category : Category
    , createdAt : Time.Posix
    , createdBy : UserId
    , date : DateField
    , geoPoint : Maybe GeoPoint
    , id : ExpenseId
    , longNote : String
    , merchant : String
    , note : String
    , paymentMethod : Maybe PaymentMethod
    , tripId : TripId
    }


encoder : Expense -> Json.Encode.Value
encoder e =
    Json.Encode.object
        ([ ( "_id", ExpenseId.encode e.id )
         , ( "amount", Money.encoder e.amount )
         , ( "category", Json.Encode.string (Category.label e.category) )
         , ( "createdAt", Json.Encode.string (Iso8601.fromPosix e.createdAt) )
         , ( "createdBy", UserId.encode e.createdBy )
         , ( "date", DateField.encoder e.date )
         , ( "longNote", Json.Encode.string e.longNote )
         , ( "merchant", Json.Encode.string e.merchant )
         , ( "note", Json.Encode.string e.note )
         , ( "tripId", TripId.encode e.tripId )
         , ( "type", Json.Encode.string "expense" )
         ]
            ++ (case e.geoPoint of
                    Just point ->
                        [ ( "lat", Json.Encode.float (GeoPoint.latDegrees point) )
                        , ( "lon", Json.Encode.float (GeoPoint.lonDegrees point) )
                        ]

                    Nothing ->
                        []
               )
            ++ (case e.paymentMethod of
                    Just v ->
                        [ ( "paymentMethod", Json.Encode.string (PaymentMethod.toString v) ) ]

                    Nothing ->
                        []
               )
        )


{-| Copy every user-visible field from a source expense onto a fresh
identity. The building block for "duplicate" (new id, same trip) and
"move" (new id, different trip).

The record-update form ensures the invariant "new identity ⇒ new
(id, createdAt) ⇒ same date/amount/category/merchant/note/longNote/
paymentMethod/geoPoint" stays stated in one place.

-}
snapshotWith : { id : ExpenseId, createdAt : Time.Posix, tripId : TripId } -> Expense -> Expense
snapshotWith fields source =
    { source
        | id = fields.id
        , createdAt = fields.createdAt
        , tripId = fields.tripId
    }


decoder : Json.Decode.Decoder Expense
decoder =
    Json.Decode.succeed Expense
        |> Pipeline.required "amount" Money.decoder
        |> Pipeline.required "category"
            (Json.Decode.string
                |> Json.Decode.andThen
                    (\s ->
                        case Category.fromStringMaybe s of
                            Just c ->
                                Json.Decode.succeed c

                            Nothing ->
                                Json.Decode.succeed Category.Misc
                    )
            )
        |> Pipeline.required "createdAt" createdAtDecoder
        |> Pipeline.optional "createdBy" UserId.decoder UserId.unknown
        |> Pipeline.required "date" DateField.decoder
        |> Pipeline.custom GeoPoint.decoderPair
        |> Pipeline.required "_id" ExpenseId.decode
        |> Pipeline.optional "longNote" Json.Decode.string ""
        |> Pipeline.required "merchant" Json.Decode.string
        |> Pipeline.required "note" Json.Decode.string
        |> Pipeline.optional "paymentMethod"
            (Json.Decode.nullable
                (Json.Decode.string
                    |> Json.Decode.andThen
                        (\s ->
                            case PaymentMethod.fromString s of
                                Just pm ->
                                    Json.Decode.succeed pm

                                Nothing ->
                                    Json.Decode.fail ("Unknown paymentMethod: " ++ s)
                        )
                )
            )
            Nothing
        |> Pipeline.required "tripId" TripId.decode



-- INTERNAL


{-| Decode the legacy `"YYYY-MM-DDTHH:MM:SSZ"` createdAt string into a
`Time.Posix`. Failed parses fall back to the epoch (`Time.millisToPosix 0`),
matching the silent-default pattern used by `Data.DateField.decoder` for
malformed legacy dates.
-}
createdAtDecoder : Json.Decode.Decoder Time.Posix
createdAtDecoder =
    Json.Decode.string
        |> Json.Decode.map Iso8601.toPosix
