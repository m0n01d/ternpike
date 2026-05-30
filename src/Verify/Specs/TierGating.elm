module Verify.Specs.TierGating exposing (Input, surface, honest, results)

{-| Pilot verification unit: the "Share a trip" create-row gate in
`Pages.Settings.SharedTrips.viewCreateRow`.

This mirrors the only live (non-screenshot) assertions in the retired
`e2e/specs/tier-gating.spec.ts`: a free (`Tern`) user sees a _disabled_ "New
shared trip" button plus the "Upgrade to Osprey to start one" copy, while paid
tiers get an enabled control. The gate is driven by `Data.Tier.isPaid`, which the
surface reuses — no gating logic is re-derived here.

The input is just the tier (plus a `corrupt` knob used only by the adversarial
probe), so the pure tier builds it directly — no `Browser.Navigation.Key`
needed — and the DOM tier projects the seeded model's `tier` into it via
`honest`. Both call `surface`.

@docs Input, surface, honest, results

-}

import Data.Tier as Tier
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


{-| The slice this unit observes. `corrupt = True` simulates a regression in the
gate (the surface lies about the tier) — only the probe fixture sets it, so the
invariants have something real to catch.
-}
type alias Input =
    { corrupt : Bool
    , tier : Tier.Tier
    }


{-| An honest input for a tier — the projection the DOM tier feeds from the
seeded model (never corrupt).
-}
honest : Tier.Tier -> Input
honest tier =
    { corrupt = False, tier = tier }


{-| Derive the create-row gate's observable surface. With `corrupt = False` this
is the real gate; with `corrupt = True` the gate is flipped to model a
regression (used only by the adversarial probe fixture).
-}
surface : Input -> Contract.Surface
surface input =
    if Basics.xor (Tier.isPaid input.tier) input.corrupt then
        [ ( "create-flock", "unlocked" ), ( "upgrade-copy", "none" ) ]

    else
        [ ( "create-flock", "locked" ), ( "upgrade-copy", "osprey" ) ]


{-| The unit spec: three honest fixtures (one per tier) plus one adversarial
probe whose injected regression must trip an invariant.
-}
spec : Spec.UnitSpec Input
spec =
    { fixtures =
        [ { input = honest Tier.Tern, name = "tern", probe = False }
        , { input = honest Tier.Osprey, name = "osprey", probe = False }
        , { input = honest Tier.Trailblazer, name = "trailblazer", probe = False }
        , { input = { corrupt = True, tier = Tier.Tern }, name = "probe-corrupt-tern", probe = True }
        ]
    , invariants =
        [ { name = "free tier locks create-flock", check = freeLocks }
        , { name = "paid tier unlocks create-flock", check = paidUnlocks }
        ]
    , name = unitName
    , surface = surface
    }


{-| The pure-tier results for this unit — collected by `Verify.Registry`. The
probe fixture is expected to produce a `Fail`; the matrix test asserts that.
-}
results : List Core.RunResult
results =
    Runner.runUnit spec


unitName : String
unitName =
    "TierGating"


{-| Free tiers must show the locked surface; on a paid tier this holds vacuously.
-}
freeLocks : Input -> Contract.Surface -> Maybe String
freeLocks input observed =
    if Tier.isPaid input.tier then
        Nothing

    else if surfaceValue "create-flock" observed == Just "locked" then
        Nothing

    else
        Just ("free tier " ++ Tier.toString input.tier ++ " did not lock create-flock")


{-| Paid tiers must show the unlocked surface; on a free tier this holds vacuously.
-}
paidUnlocks : Input -> Contract.Surface -> Maybe String
paidUnlocks input observed =
    if not (Tier.isPaid input.tier) then
        Nothing

    else if surfaceValue "create-flock" observed == Just "unlocked" then
        Nothing

    else
        Just ("paid tier " ++ Tier.toString input.tier ++ " did not unlock create-flock")


surfaceValue : String -> Contract.Surface -> Maybe String
surfaceValue key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
