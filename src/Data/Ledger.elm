module Data.Ledger exposing (LedgerMode(..))

{-| Loading-vs-ready discriminator for the Ledger page.

The Ledger renders the resolved entries for one trip. Those entries
come from folding `Data.Entry.resolve` over the cached expenses,
amendments, and voids — but the cache is empty until that trip's
`GetTripExpenses` round-trip completes.

`Pages.Ledger.ledgerMode` looks up the current route's trip in
`AuthState.tripLoaded`; if it's not there yet, the page renders a
skeleton, otherwise the resolved list.

-}

import Data.Entry exposing (EffectiveEntry)


{-| Either "still waiting for the trip's bulk fetch" or "resolved
entries are ready to render."
-}
type LedgerMode
    = LedgerLoading
    | LedgerReady (List EffectiveEntry)
