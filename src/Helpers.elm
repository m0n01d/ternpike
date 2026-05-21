module Helpers exposing
    ( effectiveEntryToExpense
    , encodeWaypoints
    , formatAmount
    , formatCoord
    , formatDateDisplay
    , isoToDayCount
    )

import Data.Category as Category
import Data.Entry exposing (EffectiveEntry)
import Data.Expense exposing (Expense)
import Json.Encode as E


effectiveEntryToExpense : EffectiveEntry -> Expense
effectiveEntryToExpense e =
    { amount        = e.amount
    , category      = e.category
    , createdAt     = e.createdAt
    , date          = e.date
    , id            = e.id
    , lat           = e.lat
    , lon           = e.lon
    , longNote      = e.longNote
    , merchant      = e.merchant
    , note          = e.note
    , paymentMethod = e.paymentMethod
    , tripId        = e.tripId
    }


formatAmount : Float -> String
formatAmount amount =
    let
        cents =
            round (amount * 100)

        dollars =
            cents // 100

        centsRem =
            remainderBy 100 (abs cents)
    in
    "$" ++ String.fromInt dollars ++ "." ++ String.padLeft 2 '0' (String.fromInt centsRem)


formatCoord : Float -> Float -> String
formatCoord lat lon =
    String.left 9 (String.fromFloat lat) ++ ", " ++ String.left 9 (String.fromFloat lon)


formatDateDisplay : String -> String
formatDateDisplay iso =
    case String.split "-" iso of
        [ y, m, d ] ->
            let
                mn =
                    case m of
                        "01" -> "Jan"
                        "02" -> "Feb"
                        "03" -> "Mar"
                        "04" -> "Apr"
                        "05" -> "May"
                        "06" -> "Jun"
                        "07" -> "Jul"
                        "08" -> "Aug"
                        "09" -> "Sep"
                        "10" -> "Oct"
                        "11" -> "Nov"
                        "12" -> "Dec"
                        _    -> m

                day =
                    String.toInt d |> Maybe.withDefault 0 |> String.fromInt
            in
            mn ++ " " ++ day ++ ", " ++ y

        _ ->
            iso


isoToDayCount : String -> Int
isoToDayCount s =
    case List.filterMap String.toInt (String.split "-" s) of
        [ y, m, d ] ->
            let
                monthOffsets =
                    [ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 ]

                offset =
                    List.drop (m - 1) monthOffsets |> List.head |> Maybe.withDefault 0
            in
            y * 365 + offset + d

        _ ->
            0


encodeWaypoints : List EffectiveEntry -> String
encodeWaypoints entries =
    let
        withCoords =
            List.filterMap
                (\e ->
                    case ( e.lat, e.lon ) of
                        ( Just la, Just lo ) ->
                            Just
                                (E.object
                                    [ ( "lat", E.float la )
                                    , ( "lon", E.float lo )
                                    , ( "label"
                                      , E.string
                                            ((if e.merchant /= "" then e.merchant else Category.label e.category)
                                                ++ " "
                                                ++ formatAmount e.amount
                                            )
                                      )
                                    ]
                                )

                        _ ->
                            Nothing
                )
                entries
    in
    E.encode 0 (E.list identity withCoords)
