module Verify.Spec exposing (Fixture, Invariant, UnitSpec)

{-| Unit-generic spec types, parameterized on a per-unit _input projection_.

A unit's input is a small, key-free slice of app state — never the whole
`Model` (which holds an unconstructable `Browser.Navigation.Key`). The pure
tier builds the input directly; the DOM tier projects the live seeded model
into it. Both tiers call the same `UnitSpec.surface`.

@docs Fixture, Invariant, UnitSpec

-}

import Verify.Contract as Contract


{-| A reproducible starting state for a unit. `probe = True` marks an
adversarial fixture whose invariants are _expected_ to fail — proof the harness
catches lies, not just confirms truths.
-}
type alias Fixture input =
    { input : input
    , name : String
    , probe : Bool
    }


{-| A predicate over a unit's input and the surface it produced. `Nothing` means
the invariant holds; `Just reason` means it was violated.
-}
type alias Invariant input =
    { check : input -> Contract.Surface -> Maybe String
    , name : String
    }


{-| Everything needed to verify one unit: how to derive its surface, the
fixtures to run, and the invariants to check against each.
-}
type alias UnitSpec input =
    { fixtures : List (Fixture input)
    , invariants : List (Invariant input)
    , name : String
    , surface : input -> Contract.Surface
    }
