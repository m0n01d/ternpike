module Verify.Core exposing
    ( Verdict(..), CheckStatus(..), Check, RunResult
    , verdictFromChecks, verdictToString, isFailed
    )

{-| The verdict taxonomy shared by every verification consumer — the pure-tier
matrix (`tests/MatrixTest.elm`), the DOM-tier `/verify` routes, and any agent
reading `window.__verify`. One taxonomy, every consumer.

This is the Elm port of the "Verifiable React" phase-3 verdict layer: a unit ×
fixture is observed at its surface, each invariant becomes a `Check`, and the
checks collapse to a single `Verdict`.

@docs Verdict, CheckStatus, Check, RunResult
@docs verdictFromChecks, verdictToString, isFailed

-}


{-| The outcome of running one fixture. `Fail` carries the concatenated detail
of every violated invariant so an agent (or a human at the dashboard) sees
_why_, not just _that_.

Only the two variants the pilot constructs are defined. `Blocked` ("couldn't
observe") and `Skip` are deliberately deferred until a unit actually produces
them — `elm-review`'s `NoUnused.CustomTypeConstructors` would otherwise flag
them.

-}
type Verdict
    = Pass
    | Fail String


{-| The status of a single invariant check. `Ok_` means the invariant held;
`Failed` means it was observed and violated.
-}
type CheckStatus
    = Ok_
    | Failed


{-| One invariant's result against an observed surface.
-}
type alias Check =
    { detail : String
    , name : String
    , status : CheckStatus
    , verifier : String
    }


{-| The full record for one unit × fixture run: the observed surface plus every
check and the rolled-up verdict. This is what the registry collects and what
serializes out to `window.__verify`.
-}
type alias RunResult =
    { checks : List Check
    , fixture : String
    , surface : List ( String, String )
    , unit : String
    , verdict : Verdict
    }


{-| Did this check fail?

    isFailed { detail = "", name = "x", status = Failed, verifier = "inv" }
    --> True

    isFailed { detail = "", name = "x", status = Ok_, verifier = "inv" }
    --> False

-}
isFailed : Check -> Bool
isFailed check =
    case check.status of
        Failed ->
            True

        Ok_ ->
            False


{-| Collapse a list of checks into a verdict. Any failed check makes the whole
fixture `Fail`, with the failed details joined; otherwise `Pass`.
-}
verdictFromChecks : List Check -> Verdict
verdictFromChecks checks =
    case List.filter isFailed checks of
        [] ->
            Pass

        failures ->
            Fail (String.join "; " (List.map .detail failures))


{-| Render a verdict for a manifest, a log line, or an agent probe.

    verdictToString Pass
    --> "PASS"

    verdictToString (Fail "tern unlocked")
    --> "FAIL: tern unlocked"

-}
verdictToString : Verdict -> String
verdictToString verdict =
    case verdict of
        Pass ->
            "PASS"

        Fail detail ->
            "FAIL: " ++ detail
