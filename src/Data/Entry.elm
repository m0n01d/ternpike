module Data.Entry exposing
    ( EffectiveEntry
    , biggestDay
    , medianAmount
    , resolve
    , topCategory
    , uniqueDates
    )

{-| The "effective" (post-amendment, non-voided) view of expenses.

# What "effective" means

A raw `Expense` is the document originally saved to PouchDB. After it's
saved, two things can happen to it:

  - **Amendments** (`Data.Amendment`) — partial edits that point at the
    expense via `targetId`. Each amendment carries only the fields that
    changed.
  - **Voids** (`Data.Void`) — tombstones that soft-delete an expense.

An `EffectiveEntry` is what the UI actually renders: the original expense
with every amendment folded in (newest wins per field), or nothing at all
if the expense has been voided. `isAmended : Bool` lets the view show an
"edited" badge.

`resolve` is the function that turns raw documents into effective entries.

# How resolve looks up amendments and voids

The naive shape would be `List.filter` on amendments by `targetId` for
every expense — O(n × m). Instead, `resolve` builds two cheap indexes
once per call:

  - `voidedIds : Set String` — ID → tombstoned? O(log n) `Set.member`.
  - `amendsByTarget : Dict String (List Amendment)` — expense ID → its
    amendments. O(log n) `Dict.get` per expense.

Expenses are then filtered by `tripId` (a small linear pass — only one
trip's expenses are in memory at a time, thanks to lazy loading) and each
surviving expense is run through `applyAmends`, which sorts amendments by
`createdAt` and folds them left-to-right.

@docs EffectiveEntry, resolve, biggestDay, medianAmount, topCategory, uniqueDates

-}

import Data.Amendment as Amendment exposing (Amendment)
import Data.Category as Category exposing (Category)
import Data.Expense as Expense exposing (Expense)
import Data.ExpenseId as ExpenseId exposing (ExpenseId)
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod)
import Data.TripId as TripId exposing (TripId)
import Data.Void as Void exposing (Void)
import Dict
import Set


{-| An expense as the user sees it right now: the original fields with all
amendments applied. `isAmended` is `True` if at least one amendment was
folded in, so the UI can render an "edited" indicator.
-}
type alias EffectiveEntry =
    { amount        : Float
    , category      : Category
    , createdAt     : String
    , date          : String
    , id            : ExpenseId
    , isAmended     : Bool
    , lat           : Maybe Float
    , lon           : Maybe Float
    , longNote      : String
    , merchant      : String
    , note          : String
    , paymentMethod : Maybe PaymentMethod
    , tripId        : TripId
    }


{-| Build the sorted list of effective entries for one trip.

Callers pass the full list of every cached amendment and void — this
function builds its own per-call indexes (`voidedIds`, `amendsByTarget`),
so passing extra docs that don't belong to this trip is harmless and
cheap. Expenses, however, should already be scoped to the trip (the
caller does a `Dict.get tripId as_.expenses` first); the `activeTripId`
argument is a final safety filter and the trip handed to `findEffective`
for single-expense resolution.
-}
resolve : List Expense -> List Amendment -> List Void -> TripId -> List EffectiveEntry
resolve expenses amendments voids activeTripId =
    let
        voidedIds =
            List.map .targetId voids
                |> List.foldr Set.insert Set.empty

        amendsByTarget =
            List.foldr
                (\a acc ->
                    Dict.update (ExpenseId.toString a.targetId)
                        (Just << Maybe.withDefault [ a ] << Maybe.map (\xs -> a :: xs))
                        acc
                )
                Dict.empty
                amendments

        applyAmends expense =
            case Dict.get (ExpenseId.toString expense.id) amendsByTarget of
                Nothing ->
                    toEffectiveEntry False expense

                Just amends ->
                    amends
                        |> List.sortBy .createdAt
                        |> List.foldl (\a acc -> applyAmendment acc a) (toEffectiveEntry True expense)
    in
    expenses
        |> List.filter (\e -> e.tripId == activeTripId && not (Set.member (ExpenseId.toString e.id) voidedIds))
        |> List.map applyAmends
        |> List.sortBy .date


toEffectiveEntry : Bool -> Expense -> EffectiveEntry
toEffectiveEntry isAmended e =
    { amount        = e.amount
    , category      = e.category
    , createdAt     = e.createdAt
    , date          = e.date
    , id            = e.id
    , isAmended     = isAmended
    , lat           = e.lat
    , lon           = e.lon
    , longNote      = e.longNote
    , merchant      = e.merchant
    , note          = e.note
    , paymentMethod = e.paymentMethod
    , tripId        = e.tripId
    }


applyAmendment : EffectiveEntry -> Amendment -> EffectiveEntry
applyAmendment e a =
    { amount        = Maybe.withDefault e.amount a.amount
    , category      = Maybe.withDefault e.category a.category
    , createdAt     = e.createdAt
    , date          = Maybe.withDefault e.date a.date
    , id            = e.id
    , isAmended     = True
    , lat           = e.lat
    , lon           = e.lon
    , longNote      = Maybe.withDefault e.longNote a.longNote
    , merchant      = Maybe.withDefault e.merchant a.merchant
    , note          = Maybe.withDefault e.note a.note
    , paymentMethod = if a.paymentMethod /= Nothing then a.paymentMethod else e.paymentMethod
    , tripId        = e.tripId
    }


uniqueDates : List EffectiveEntry -> List String
uniqueDates entries =
    entries
        |> List.map .date
        |> List.foldr
            (\d acc ->
                if List.member d acc then
                    acc

                else
                    d :: acc
            )
            []
        |> List.sort
        |> List.reverse


medianAmount : List EffectiveEntry -> Float
medianAmount entries =
    let
        amounts =
            List.sort (List.map .amount entries)

        n =
            List.length amounts

        mid =
            n // 2
    in
    if n == 0 then
        0

    else if remainderBy 2 n == 1 then
        amounts |> List.drop mid |> List.head |> Maybe.withDefault 0

    else
        let
            a =
                amounts |> List.drop (mid - 1) |> List.head |> Maybe.withDefault 0

            b =
                amounts |> List.drop mid |> List.head |> Maybe.withDefault 0
        in
        (a + b) / 2


topCategory : List EffectiveEntry -> Maybe Category
topCategory entries =
    Category.all
        |> List.map
            (\cat ->
                ( cat
                , entries
                    |> List.filter (\e -> e.category == cat)
                    |> List.map .amount
                    |> List.sum
                )
            )
        |> List.sortBy (negate << Tuple.second)
        |> List.head
        |> Maybe.andThen
            (\( cat, total ) ->
                if total > 0 then
                    Just cat

                else
                    Nothing
            )


biggestDay : List EffectiveEntry -> Maybe ( String, Float )
biggestDay entries =
    uniqueDates entries
        |> List.map
            (\date ->
                ( date
                , entries
                    |> List.filter (\e -> e.date == date)
                    |> List.map .amount
                    |> List.sum
                )
            )
        |> List.sortBy (negate << Tuple.second)
        |> List.head
