module Data.ColorScheme exposing (ColorScheme(..), fromString, toString)

{-| User's preferred color scheme. Stored in localStorage as `color_scheme`.

`Auto` means "follow the system preference" — the JS layer watches
`prefers-color-scheme` and applies `html.dark` accordingly. `Dark` and
`Light` are explicit overrides that ignore the system setting.

-}


type ColorScheme
    = Auto
    | Dark
    | Light


{-| Wire-format label for localStorage / flags.
-}
toString : ColorScheme -> String
toString scheme =
    case scheme of
        Auto ->
            "auto"

        Dark ->
            "dark"

        Light ->
            "light"


{-| Parse the wire-format label from localStorage / flags.
-}
fromString : String -> Maybe ColorScheme
fromString s =
    case s of
        "auto" ->
            Just Auto

        "dark" ->
            Just Dark

        "light" ->
            Just Light

        _ ->
            Nothing
