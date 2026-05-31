module MilepostReconcileTest exposing (suite)

{-| Pins every branch of `Data.MilepostProgress.reconcile` — the pure decision
at the heart of `Main.reconcileMileposts` (issue #428).

The headline invariant is **silent first load**: seeding the persisted map from
a pre-existing backlog must never enqueue celebration toasts. The other branches
cover idempotency (no write churn), fresh earns (persist + enqueue), `_rev`
threading, and the never-un-earn property.

-}

import Data.MilepostProgress as MilepostProgress
import Dict
import Expect
import Set
import Test exposing (Test, describe, test)
import Time
import Types exposing (MilepostState(..))


suite : Test
suite =
    describe "Data.MilepostProgress.reconcile"
        [ describe "NotLoaded (first load)"
            [ test "seeds persist from the current backlog but enqueues NOTHING" <|
                \_ ->
                    let
                        result : { persist : Maybe MilepostProgress.MilepostProgress, rev : Maybe String, toEnqueue : List String }
                        result =
                            MilepostProgress.reconcile
                                { earnedNow = Set.fromList [ "first-trip", "ten-trips" ]
                                , now = Time.millisToPosix 1000
                                , state = NotLoaded
                                }
                    in
                    Expect.all
                        [ \r -> Expect.equal (Just (Dict.keys (earnedOf r.persist))) (Just [ "first-trip", "ten-trips" ])
                        , \r -> Expect.equal [] r.toEnqueue
                        , \r -> Expect.equal Nothing r.rev
                        ]
                        result
            , test "stamps every seeded id with `now`" <|
                \_ ->
                    let
                        result =
                            MilepostProgress.reconcile
                                { earnedNow = Set.fromList [ "first-trip" ]
                                , now = Time.millisToPosix 0
                                , state = NotLoaded
                                }
                    in
                    Expect.equal
                        (Just (Dict.fromList [ ( "first-trip", "1970-01-01T00:00:00Z" ) ]))
                        (Maybe.map .earned result.persist)
            , test "an empty backlog still persists (an empty doc) silently" <|
                \_ ->
                    let
                        result =
                            MilepostProgress.reconcile
                                { earnedNow = Set.empty
                                , now = Time.millisToPosix 0
                                , state = NotLoaded
                                }
                    in
                    Expect.all
                        [ \r -> Expect.equal (Just Dict.empty) (Maybe.map .earned r.persist)
                        , \r -> Expect.equal [] r.toEnqueue
                        ]
                        result
            ]
        , describe "Loaded — idempotent"
            [ test "nothing new earned → no write, no enqueue" <|
                \_ ->
                    let
                        result =
                            MilepostProgress.reconcile
                                { earnedNow = Set.fromList [ "first-trip" ]
                                , now = Time.millisToPosix 9999
                                , state =
                                    Loaded
                                        { earned = Dict.fromList [ ( "first-trip", "2024-01-01T00:00:00.000Z" ) ]
                                        , rev = Just "3-abc"
                                        }
                                }
                    in
                    Expect.all
                        [ \r -> Expect.equal Nothing r.persist
                        , \r -> Expect.equal [] r.toEnqueue
                        ]
                        result
            , test "earnedNow is a subset of persisted → still no write" <|
                \_ ->
                    let
                        result =
                            MilepostProgress.reconcile
                                { earnedNow = Set.fromList [ "first-trip" ]
                                , now = Time.millisToPosix 0
                                , state =
                                    Loaded
                                        { earned =
                                            Dict.fromList
                                                [ ( "first-trip", "2024-01-01T00:00:00.000Z" )
                                                , ( "ten-trips", "2024-02-01T00:00:00.000Z" )
                                                ]
                                        , rev = Nothing
                                        }
                                }
                    in
                    Expect.equal Nothing result.persist
            ]
        , describe "Loaded — fresh earn"
            [ test "one new id → toEnqueue is exactly that id, persist includes it" <|
                \_ ->
                    let
                        result =
                            MilepostProgress.reconcile
                                { earnedNow = Set.fromList [ "first-trip", "ten-trips" ]
                                , now = Time.millisToPosix 0
                                , state =
                                    Loaded
                                        { earned = Dict.fromList [ ( "first-trip", "2024-01-01T00:00:00.000Z" ) ]
                                        , rev = Just "5-xyz"
                                        }
                                }
                    in
                    Expect.all
                        [ \r -> Expect.equal [ "ten-trips" ] r.toEnqueue
                        , \r -> Expect.equal (Just True) (Maybe.map (\p -> Dict.member "ten-trips" p.earned) r.persist)
                        ]
                        result
            , test "the new id is stamped with `now`, not the old timestamp" <|
                \_ ->
                    let
                        result =
                            MilepostProgress.reconcile
                                { earnedNow = Set.fromList [ "ten-trips" ]
                                , now = Time.millisToPosix 0
                                , state =
                                    Loaded
                                        { earned = Dict.fromList [ ( "first-trip", "2024-01-01T00:00:00.000Z" ) ]
                                        , rev = Nothing
                                        }
                                }
                    in
                    Expect.equal
                        (Just (Just "1970-01-01T00:00:00Z"))
                        (Maybe.map (\p -> Dict.get "ten-trips" p.earned) result.persist)
            ]
        , describe "_rev threading"
            [ test "Loaded write path carries the existing rev back out" <|
                \_ ->
                    let
                        result =
                            MilepostProgress.reconcile
                                { earnedNow = Set.fromList [ "ten-trips" ]
                                , now = Time.millisToPosix 0
                                , state =
                                    Loaded
                                        { earned = Dict.fromList [ ( "first-trip", "2024-01-01T00:00:00.000Z" ) ]
                                        , rev = Just "7-deadbeef"
                                        }
                                }
                    in
                    Expect.equal (Just "7-deadbeef") result.rev
            ]
        , describe "never un-earn"
            [ test "an id in persisted but not earnedNow stays in persist's earned map" <|
                \_ ->
                    let
                        result =
                            MilepostProgress.reconcile
                                { earnedNow = Set.fromList [ "ten-trips" ]
                                , now = Time.millisToPosix 0
                                , state =
                                    Loaded
                                        { earned = Dict.fromList [ ( "first-trip", "2024-01-01T00:00:00.000Z" ) ]
                                        , rev = Just "2-keep"
                                        }
                                }
                    in
                    Expect.all
                        [ \r -> Expect.equal (Just True) (Maybe.map (\p -> Dict.member "first-trip" p.earned) r.persist)
                        , \r -> Expect.equal (Just (Just "2024-01-01T00:00:00.000Z")) (Maybe.map (\p -> Dict.get "first-trip" p.earned) r.persist)
                        , \r -> Expect.equal (Just True) (Maybe.map (\p -> Dict.member "ten-trips" p.earned) r.persist)
                        ]
                        result
            ]
        ]


earnedOf : Maybe MilepostProgress.MilepostProgress -> Dict.Dict String String
earnedOf maybeProgress =
    maybeProgress
        |> Maybe.map .earned
        |> Maybe.withDefault Dict.empty
