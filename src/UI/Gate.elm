module UI.Gate exposing (paidOnly, requiresPaid)

{-| Uniform feature-gating helpers.

The codebase has three subscription tiers (`Tern` free, `Osprey` paid
recurring, `Trailblazer` paid one-time — see `Data.Tier`). Most call
sites only need the binary "paid vs free" answer; `paidOnly` and
`requiresPaid` collapse the three-tier type for that case while leaving
the full `case` available for tier-specific UI (badges, billing screen).

Server endpoints back every paid feature with their own tier re-check.
Client gating is UX, not security — never trust it as the only gate.

-}

import Data.Tier as Tier exposing (Tier)
import Html exposing (Html)


{-| Render `paidView` if the user is on any paid tier (Osprey or
Trailblazer), otherwise render `upgradePrompt`. Use for inline UI
elements that should swap rather than hide — Tern users should know
what paid unlocks.

    -- intentionally no `-->` example: returns Html, not pure data.



-}
paidOnly : Tier -> { paidView : Html msg, upgradePrompt : Html msg } -> Html msg
paidOnly tier views =
    if Tier.isPaid tier then
        views.paidView

    else
        views.upgradePrompt


{-| Predicate for guarding handlers / Cmds. Alias for `Data.Tier.isPaid`
that reads more naturally at call sites — `requiresPaid as_.tier` reads
better than `Tier.isPaid as_.tier` when you mean "this thing requires paid".
Returns `False` for `Tern`, `True` for `Osprey` and `Trailblazer`.
See `Data.Tier.isPaid` for inline examples.
-}
requiresPaid : Tier -> Bool
requiresPaid =
    Tier.isPaid
