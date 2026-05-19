module Data.Category exposing
    ( Category(..)
    , all
    , color
    , fromString
    , fromStringMaybe
    , icon
    , label
    )


type Category
    = Activities
    | Camp
    | Ferry
    | Food
    | Fuel
    | Gear
    | Lodging
    | Medical
    | Misc
    | Shopping
    | Transport


all : List Category
all =
    [ Fuel, Food, Camp, Lodging, Ferry, Activities, Shopping, Gear, Transport, Medical, Misc ]


color : Category -> String
color cat =
    case cat of
        Activities -> "#f0b040"
        Camp       -> "#4090e0"
        Ferry      -> "#c060e0"
        Food       -> "#3ecf6a"
        Fuel       -> "#e8a020"
        Gear       -> "#e85030"
        Lodging    -> "#40c0b0"
        Medical    -> "#ff6060"
        Misc       -> "#7a8a80"
        Shopping   -> "#e060a0"
        Transport  -> "#a0a0e0"


fromString : String -> Category
fromString s =
    case s of
        "activities" -> Activities
        "camp"       -> Camp
        "ferry"      -> Ferry
        "food"       -> Food
        "fuel"       -> Fuel
        "gear"       -> Gear
        "lodging"    -> Lodging
        "medical"    -> Medical
        "shopping"   -> Shopping
        "transport"  -> Transport
        _            -> Misc


fromStringMaybe : String -> Maybe Category
fromStringMaybe s =
    case s of
        "activities" -> Just Activities
        "camp"       -> Just Camp
        "ferry"      -> Just Ferry
        "food"       -> Just Food
        "fuel"       -> Just Fuel
        "gear"       -> Just Gear
        "lodging"    -> Just Lodging
        "medical"    -> Just Medical
        "misc"       -> Just Misc
        "shopping"   -> Just Shopping
        "transport"  -> Just Transport
        _            -> Nothing


icon : Category -> String
icon cat =
    case cat of
        Activities -> "🎯"
        Camp       -> "⛺"
        Ferry      -> "⛴"
        Food       -> "🍔"
        Fuel       -> "⛽"
        Gear       -> "🔧"
        Lodging    -> "🏨"
        Medical    -> "💊"
        Misc       -> "📦"
        Shopping   -> "🛍"
        Transport  -> "🚌"


label : Category -> String
label cat =
    case cat of
        Activities -> "activities"
        Camp       -> "camp"
        Ferry      -> "ferry"
        Food       -> "food"
        Fuel       -> "fuel"
        Gear       -> "gear"
        Lodging    -> "lodging"
        Medical    -> "medical"
        Misc       -> "misc"
        Shopping   -> "shopping"
        Transport  -> "transport"
