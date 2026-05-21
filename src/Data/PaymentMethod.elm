module Data.PaymentMethod exposing (PaymentMethod(..), fromString, label, toString)

{-| How the expense was paid for. `toString` is the lowercase wire form;
`label` is the display form ("Cash" / "Credit"). Optional on `Expense` —
older receipts predate this field.

Examples:

    toString Cash
    --> "cash"

    label Cash
    --> "Cash"

    fromString "cash"
    --> Just Cash

    fromString "unknown"
    --> Nothing

-}


type PaymentMethod
    = Cash
    | Credit


fromString : String -> Maybe PaymentMethod
fromString s =
    case String.toLower s of
        "cash" ->
            Just Cash

        "credit" ->
            Just Credit

        _ ->
            Nothing


toString : PaymentMethod -> String
toString pm =
    case pm of
        Cash ->
            "cash"

        Credit ->
            "credit"


label : PaymentMethod -> String
label pm =
    case pm of
        Cash ->
            "Cash"

        Credit ->
            "Credit"
