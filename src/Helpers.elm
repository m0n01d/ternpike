module Helpers exposing (effectiveEntryToExpense, encodeWaypoints, formatSyncTime)

import Data.Category as Category
import Data.DateField as DateField
import Data.Entry exposing (EffectiveEntry)
import Data.Expense exposing (Expense)
import Data.GeoPoint as GeoPoint
import Data.Money as Money
import Json.Encode
import Time


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


{-| Encode the geo-tagged entries as JSON for the `<waypoint-map>`
custom element. Each point carries `date`, `dayIndex` (1-based, in
chronological order), `dayLabel` ("May 21"), and `isDayBoundary` (True
for the first stop of each day) so the JS side can render one
chronological polyline plus labelled day pills without re-sorting.

Sort key is `(date, createdAt)` so same-day stops appear in entry
order. Entries with no geoPoint are silently dropped.

-}
encodeWaypoints : List EffectiveEntry -> String
encodeWaypoints entries =
    let
        withCoords =
            entries
                |> List.filter (\e -> e.geoPoint /= Nothing)
                |> List.sortWith
                    (\a b ->
                        case DateField.compare a.date b.date of
                            EQ ->
                                Basics.compare
                                    (Time.posixToMillis a.createdAt)
                                    (Time.posixToMillis b.createdAt)

                            other ->
                                other
                    )

        annotated =
            List.foldl
                (\e acc ->
                    let
                        iso =
                            DateField.toIso e.date

                        ( nextIndex, nextLastIso, isBoundary ) =
                            case acc.lastIso of
                                Just prev ->
                                    if prev == iso then
                                        ( acc.nextIndex, Just iso, False )

                                    else
                                        ( acc.nextIndex + 1, Just iso, True )

                                Nothing ->
                                    ( 1, Just iso, True )
                    in
                    { lastIso = nextLastIso
                    , nextIndex = nextIndex
                    , points = ( e, nextIndex, isBoundary ) :: acc.points
                    }
                )
                { lastIso = Nothing, nextIndex = 0, points = [] }
                withCoords
                |> .points
                |> List.reverse
    in
    annotated
        |> List.filterMap encodePoint
        |> Json.Encode.list identity
        |> Json.Encode.encode 0


encodePoint : ( EffectiveEntry, Int, Bool ) -> Maybe Json.Encode.Value
encodePoint ( e, dayIndex, isBoundary ) =
    case e.geoPoint of
        Just point ->
            Just
                (Json.Encode.object
                    [ ( "date", Json.Encode.string (DateField.toIso e.date) )
                    , ( "dayIndex", Json.Encode.int dayIndex )
                    , ( "dayLabel", Json.Encode.string (DateField.formatMonthDay e.date) )
                    , ( "isDayBoundary", Json.Encode.bool isBoundary )
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
                    , ( "lat", Json.Encode.float (GeoPoint.latDegrees point) )
                    , ( "lon", Json.Encode.float (GeoPoint.lonDegrees point) )
                    ]
                )

        Nothing ->
            Nothing


{-| Render a `Time.Posix` for the Settings "Last synced" line. Uses the
caller's local `Time.Zone` to produce something like `"May 26 at 5:42 PM"`.
The date portion reuses `DateField.formatMonthDay`; the time portion is
12-hour with AM/PM and a zero-padded minute.

    import Time

    formatSyncTime Time.utc (Time.millisToPosix 0)
    --> "Jan 1 at 12:00 AM"

    formatSyncTime Time.utc (Time.millisToPosix (12 * 3600 * 1000))
    --> "Jan 1 at 12:00 PM"

    formatSyncTime Time.utc (Time.millisToPosix (13 * 3600 * 1000 + 42 * 60 * 1000))
    --> "Jan 1 at 1:42 PM"

    formatSyncTime Time.utc (Time.millisToPosix (9 * 3600 * 1000 + 5 * 60 * 1000))
    --> "Jan 1 at 9:05 AM"

-}
formatSyncTime : Time.Zone -> Time.Posix -> String
formatSyncTime zone posix =
    let
        datePart =
            DateField.formatMonthDay (DateField.today zone posix)

        hour24 =
            Time.toHour zone posix

        ampm =
            if hour24 < 12 then
                "AM"

            else
                "PM"

        hour12 =
            if hour24 == 0 then
                12

            else if hour24 > 12 then
                hour24 - 12

            else
                hour24

        minute =
            Time.toMinute zone posix
                |> String.fromInt
                |> String.padLeft 2 '0'
    in
    String.concat
        [ datePart
        , " at "
        , String.fromInt hour12
        , ":"
        , minute
        , " "
        , ampm
        ]
