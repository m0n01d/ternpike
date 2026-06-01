module Data.EntryTest exposing (suite)

{-| Verify that amendments to the `address` field fold into the
`EffectiveEntry` via `Data.Entry.resolve` (which is the only public
entry point for amendment application).
-}

import Data.Amendment as Amendment
import Data.AmendmentId as AmendmentId
import Data.Category exposing (Category(..))
import Data.Currency
import Data.DateField as DateField
import Data.Entry as Entry
import Data.ExchangeRate as ExchangeRate
import Data.Expense exposing (Expense)
import Data.ExpenseId as ExpenseId
import Data.Money as Money
import Data.TripId as TripId
import Data.UserId as UserId
import Dict
import Expect
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Data.Entry"
        [ describe "resolve — address amendments"
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
        , describe "resolve — currency amendments"
            [ test "amendment with Just currency overrides the original (USD → CAD)" <|
                \_ ->
                    let
                        tripId =
                            TripId.fromString "trip::2024-05-21T14:30:45Z::zzzzzzzz"

                        expense =
                            baseExpense tripId

                        amend =
                            baseAmendment expense.id
                                |> (\a -> { a | currency = Just (Data.Currency.fromLabel "cad") })
                    in
                    Entry.resolve [ expense ] [ amend ] [] tripId
                        |> List.map .currency
                        |> Expect.equal [ Data.Currency.fromLabel "cad" ]
            , test "amendment with Nothing currency keeps the original" <|
                \_ ->
                    let
                        tripId =
                            TripId.fromString "trip::2024-05-21T14:30:45Z::zzzzzzzz"

                        expense =
                            baseExpense tripId
                    in
                    Entry.resolve [ expense ] [ baseAmendment expense.id ] [] tripId
                        |> List.map .currency
                        |> Expect.equal [ Data.Currency.usd ]
            ]
        , describe "totalsByCurrency"
            [ test "an all-USD trip yields a single USD subtotal (today's behaviour)" <|
                \_ ->
                    entriesWith [ ( Data.Currency.usd, 1000 ), ( Data.Currency.usd, 500 ) ]
                        |> Entry.totalsByCurrency
                        |> List.map (Tuple.mapSecond Money.toCents)
                        |> Expect.equal [ ( Data.Currency.usd, 1500 ) ]
            , test "a mixed trip yields per-currency subtotals, USD first" <|
                \_ ->
                    entriesWith [ ( Data.Currency.usd, 1000 ), ( Data.Currency.fromLabel "cad", 2000 ), ( Data.Currency.usd, 500 ) ]
                        |> Entry.totalsByCurrency
                        |> List.map (Tuple.mapSecond Money.toCents)
                        |> Expect.equal [ ( Data.Currency.usd, 1500 ), ( Data.Currency.fromLabel "cad", 2000 ) ]
            , test "an empty list yields no subtotals" <|
                \_ ->
                    Entry.totalsByCurrency []
                        |> Expect.equal []
            ]
        , describe "primaryCurrency"
            [ test "picks the most common currency" <|
                \_ ->
                    entriesWith [ ( Data.Currency.usd, 1 ), ( Data.Currency.fromLabel "cad", 1 ), ( Data.Currency.usd, 1 ) ]
                        |> Entry.primaryCurrency
                        |> Expect.equal Data.Currency.usd
            , test "a CAD-only trip is primarily CAD" <|
                \_ ->
                    entriesWith [ ( Data.Currency.fromLabel "cad", 1 ), ( Data.Currency.fromLabel "cad", 1 ) ]
                        |> Entry.primaryCurrency
                        |> Expect.equal (Data.Currency.fromLabel "cad")
            , test "ties resolve to USD" <|
                \_ ->
                    entriesWith [ ( Data.Currency.usd, 1 ), ( Data.Currency.fromLabel "cad", 1 ) ]
                        |> Entry.primaryCurrency
                        |> Expect.equal Data.Currency.usd
            , test "an empty list defaults to USD" <|
                \_ ->
                    Entry.primaryCurrency []
                        |> Expect.equal Data.Currency.usd
            ]
        , describe "estimatedHomeTotal"
            [ test "all-USD trip estimates to its own sum, nothing missing" <|
                \_ ->
                    entriesWith [ ( Data.Currency.usd, 1000 ), ( Data.Currency.usd, 500 ) ]
                        |> Entry.estimatedHomeTotal (ExchangeRate.estimate estimateTable)
                        |> (\r -> ( Money.toCents r.total, r.missing ))
                        |> Expect.equal ( 1500, [] )
            , test "mixed trip with rates folds each subtotal into USD" <|
                \_ ->
                    -- USD 10.00 + CAD 100.00 @ 0.73 = 10.00 + 73.00 = 83.00
                    entriesWith [ ( Data.Currency.usd, 1000 ), ( Data.Currency.fromLabel "cad", 10000 ) ]
                        |> Entry.estimatedHomeTotal (ExchangeRate.estimate estimateTable)
                        |> (\r -> ( Money.toCents r.total, r.missing ))
                        |> Expect.equal ( 8300, [] )
            , test "a currency with no rate is summed-around and reported as missing" <|
                \_ ->
                    entriesWith [ ( Data.Currency.usd, 1000 ), ( Data.Currency.fromLabel "mxn", 5000 ) ]
                        |> Entry.estimatedHomeTotal (ExchangeRate.estimate estimateTable)
                        |> (\r -> ( Money.toCents r.total, List.map Data.Currency.code r.missing ))
                        |> Expect.equal ( 1000, [ "MXN" ] )
            ]
        ]


