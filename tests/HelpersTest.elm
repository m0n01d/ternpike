module HelpersTest exposing (suite)

{-| Verify that `Helpers.encodeWaypoints` emits the chronological,
day-indexed JSON shape consumed by `<waypoint-map>` (#151).
-}

import Data.Category exposing (Category(..))
import Data.Currency
import Data.DateField as DateField
import Data.Entry exposing (EffectiveEntry)
import Data.ExpenseId as ExpenseId
import Data.GeoPoint as GeoPoint
import Data.Money as Money
import Data.TripId as TripId
import Data.UserId as UserId
import Expect
import Helpers
import Json.Decode
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Helpers.encodeWaypoints"
        [ test "assigns 1-based dayIndex in chronological order" <|
            \_ ->
                let
                    entries =
                        [ entry { iso = "2024-05-22", millis = 200, merchant = "B1" }
                        , entry { iso = "2024-05-21", millis = 100, merchant = "A1" }
                        , entry { iso = "2024-05-23", millis = 300, merchant = "C1" }
                        ]
                in
                decodePoints (Helpers.encodeWaypoints entries)
                    |> Result.map (List.map .dayIndex)
                    |> Expect.equal (Ok [ 1, 2, 3 ])
        , test "same-day stops share a dayIndex; second is not a boundary" <|
            \_ ->
                let
                    entries =
                        [ entry { iso = "2024-05-21", millis = 100, merchant = "A1" }
                        , entry { iso = "2024-05-21", millis = 200, merchant = "A2" }
                        , entry { iso = "2024-05-22", millis = 300, merchant = "B1" }
                        , entry { iso = "2024-05-22", millis = 400, merchant = "B2" }
                        ]
                in
                decodePoints (Helpers.encodeWaypoints entries)
                    |> Result.map (List.map (\p -> ( p.dayIndex, p.isDayBoundary )))
                    |> Expect.equal
                        (Ok
                            [ ( 1, True )
                            , ( 1, False )
                            , ( 2, True )
                            , ( 2, False )
                            ]
                        )
        , test "sorts same-day stops by createdAt" <|
            \_ ->
                let
                    entries =
                        [ entry { iso = "2024-05-21", millis = 300, merchant = "Late" }
                        , entry { iso = "2024-05-21", millis = 100, merchant = "Early" }
                        , entry { iso = "2024-05-21", millis = 200, merchant = "Middle" }
                        ]
                in
                decodePoints (Helpers.encodeWaypoints entries)
                    |> Result.map (List.map .label)
                    |> Result.map (List.map (String.split " " >> List.head >> Maybe.withDefault ""))
                    |> Expect.equal (Ok [ "Early", "Middle", "Late" ])
        , test "all entries on one day produces a single dayIndex" <|
            \_ ->
                let
                    entries =
                        [ entry { iso = "2024-05-21", millis = 100, merchant = "A" }
                        , entry { iso = "2024-05-21", millis = 200, merchant = "B" }
                        , entry { iso = "2024-05-21", millis = 300, merchant = "C" }
                        ]
                in
                decodePoints (Helpers.encodeWaypoints entries)
                    |> Result.map (List.map .dayIndex)
                    |> Expect.equal (Ok [ 1, 1, 1 ])
        , test "entries with no geoPoint are silently dropped" <|
            \_ ->
                let
                    entries =
                        [ entry { iso = "2024-05-21", millis = 100, merchant = "A" }
                        , entryNoGeo { iso = "2024-05-22", millis = 200, merchant = "B" }
                        , entry { iso = "2024-05-23", millis = 300, merchant = "C" }
                        ]
                in
                decodePoints (Helpers.encodeWaypoints entries)
                    |> Result.map (List.map .dayIndex)
                    |> Expect.equal (Ok [ 1, 2 ])
        , test "empty input encodes to []" <|
            \_ ->
                Helpers.encodeWaypoints []
                    |> Expect.equal "[]"
        , test "dayLabel renders MMM d" <|
            \_ ->
                let
                    entries =
                        [ entry { iso = "2024-05-21", millis = 100, merchant = "A" }
                        , entry { iso = "2024-12-31", millis = 200, merchant = "B" }
                        ]
                in
                decodePoints (Helpers.encodeWaypoints entries)
                    |> Result.map (List.map .dayLabel)
                    |> Expect.equal (Ok [ "May 21", "Dec 31" ])
        ]



-- HELPERS


type alias DecodedPoint =
    { date : String
    , dayIndex : Int
    , dayLabel : String
    , isDayBoundary : Bool
    , label : String
    }


pointDecoder : Json.Decode.Decoder DecodedPoint
pointDecoder =
    Json.Decode.map5 DecodedPoint
        (Json.Decode.field "date" Json.Decode.string)
        (Json.Decode.field "dayIndex" Json.Decode.int)
        (Json.Decode.field "dayLabel" Json.Decode.string)
        (Json.Decode.field "isDayBoundary" Json.Decode.bool)
        (Json.Decode.field "label" Json.Decode.string)


decodePoints : String -> Result Json.Decode.Error (List DecodedPoint)
decodePoints raw =
    Json.Decode.decodeString (Json.Decode.list pointDecoder) raw


entry : { iso : String, millis : Int, merchant : String } -> EffectiveEntry
entry r =
    { address = ""
    , amount = Money.fromCents 1000
    , category = Food
    , createdAt = Time.millisToPosix r.millis
    , createdBy = UserId.fromString "alice@example.com"
    , currency = Data.Currency.USD
    , date = DateField.fromIso r.iso |> Maybe.withDefault epoch
    , fuelDetail = Nothing
    , geoPoint = Just (GeoPoint.fromDegrees 64.0 -149.0)
    , id = ExpenseId.fromString ("expense::" ++ r.iso ++ "T00:00:00Z::" ++ String.fromInt r.millis)
    , isAmended = False
    , longNote = ""
    , merchant = r.merchant
    , note = ""
    , paymentMethod = Nothing
    , tripId = TripId.fromString "trip::2024-05-21T14:30:45Z::zzzzzzzz"
    }


entryNoGeo : { iso : String, millis : Int, merchant : String } -> EffectiveEntry
entryNoGeo r =
    let
        e =
            entry r
    in
    { e | geoPoint = Nothing }


epoch : DateField.DateField
epoch =
    DateField.today Time.utc (Time.millisToPosix 0)
