module Data.PendingEntry exposing
    ( AddPageMode(..)
    , ParsedEntry
    , PendingEntry
    , PendingForm(..)
    , defaultPendingEntry
    , formPending
    , mapForm
    , parseEntry
    , setLocation
    )

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

`ParsedEntry` is what `parseEntry` returns once the String-typed input
fields have been validated and parsed into their typed counterparts.
Submit handlers in `Main` consume this — instead of each call site
re-doing `String.toFloat ... |> Maybe.withDefault 0`, the parsing lives
in one place that can be tested in isolation.

-}

import Data.Category as Category exposing (Category)
import Data.Currency as Currency exposing (Currency)
import Data.DateField as DateField exposing (DateField)
import Data.ExpenseId exposing (ExpenseId)
import Data.FuelDetail exposing (FuelDetail)
import Data.FuelGrade as FuelGrade
import Data.Gallons as Gallons
import Data.GeoPoint exposing (GeoPoint)
import Data.Liters as Liters
import Data.Location exposing (LocationState(..))
import Data.Money as Money exposing (Money)
import Data.PaymentMethod exposing (PaymentMethod)
import Data.PricePerGallon as PricePerGallon
import Data.PricePerLiter as PricePerLiter
import Maybe.Extra


{-| Raw user input for one in-progress expense.

`paymentMethod` is the one field that's a `Maybe` instead of a string —
the toggle UI emits `Cash`, `Credit`, or `Nothing`, so storing the
parsed value avoids a needless string round-trip.

`fuelPricePerGallon` / `fuelGallons` / `fuelGrade` are the raw fuel
inputs shown only when `category == Fuel`. They stay `String` like the
other text fields and are parsed into a `Data.FuelDetail.FuelDetail` by
`parseEntry` — and only when the category is `Fuel`, so a price typed
and then re-categorised to `Food` is dropped rather than saved.

`currency` is the currency the amount was paid in. It also drives the
fuel volume unit: for a metric currency (anything but USD — see
`Data.Currency.usesGallons`) the `fuelGallons` / `fuelPricePerGallon`
strings are parsed as **liters** and **price-per-liter** respectively
(the inputs are relabeled in `Pages.Add`), so the same two raw fields
serve both unit systems.

-}
type alias PendingEntry =
    { address : String
    , amount : String
    , category : Category
    , currency : Currency
    , date : String
    , fuelGallons : String
    , fuelGrade : String
    , fuelPricePerGallon : String
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
  - `AddPageEditing` — editing an expense; the form is already
    hydrated with its current values.
  - `AddPageLoading` — we know we want to edit an expense, but
    its document hasn't arrived from PouchDB yet; show a skeleton.

-}
type AddPageMode
    = AddPageEditing
    | AddPageLoading
    | AddPageNew


{-| A `PendingEntry` whose String-typed input fields have been parsed
and validated. The submit handlers in `Main` consume this — branching
on the `Result (List String) ParsedEntry` returned by `parseEntry` —
so the inline `String.toFloat |> Maybe.withDefault 0` pattern lives in
exactly one place.

`geoPoint` is derived from `PendingEntry.locationState`: only
`LocationGot point _` contributes a point; every other state collapses
to `Nothing` (the user either skipped or hasn't resolved yet, both of
which mean "no location stamped").

-}
type alias ParsedEntry =
    { address : String
    , amount : Money
    , category : Category
    , currency : Currency
    , date : DateField
    , fuelDetail : Maybe FuelDetail
    , geoPoint : Maybe GeoPoint
    , longNote : String
    , merchant : String
    , note : String
    , paymentMethod : Maybe PaymentMethod
    }


