module Data.Expense exposing (Expense, decoder, encoder, findLikelyDuplicate, snapshotWith)

{-| One expense as originally saved.

`Expense` is **immutable after creation**. Edits never overwrite an expense —
they produce an `Amendment` instead (see `Data.Amendment`). Deletes produce a
`Void`. The user-facing view is built by `Data.Entry.resolve`, which folds
amendments onto the raw expense to produce an `EffectiveEntry`.

The encoder adds `"type": "expense"` so the live-changes feed in `pouch.js`
can route incoming docs to the right decoder. `_id` is the PouchDB document
key and comes from `ExpenseId.encode`.

Unknown categories decode to `Misc` rather than failing — receipts older than
the current category list still load. `createdBy` is decoded with a
`UserId.unknown` fallback so documents written before the field existed still
load cleanly.

Field types reflect the typed-primitives refactor (#92):

  - `amount : Data.Money.Money` — was `Float`. Encoder still emits `Float`
    dollars so the wire format is unchanged.
  - `createdAt : Time.Posix` — was `String`. Wire format remains the ISO
    `"YYYY-MM-DDTHH:MM:SSZ"` string for backward compatibility.
  - `date : Data.DateField.DateField` — was `String`. Wire format remains
    ISO `"YYYY-MM-DD"`.
  - `geoPoint : Maybe Data.GeoPoint.GeoPoint` — replaces the parallel
    `lat : Maybe Float, lon : Maybe Float` pair. Encoder still emits the
    sibling `"lat"` / `"lon"` fields when present.

-}

import Data.Category as Category exposing (Category)
import Data.DateField as DateField exposing (DateField)
import Data.ExpenseId as ExpenseId exposing (ExpenseId)
import Data.GeoPoint as GeoPoint exposing (GeoPoint)
import Data.Iso8601 as Iso8601
import Data.Money as Money exposing (Money)
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod)
import Data.TripId as TripId exposing (TripId)
import Data.UserId as UserId exposing (UserId)
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode
import Time


type alias Expense =
    { address : String
    , amount : Money
    , category : Category
    , createdAt : Time.Posix
    , createdBy : UserId
    , date : DateField
    , geoPoint : Maybe GeoPoint
    , id : ExpenseId
    , longNote : String
    , merchant : String
    , note : String
    , paymentMethod : Maybe PaymentMethod
    , tripId : TripId
    }


encoder : Expense -> Json.Encode.Value
encoder e =
    Json.Encode.object
        ([ ( "_id", ExpenseId.encode e.id )
         , ( "address", Json.Encode.string e.address )
         , ( "amount", Money.encoder e.amount )
         , ( "category", Json.Encode.string (Category.label e.category) )
         , ( "createdAt", Json.Encode.string (Iso8601.fromPosix e.createdAt) )
         , ( "createdBy", UserId.encode e.createdBy )
         , ( "date", DateField.encoder e.date )
         , ( "longNote", Json.Encode.string e.longNote )
         , ( "merchant", Json.Encode.string e.merchant )
         , ( "note", Json.Encode.string e.note )
         , ( "tripId", TripId.encode e.tripId )
         , ( "type", Json.Encode.string "expense" )
         ]
            ++ (case e.geoPoint of
                    Just point ->
                        [ ( "lat", Json.Encode.float (GeoPoint.latDegrees point) )
                        , ( "lon", Json.Encode.float (GeoPoint.lonDegrees point) )
                        ]

                    Nothing ->
                        []
               )
            ++ (case e.paymentMethod of
                    Just v ->
                        [ ( "paymentMethod", Json.Encode.string (PaymentMethod.toString v) ) ]

                    Nothing ->
                        []
               )
        )


{-| Copy every user-visible field from a source expense onto a fresh
identity. The building block for "duplicate" (new id, same trip) and
"move" (new id, different trip).

The record-update form ensures the invariant "new identity ⇒ new
(id, createdAt) ⇒ same date/amount/category/merchant/note/longNote/
paymentMethod/geoPoint" stays stated in one place.

-}
snapshotWith : { id : ExpenseId, createdAt : Time.Posix, tripId : TripId } -> Expense -> Expense
snapshotWith fields source =
    { source
        | id = fields.id
        , createdAt = fields.createdAt
        , tripId = fields.tripId
    }


