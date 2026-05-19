module Data.Expense exposing (Expense, decoder, encoder)

import Data.Category as Category exposing (Category)
import Json.Decode as D
import Json.Decode.Pipeline as Pipeline
import Json.Encode as E


type alias Expense =
    { amount    : Float
    , category  : Category
    , createdAt : String
    , date      : String
    , id        : String
    , lat       : Maybe Float
    , lon       : Maybe Float
    , longNote  : String
    , merchant  : String
    , note      : String
    , tripId    : String
    }


encoder : Expense -> E.Value
encoder e =
    E.object
        ([ ( "_id",       E.string e.id )
         , ( "amount",    E.float e.amount )
         , ( "category",  E.string (Category.label e.category) )
         , ( "createdAt", E.string e.createdAt )
         , ( "date",      E.string e.date )
         , ( "longNote",  E.string e.longNote )
         , ( "merchant",  E.string e.merchant )
         , ( "note",      E.string e.note )
         , ( "tripId",    E.string e.tripId )
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
        |> Pipeline.required "_id"       D.string
        |> Pipeline.optional "lat"       (D.nullable D.float) Nothing
        |> Pipeline.optional "lon"       (D.nullable D.float) Nothing
        |> Pipeline.optional "longNote"  D.string ""
        |> Pipeline.required "merchant"  D.string
        |> Pipeline.required "note"      D.string
        |> Pipeline.required "tripId"    D.string