estimateTable : ExchangeRate.RateTable
estimateTable =
    { asOf = Nothing, rates = Dict.fromList [ ( "cad", 0.73 ) ] }


{-| Build effective entries (via the real `resolve`) with the given
`(currency, cents)` pairs, each on a unique id so none are deduped.
-}
entriesWith : List ( Data.Currency.Currency, Int ) -> List Entry.EffectiveEntry
entriesWith pairs =
    let
        tripId =
            TripId.fromString "trip::2024-05-21T14:30:45Z::zzzzzzzz"

        expenses =
            List.indexedMap
                (\i ( currency, cents ) ->
                    { tripId = tripId
                    , address = ""
                    , amount = Money.fromCents cents
                    , category = Food
                    , createdAt = Time.millisToPosix (1700000000000 + i)
                    , createdBy = UserId.fromString "alice@example.com"
                    , currency = currency
                    , date = DateField.fromIso "2024-05-21" |> Maybe.withDefault epoch
                    , fuelDetail = Nothing
                    , geoPoint = Nothing
                    , id = ExpenseId.fromString ("expense::2024-05-21T14:30:45Z::id" ++ String.fromInt i)
                    , longNote = ""
                    , merchant = ""
                    , note = ""
                    , paymentMethod = Nothing
                    }
                )
                pairs
    in
    Entry.resolve expenses [] [] tripId


baseExpense : TripId.TripId -> Expense
baseExpense tripId =
    { address = ""
    , amount = Money.fromCents 1234
    , category = Food
    , createdAt = Time.millisToPosix 1700000000000
    , createdBy = UserId.fromString "alice@example.com"
    , currency = Data.Currency.usd
    , date = DateField.fromIso "2024-05-21" |> Maybe.withDefault epoch
    , fuelDetail = Nothing
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
    , currency = Nothing
    , date = Nothing
    , fuelDetail = Nothing
    , id = AmendmentId.fromString "amend::expense::2024-05-21T14:30:45Z::abcd1234::ef567890"
    , longNote = Nothing
    , merchant = Nothing
    , note = Nothing
    , paymentMethod = Nothing
    , targetId = targetId
    }
