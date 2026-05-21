module UI.FlockBadge exposing (view)

{-| Inline rust-tinted pill identifying a flock.

The visual language: a rounded-full capsule, `bg-rust-tint`
background, `text-rust-deep` text, a leading dot, the flock name in
uppercase mono. Used wherever a trip's flock identity surfaces — the
Trips list card, the active-trip hero, the Add/Scan context strip,
the Trip Picker drawer, and the Flocks settings cards.

One exposed function so the chrome stays identical everywhere it
appears; if a smaller variant becomes necessary (drawer chrome
constraints, dense lists), add a `viewSmall` rather than letting call
sites hand-roll the markup.

@docs view

-}

import Data.Flock exposing (Flock)
import Html exposing (Html)
import Html.Attributes


{-| Render a flock's pill.
-}
view : Flock -> Html msg
view flock =
    Html.span
        [ Html.Attributes.class "inline-flex items-center gap-1.5 bg-rust-tint text-rust-deep rounded-full px-2.5 py-0.5 text-xs font-mono uppercase tracking-widest" ]
        [ Html.span [ Html.Attributes.class "w-1.5 h-1.5 rounded-full bg-rust-deep" ] []
        , Html.text flock.name
        ]
