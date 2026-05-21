module Data.Expense exposing (Expense, decoder, encoder)

{-| One expense as originally saved.

`Expense` is **immutable after creation**. Edits never overwrite an expense —
they produce an `Amendment` instead (see `Data.Amendment`). Deletes produce a
`Void`. The user-facing view is built by `Data.Entry.resolve`, which folds
amendments onto the raw expense to produce an `EffectiveEntry`.

The encoder adds `"type": "expense"` so the live-changes feed in `pouch.js`
can route incoming docs to the right decoder. `_id` is the PouchDB document
key and comes from `ExpenseId.encode`.

Unknown categories decode to `Misc` rather than failing — receipts older than
the current category list still load.
-}

import Data.Category as Category exposing (Category)
import Data.ExpenseId as ExpenseId exposing (ExpenseId)
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod)
import Data.TripId as TripId exposing (TripId)
import Json.Decode as D
import Json.Decode.Pipeline as Pipeline
import Json.Encode as E


type alias Expense =
    { amount        : Float
    , category      : Category
    , createdAt     : String
    , date          : String
    , id            : ExpenseId
    , lat           : Maybe Float
    , lon           : Maybe Float
    , longNote      : String
    , merchant      : String
    , note          : String
    , paymentMethod : Maybe PaymentMethod
    , tripId        : TripId
    }


encoder : Expense -> E.Value
encoder e =
    E.object
        ([ ( "_id",       ExpenseId.encode e.id )
         , ( "amount",    E.float e.amount )
         , ( "category",  E.string (Category.label e.category) )
         , ( "createdAt", E.string e.createdAt )
         , ( "date",      E.string e.date )
         , ( "longNote",  E.string e.longNote )
         , ( "merchant",  E.string e.merchant )
         , ( "note",      E.string e.note )
         , ( "tripId",    TripId.encode e.tripId )
         , ( "type",      E.string "expense" )
         ]
         ++ (case e.lat of
                Just v  -> [ ( "lat", E.float v ) ]
                Nothing -> []
            )
         ++ (case e.lon of
                Just v  -> [ ( "lon", E.float v ) ]
                Nothing -> []
            )
         ++ (case e.paymentMethod of
                Just v  -> [ ( "paymentMethod", E.string (PaymentMethod.toString v) ) ]
                Nothing -> []
            )
        )


decoder : D.Decoder Expense
decoder =
    D.succeed Expense
        |> Pipeline.required "amount"    D.float
        |> Pipeline.required "category"
            (D.string
                |> D.andThen
                    (\s ->
                        case Category.fromStringMaybe s of
                            Just c  -> D.succeed c
                            Nothing -> D.succeed Category.Misc
                    )
            )
        |> Pipeline.required "createdAt" D.string
        |> Pipeline.required "date"      D.string
        |> Pipeline.required "_id"       ExpenseId.decode
        |> Pipeline.optional "lat"           (D.nullable D.float) Nothing
        |> Pipeline.optional "lon"           (D.nullable D.float) Nothing
        |> Pipeline.optional "longNote"      D.string ""
        |> Pipeline.required "merchant"      D.string
        |> Pipeline.required "note"          D.string
        |> Pipeline.optional "paymentMethod"
            (D.nullable
                (D.string
                    |> D.andThen
                        (\s ->
                            case PaymentMethod.fromString s of
                                Just pm -> D.succeed pm
                                Nothing -> D.fail ("Unknown paymentMethod: " ++ s)
                        )
                )
            )
            Nothing
        |> Pipeline.required "tripId"        TripId.decode
