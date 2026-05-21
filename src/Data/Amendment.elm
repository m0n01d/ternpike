module Data.Amendment exposing (Amendment, decoder, encoder)

import Data.Category as Category exposing (Category)
import Data.ExpenseId as ExpenseId exposing (ExpenseId)
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod)
import Json.Decode as D
import Json.Decode.Pipeline as Pipeline
import Json.Encode as E


type alias Amendment =
    { amount        : Maybe Float
    , category      : Maybe Category
    , createdAt     : String
    , date          : Maybe String
    , id            : String
    , longNote      : Maybe String
    , merchant      : Maybe String
    , note          : Maybe String
    , paymentMethod : Maybe PaymentMethod
    , targetId      : ExpenseId
    }


encoder : Amendment -> E.Value
encoder a =
    E.object
        ([ ( "_id",      E.string a.id )
         , ( "targetId", ExpenseId.encode a.targetId )
         , ( "createdAt", E.string a.createdAt )
         , ( "type",     E.string "amend" )
         ]
         ++ (case a.amount of
                Just v  -> [ ( "amount",   E.float v ) ]
                Nothing -> []
            )
         ++ (case a.category of
                Just v  -> [ ( "category", E.string (Category.label v) ) ]
                Nothing -> []
            )
         ++ (case a.date of
                Just v  -> [ ( "date",     E.string v ) ]
                Nothing -> []
            )
         ++ (case a.longNote of
                Just v  -> [ ( "longNote", E.string v ) ]
                Nothing -> []
            )
         ++ (case a.merchant of
                Just v  -> [ ( "merchant", E.string v ) ]
                Nothing -> []
            )
         ++ (case a.note of
                Just v  -> [ ( "note",          E.string v ) ]
                Nothing -> []
            )
         ++ (case a.paymentMethod of
                Just v  -> [ ( "paymentMethod", E.string (PaymentMethod.toString v) ) ]
                Nothing -> []
            )
        )


decoder : D.Decoder Amendment
decoder =
    D.succeed Amendment
        |> Pipeline.optional "amount"
            (D.nullable D.float)
            Nothing
        |> Pipeline.optional "category"
            (D.nullable
                (D.string
                    |> D.andThen
                        (\s ->
                            case Category.fromStringMaybe s of
                                Just c  -> D.succeed c
                                Nothing -> D.fail ("Unknown category: " ++ s)
                        )
                )
            )
            Nothing
        |> Pipeline.required "createdAt" D.string
        |> Pipeline.optional "date"      (D.nullable D.string) Nothing
        |> Pipeline.required "_id"       D.string
        |> Pipeline.optional "longNote"      (D.nullable D.string) Nothing
        |> Pipeline.optional "merchant"      (D.nullable D.string) Nothing
        |> Pipeline.optional "note"          (D.nullable D.string) Nothing
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
        |> Pipeline.required "targetId"      ExpenseId.decode
