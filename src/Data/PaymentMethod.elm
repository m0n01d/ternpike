module Data.PaymentMethod exposing (PaymentMethod(..), fromString, label, toString)


type PaymentMethod
    = Cash
    | Credit


fromString : String -> Maybe PaymentMethod
fromString s =
    case String.toLower s of
        "cash"   -> Just Cash
        "credit" -> Just Credit
        _        -> Nothing


toString : PaymentMethod -> String
toString pm =
    case pm of
        Cash   -> "cash"
        Credit -> "credit"


label : PaymentMethod -> String
label pm =
    case pm of
        Cash   -> "Cash"
        Credit -> "Credit"
