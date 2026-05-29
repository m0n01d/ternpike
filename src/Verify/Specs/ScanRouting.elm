module Verify.Specs.ScanRouting exposing (results)

{-| Verification unit for the OCR-routing decision (#348): given the user's BYO
key and tier, which path does a scan take — hosted proxy, the user's own key, or
unscannable?

The decision is `Data.OcrPath.resolve`, reused here so the surface can't drift.
This is the regression-prone logic the e2e `scan-byo-vs-hosted.spec.ts` guarded;
covering it hermetically takes the _decision_ off the browser harness (the
remaining "which network endpoint actually fired" wiring stays in the nightly
e2e until a DOM probe or server check covers it).

Pure-tier only for now: the surface lives on the per-trip Scan page, so a DOM
probe waits on generalizing `/verify` seeding to mount a trip + Scan route. Only
`results` is exposed — the registry's sole consumer.

@docs results

-}

import Data.AnthropicKey as AnthropicKey exposing (AnthropicKey)
import Data.OcrPath as OcrPath
import Data.Tier as Tier
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


type alias Input =
    { corrupt : Bool
    , key : Maybe AnthropicKey
    , tier : Tier.Tier
    }


{-| The pure-tier results for this unit, collected by `Verify.Registry`.
-}
results : List Core.RunResult
results =
    Runner.runUnit spec


spec : Spec.UnitSpec Input
spec =
    { fixtures =
        [ { input = { corrupt = False, key = Nothing, tier = Tier.Tern }, name = "unscannable", probe = False }
        , { input = { corrupt = False, key = Nothing, tier = Tier.Osprey }, name = "hosted", probe = False }
        , { input = { corrupt = False, key = sampleKey, tier = Tier.Osprey }, name = "byo", probe = False }
        , { input = { corrupt = False, key = sampleKey, tier = Tier.Tern }, name = "byo-on-free", probe = False }
        , { input = { corrupt = True, key = Nothing, tier = Tier.Tern }, name = "probe-corrupt-unscannable", probe = True }
        ]
    , invariants =
        [ { name = "free tier without a key is unscannable", check = freeNoKeyUnscannable }
        , { name = "a BYO key always routes to byo", check = keyRoutesByo }
        , { name = "paid tier without a key routes to hosted", check = paidNoKeyHosted }
        ]
    , name = "ScanRouting"
    , surface = surface
    }


sampleKey : Maybe AnthropicKey
sampleKey =
    AnthropicKey.fromInput "sk-ant-verify-fixture"


surface : Input -> Contract.Surface
surface input =
    let
        path : String
        path =
            if input.corrupt then
                -- A regression: claim BYO regardless of key/tier.
                "byo"

            else
                pathKey (OcrPath.resolve input.key input.tier)
    in
    [ ( "ocr-path", path ) ]


pathKey : OcrPath.OcrPath -> String
pathKey ocrPath =
    case ocrPath of
        OcrPath.ByoPath _ ->
            "byo"

        OcrPath.HostedPath ->
            "hosted"

        OcrPath.Unscannable ->
            "unscannable"



-- INVARIANTS


freeNoKeyUnscannable : Input -> Contract.Surface -> Maybe String
freeNoKeyUnscannable input observed =
    if Tier.isPaid input.tier || input.key /= Nothing then
        Nothing

    else if value "ocr-path" observed == Just "unscannable" then
        Nothing

    else
        Just "free tier without a key was not unscannable"


keyRoutesByo : Input -> Contract.Surface -> Maybe String
keyRoutesByo input observed =
    if input.key == Nothing then
        Nothing

    else if value "ocr-path" observed == Just "byo" then
        Nothing

    else
        Just "a BYO key did not route to byo"


paidNoKeyHosted : Input -> Contract.Surface -> Maybe String
paidNoKeyHosted input observed =
    if not (Tier.isPaid input.tier) || input.key /= Nothing then
        Nothing

    else if value "ocr-path" observed == Just "hosted" then
        Nothing

    else
        Just "paid tier without a key did not route to hosted"


value : String -> Contract.Surface -> Maybe String
value key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
