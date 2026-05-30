module Verify.Specs.ScanDeferral exposing (results)

{-| Verification unit for the capture-route decision in the offline scan
queue: given connectivity and the OCR path, should a freshly-captured
image fire OCR immediately (`now`), park as `ScanDeferred` (`deferred`),
or land in `ScanReady` for manual fill (`manual`)?

The decision is `Data.Scan.captureRoute`, reused here so the surface
can't drift from the real branching. This is the regression-prone
offline-gate: the riskiest failure mode is "the app fires an OCR call
while offline," which this unit catches deterministically.

Three invariants are checked for every fixture:

1.  **offline implies deferred or manual** — if the network is offline
    and a scannable path exists, the route must be `deferred`, not `now`.
    If the path is `Unscannable`, `manual` is also acceptable offline.
2.  **unscannable is always manual** — `captureRoute` with `Unscannable`
    must return `manual` regardless of connectivity. No deferred items
    accumulate for a path that can never OCR.
3.  **online + scannable is now** — online connectivity with a real OCR
    path must dispatch immediately.

The `probe-offline-fires-now` fixture is the adversarial regression: it
sets `offline = True` with a `HostedPath` but lies about the route being
`now`. Any regression in `captureRoute` that fires OCR while offline will
make invariant 1 trip and give an actionable failure.

Pure-tier only: the surface is a pure function of connectivity + OcrPath,
so no DOM seeding is needed. `verify:dom` is blocked on generalizing
`/verify` seeding to mount a trip + Scan route (documented in the PR).

@docs results

-}

import Data.AnthropicKey as AnthropicKey
import Data.OcrPath as OcrPath
import Data.Scan as Scan
import Verify.Contract as Contract
import Verify.Core as Core
import Verify.Runner as Runner
import Verify.Spec as Spec


type alias Input =
    { corrupt : Bool
    , offline : Bool
    , ocrPath : OcrPath.OcrPath
    }


{-| The pure-tier results for this unit, collected by `Verify.Registry`.
-}
results : List Core.RunResult
results =
    Runner.runUnit spec


spec : Spec.UnitSpec Input
spec =
    { fixtures =
        [ { input = { corrupt = False, offline = False, ocrPath = OcrPath.HostedPath }
          , name = "online-hosted-now"
          , probe = False
          }
        , { input = { corrupt = False, offline = False, ocrPath = byoFixturePath }
          , name = "online-byo-now"
          , probe = False
          }
        , { input = { corrupt = False, offline = True, ocrPath = OcrPath.HostedPath }
          , name = "offline-hosted-deferred"
          , probe = False
          }
        , { input = { corrupt = False, offline = True, ocrPath = byoFixturePath }
          , name = "offline-byo-deferred"
          , probe = False
          }
        , { input = { corrupt = False, offline = False, ocrPath = OcrPath.Unscannable }
          , name = "online-unscannable-manual"
          , probe = False
          }
        , { input = { corrupt = False, offline = True, ocrPath = OcrPath.Unscannable }
          , name = "offline-unscannable-manual"
          , probe = False
          }
        , -- Adversarial probe: offline + HostedPath but the corrupt surface
          -- claims "now". Invariant 1 must fire.
          { input = { corrupt = True, offline = True, ocrPath = OcrPath.HostedPath }
          , name = "probe-offline-fires-now"
          , probe = True
          }
        ]
    , invariants =
        [ { name = "offline never reaches now", check = offlineNeverNow }
        , { name = "unscannable is always manual", check = unscannableAlwaysManual }
        , { name = "online + scannable is now", check = onlineScannableIsNow }
        ]
    , name = "ScanDeferral"
    , surface = surface
    }


{-| A `ByoPath` fixture using a sample key. `fromInput` returns `Maybe` but we
know the non-empty string is safe, so we fall through to `HostedPath` (which
exercises the same `captureRoute` branch) if the key somehow fails to parse.
-}
byoFixturePath : OcrPath.OcrPath
byoFixturePath =
    case AnthropicKey.fromInput "sk-ant-verify-fixture" of
        Just key ->
            OcrPath.ByoPath key

        Nothing ->
            OcrPath.HostedPath


surface : Input -> Contract.Surface
surface input =
    let
        route : String
        route =
            if input.corrupt then
                -- Inject a regression: claim "now" regardless of offline state.
                "now"

            else
                routeKey (Scan.captureRoute { offline = input.offline } input.ocrPath)
    in
    [ ( "capture-route", route )
    , ( "offline", boolStr input.offline )
    , ( "ocr-path", ocrPathKey input.ocrPath )
    ]


routeKey : Scan.CaptureRoute -> String
routeKey route =
    case route of
        Scan.Deferred ->
            "deferred"

        Scan.Manual ->
            "manual"

        Scan.Now ->
            "now"


ocrPathKey : OcrPath.OcrPath -> String
ocrPathKey path =
    case path of
        OcrPath.ByoPath _ ->
            "byo"

        OcrPath.HostedPath ->
            "hosted"

        OcrPath.Unscannable ->
            "unscannable"


boolStr : Bool -> String
boolStr b =
    if b then
        "true"

    else
        "false"



-- INVARIANTS


{-| When offline is true and the path is scannable (BYO or Hosted), the
route must be `deferred` — never `now`. An offline OCR call would fail
immediately and burn the retry budget.
-}
offlineNeverNow : Input -> Contract.Surface -> Maybe String
offlineNeverNow input observed =
    if not input.offline then
        Nothing

    else
        case input.ocrPath of
            OcrPath.Unscannable ->
                Nothing

            OcrPath.ByoPath _ ->
                checkNotNow observed

            OcrPath.HostedPath ->
                checkNotNow observed


checkNotNow : Contract.Surface -> Maybe String
checkNotNow observed =
    case value "capture-route" observed of
        Just "now" ->
            Just "offline + scannable path produced 'now' — OCR would fire while offline"

        _ ->
            Nothing


{-| `Unscannable` always yields `manual`, regardless of connectivity.
There is no scannable path to defer to.
-}
unscannableAlwaysManual : Input -> Contract.Surface -> Maybe String
unscannableAlwaysManual input observed =
    case input.ocrPath of
        OcrPath.Unscannable ->
            case value "capture-route" observed of
                Just "manual" ->
                    Nothing

                other ->
                    Just ("Unscannable produced '" ++ Maybe.withDefault "nothing" other ++ "' instead of 'manual'")

        OcrPath.ByoPath _ ->
            Nothing

        OcrPath.HostedPath ->
            Nothing


{-| Online connectivity with a real scannable path must dispatch
immediately — deferral in the online case would silently drop the OCR call.
-}
onlineScannableIsNow : Input -> Contract.Surface -> Maybe String
onlineScannableIsNow input observed =
    if input.offline then
        Nothing

    else
        case input.ocrPath of
            OcrPath.Unscannable ->
                Nothing

            OcrPath.ByoPath _ ->
                checkIsNow observed

            OcrPath.HostedPath ->
                checkIsNow observed


checkIsNow : Contract.Surface -> Maybe String
checkIsNow observed =
    case value "capture-route" observed of
        Just "now" ->
            Nothing

        other ->
            Just ("online + scannable produced '" ++ Maybe.withDefault "nothing" other ++ "' instead of 'now'")


value : String -> Contract.Surface -> Maybe String
value key observed =
    observed
        |> List.filter (\( k, _ ) -> k == key)
        |> List.head
        |> Maybe.map Tuple.second
