module RoutingTest exposing (suite)

import Data.ExpenseId as ExpenseId
import Data.TripId as TripId
import Expect
import Routing exposing (editEntryPath, routeFromUrl)
import Test exposing (Test, describe, test)
import Types exposing (Route(..))
import Url


testUrl : String -> Maybe String -> Url.Url
testUrl path query =
    { protocol = Url.Https
    , host = "example.com"
    , port_ = Nothing
    , path = path
    , query = query
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
                        |> Expect.equal "/trip/ledger/edit?tripId=trip::abc&expenseId=expense::def"
            , test "subdirectory basePath" <|
                \_ ->
                    editEntryPath "/ternpike/"
                        (TripId.fromString "trip::abc")
                        (ExpenseId.fromString "expense::def")
                        |> Expect.equal "/ternpike/trip/ledger/edit?tripId=trip::abc&expenseId=expense::def"
            ]
        , describe "routeFromUrl"
            [ test "parses edit route at root" <|
                \_ ->
                    routeFromUrl "/"
                        (testUrl "/trip/ledger/edit" (Just "tripId=trip::abc&expenseId=expense::def"))
                        |> Expect.equal
                            (RouteEditEntry
                                (TripId.fromString "trip::abc")
                                (ExpenseId.fromString "expense::def")
                            )
            , test "parses edit route with basePath" <|
                \_ ->
                    routeFromUrl "/ternpike/"
                        (testUrl "/ternpike/trip/ledger/edit" (Just "tripId=trip::abc&expenseId=expense::def"))
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

                        built =
                            editEntryPath "/" tripId expId

                        ( path, query ) =
                            case String.split "?" built of
                                p :: q :: _ ->
                                    ( p, Just q )

                                _ ->
                                    ( built, Nothing )
                    in
                    routeFromUrl "/" (testUrl path query)
                        |> Expect.equal (RouteEditEntry tripId expId)
            , test "percent-encoded query values decode back to ::" <|
                \_ ->
                    routeFromUrl "/"
                        (testUrl "/trip/ledger/edit"
                            (Just "tripId=trip%3A%3Aabc&expenseId=expense%3A%3Adef")
                        )
                        |> Expect.equal
                            (RouteEditEntry
                                (TripId.fromString "trip::abc")
                                (ExpenseId.fromString "expense::def")
                            )
            , test "parses ledger route" <|
                \_ ->
                    routeFromUrl "/"
                        (testUrl "/trip/ledger" (Just "tripId=trip::abc"))
                        |> Expect.equal (RouteLedger (TripId.fromString "trip::abc"))
            , test "ledger without tripId falls back to RouteTrips" <|
                \_ ->
                    routeFromUrl "/" (testUrl "/trip/ledger" Nothing)
                        |> Expect.equal RouteTrips
            , test "edit without expenseId falls back to RouteTrips" <|
                \_ ->
                    routeFromUrl "/"
                        (testUrl "/trip/ledger/edit" (Just "tripId=trip::abc"))
                        |> Expect.equal RouteTrips
            ]
        ]
