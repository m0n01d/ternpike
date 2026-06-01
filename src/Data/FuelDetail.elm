module Data.FuelDetail exposing
    ( FuelDetail
    , decoder
    , encoder
    , isEmpty
    )

{-| The fuel-specific detail captured for a gas purchase: unit price,
volume, and grade. Bundled into one optional record so the data only
exists in fuel-shaped form — there is no loose `pricePerGallon` field
floating on every expense (see `Data.Expense.fuelDetail : Maybe
FuelDetail`). `Data.Category` stays a plain comparable enum, so grouping
expenses by category (Stats, Milepost badges) is unaffected.

Each sub-field is independently optional because OCR reads them
best-effort: a smudged pump receipt might give the price but not the
grade.

Wire format (under the `"fuel"` key of an expense, flat siblings in the
OCR JSON): each present sub-field is a JSON `Float` (price/gallons) or
string (grade); absent ones are omitted or `null`. `decoder` reads the
three sub-fields from whatever object it's applied to, so the same
decoder serves both the nested expense doc and the flat OCR response.

-}

import Data.FuelGrade as FuelGrade exposing (FuelGrade)
import Data.Gallons as Gallons exposing (Gallons)
import Data.Liters as Liters exposing (Liters)
import Data.PricePerGallon as PricePerGallon exposing (PricePerGallon)
import Data.PricePerLiter as PricePerLiter exposing (PricePerLiter)
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode


{-| Fuel detail: any subset of unit price, volume, and grade.

A fuel-up is recorded in **either** imperial (`gallons` + `pricePerGallon`)
**or** metric (`liters` + `pricePerLiter`) units, never both — which pair is
filled is driven by the expense's `Data.Currency` (CAD ⇒ liters). The metric
fields were added additively (#liters track): legacy and US docs decode with
`liters` / `pricePerLiter` as `Nothing`, so the wire format stays compatible.

-}
type alias FuelDetail =
    { gallons : Maybe Gallons
    , grade : Maybe FuelGrade
    , liters : Maybe Liters
    , pricePerGallon : Maybe PricePerGallon
    , pricePerLiter : Maybe PricePerLiter
    }


{-| True when no sub-field is set — the signal that there's no fuel
detail worth persisting, so callers store `Nothing` rather than an
all-empty record.
-}
isEmpty : FuelDetail -> Bool
isEmpty detail =
    (detail.gallons == Nothing)
        && (detail.grade == Nothing)
        && (detail.liters == Nothing)
        && (detail.pricePerGallon == Nothing)
        && (detail.pricePerLiter == Nothing)


{-| Decode the fuel sub-fields from the surrounding object. Each is
optional and lenient: a missing field, JSON `null`, or a value of the
wrong type collapses to `Nothing` on that sub-field rather than failing
the whole receipt.
-}
decoder : Json.Decode.Decoder FuelDetail
decoder =
    Json.Decode.succeed FuelDetail
        |> Pipeline.optional "gallons" (lenient Gallons.decoder) Nothing
        |> Pipeline.optional "grade" (lenient FuelGrade.decoder) Nothing
        |> Pipeline.optional "liters" (lenient Liters.decoder) Nothing
        |> Pipeline.optional "pricePerGallon" (lenient PricePerGallon.decoder) Nothing
        |> Pipeline.optional "pricePerLiter" (lenient PricePerLiter.decoder) Nothing


{-| Encode the present sub-fields as an object. Absent sub-fields are
written as JSON `null`, which `decoder` reads back as `Nothing`.
-}
encoder : FuelDetail -> Json.Encode.Value
encoder detail =
    Json.Encode.object
        [ ( "gallons", maybe Gallons.encoder detail.gallons )
        , ( "grade", maybe FuelGrade.encoder detail.grade )
        , ( "liters", maybe Liters.encoder detail.liters )
        , ( "pricePerGallon", maybe PricePerGallon.encoder detail.pricePerGallon )
        , ( "pricePerLiter", maybe PricePerLiter.encoder detail.pricePerLiter )
        ]


{-| Wrap a strict decoder so JSON `null`, a wrong type, or any decode
failure on this one sub-field collapses to `Nothing`.
-}
lenient : Json.Decode.Decoder a -> Json.Decode.Decoder (Maybe a)
lenient strict =
    Json.Decode.oneOf
        [ Json.Decode.null Nothing
        , Json.Decode.map Just strict
        , Json.Decode.succeed Nothing
        ]


maybe : (a -> Json.Encode.Value) -> Maybe a -> Json.Encode.Value
maybe enc m =
    case m of
        Just a ->
            enc a

        Nothing ->
            Json.Encode.null
