module Data.PendingEntry exposing (AddPageMode(..), PendingEntry, PendingForm(..))

{-| In-progress expense form on the Add page.

`PendingEntry` is the raw user input: every text field is a `String`
(not a `Float` or a parsed date) because validation only happens on
submit. Pre-submit the form must be able to hold "in-progress" values
like `"12."` while the user is still typing.

`PendingForm` discriminates whether we're creating a new expense or
editing an existing one — `EditForm` carries the original `ExpenseId`
so the submit handler can write an `Amendment` instead of a new
`Expense`.

`AddPageMode` is what the Add page actually renders: new form, editing
form, or a skeleton while the underlying expense is still being fetched
from PouchDB. It's derived from the current route and the `PendingForm`
state by `Pages.Add.addPageMode`.

-}

import Data.Category exposing (Category)
import Data.ExpenseId exposing (ExpenseId)
import Data.Location exposing (LocationState)
import Data.PaymentMethod exposing (PaymentMethod)


{-| Raw user input for one in-progress expense.

`paymentMethod` is the one field that's a `Maybe` instead of a string —
the toggle UI emits `Cash`, `Credit`, or `Nothing`, so storing the
parsed value avoids a needless string round-trip.

-}
type alias PendingEntry =
    { amount : String
    , category : Category
    , date : String
    , locationState : LocationState
    , longNote : String
    , merchant : String
    , note : String
    , paymentMethod : Maybe PaymentMethod
    }


{-| Either a fresh form or an edit of a known expense.

The submit handler in `Main.update` branches on this constructor: a
`FreshForm` writes a new `Data.Expense.Expense`; an `EditForm` diffs
against the original and writes a `Data.Amendment.Amendment` for only
the changed fields.

-}
type PendingForm
    = EditForm ExpenseId PendingEntry
    | FreshForm PendingEntry


{-| What the Add page should render right now.

  - `AddPageNew` — fresh expense form, the default.
  - `AddPageEditing id` — editing this expense; the form is already
    hydrated with its current values.
  - `AddPageLoading id` — we know we want to edit this expense, but
    its document hasn't arrived from PouchDB yet; show a skeleton.

-}
type AddPageMode
    = AddPageEditing ExpenseId
    | AddPageLoading ExpenseId
    | AddPageNew
