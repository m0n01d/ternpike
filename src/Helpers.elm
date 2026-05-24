module Helpers exposing (effectiveEntryToExpense, encodeWaypoints)

import Data.Category as Category
import Data.Entry exposing (EffectiveEntry)
import Data.Expense exposing (Expense)
import Data.GeoPoint as GeoPoint
import Data.Money as Money
import Json.Encode


effectiveEntryToExpense : EffectiveEntry -> Expense
effectiveEntryToExpense e =
    { address = e.address
    , amount = e.amount
    , category = e.category
    , createdAt = e.createdAt
    , createdBy = e.createdBy
    , date = e.date
    , geoPoint = e.geoPoint
    , id = e.id
    , longNote = e.longNote
    , merchant = e.merchant
    , note = e.note
    , paymentMethod = e.paymentMethod
    , tripId = e.tripId
    }


encodeWaypoints : List EffectiveEntry -> String
encodeWaypoints entries =
    let
        withCoords =
            List.filterMap
                (\e ->
                    case e.geoPoint of
                        Just point ->
                            Just
                                (Json.Encode.object
                                    [ ( "lat", Json.Encode.float (GeoPoint.latDegrees point) )
                                    , ( "lon", Json.Encode.float (GeoPoint.lonDegrees point) )
                                    , ( "label"
                                      , Json.Encode.string
                                            ((if e.merchant /= "" then
                                                e.merchant

                                              else
                                                Category.label e.category
                                             )
                                                ++ " "
                                                ++ Money.format e.amount
                                            )
                                      )
                                    ]
                                )

                        Nothing ->
                            Nothing
                )
                entries
    in
    Json.Encode.encode 0 (Json.Encode.list identity withCoords)
