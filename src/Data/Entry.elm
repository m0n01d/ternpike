module Data.Entry exposing
    ( EffectiveEntry
    , biggestDay
    , medianAmount
    , resolve
    , topCategory
    , uniqueDates
    )

import Data.Amendment as Amendment exposing (Amendment)
import Data.Category as Category exposing (Category)
import Data.Expense as Expense exposing (Expense)
import Data.ExpenseId as ExpenseId exposing (ExpenseId)
import Data.TripId as TripId exposing (TripId)
import Data.Void as Void exposing (Void)
import Dict
import Set


type alias EffectiveEntry =
    { amount    : Float
    , category  : Category
    , createdAt : String
    , date      : String
    , id        : ExpenseId
    , isAmended : Bool
    , lat       : Maybe Float
    , lon       : Maybe Float
    , longNote  : String
    , merchant  : String
    , note      : String
    , tripId    : TripId
    }


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
                    let
                        latest =
                            List.sortBy .createdAt amends
                                |> List.reverse
                                |> List.head
                    in
                    Maybe.map (applyAmendment expense) latest
                        |> Maybe.withDefault (toEffectiveEntry False expense)
    in
    expenses
        |> List.filter (\e -> e.tripId == activeTripId && not (Set.member (ExpenseId.toString e.id) voidedIds))
        |> List.map applyAmends
        |> List.sortBy .date


toEffectiveEntry : Bool -> Expense -> EffectiveEntry
toEffectiveEntry isAmended e =
    { amount    = e.amount
    , category  = e.category
    , createdAt = e.createdAt
    , date      = e.date
    , id        = e.id
    , isAmended = isAmended
    , lat       = e.lat
    , lon       = e.lon
    , longNote  = e.longNote
    , merchant  = e.merchant
    , note      = e.note
    , tripId    = e.tripId
    }


applyAmendment : Expense -> Amendment -> EffectiveEntry
applyAmendment e a =
    { amount    = Maybe.withDefault e.amount a.amount
    , category  = Maybe.withDefault e.category a.category
    , createdAt = e.createdAt
    , date      = Maybe.withDefault e.date a.date
    , id        = e.id
    , isAmended = True
    , lat       = e.lat
    , lon       = e.lon
    , longNote  = Maybe.withDefault e.longNote a.longNote
    , merchant  = Maybe.withDefault e.merchant a.merchant
    , note      = Maybe.withDefault e.note a.note
    , tripId    = e.tripId
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
