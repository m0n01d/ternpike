module Verify.Registry exposing (runAll, encode)

{-| The one list every consumer iterates: the pure-tier matrix
(`tests/MatrixTest.elm`), the DOM-tier `/verify` route, and `window.__verify`.

Each spec module is parameterized on its own input type, so the registry erases
that type param by collecting already-run `RunResult`s rather than the specs
themselves.

@docs runAll, encode

-}

import Json.Encode as Encode
import Verify.Core as Core
import Verify.Specs.JoinSharedTrip as JoinSharedTrip
import Verify.Specs.NotificationsPaywall as NotificationsPaywall
import Verify.Specs.ScanRouting as ScanRouting
import Verify.Specs.SharedTripCard as SharedTripCard
import Verify.Specs.TierGating as TierGating


{-| Every unit × fixture result. Add a unit by appending its `results` here.
-}
runAll : List Core.RunResult
runAll =
    List.concat
        [ TierGating.results
        , NotificationsPaywall.results
        , ScanRouting.results
        , JoinSharedTrip.results
        , SharedTripCard.results
        ]


{-| Serialize results for `window.__verify`. Each result becomes
`{ unit, fixture, verdict, surface, checks }` so an agent reads the same truth
the dashboard and the matrix test see.
-}
encode : List Core.RunResult -> Encode.Value
encode results =
    Encode.list encodeResult results


encodeResult : Core.RunResult -> Encode.Value
encodeResult result =
    Encode.object
        [ ( "unit", Encode.string result.unit )
        , ( "fixture", Encode.string result.fixture )
        , ( "verdict", Encode.string (Core.verdictToString result.verdict) )
        , ( "surface", Encode.object (List.map (\( k, v ) -> ( k, Encode.string v )) result.surface) )
        , ( "checks", Encode.list encodeCheck result.checks )
        ]


encodeCheck : Core.Check -> Encode.Value
encodeCheck check =
    Encode.object
        [ ( "name", Encode.string check.name )
        , ( "verifier", Encode.string check.verifier )
        , ( "detail", Encode.string check.detail )
        , ( "failed", Encode.bool (Core.isFailed check) )
        ]
