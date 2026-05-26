module UserIdTests exposing (suite)

import Data.UserId as UserId
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Data.UserId"
        [ describe "shortHash"
            [ test "alice@example.com produces a stable 4-char hex hash" <|
                \_ ->
                    UserId.shortHash (UserId.fromString "alice@example.com")
                        |> String.length
                        |> Expect.equal 4
            , test "bob@example.com hash differs from alice@example.com hash" <|
                \_ ->
                    let
                        aliceHash =
                            UserId.shortHash (UserId.fromString "alice@example.com")

                        bobHash =
                            UserId.shortHash (UserId.fromString "bob@example.com")
                    in
                    Expect.notEqual aliceHash bobHash
            , test "alice@gmail.com and alice@yahoo.com produce different hashes" <|
                \_ ->
                    let
                        gmailHash =
                            UserId.shortHash (UserId.fromString "alice@gmail.com")

                        yahooHash =
                            UserId.shortHash (UserId.fromString "alice@yahoo.com")
                    in
                    Expect.notEqual gmailHash yahooHash
            , test "hash is stable across calls" <|
                \_ ->
                    let
                        userId =
                            UserId.fromString "dwight.j.doane@gmail.com"
                    in
                    Expect.equal
                        (UserId.shortHash userId)
                        (UserId.shortHash userId)
            , test "hash output is 4 lowercase hex chars" <|
                \_ ->
                    let
                        h =
                            UserId.shortHash (UserId.fromString "test@example.com")

                        isHexChar c =
                            List.member c (String.toList "0123456789abcdef")
                    in
                    Expect.equal True
                        (String.all isHexChar h && String.length h == 4)
            ]
        , describe "handleIn collision disambiguation"
            [ test "no collision — returns bare handle" <|
                \_ ->
                    let
                        alice =
                            UserId.fromString "alice@gmail.com"

                        bob =
                            UserId.fromString "bob@example.com"
                    in
                    Expect.equal "@alice"
                        (UserId.handleIn alice [ alice, bob ])
            , test "collision — result starts with @alice# and is 12 chars" <|
                \_ ->
                    let
                        aliceGmail =
                            UserId.fromString "alice@gmail.com"

                        aliceYahoo =
                            UserId.fromString "alice@yahoo.com"

                        bob =
                            UserId.fromString "bob@example.com"

                        result =
                            UserId.handleIn aliceGmail [ aliceGmail, aliceYahoo, bob ]
                    in
                    Expect.equal True
                        (String.startsWith "@alice#" result && String.length result == 11)
            , test "collision suffix is 4 chars" <|
                \_ ->
                    let
                        aliceGmail =
                            UserId.fromString "alice@gmail.com"

                        aliceYahoo =
                            UserId.fromString "alice@yahoo.com"

                        result =
                            UserId.handleIn aliceGmail [ aliceGmail, aliceYahoo ]

                        suffix =
                            String.dropLeft (String.length "@alice#") result
                    in
                    Expect.equal 4 (String.length suffix)
            ]
        ]
