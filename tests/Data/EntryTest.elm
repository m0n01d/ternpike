module Data.EntryTest exposing (suite)

{-| Verify that amendments to the `address` field fold into the
`EffectiveEntry` via `Data.Entry.resolve` (which is the only public
entry point for amendment application).
-}

import Data.Amendment as Amendment
import Data.AmendmentId as AmendmentId
import Data.Category exposing (Category(..))
import Data.DateField as DateField
import Data.Entry as Entry
import Data.Expense exposing (Expense)
import Data.ExpenseId as ExpenseId
import Data.Money as Money
import Data.TripId as TripId
import Data.UserId as UserId
import Expect
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Data.Entry.resolve — address amendments"
        [ test "amendment with Just address overrides the original" <|
            \_ ->
                let
                    tripId =
                        TripId.fromString "trip::2024-05-21T14:30:45Z::zzzzzzzz"

                    expense =
                        baseExpense tripId
                            |> (\e -> { e | address = "Original Address" })

                    amend =
                        baseAmendment expense.id
                            |> (\a -> { a | address = Just "Updated Address" })
                in
                Entry.resolve [ expense ] [ amend ] [] tripId
                    |> List.map .address
                    |> Expect.equal [ "Updated Address" ]
        , test "amendment with Nothing address keeps the original" <|
            \_ ->
                let
                    tripId =
                        TripId.fromString "trip::2024-05-21T14:30:45Z::zzzzzzzz"

                    expense =
                        baseExpense tripId
                            |> (\e -> { e | address = "Original Address" })

                    amend =
                        baseAmendment expense.id
                in
                Entry.resolve [ expense ] [ amend ] [] tripId
                    |> List.map .address
                    |> Expect.equal [ "Original Address" ]
        ]


baseExpense : TripId.TripId -> Expense
baseExpense tripId =
    { address = ""
    , amount = Money.fromCents 1234
    , category = Food
    , createdAt = Time.millisToPosix 1700000000000
    , createdBy = UserId.fromString "alice@example.com"
    , date = DateField.fromIso "2024-05-21" |> Maybe.withDefault epoch
    , geoPoint = Nothing
    , id = ExpenseId.fromString "expense::2024-05-21T14:30:45Z::abcd1234"
    , longNote = ""
    , merchant = "Cafe Halibut"
    , note = "lunch"
    , paymentMethod = Nothing
    , tripId = tripId
    }


epoch : DateField.DateField
epoch =
    DateField.today Time.utc (Time.millisToPosix 0)


baseAmendment : ExpenseId.ExpenseId -> Amendment.Amendment
baseAmendment targetId =
    { address = Nothing
    , amount = Nothing
    , category = Nothing
    , createdAt = Time.millisToPosix 1700000100000
    , createdBy = UserId.fromString "alice@example.com"
    , date = Nothing
    , id = AmendmentId.fromString "amend::expense::2024-05-21T14:30:45Z::abcd1234::ef567890"
    , longNote = Nothing
    , merchant = Nothing
    , note = Nothing
    , paymentMethod = Nothing
    , targetId = targetId
    }