{-| Find the most recently created expense in `existing` that looks like a
likely duplicate of `candidate`. Returns `Nothing` when the candidate's
merchant is empty or no match exists.

Match criteria: same merchant (case-insensitive, trimmed), amount within
$1 (100 cents), same date. Caller is responsible for passing only expenses
from the relevant trip — this helper does not filter by trip.

    import Data.Category
    import Data.DateField
    import Data.ExpenseId
    import Data.Money
    import Data.TripId
    import Data.UserId
    import Time

    epoch : Data.DateField.DateField
    epoch =
        Data.DateField.today Time.utc (Time.millisToPosix 0)

    date24 : Data.DateField.DateField
    date24 =
        Data.DateField.fromIsoOr epoch "2024-05-24"

    date25 : Data.DateField.DateField
    date25 =
        Data.DateField.fromIsoOr epoch "2024-05-25"

    baseExpense : Expense
    baseExpense =
        { address = ""
        , amount = Data.Money.fromCents 4520
        , category = Data.Category.Misc
        , createdAt = Time.millisToPosix 1000
        , createdBy = Data.UserId.unknown
        , date = date24
        , geoPoint = Nothing
        , id = Data.ExpenseId.fromString "expense::2024-05-24T00:00:00Z::aaa"
        , longNote = ""
        , merchant = "Trattoria Vecchia"
        , note = ""
        , paymentMethod = Nothing
        , tripId = Data.TripId.fromString "trip::2024-05-24T00:00:00Z::bbb"
        }

    -- Exact match: same merchant, amount, date — returns the expense
    Maybe.map .merchant (findLikelyDuplicate baseExpense [ baseExpense ])
    --> Just "Trattoria Vecchia"

    -- Different merchant returns Nothing
    findLikelyDuplicate { baseExpense | merchant = "Other Place" } [ baseExpense ]
    --> Nothing

    -- Empty merchant always returns Nothing (check is skipped entirely)
    findLikelyDuplicate { baseExpense | merchant = "" } [ baseExpense ]
    --> Nothing

    -- Amount more than $1 (101 cents) different returns Nothing
    findLikelyDuplicate { baseExpense | amount = Data.Money.fromCents 4621 } [ baseExpense ]
    --> Nothing

    -- Amount within $1 (exactly 100 cents) still matches
    Maybe.map .merchant (findLikelyDuplicate { baseExpense | amount = Data.Money.fromCents 4620 } [ baseExpense ])
    --> Just "Trattoria Vecchia"

    -- Different date returns Nothing
    findLikelyDuplicate { baseExpense | date = date25 } [ baseExpense ]
    --> Nothing

    -- Returns the most recently created when multiple expenses match
    Maybe.map (Time.posixToMillis << .createdAt)
        (findLikelyDuplicate baseExpense
            [ { baseExpense | createdAt = Time.millisToPosix 500 }
            , { baseExpense | createdAt = Time.millisToPosix 2000 }
            ]
        )
    --> Just 2000

-}
findLikelyDuplicate : Expense -> List Expense -> Maybe Expense
findLikelyDuplicate candidate existing =
    let
        normaliseMerchant : String -> String
        normaliseMerchant m =
            String.toLower (String.trim m)

        candidateMerchant : String
        candidateMerchant =
            normaliseMerchant candidate.merchant
    in
    if String.isEmpty candidateMerchant then
        Nothing

    else
        existing
            |> List.filter
                (\e ->
                    normaliseMerchant e.merchant
                        == candidateMerchant
                        && Money.absDiff candidate.amount e.amount
                        <= 100
                        && DateField.compare candidate.date e.date
                        == EQ
                )
            |> List.sortBy (\e -> -(Time.posixToMillis e.createdAt))
            |> List.head


decoder : Json.Decode.Decoder Expense
decoder =
    Json.Decode.succeed Expense
        |> Pipeline.optional "address" Json.Decode.string ""
        |> Pipeline.required "amount" Money.decoder
        |> Pipeline.required "category"
            (Json.Decode.string
                |> Json.Decode.map
                    (\s ->
                        case Category.fromStringMaybe s of
                            Just c ->
                                c

                            Nothing ->
                                Category.Misc
                    )
            )
        |> Pipeline.required "createdAt" createdAtDecoder
        |> Pipeline.optional "createdBy" UserId.decoder UserId.unknown
        |> Pipeline.required "date" DateField.decoder
        |> Pipeline.custom GeoPoint.decoderPair
        |> Pipeline.required "_id" ExpenseId.decode
        |> Pipeline.optional "longNote" Json.Decode.string ""
        |> Pipeline.required "merchant" Json.Decode.string
        |> Pipeline.required "note" Json.Decode.string
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
        |> Pipeline.required "tripId" TripId.decode



-- INTERNAL


{-| Decode the legacy `"YYYY-MM-DDTHH:MM:SSZ"` createdAt string into a
`Time.Posix`. Failed parses fall back to the epoch (`Time.millisToPosix 0`),
matching the silent-default pattern used by `Data.DateField.decoder` for
malformed legacy dates.
-}
createdAtDecoder : Json.Decode.Decoder Time.Posix
createdAtDecoder =
    Json.Decode.string
        |> Json.Decode.map Iso8601.toPosix
