module Data.CsvExport exposing (toCsv)

{-| Formats a list of expenses as a CSV string for browser download.

Column order: id, date, amount, category, paymentMethod, note, merchant,
createdAt, lat, lon, longNote, tripId

-}

import Data.Category as Category
import Data.DateField as DateField
import Data.Expense exposing (Expense)
import Data.ExpenseId as ExpenseId
import Data.GeoPoint as GeoPoint
import Data.Iso8601 as Iso8601
import Data.Money as Money
import Data.PaymentMethod as PaymentMethod
import Data.TripId as TripId


{-| Convert a list of expenses to a CSV string.

Column order: id, date, amount, category, paymentMethod, note, merchant,
createdAt, lat, lon, longNote, tripId

    toCsv []
    --> "id,date,amount,category,paymentMethod,note,merchant,createdAt,lat,lon,longNote,tripId\n"

-}
toCsv : List Expense -> String
toCsv expenses =
    let
        header =
            "id,date,amount,category,paymentMethod,note,merchant,createdAt,lat,lon,longNote,tripId"

        rows =
            List.map toRow expenses
    in
    String.join "\n" (header :: rows) ++ "\n"


toRow : Expense -> String
toRow e =
    let
        lat =
            e.geoPoint
                |> Maybe.map (GeoPoint.latDegrees >> String.fromFloat)
                |> Maybe.withDefault ""

        lon =
            e.geoPoint
                |> Maybe.map (GeoPoint.lonDegrees >> String.fromFloat)
                |> Maybe.withDefault ""

        amountDollars =
            toFloat (Money.toCents e.amount) / 100.0

        paymentMethod =
            e.paymentMethod
                |> Maybe.map PaymentMethod.toString
                |> Maybe.withDefault ""
    in
    [ ExpenseId.toString e.id
    , DateField.toIso e.date
    , String.fromFloat amountDollars
    , Category.label e.category
    , paymentMethod
    , csvEscape e.note
    , csvEscape e.merchant
    , Iso8601.fromPosix e.createdAt
    , lat
    , lon
    , csvEscape e.longNote
    , TripId.toString e.tripId
    ]
        |> String.join ","


csvEscape : String -> String
csvEscape s =
    if String.contains "," s || String.contains "\"" s || String.contains "\n" s then
        "\"" ++ String.replace "\"" "\"\"" s ++ "\""

    else
        s