{-| Parse a `PendingEntry` into a `ParsedEntry`, collecting every
validation failure into the `List String` error case. The two fields
that can fail today are `amount` (must be a non-empty, parseable dollar
string) and `date` (must be a non-empty ISO `YYYY-MM-DD`). Every other
field is already typed in `PendingEntry`, so it passes straight through.

This is intentionally minimal: the goal is to fail loudly on blank-
amount submit instead of silently saving `$0.00`. Heavier validation
(date inside trip range, non-negative amount caps, etc) is layered on
top of this in a future iteration.

-}
parseEntry : PendingEntry -> Result (List String) ParsedEntry
parseEntry pe =
    let
        amountResult : Result String Money
        amountResult =
            case Money.fromDollarString pe.amount of
                Just m ->
                    Ok m

                Nothing ->
                    Err "Enter a valid amount."

        dateResult : Result String DateField
        dateResult =
            case DateField.fromIso pe.date of
                Just d ->
                    Ok d

                Nothing ->
                    Err "Enter a valid date."

        geoPoint : Maybe GeoPoint
        geoPoint =
            case pe.locationState of
                LocationGot point _ ->
                    Just point

                _ ->
                    Nothing

        fuelDetail : Maybe FuelDetail
        fuelDetail =
            if pe.category == Category.Fuel then
                let
                    grade : Maybe FuelGrade.FuelGrade
                    grade =
                        if String.trim pe.fuelGrade == "" then
                            Nothing

                        else
                            Just (FuelGrade.fromString pe.fuelGrade)

                    -- The volume unit follows the currency: a metric fuel-up is
                    -- metered in liters at a price-per-liter, a US one in
                    -- gallons at a price-per-gallon. The same two raw input
                    -- strings (`fuelGallons` / `fuelPricePerGallon`) feed
                    -- whichever pair the currency selects.
                    detail : FuelDetail
                    detail =
                        if Currency.usesGallons pe.currency then
                            { gallons = Gallons.fromString pe.fuelGallons
                            , grade = grade
                            , liters = Nothing
                            , pricePerGallon = PricePerGallon.fromString pe.fuelPricePerGallon
                            , pricePerLiter = Nothing
                            }

                        else
                            { gallons = Nothing
                            , grade = grade
                            , liters = Liters.fromString pe.fuelGallons
                            , pricePerGallon = Nothing
                            , pricePerLiter = PricePerLiter.fromString pe.fuelPricePerGallon
                            }
                in
                if Data.FuelDetail.isEmpty detail then
                    Nothing

                else
                    Just detail

            else
                Nothing

        errs : List String
        errs =
            Maybe.Extra.values
                [ errorOf amountResult
                , errorOf dateResult
                ]
    in
    case ( amountResult, dateResult ) of
        ( Ok amount, Ok date ) ->
            Ok
                { address = pe.address
                , amount = amount
                , category = pe.category
                , currency = pe.currency
                , date = date
                , fuelDetail = fuelDetail
                , geoPoint = geoPoint
                , longNote = pe.longNote
                , merchant = pe.merchant
                , note = pe.note
                , paymentMethod = pe.paymentMethod
                }

        _ ->
            Err errs


errorOf : Result e a -> Maybe e
errorOf r =
    case r of
        Ok _ ->
            Nothing

        Err e ->
            Just e


{-| A blank `PendingEntry` for a brand-new expense on the given day.
Category defaults to `Fuel` and location to `LocationIdle`.
-}
defaultPendingEntry : DateField -> PendingEntry
defaultPendingEntry today =
    { address = ""
    , amount = ""
    , category = Category.Fuel
    , currency = Currency.usd
    , date = DateField.toIso today
    , fuelGallons = ""
    , fuelGrade = ""
    , fuelPricePerGallon = ""
    , locationState = LocationIdle
    , longNote = ""
    , merchant = ""
    , note = ""
    , paymentMethod = Nothing
    }


{-| Apply a transform to whichever `PendingEntry` the form is holding,
preserving the `EditForm` / `FreshForm` discriminator.
-}
mapForm : (PendingEntry -> PendingEntry) -> PendingForm -> PendingForm
mapForm f form =
    case form of
        EditForm id p ->
            EditForm id (f p)

        FreshForm p ->
            FreshForm (f p)


{-| Extract the underlying `PendingEntry` from a `PendingForm`.
-}
formPending : PendingForm -> PendingEntry
formPending form =
    case form of
        EditForm _ p ->
            p

        FreshForm p ->
            p


{-| Set the `locationState` on a `PendingEntry`.
-}
setLocation : LocationState -> PendingEntry -> PendingEntry
setLocation ls p =
    { p | locationState = ls }
