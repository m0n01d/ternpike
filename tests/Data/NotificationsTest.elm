module Data.NotificationsTest exposing (suite)

{-| Decoder roundtrip test for `Data.Notifications`.

Verifies that `encodePrefs >> decodePrefs` is identity, covering both
`True` and `False` for the `weeklyScanReminder` field. A fuzz test
ensures the property holds for all boolean values, not just the defaults.

Closes the "Elm decoder roundtrip" requirement from #183.

-}

import Data.Notifications as Notifications
import Expect
import Fuzz
import Json.Decode
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "Data.Notifications"
        [ describe "encodePrefs / decodePrefs roundtrip"
            [ fuzz (Fuzz.map3 (\a b c -> ( a, b, c )) Fuzz.bool Fuzz.bool Fuzz.bool) "encodePrefs >> decodePrefs is identity" <|
                \( activity, stalled, weekly ) ->
                    let
                        prefs =
                            { sharedTripActivity = activity, syncStalled = stalled, weeklyScanReminder = weekly }
                    in
                    Notifications.encodePrefs prefs
                        |> Json.Decode.decodeValue Notifications.decodePrefs
                        |> Expect.equal (Ok prefs)
            , test "defaultPrefs survives a roundtrip" <|
                \_ ->
                    Notifications.encodePrefs Notifications.defaultPrefs
                        |> Json.Decode.decodeValue Notifications.decodePrefs
                        |> Expect.equal (Ok Notifications.defaultPrefs)
            , test "decodePrefs falls back to defaultPrefs on empty object" <|
                \_ ->
                    Json.Decode.decodeString Notifications.decodePrefs "{}"
                        |> Expect.equal (Ok Notifications.defaultPrefs)
            ]
        ]
