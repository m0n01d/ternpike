module Data.Iso8601 exposing (fromPosix, toPosix)

{-| Round-trip helpers between `Time.Posix` and the legacy ISO
`"YYYY-MM-DDTHH:MM:SSZ"` String shape used by PouchDB / CouchDB documents
(expense `createdAt`, amendment `createdAt`, void `createdAt`, trip
`createdAt`, etc.).

Rolling our own keeps the dependency footprint tight — we already need
this for two modules (`Data.Expense`, `Data.Amendment`) and the
`expense::` / `trip::` / `amend::` ID builders in `Main.elm`, so a tiny
internal helper module beats pulling in a date-parsing package.

Falls back to the epoch (`Time.millisToPosix 0`) on malformed input,
matching the silent-default pattern used by `Data.DateField.decoder` for
malformed legacy dates.

@docs fromPosix, toPosix

-}

import List.Extra
import Time


{-| Render a `Time.Posix` as the legacy ISO `"YYYY-MM-DDTHH:MM:SSZ"`
wire shape. All fields are zero-padded to two digits.
-}
fromPosix : Time.Posix -> String
fromPosix posix =
    let
        y =
            String.fromInt (Time.toYear Time.utc posix)

        m =
            String.fromInt (monthNum (Time.toMonth Time.utc posix)) |> String.padLeft 2 '0'

        d =
            String.fromInt (Time.toDay Time.utc posix) |> String.padLeft 2 '0'

        h =
            String.fromInt (Time.toHour Time.utc posix) |> String.padLeft 2 '0'

        mi =
            String.fromInt (Time.toMinute Time.utc posix) |> String.padLeft 2 '0'

        s =
            String.fromInt (Time.toSecond Time.utc posix) |> String.padLeft 2 '0'
    in
    y ++ "-" ++ m ++ "-" ++ d ++ "T" ++ h ++ ":" ++ mi ++ ":" ++ s ++ "Z"


{-| Parse an ISO `"YYYY-MM-DDTHH:MM:SSZ"` String into `Time.Posix`. Falls
back to `Time.millisToPosix 0` (epoch) on malformed input — unknown
formats land on `1970-01-01T00:00:00Z` so the document still loads.
-}
toPosix : String -> Time.Posix
toPosix raw =
    case String.split "T" raw of
        [ datePart, timePart ] ->
            case ( String.split "-" datePart, parseTimePart timePart ) of
                ( [ ys, ms, ds ], Just ( h, mi, s ) ) ->
                    case ( String.toInt ys, String.toInt ms, String.toInt ds ) of
                        ( Just y, Just mo, Just d ) ->
                            Time.millisToPosix (millisFromUtc y mo d h mi s)

                        _ ->
                            Time.millisToPosix 0

                _ ->
                    Time.millisToPosix 0

        _ ->
            Time.millisToPosix 0



-- INTERNAL


parseTimePart : String -> Maybe ( Int, Int, Int )
parseTimePart raw =
    let
        stripped =
            if String.endsWith "Z" raw then
                String.dropRight 1 raw

            else
                raw
    in
    case String.split ":" stripped of
        [ hs, mis, ss ] ->
            Maybe.map3 (\h mi s -> ( h, mi, s ))
                (String.toInt hs)
                (String.toInt mis)
                (String.toInt (String.left 2 ss))

        _ ->
            Nothing


{-| Convert a UTC Y-M-D-H-M-S tuple into a posix millis count. Uses the
proleptic Gregorian calendar via the cumulative-day approach: count days
from 1970-01-01 to the target date, then add the time-of-day seconds.
-}
millisFromUtc : Int -> Int -> Int -> Int -> Int -> Int -> Int
millisFromUtc y mo d h mi s =
    let
        daysFromEpoch =
            daysBeforeYear y + daysBeforeMonth y mo + (d - 1)
    in
    ((daysFromEpoch * 86400) + (h * 3600) + (mi * 60) + s) * 1000


daysBeforeYear : Int -> Int
daysBeforeYear y =
    let
        years =
            y - 1970
    in
    (years * 365)
        + leapDaysBetween 1970 y


leapDaysBetween : Int -> Int -> Int
leapDaysBetween start end =
    countLeapYears (end - 1) - countLeapYears (start - 1)


countLeapYears : Int -> Int
countLeapYears y =
    (y // 4) - (y // 100) + (y // 400)


daysBeforeMonth : Int -> Int -> Int
daysBeforeMonth y mo =
    let
        offsets =
            if isLeapYear y then
                [ 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335 ]

            else
                [ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 ]
    in
    List.Extra.getAt (mo - 1) offsets |> Maybe.withDefault 0


isLeapYear : Int -> Bool
isLeapYear y =
    (modBy 4 y == 0 && modBy 100 y /= 0) || modBy 400 y == 0


monthNum : Time.Month -> Int
monthNum month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
