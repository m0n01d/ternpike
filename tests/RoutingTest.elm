module RoutingTest exposing (suite)

import Data.ExpenseId as ExpenseId
import Data.TripId as TripId
import Expect
import Routing exposing (editEntryPath, routeFromUrl)
import Test exposing (Test, describe, test)
import Types exposing (Route(..))
import Url


testUrl : String -> Url.Url
testUrl path =
    { protocol = Url.Https
    , host = "example.com"
    , port_ = Nothing
    , path = path
    , query = Nothing
    , fragment = Nothing
    }


suite : Test
suite =
    describe "Edit entry routing"
        [ describe "editEntryPath"
            [ test "root basePath" <|
                \_ ->
                    editEntryPath "/"
                        (TripId.fromString "trip::abc")
                        (ExpenseId.fromString "expense::def")
                        |> Expect.equal "/trip/trip::abc/ledger/expense::def/edit"
            , test "subdirectory basePath" <|
                \_ ->
                    editEntryPath "/ternpike/"
                        (TripId.fromString "trip::abc")
                        (ExpenseId.fromString "expense::def")
                        |> Expect.equal "/ternpike/trip/trip::abc/ledger/expense::def/edit"
            ]
        , describe "routeFromUrl"
            [ test "parses edit route at root" <|
                \_ ->
                    routeFromUrl "/" (testUrl "/trip/trip::abc/ledger/expense::def/edit")
                        |> Expect.equal
                            (RouteEditEntry
                                (TripId.fromString "trip::abc")
                                (ExpenseId.fromString "expense::def")
                            )
            , test "parses edit route with basePath" <|
                \_ ->
                    routeFromUrl "/ternpike/" (testUrl "/ternpike/trip/trip::abc/ledger/expense::def/edit")
                        |> Expect.equal
                            (RouteEditEntry
                                (TripId.fromString "trip::abc")
                                (ExpenseId.fromString "expense::def")
                            )
            , test "IDs with full timestamp colons survive roundtrip" <|
                \_ ->
                    let
                        tripId =
                            TripId.fromString "trip::2024-01-15T10:30:00.000Z::17000000"

                        expId =
                            ExpenseId.fromString "expense::2024-01-15T10:30:00.000Z::17000001"
                    in
                    routeFromUrl "/" (testUrl (editEntryPath "/" tripId expId))
                        |> Expect.equal (RouteEditEntry tripId expId)
            ]
        ]
