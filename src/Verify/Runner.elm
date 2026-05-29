module Verify.Runner exposing (runUnit)

{-| The mount → observe → verify → verdict path, shared by both tiers. For the
pilot there is no `Msg`-folding: a unit's input _is_ its starting state, so we
derive the surface, run the invariants, and roll up a verdict. (Folding `Msg`s
through the real `Main.update` for interactive units is deferred — see the
Verify track plan.)

The driver takes no `update` argument and never imports `Main`, so the spec
layer stays free of the `Main → Registry → Specs → Main` cycle.

@docs runUnit

-}

import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Spec as Spec


{-| Run one fixture: derive its surface, evaluate every invariant into a
`Check`, and collapse to a verdict.
-}
runFixture : Spec.UnitSpec input -> Spec.Fixture input -> Core.RunResult
runFixture spec fixture =
    let
        surface : Contract.Surface
        surface =
            spec.surface fixture.input

        checks : List Core.Check
        checks =
            List.map (toCheck fixture.input surface) spec.invariants
    in
    { checks = checks
    , fixture = fixture.name
    , surface = surface
    , unit = spec.name
    , verdict = Core.verdictFromChecks checks
    }


{-| Run every fixture declared by a unit.
-}
runUnit : Spec.UnitSpec input -> List Core.RunResult
runUnit spec =
    List.map (runFixture spec) spec.fixtures


toCheck : input -> Contract.Surface -> Spec.Invariant input -> Core.Check
toCheck input surface invariant =
    case invariant.check input surface of
        Nothing ->
            { detail = invariant.name ++ " held"
            , name = invariant.name
            , status = Core.Ok_
            , verifier = invariant.name
            }

        Just reason ->
            { detail = invariant.name ++ ": " ++ reason
            , name = invariant.name
            , status = Core.Failed
            , verifier = invariant.name
            }
