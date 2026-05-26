module Data.OcrPath exposing (OcrPath(..), resolve)

{-| The three OCR-credential states for a given scan context.

Replaces the `String + Bool` pattern (`anthropicKey == ""`, `Tier.isPaid`) that
was scattered across every OCR call site. `resolve` is the single decision point;
consumers pattern-match on the result so the compiler enforces all three branches.

-}

import Data.AnthropicKey exposing (AnthropicKey)
import Data.Tier exposing (Tier)


{-| How an OCR call will be authenticated.

  - `ByoPath key` — the user has provided their own Anthropic key; calls go
    browser → Anthropic directly using `key`.
  - `HostedPath` — the user's tier is paid and they have no BYO key; calls
    go through the Ternpike-hosted proxy at `api.ternpike.com/scan`. The proxy
    key never touches the browser.
  - `Unscannable` — the tier is free and there is no BYO key; scanning is not
    available without either upgrading or supplying a key.

-}
type OcrPath
    = ByoPath AnthropicKey
    | HostedPath
    | Unscannable


{-| Derive the OCR path from the user's key and tier.

BYO key takes priority over tier: a paid user who supplies their own key gets
`ByoPath`, not `HostedPath`. This matches CLAUDE.md — "BYO keys are available
on all tiers; paid is purely additive."

  - `(Nothing, Tern)` → `Unscannable`
  - `(Nothing, Osprey)` → `HostedPath`
  - `(Nothing, Trailblazer)` → `HostedPath`
  - `(Just key, any)` → `ByoPath key`

-}
resolve : Maybe AnthropicKey -> Tier -> OcrPath
resolve maybeKey tier =
    case ( maybeKey, Data.Tier.isPaid tier ) of
        ( Just key, _ ) ->
            ByoPath key

        ( Nothing, True ) ->
            HostedPath

        ( Nothing, False ) ->
            Unscannable
