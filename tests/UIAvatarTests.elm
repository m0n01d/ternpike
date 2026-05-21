module UIAvatarTests exposing (suite)

{-| Pinning-tests for `UI.Avatar.colourClass`.

The hash function is `sum-of-char-codes mod 5` so Alice keeps her
slot across devices. These tests pin a handful of inputs so a casual
refactor of the hashing function gets caught.

-}

import Data.UserId as UserId
import Expect
import Test exposing (Test)
import UI.Avatar


suite : Test
suite =
    Test.describe "UI.Avatar.colourClass"
        [ Test.test "empty UserId hashes to slot 0 (bg-rust)" <|
            \() ->
                UI.Avatar.colourClass (UserId.fromString "")
                    |> Expect.equal "bg-rust text-parchment"
        , Test.test "'alice@example.com' hashes to slot 2 (bg-moss)" <|
            \() ->
                UI.Avatar.colourClass (UserId.fromString "alice@example.com")
                    |> Expect.equal "bg-moss text-parchment"
        , Test.test "'bob@example.com' hashes to slot 4 (bg-tan)" <|
            \() ->
                UI.Avatar.colourClass (UserId.fromString "bob@example.com")
                    |> Expect.equal "bg-tan text-forest"
        , Test.test "deterministic — same input twice yields same class" <|
            \() ->
                let
                    user =
                        UserId.fromString "alice@flock.test"
                in
                Expect.equal (UI.Avatar.colourClass user)
                    (UI.Avatar.colourClass user)
        ]
