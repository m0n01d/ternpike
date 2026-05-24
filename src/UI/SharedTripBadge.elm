module UI.SharedTripBadge exposing (view)

{-| Inline rust-tinted pill identifying a shared trip.

The visual language: a rounded-full capsule, `bg-rust-tint`
background, `text-rust-deep` text, a leading dot, the shared trip name in
uppercase mono. Used wherever a trip's shared trip identity surfaces — the
Trips list card, the active-trip hero, the Add/Scan context strip,
the Trip Picker drawer, and the SharedTrips settings cards.

One exposed function so the chrome stays identical everywhere it
appears; if a smaller variant becomes necessary (drawer chrome
constraints, dense lists), add a `viewSmall` rather than letting call
sites hand-roll the markup.

@docs view

-}

import Data.SharedTrip exposing (SharedTrip)
import Html exposing (Html)
import Html.Attributes


{-| Render a shared trip's pill.
-}
view : SharedTrip -> Html msg
view sharedTrip =
    Html.span
        [ Html.Attributes.class "inline-flex items-center gap-1.5 bg-rust-tint text-rust-deep rounded-full px-2.5 py-0.5 text-xs font-mono uppercase tracking-widest" ]
        [ Html.span [ Html.Attributes.class "w-1.5 h-1.5 rounded-full bg-rust-deep" ] []
        , Html.text sharedTrip.name
        ]
