module UI.Icons exposing
    ( blazeTrail
    , camera
    , cautionDiamond
    , chart
    , chevronRight
    , close
    , collapse
    , copy
    , download
    , expand
    , flag
    , fuelPump
    , journal
    , kebab
    , map
    , mileShield
    , move
    , pencil
    , pin
    , plus
    , settings
    , share
    , trash
    )

import Svg
import Svg.Attributes


common : String -> List (Svg.Attribute msg)
common classes =
    [ Svg.Attributes.class classes
    , Svg.Attributes.viewBox "0 0 24 24"
    , Svg.Attributes.fill "none"
    , Svg.Attributes.stroke "currentColor"
    , Svg.Attributes.strokeWidth "1.5"
    , Svg.Attributes.strokeLinecap "round"
    , Svg.Attributes.strokeLinejoin "round"
    ]


camera : String -> Svg.Svg msg
camera classes =
    Svg.svg (common classes)
        [ Svg.path
            [ Svg.Attributes.d "M3 8.5 A1.5 1.5 0 0 1 4.5 7 H8 L9.5 5 H14.5 L16 7 H19.5 A1.5 1.5 0 0 1 21 8.5 V18 A1.5 1.5 0 0 1 19.5 19.5 H4.5 A1.5 1.5 0 0 1 3 18 Z" ]
            []
        , Svg.circle
            [ Svg.Attributes.cx "12"
            , Svg.Attributes.cy "13"
            , Svg.Attributes.r "3.5"
            ]
            []
        ]


chart : String -> Svg.Svg msg
chart classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M5 19 V14" ] []
        , Svg.path [ Svg.Attributes.d "M12 19 V10" ] []
        , Svg.path [ Svg.Attributes.d "M19 19 V5" ] []
        , Svg.path [ Svg.Attributes.d "M3 21 H21" ] []
        ]


chevronRight : String -> Svg.Svg msg
chevronRight classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M9 6 L15 12 L9 18" ] [] ]


close : String -> Svg.Svg msg
close classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M6 6 L18 18" ] []
        , Svg.path [ Svg.Attributes.d "M18 6 L6 18" ] []
        ]


{-| Four corner brackets pointing inward — toggles the Ledger map back
to its compact 260-px size from the expanded view.
-}
collapse : String -> Svg.Svg msg
collapse classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M9 4 V9 H4" ] []
        , Svg.path [ Svg.Attributes.d "M15 4 V9 H20" ] []
        , Svg.path [ Svg.Attributes.d "M9 20 V15 H4" ] []
        , Svg.path [ Svg.Attributes.d "M15 20 V15 H20" ] []
        ]


copy : String -> Svg.Svg msg
copy classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M9 9 H19 A1 1 0 0 1 20 10 V20 A1 1 0 0 1 19 21 H9 A1 1 0 0 1 8 20 V10 A1 1 0 0 1 9 9 Z" ] []
        , Svg.path [ Svg.Attributes.d "M5 15 H4 A1 1 0 0 1 3 14 V4 A1 1 0 0 1 4 3 H14 A1 1 0 0 1 15 4 V5" ] []
        ]


{-| Arrow pointing down into a tray — download / export action.
-}
download : String -> Svg.Svg msg
download classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M12 3 L12 15" ] []
        , Svg.path [ Svg.Attributes.d "M8 11 L12 15 L16 11" ] []
        , Svg.path [ Svg.Attributes.d "M3 18 L3 21 L21 21 L21 18" ] []
        ]


{-| Four corner brackets pointing outward — toggles the Ledger map to
its expanded ~70vh size that replaces the ledger list.
-}
expand : String -> Svg.Svg msg
expand classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M4 9 V4 H9" ] []
        , Svg.path [ Svg.Attributes.d "M20 9 V4 H15" ] []
        , Svg.path [ Svg.Attributes.d "M4 15 V20 H9" ] []
        , Svg.path [ Svg.Attributes.d "M20 15 V20 H15" ] []
        ]


{-| A trail-marker flag on a post — the header affordance for The Milepost
achievements screen (#409).
-}
flag : String -> Svg.Svg msg
flag classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M6 21 V4" ] []
        , Svg.path [ Svg.Attributes.d "M6 4 H17 L14 8 L17 12 H6" ] []
        ]


