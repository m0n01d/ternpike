module Data.AmendmentTest exposing (suite)

{-| Verify that `Data.Amendment.decoder` still accepts the legacy wire shape
written by pre-#94 clients: `_id` as a plain String, `amount` as a JSON
number (dollars), `date` as a `"YYYY-MM-DD"` string, and `createdAt` as
`"YYYY-MM-DDTHH:MM:SSZ"`.

Closes the "old PouchDB amendment doc still decodes after this lands"
verification check from the #94 issue body.

-}

import Data.Amendment as Amendment
import Data.AmendmentId as AmendmentId
import Data.DateField as DateField
import Data.Money as Money
import Expect
import Json.Decode
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Data.Amendment.decoder"
        [ test "accepts a legacy doc with float amount and ISO date/createdAt" <|
            \_ ->
                let
                    wire =
                        """
                        { "_id": "amend::expense::2024-05-21T14:30:45Z::abcd1234::ef567890"
                        , "amount": 19.99
                        , "category": "food"
                        , "createdAt": "2024-05-21T15:45:00Z"
                        , "createdBy": "alice@example.com"
                        , "date": "2024-05-22"
                        , "merchant": "Cafe Halibut"
                        , "note": "lunch (corrected)"
                        , "targetId": "expense::2024-05-21T14:30:45Z::abcd1234"
                        , "type": "amend"
                        }
                        """
                in
                case Json.Decode.decodeString Amendment.decoder wire of
                    Ok a ->
                        Expect.all
                            [ \am ->
                                AmendmentId.toString am.id
                                    |> Expect.equal "amend::expense::2024-05-21T14:30:45Z::abcd1234::ef567890"
                            , \am ->
                                am.amount
                                    |> Maybe.map Money.toCents
                                    |> Expect.equal (Just 1999)
                            , \am ->
                                am.date
                                    |> Maybe.map DateField.toIso
                                    |> Expect.equal (Just "2024-05-22")
                            , \am ->
                                Time.posixToMillis am.createdAt
                                    |> Expect.equal (Time.posixToMillis (legacyPosix 2024 5 21 15 45 0))
                            , \am ->
                                Expect.equal (Just "lunch (corrected)") am.note
                            ]
                            a

                    Err err ->
                        Expect.fail (Json.Decode.errorToString err)
        , test "missing optional fields decode to Nothing" <|
            \_ ->
                let
                    wire =
                        """
                        { "_id": "amend::expense::2024-05-21T14:30:45Z::abcd1234::ef567890"
                        , "createdAt": "2024-05-21T15:45:00Z"
                        , "createdBy": "alice@example.com"
                        , "targetId": "expense::2024-05-21T14:30:45Z::abcd1234"
                        , "type": "amend"
                        }
                        """
                in
                case Json.Decode.decodeString Amendment.decoder wire of
                    Ok a ->
                        Expect.all
                            [ \am -> Expect.equal Nothing am.amount
                            , \am -> Expect.equal Nothing am.date
                            , \am -> Expect.equal Nothing am.note
                            , \am -> Expect.equal Nothing am.merchant
                            , \am -> Expect.equal Nothing am.longNote
                            , \am -> Expect.equal Nothing am.paymentMethod
                            , \am -> Expect.equal Nothing am.category
                            ]
                            a

                    Err err ->
                        Expect.fail (Json.Decode.errorToString err)
        , test "roundtrips through encoder/decoder" <|
            \_ ->
                let
                    wire =
                        """
                        { "_id": "amend::expense::2024-05-21T14:30:45Z::abcd1234::ef567890"
                        , "amount": 12.50
                        , "createdAt": "2024-05-21T15:45:00Z"
                        , "createdBy": "bob@example.com"
                        , "date": "2024-05-22"
                        , "targetId": "expense::2024-05-21T14:30:45Z::abcd1234"
                        , "type": "amend"
                        }
                        """

                    decoded =
                        Json.Decode.decodeString Amendment.decoder wire

                    reencoded =
                        decoded
                            |> Result.map Amendment.encoder
                            |> Result.map (Json.Decode.decodeValue Amendment.decoder)
                in
                case ( decoded, reencoded ) of
                    ( Ok first, Ok (Ok second) ) ->
                        Expect.all
                            [ \_ ->
                                Expect.equal
                                    (Maybe.map Money.toCents first.amount)
                                    (Maybe.map Money.toCents second.amount)
                            , \_ ->
                                Expect.equal
                                    (Maybe.map DateField.toIso first.date)
                                    (Maybe.map DateField.toIso second.date)
                            , \_ ->
                                Expect.equal
                                    (Time.posixToMillis first.createdAt)
                                    (Time.posixToMillis second.createdAt)
                            , \_ ->
                                Expect.equal
                                    (AmendmentId.toString first.id)
                                    (AmendmentId.toString second.id)
                            ]
                            ()

                    _ ->
                        Expect.fail "expected both decode + reencode to succeed"
        ]



-- INTERNAL


{-| Build a `Time.Posix` from a UTC Y-M-D-H-M-S tuple. Mirrors the algorithm
in `Data.Iso8601` for the purpose of cross-checking the decoder.
-}
legacyPosix : Int -> Int -> Int -> Int -> Int -> Int -> Time.Posix
legacyPosix y mo d h mi s =
    let
        daysFromEpoch =
            daysBeforeYear y + daysBeforeMonth y mo + (d - 1)
    in
    Time.millisToPosix (((daysFromEpoch * 86400) + (h * 3600) + (mi * 60) + s) * 1000)


daysBeforeYear : Int -> Int
daysBeforeYear y =
    let
        years =
            y - 1970
    in
    (years * 365) + leapDaysBetween 1970 y


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
    List.drop (mo - 1) offsets |> List.head |> Maybe.withDefault 0


isLeapYear : Int -> Bool
isLeapYear y =
    (modBy 4 y == 0 && modBy 100 y /= 0) || modBy 400 y == 0
