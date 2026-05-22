module Data.Amendment exposing (Amendment, decoder, encoder)

{-| A patch applied to an existing `Expense`.

Editing an expense never mutates the original — it writes a new `Amendment`
document keyed `amend::<expenseId>::<8-char nonce>`. Each `Maybe` field on
the record means "this column was changed"; `Nothing` means "leave the
original value alone." `Data.Entry.resolve` folds amendments in `createdAt`
order to produce the user-facing `EffectiveEntry`.

Why this pattern:

  - Edit history is preserved automatically.
  - Sync conflicts are rare — two devices editing the same field still
    converge deterministically by `createdAt`.
  - We can reconstruct any past state of an expense.

The encoder omits any field that is `Nothing` so the stored document only
contains the actual changes. `createdBy` is required-with-fallback: writes
always include it (sourced from the signed-in user), and legacy documents
without the field decode to `UserId.unknown`.

Field types reflect the typed-primitives refactor (#94 — R3):

  - `amount : Maybe Data.Money.Money` — was `Maybe Float`. Encoder still
    emits `Float` dollars so the wire format is unchanged.
  - `createdAt : Time.Posix` — was `String`. Wire format remains the
    legacy ISO `"YYYY-MM-DDTHH:MM:SSZ"` string for backward compatibility.
  - `date : Maybe Data.DateField.DateField` — was `Maybe String`. Wire
    format remains ISO `"YYYY-MM-DD"`.
  - `id : Data.AmendmentId.AmendmentId` — was `String`.

-}

import Data.AmendmentId as AmendmentId exposing (AmendmentId)
import Data.Category as Category exposing (Category)
import Data.DateField as DateField exposing (DateField)
import Data.ExpenseId as ExpenseId exposing (ExpenseId)
import Data.Iso8601 as Iso8601
import Data.Money as Money exposing (Money)
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod)
import Data.UserId as UserId exposing (UserId)
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode
import Time


type alias Amendment =
    { amount : Maybe Money
    , category : Maybe Category
    , createdAt : Time.Posix
    , createdBy : UserId
    , date : Maybe DateField
    , id : AmendmentId
    , longNote : Maybe String
    , merchant : Maybe String
    , note : Maybe String
    , paymentMethod : Maybe PaymentMethod
    , targetId : ExpenseId
    }


encoder : Amendment -> Json.Encode.Value
encoder a =
    Json.Encode.object
        ([ ( "_id", AmendmentId.encode a.id )
         , ( "targetId", ExpenseId.encode a.targetId )
         , ( "createdAt", Json.Encode.string (Iso8601.fromPosix a.createdAt) )
         , ( "createdBy", UserId.encode a.createdBy )
         , ( "type", Json.Encode.string "amend" )
         ]
            ++ (case a.amount of
                    Just v ->
                        [ ( "amount", Money.encoder v ) ]

                    Nothing ->
                        []
               )
            ++ (case a.category of
                    Just v ->
                        [ ( "category", Json.Encode.string (Category.label v) ) ]

                    Nothing ->
                        []
               )
            ++ (case a.date of
                    Just v ->
                        [ ( "date", DateField.encoder v ) ]

                    Nothing ->
                        []
               )
            ++ (case a.longNote of
                    Just v ->
                        [ ( "longNote", Json.Encode.string v ) ]

                    Nothing ->
                        []
               )
            ++ (case a.merchant of
                    Just v ->
                        [ ( "merchant", Json.Encode.string v ) ]

                    Nothing ->
                        []
               )
            ++ (case a.note of
                    Just v ->
                        [ ( "note", Json.Encode.string v ) ]

                    Nothing ->
                        []
               )
            ++ (case a.paymentMethod of
                    Just v ->
                        [ ( "paymentMethod", Json.Encode.string (PaymentMethod.toString v) ) ]

                    Nothing ->
                        []
               )
        )


decoder : Json.Decode.Decoder Amendment
decoder =
    Json.Decode.succeed Amendment
        |> Pipeline.optional "amount"
            (Json.Decode.nullable Money.decoder)
            Nothing
        |> Pipeline.optional "category"
            (Json.Decode.nullable
                (Json.Decode.string
                    |> Json.Decode.andThen
                        (\s ->
                            case Category.fromStringMaybe s of
                                Just c ->
                                    Json.Decode.succeed c

                                Nothing ->
                                    Json.Decode.fail ("Unknown category: " ++ s)
                        )
                )
            )
            Nothing
        |> Pipeline.required "createdAt" createdAtDecoder
        |> Pipeline.optional "createdBy" UserId.decoder UserId.unknown
        |> Pipeline.optional "date" (Json.Decode.nullable DateField.decoder) Nothing
        |> Pipeline.required "_id" AmendmentId.decode
        |> Pipeline.optional "longNote" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "merchant" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "note" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "paymentMethod"
            (Json.Decode.nullable
                (Json.Decode.string
                    |> Json.Decode.andThen
                        (\s ->
                            case PaymentMethod.fromString s of
                                Just pm ->
                                    Json.Decode.succeed pm

                                Nothing ->
                                    Json.Decode.fail ("Unknown paymentMethod: " ++ s)
                        )
                )
            )
            Nothing
        |> Pipeline.required "targetId" ExpenseId.decode



-- INTERNAL


{-| Decode the legacy `"YYYY-MM-DDTHH:MM:SSZ"` createdAt string into a
`Time.Posix`. Failed parses fall back to the epoch via `Data.Iso8601.toPosix`,
matching the silent-default pattern used elsewhere for malformed legacy values.
-}
createdAtDecoder : Json.Decode.Decoder Time.Posix
createdAtDecoder =
    Json.Decode.string
        |> Json.Decode.map Iso8601.toPosix
