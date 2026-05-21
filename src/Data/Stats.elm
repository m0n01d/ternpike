module Data.Stats exposing (StatsMode(..))

{-| Loading-vs-ready discriminator for the Stats page.

The Stats page renders aggregates (totals, daily burn, top categories,
charts) over the resolved entries for one trip. Those entries come from
folding `Data.Entry.resolve` over the cached expenses, amendments, and
voids — but the cache is empty until that trip's `GetTripExpenses`
round-trip completes.

`Pages.Stats.statsMode` looks up the current route's trip in
`AuthState.tripLoaded`; if it's not there yet, the page renders skeleton
placeholders, otherwise the resolved aggregates (or an empty-state
mascot if the loaded trip has no entries).

-}

import Data.Entry exposing (EffectiveEntry)


{-| Either "still waiting for the trip's bulk fetch" or "resolved
entries are ready to render."
-}
type StatsMode
    = StatsLoading
    | StatsReady (List EffectiveEntry)
