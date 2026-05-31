module Data.Entry exposing (Band(..), EffectiveEntry, biggestDay, dailyTotals, medianAmount, primaryCurrency, resolve, spendBand, topCategory, totalsByCurrency, tripMedian, uniqueDates)

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

@docs Band, EffectiveEntry, biggestDay, dailyTotals, medianAmount, primaryCurrency, resolve, spendBand, topCategory, totalsByCurrency, tripMedian, uniqueDates

-}

import Data.Amendment exposing (Amendment)
import Data.Category as Category exposing (Category)
import Data.Currency as Currency exposing (Currency)
import Data.DateField as DateField exposing (DateField)
import Data.Expense exposing (Expense)
import Data.ExpenseId as ExpenseId exposing (ExpenseId)
import Data.FuelDetail exposing (FuelDetail)
import Data.GeoPoint exposing (GeoPoint)
import Data.Money as Money exposing (Money)
import Data.PaymentMethod exposing (PaymentMethod)
import Data.TripId exposing (TripId)
import Data.UserId exposing (UserId)
import Data.Void exposing (Void)
import Dict exposing (Dict)
import List.Extra
import Set
import Time


{-| An expense as the user sees it right now: the original fields with all
amendments applied. `isAmended` is `True` if at least one amendment was
folded in, so the UI can render an "edited" indicator.
-}
type alias EffectiveEntry =
    { address : String
    , amount : Money
    , category : Category
    , createdAt : Time.Posix
    , createdBy : UserId
    , currency : Currency
    , date : DateField
    , fuelDetail : Maybe FuelDetail
    , geoPoint : Maybe GeoPoint
    , id : ExpenseId
    , isAmended : Bool
    , longNote : String
    , merchant : String
    , note : String
    , paymentMethod : Maybe PaymentMethod
    , tripId : TripId
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
                        |> List.sortBy (Time.posixToMillis << .createdAt)
                        |> List.foldl (\a acc -> applyAmendment acc a) (toEffectiveEntry True expense)
    in
    expenses
        |> List.filter (\e -> e.tripId == activeTripId && not (Set.member (ExpenseId.toString e.id) voidedIds))
        |> List.map applyAmends
        |> List.sortWith (\a b -> DateField.compare a.date b.date)


toEffectiveEntry : Bool -> Expense -> EffectiveEntry
toEffectiveEntry isAmended e =
    { address = e.address
    , amount = e.amount
    , category = e.category
    , createdAt = e.createdAt
    , createdBy = e.createdBy
    , currency = e.currency
    , date = e.date
    , fuelDetail = e.fuelDetail
    , geoPoint = e.geoPoint
    , id = e.id
    , isAmended = isAmended
    , longNote = e.longNote
    , merchant = e.merchant
    , note = e.note
    , paymentMethod = e.paymentMethod
    , tripId = e.tripId
    }


applyAmendment : EffectiveEntry -> Amendment -> EffectiveEntry
applyAmendment e a =
    { address = Maybe.withDefault e.address a.address
    , amount = Maybe.withDefault e.amount a.amount
    , category = Maybe.withDefault e.category a.category
    , createdAt = e.createdAt
    , createdBy = e.createdBy
    , currency = Maybe.withDefault e.currency a.currency
    , date = Maybe.withDefault e.date a.date
    , fuelDetail =
        if a.fuelDetail /= Nothing then
            a.fuelDetail

        else
            e.fuelDetail
    , geoPoint = e.geoPoint
    , id = e.id
    , isAmended = True
    , longNote = Maybe.withDefault e.longNote a.longNote
    , merchant = Maybe.withDefault e.merchant a.merchant
    , note = Maybe.withDefault e.note a.note
    , paymentMethod =
        if a.paymentMethod /= Nothing then
            a.paymentMethod

        else
            e.paymentMethod
    , tripId = e.tripId
    }


{-| Total spend per currency, in a stable order (`USD` before `CAD`), with
only the currencies that actually appear in `entries`.

Ternpike never converts between currencies, so a mixed US/Canada trip can't
be summed into one number. This returns one subtotal per currency present —
a single-element list (the today behaviour) for a trip that's all one
currency, two entries for a trip that crossed the border. The Ledger and
Stats hero totals render each pair through `UI.MoneyView.amount`.

-}
totalsByCurrency : List EffectiveEntry -> List ( Currency, Money )
totalsByCurrency entries =
    Currency.all
        |> List.filterMap
            (\cur ->
                case List.filter (\e -> e.currency == cur) entries of
                    [] ->
                        Nothing

                    matching ->
                        Just ( cur, Money.sum (List.map .amount matching) )
            )


{-| The single currency to label a derived, scalar aggregate with — the
median, the daily burn, a category subtotal — where showing a per-currency
split would be noise. It's the most common currency across `entries`, with
`USD` winning ties and empty lists (so existing all-USD trips are unaffected).

Derived scalars over a genuinely mixed-currency trip are approximate by
nature (Ternpike never converts); this picks the currency the trip is
mostly in. The exact, non-lossy figure is the per-currency split from
`totalsByCurrency`, which the hero totals show alongside.

-}
primaryCurrency : List EffectiveEntry -> Currency
primaryCurrency entries =
    Currency.all
        |> List.map (\cur -> ( cur, List.length (List.filter (\e -> e.currency == cur) entries) ))
        |> List.sortBy (negate << Tuple.second)
        |> List.head
        |> Maybe.map Tuple.first
        |> Maybe.withDefault Currency.USD


uniqueDates : List EffectiveEntry -> List DateField
uniqueDates entries =
    entries
        |> List.map .date
        |> List.foldr
            (\d acc ->
                if List.any (\x -> DateField.compare x d == EQ) acc then
                    acc

                else
                    d :: acc
            )
            []
        |> List.sortWith DateField.compare
        |> List.reverse


medianAmount : List EffectiveEntry -> Money
medianAmount entries =
    let
        amounts =
            entries
                |> List.map .amount
                |> List.sortBy Money.toCents

        n =
            List.length amounts

        mid =
            n // 2
    in
    if n == 0 then
        Money.zero

    else if remainderBy 2 n == 1 then
        List.Extra.getAt mid amounts |> Maybe.withDefault Money.zero

    else
        let
            a =
                List.Extra.getAt (mid - 1) amounts |> Maybe.withDefault Money.zero

            b =
                List.Extra.getAt mid amounts |> Maybe.withDefault Money.zero
        in
        Money.fromCents ((Money.toCents a + Money.toCents b) // 2)


topCategory : List EffectiveEntry -> Maybe Category
topCategory entries =
    Category.all
        |> List.map
            (\cat ->
                ( cat
                , entries
                    |> List.filter (\e -> e.category == cat)
                    |> List.map .amount
                    |> Money.sum
                )
            )
        |> List.sortBy (negate << Money.toCents << Tuple.second)
        |> List.head
        |> Maybe.andThen
            (\( cat, total ) ->
                if Money.toCents total > 0 then
                    Just cat

                else
                    Nothing
            )


biggestDay : List EffectiveEntry -> Maybe ( DateField, Money )
biggestDay entries =
    uniqueDates entries
        |> List.map
            (\date ->
                ( date
                , entries
                    |> List.filter (\e -> DateField.compare e.date date == EQ)
                    |> List.map .amount
                    |> Money.sum
                )
            )
        |> List.sortBy (negate << Money.toCents << Tuple.second)
        |> List.head


{-| Sum each entry's amount into its date bucket. Keyed by the ISO date string.

Used by the Ledger's day-spending tint to compare each day against the trip's
median. Pairs naturally with `tripMedian` and `spendBand`.

-}
dailyTotals : List EffectiveEntry -> Dict String Money
dailyTotals entries =
    List.foldr
        (\e ->
            Dict.update (DateField.toIso e.date)
                (Just << Money.add e.amount << Maybe.withDefault Money.zero)
        )
        Dict.empty
        entries


{-| Median value across the daily-total dict.

This is the median of _days that had spending_. Empty-spend days inside a
trip's span don't pull the baseline down — the comparison is "vs. a normal
spending day on this trip."

-}
tripMedian : Dict String Money -> Money
tripMedian totals =
    let
        sorted =
            Dict.values totals
                |> List.sortBy Money.toCents

        n =
            List.length sorted

        mid =
            n // 2
    in
    if n == 0 then
        Money.zero

    else if remainderBy 2 n == 1 then
        List.Extra.getAt mid sorted |> Maybe.withDefault Money.zero

    else
        let
            a =
                List.Extra.getAt (mid - 1) sorted |> Maybe.withDefault Money.zero

            b =
                List.Extra.getAt mid sorted |> Maybe.withDefault Money.zero
        in
        Money.fromCents ((Money.toCents a + Money.toCents b) // 2)


{-| Five-step scale for how a day's total compares to the trip's median
daily spend. `Frugal` is well under, `Splurge` is well over, `Typical` is
right around the median.
-}
type Band
    = Above
    | Below
    | Frugal
    | Splurge
    | Typical


{-| Classify a day's total against the trip's median daily spend.

Edge cases — zero or negative median (single-day trips, no spend at all) —
fall back to `Typical` so the UI stays neutral.

    import Data.Money

    spendBand (Data.Money.fromCents 10000) (Data.Money.fromCents 3000)
    --> Frugal

    spendBand (Data.Money.fromCents 10000) (Data.Money.fromCents 7000)
    --> Below

    spendBand (Data.Money.fromCents 10000) (Data.Money.fromCents 10000)
    --> Typical

    spendBand (Data.Money.fromCents 10000) (Data.Money.fromCents 15000)
    --> Above

    spendBand (Data.Money.fromCents 10000) (Data.Money.fromCents 25000)
    --> Splurge

    spendBand Data.Money.zero (Data.Money.fromCents 5000)
    --> Typical

-}
spendBand : Money -> Money -> Band
spendBand median daily =
    let
        medianCents =
            Money.toCents median

        dailyCents =
            Money.toCents daily
    in
    if medianCents <= 0 then
        Typical

    else
        let
            ratio =
                toFloat dailyCents / toFloat medianCents
        in
        if ratio < 0.5 then
            Frugal

        else if ratio < 0.85 then
            Below

        else if ratio <= 1.15 then
            Typical

        else if ratio <= 1.75 then
            Above

        else
            Splurge
