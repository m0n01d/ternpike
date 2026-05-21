module Data.Category exposing
    ( Category(..)
    , all
    , color
    , fromString
    , fromStringMaybe
    , icon
    , label
    )

{-| Closed enum of the 12 expense categories.

`label` is the canonical serialization (lowercase, matches the on-disk
`category` field and the OCR prompt). `icon` and `color` are presentation.
`all` is the canonical display order — alphabetical input order on the
type, but the `all` list reorders for UX.

Two parsers:

  - `fromString` always succeeds, falling back to `Misc` for unknown
    inputs. Used by `Expense.decoder` so a stored receipt with a
    category we've since removed still loads.
  - `fromStringMaybe` returns `Nothing` for unknown inputs. Used by
    `Amendment.decoder` (where `Nothing` legitimately means "category
    wasn't changed") so we don't conflate "unknown" with "unchanged."

Examples:

    label Fuel
    --> "fuel"

    fromString "fuel"
    --> Fuel

    fromString "unknown"
    --> Misc

    fromStringMaybe "fuel"
    --> Just Fuel

    fromStringMaybe "unknown"
    --> Nothing

-}


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
    | Parks
    | Shopping
    | Transport


all : List Category
all =
    [ Fuel, Food, Camp, Lodging, Ferry, Activities, Shopping, Gear, Transport, Medical, Parks, Misc ]


color : Category -> String
color cat =
    case cat of
        Activities ->
            "#f0b040"

        Camp ->
            "#4090e0"

        Ferry ->
            "#c060e0"

        Food ->
            "#3ecf6a"

        Fuel ->
            "#e8a020"

        Gear ->
            "#e85030"

        Lodging ->
            "#40c0b0"

        Medical ->
            "#ff6060"

        Misc ->
            "#7a8a80"

        Parks ->
            "#5a9a50"

        Shopping ->
            "#e060a0"

        Transport ->
            "#a0a0e0"


fromString : String -> Category
fromString s =
    case s of
        "activities" ->
            Activities

        "camp" ->
            Camp

        "ferry" ->
            Ferry

        "food" ->
            Food

        "fuel" ->
            Fuel

        "gear" ->
            Gear

        "lodging" ->
            Lodging

        "medical" ->
            Medical

        "shopping" ->
            Shopping

        "transport" ->
            Transport

        "parks" ->
            Parks

        _ ->
            Misc


fromStringMaybe : String -> Maybe Category
fromStringMaybe s =
    case s of
        "activities" ->
            Just Activities

        "camp" ->
            Just Camp

        "ferry" ->
            Just Ferry

        "food" ->
            Just Food

        "fuel" ->
            Just Fuel

        "gear" ->
            Just Gear

        "lodging" ->
            Just Lodging

        "medical" ->
            Just Medical

        "misc" ->
            Just Misc

        "parks" ->
            Just Parks

        "shopping" ->
            Just Shopping

        "transport" ->
            Just Transport

        _ ->
            Nothing


icon : Category -> String
icon cat =
    case cat of
        Activities ->
            "🎯"

        Camp ->
            "⛺"

        Ferry ->
            "⛴"

        Food ->
            "🍔"

        Fuel ->
            "⛽"

        Gear ->
            "🔧"

        Lodging ->
            "🏨"

        Medical ->
            "💊"

        Misc ->
            "📦"

        Parks ->
            "🏞"

        Shopping ->
            "🛍"

        Transport ->
            "🚌"


label : Category -> String
label cat =
    case cat of
        Activities ->
            "activities"

        Camp ->
            "camp"

        Ferry ->
            "ferry"

        Food ->
            "food"

        Fuel ->
            "fuel"

        Gear ->
            "gear"

        Lodging ->
            "lodging"

        Medical ->
            "medical"

        Misc ->
            "misc"

        Parks ->
            "parks"

        Shopping ->
            "shopping"

        Transport ->
            "transport"
