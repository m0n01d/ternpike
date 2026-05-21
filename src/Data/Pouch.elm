module Data.Pouch exposing
    ( DocChange(..)
    , ExpenseBundle
    , PouchInbound(..)
    , PouchOutbound(..)
    , TripBundle
    )

{-| Typed protocol for the `pouchOut` / `pouchIn` ports.

JS side: `src/pouch.js`. Tagged JSON travels both directions. Encoding
of outbound commands and decoding of inbound events lives in
`Main.elm` (`encodePouchOut`, `pouchInDecoder`). This module owns just
the type shapes so every variant is a single-line check in the decoder
and a single match arm in the update.

Request → response mapping:

  - `GetAllTrips` → `TripsFetched (Dict String Trip)`
  - `GetTripExpenses tripId` → `TripExpensesFetched tripId TripBundle`
  - `GetExpense expenseId` → `ExpenseFetched expenseId ExpenseBundle`
  - `SaveAmend` / `SaveExpense` / `SaveTrip` / `SaveVoid` → fire-and-
    forget; the live-changes feed delivers the saved doc back as a
    `DbChange`, which is how we confirm the write.

`DbChange` exists separately from `PouchInbound` because the JS side
emits a single `"DbChange"` tag for every document type and discriminates
by the document's `type` field. Decoding peels that one layer.

`TripBundle` and `ExpenseBundle` are the multi-document responses that
bulk fetches return — pre-grouped on the JS side so a single inbound
event delivers all the related documents at once.

-}

import Data.Amendment exposing (Amendment)
import Data.Expense exposing (Expense)
import Data.ExpenseId exposing (ExpenseId)
import Data.Sync exposing (SyncState)
import Data.Trip exposing (Trip)
import Data.TripId exposing (TripId)
import Data.Void exposing (Void)
import Dict exposing (Dict)
import Json.Decode


{-| Commands sent through the `pouchOut` port. `Save*` constructors carry
the already-encoded JSON to keep this module free of encoder
dependencies on the inner records.
-}
type PouchOutbound
    = GetAllTrips
    | GetExpense ExpenseId
    | GetTripExpenses TripId
    | SaveAmend Json.Decode.Value
    | SaveExpense Json.Decode.Value
    | SaveTrip Json.Decode.Value
    | SaveVoid Json.Decode.Value


{-| Events received through the `pouchIn` port.

  - `AuthExpiredMsg` — sync's CouchDB request was 401'd; drop to
    `GuestModel SessionExpired`.
  - `DbChange` — one document just appeared (local write or sync pull).
  - `DbDeleted` — a `_deleted` revision arrived; rare, because we
    soft-delete via `Void` docs in normal flow.
  - `DbError` — non-fatal error message to surface as a toast/banner.
  - `ExpenseFetched` / `TripExpensesFetched` / `TripsFetched` —
    responses to the corresponding outbound queries.
  - `SyncStateMsg` — sync health update.

-}
type PouchInbound
    = AuthExpiredMsg
    | DbChange DocChange
    | DbDeleted String
    | DbError String
    | ExpenseFetched ExpenseId ExpenseBundle
    | SyncStateMsg SyncState
    | TripExpensesFetched TripId TripBundle
    | TripsFetched (Dict String Trip)


{-| One document arriving via the live-changes feed, discriminated by
the doc's `type` field on the JS side.
-}
type DocChange
    = AmendChanged Amendment
    | ExpenseChanged Expense
    | TripChanged Trip
    | VoidChanged Void


{-| Bulk response to `GetTripExpenses`. Carries every document that
participates in resolving the trip's effective entries: the raw
expenses, all amendments (folded in by `Data.Entry.resolve`), and any
voids (which mark expenses as deleted).
-}
type alias TripBundle =
    { amendments : Dict String Amendment
    , expenses : Dict String Expense
    , voids : Dict String Void
    }


{-| Bulk response to `GetExpense`. Both `expense` and `void` are
nullable because the document may not exist (deleted/unknown id) or may
exist only as a void tombstone.
-}
type alias ExpenseBundle =
    { amendments : Dict String Amendment
    , expense : Maybe Expense
    , void : Maybe Void
    }