{-| A trail blaze — a tall rounded vertical rectangle, mimicking the painted
rectangular blazes used to mark hiking trails. Used as the TrailDiscipline
family icon in The Milepost (#418).
-}
blazeTrail : String -> Svg.Svg msg
blazeTrail classes =
    Svg.svg
        [ Svg.Attributes.class classes
        , Svg.Attributes.viewBox "0 0 24 24"
        , Svg.Attributes.fill "currentColor"
        , Svg.Attributes.stroke "none"
        ]
        [ Svg.rect
            [ Svg.Attributes.x "7"
            , Svg.Attributes.y "3"
            , Svg.Attributes.width "10"
            , Svg.Attributes.height "18"
            , Svg.Attributes.rx "3"
            , Svg.Attributes.ry "3"
            ]
            []
        ]


{-| A mile-marker shield — the classic rounded-top pentagon road marker shape.
Used as the MileMarkers family icon in The Milepost (#418).
-}
mileShield : String -> Svg.Svg msg
mileShield classes =
    Svg.svg
        [ Svg.Attributes.class classes
        , Svg.Attributes.viewBox "0 0 24 24"
        , Svg.Attributes.fill "currentColor"
        , Svg.Attributes.stroke "none"
        ]
        [ Svg.path
            [ Svg.Attributes.d "M12 2 L20 7 L20 19 A1 1 0 0 1 19 20 L5 20 A1 1 0 0 1 4 19 L4 7 Z" ]
            []
        ]


{-| A fuel pump — a simple pump silhouette with a nozzle arm. Used as the
Odometer family icon in The Milepost (#418).
-}
fuelPump : String -> Svg.Svg msg
fuelPump classes =
    Svg.svg (common classes)
        [ Svg.rect
            [ Svg.Attributes.x "3"
            , Svg.Attributes.y "2"
            , Svg.Attributes.width "12"
            , Svg.Attributes.height "20"
            , Svg.Attributes.rx "1"
            , Svg.Attributes.fill "none"
            , Svg.Attributes.stroke "currentColor"
            ]
            []
        , Svg.rect
            [ Svg.Attributes.x "6"
            , Svg.Attributes.y "6"
            , Svg.Attributes.width "6"
            , Svg.Attributes.height "5"
            , Svg.Attributes.rx "0.5"
            , Svg.Attributes.fill "currentColor"
            , Svg.Attributes.stroke "none"
            ]
            []
        , Svg.path [ Svg.Attributes.d "M15 5 L19 5 A1 1 0 0 1 20 6 L20 11 A1 1 0 0 1 19 12 L17 12 L17 16 A1 1 0 0 0 18 17 L19 17" ] []
        ]


{-| A caution diamond — a rotated square with an exclamation mark. Used as
the CautionSigns family icon in The Milepost (#418).
-}
cautionDiamond : String -> Svg.Svg msg
cautionDiamond classes =
    Svg.svg (common classes)
        [ Svg.path
            [ Svg.Attributes.d "M12 2 L22 12 L12 22 L2 12 Z" ]
            []
        , Svg.path [ Svg.Attributes.d "M12 8 L12 13" ] []
        , Svg.circle
            [ Svg.Attributes.cx "12"
            , Svg.Attributes.cy "16.5"
            , Svg.Attributes.r "0.6"
            , Svg.Attributes.fill "currentColor"
            ]
            []
        ]


journal : String -> Svg.Svg msg
journal classes =
    Svg.svg (common classes)
        [ Svg.path
            [ Svg.Attributes.d "M6 3 H19 A1 1 0 0 1 20 4 V20 A1 1 0 0 1 19 21 H6 A2 2 0 0 1 4 19 V5 A2 2 0 0 1 6 3 Z" ]
            []
        , Svg.path [ Svg.Attributes.d "M8 3 V21" ] []
        , Svg.path [ Svg.Attributes.d "M11 8 H17" ] []
        , Svg.path [ Svg.Attributes.d "M11 12 H17" ] []
        ]


kebab : String -> Svg.Svg msg
kebab classes =
    Svg.svg (common classes)
        [ Svg.circle
            [ Svg.Attributes.cx "12"
            , Svg.Attributes.cy "5"
            , Svg.Attributes.r "1.4"
            , Svg.Attributes.fill "currentColor"
            , Svg.Attributes.stroke "none"
            ]
            []
        , Svg.circle
            [ Svg.Attributes.cx "12"
            , Svg.Attributes.cy "12"
            , Svg.Attributes.r "1.4"
            , Svg.Attributes.fill "currentColor"
            , Svg.Attributes.stroke "none"
            ]
            []
        , Svg.circle
            [ Svg.Attributes.cx "12"
            , Svg.Attributes.cy "19"
            , Svg.Attributes.r "1.4"
            , Svg.Attributes.fill "currentColor"
            , Svg.Attributes.stroke "none"
            ]
            []
        ]


map : String -> Svg.Svg msg
map classes =
    Svg.svg (common classes)
        [ Svg.path
            [ Svg.Attributes.d "M3 6 L9 4 L15 6 L21 4 V18 L15 20 L9 18 L3 20 Z" ]
            []
        , Svg.path [ Svg.Attributes.d "M9 4 V18" ] []
        , Svg.path [ Svg.Attributes.d "M15 6 V20" ] []
        , Svg.circle
            [ Svg.Attributes.cx "12"
            , Svg.Attributes.cy "11"
            , Svg.Attributes.r "0.8"
            , Svg.Attributes.fill "currentColor"
            ]
            []
        ]


move : String -> Svg.Svg msg
move classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M4 12 H20" ] []
        , Svg.path [ Svg.Attributes.d "M15 7 L20 12 L15 17" ] []
        , Svg.path [ Svg.Attributes.d "M4 6 V18" ] []
        ]


pencil : String -> Svg.Svg msg
pencil classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M4 20 L8 19 L20 7 L17 4 L5 16 Z" ] []
        , Svg.path [ Svg.Attributes.d "M14 7 L17 10" ] []
        , Svg.path [ Svg.Attributes.d "M5 16 L8 19" ] []
        ]


share : String -> Svg.Svg msg
share classes =
    Svg.svg (common classes)
        [ Svg.circle [ Svg.Attributes.cx "18", Svg.Attributes.cy "5", Svg.Attributes.r "3" ] []
        , Svg.circle [ Svg.Attributes.cx "6", Svg.Attributes.cy "12", Svg.Attributes.r "3" ] []
        , Svg.circle [ Svg.Attributes.cx "18", Svg.Attributes.cy "19", Svg.Attributes.r "3" ] []
        , Svg.path [ Svg.Attributes.d "M8.6 13.5 L15.4 17.5" ] []
        , Svg.path [ Svg.Attributes.d "M15.4 6.5 L8.6 10.5" ] []
        ]


pin : String -> Svg.Svg msg
pin classes =
    Svg.svg (common classes)
        [ Svg.path
            [ Svg.Attributes.d "M12 2 C8.5 2 6 4.5 6 8 C6 12.5 12 21 12 21 C12 21 18 12.5 18 8 C18 4.5 15.5 2 12 2 Z" ]
            []
        , Svg.circle
            [ Svg.Attributes.cx "12"
            , Svg.Attributes.cy "8"
            , Svg.Attributes.r "2"
            ]
            []
        ]


plus : String -> Svg.Svg msg
plus classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M12 5 V19" ] []
        , Svg.path [ Svg.Attributes.d "M5 12 H19" ] []
        ]


settings : String -> Svg.Svg msg
settings classes =
    Svg.svg (common classes)
        [ Svg.path
            [ Svg.Attributes.d "M12 3 L18.5 6.5 V13.5 L12 17 L5.5 13.5 V6.5 Z" ]
            []
        , Svg.circle
            [ Svg.Attributes.cx "12"
            , Svg.Attributes.cy "10"
            , Svg.Attributes.r "2.5"
            ]
            []
        ]


trash : String -> Svg.Svg msg
trash classes =
    Svg.svg (common classes)
        [ Svg.path [ Svg.Attributes.d "M4 7 H20" ] []
        , Svg.path [ Svg.Attributes.d "M9 7 V5 A1 1 0 0 1 10 4 H14 A1 1 0 0 1 15 5 V7" ] []
        , Svg.path [ Svg.Attributes.d "M6 7 L7 20 A1 1 0 0 0 8 21 H16 A1 1 0 0 0 17 20 L18 7" ] []
        , Svg.path [ Svg.Attributes.d "M10 11 V17" ] []
        , Svg.path [ Svg.Attributes.d "M14 11 V17" ] []
        ]
