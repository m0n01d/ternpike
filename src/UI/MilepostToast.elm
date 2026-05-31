module UI.MilepostToast exposing (next, view)

{-| The earn-toast celebration that fires when a milepost marker is newly
earned (#410).

`reconcileMileposts` (in `Main`) appends every newly-`Earned` `Marker` to
`AuthState.milepostToasts`. This module renders the head of that queue as a
bottom-anchored forest plaque that slides up over the dimmed view, and exposes
the pure queue-head decision (`next`) so the view and the Verify surface
(`Verify.Specs.MilepostToast`) read from one source of truth.

The plaque reuses `UI.Milepost`'s family accent + glyph so the parchment badge
matches the collection screen, and the rust CTA links to `/milepost` (the
collection screen) via `basePath`. Tokens/utilities only — the forest gradient,
topo texture, parchment badge, and `animate-fade-up` slide all come from
`src/theme.css`.

@docs next, view

-}

import Data.Milepost as Milepost
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Types exposing (AuthMsg_(..), AuthState, Msg(..))
import UI.Icons
import UI.Milepost


{-| The marker currently being celebrated: the head of the earn-toast queue, or
`Nothing` when the queue is empty.

This is the single branch decision shared by `view` and the Verify surface —
neither re-derives "which marker shows" independently.

-}
next : List Milepost.Marker -> Maybe Milepost.Marker
next queue =
    List.head queue


{-| Render the earn-toast plaque for the head of `as_.milepostToasts`. Renders
nothing when the queue is empty.

The plaque is a bottom-anchored, full-width forest card that slides up
(`animate-fade-up`) over a dimmed scrim: a "NEW MARKER REACHED" kicker, a
parchment badge carrying the family glyph, the marker name (Playfair) + blurb,
a rust "See the Milepost" CTA linking to the collection screen, and a ghost
"Dismiss" button that drops the head of the queue.

-}
view : AuthState -> Html Msg
view as_ =
    case next as_.milepostToasts of
        Nothing ->
            Html.text ""

        Just marker ->
            Html.div
                [ Html.Attributes.class "fixed inset-0 z-[60] flex items-end justify-center bg-forest-deep/60 px-4 pb-[calc(env(safe-area-inset-bottom)+1rem)]"
                , Html.Attributes.attribute "role" "status"
                , Html.Attributes.attribute "aria-live" "polite"
                ]
                [ Html.div
                    [ Html.Attributes.class "animate-fade-up relative w-full max-w-md overflow-hidden rounded-panel bg-forest-deep text-parchment shadow-lift bg-[image:var(--bg-topo-atlas)] bg-cover"
                    ]
                    [ Html.div [ Html.Attributes.class "relative flex flex-col gap-4 p-6" ]
                        [ Html.p [ Html.Attributes.class "flex items-center gap-2 text-[11px] font-mono uppercase tracking-[0.2em] text-tan" ]
                            [ Html.span [ Html.Attributes.attribute "aria-hidden" "true" ] [ Html.text "⛰" ]
                            , Html.text "New marker reached"
                            ]
                        , Html.div [ Html.Attributes.class "flex items-center gap-4" ]
                            [ badge marker.family
                            , Html.div [ Html.Attributes.class "min-w-0 flex-1" ]
                                [ Html.h2 [ Html.Attributes.class "font-display text-2xl font-bold leading-tight text-parchment" ]
                                    [ Html.text marker.name ]
                                , Html.p [ Html.Attributes.class "mt-1 text-sm text-cream/80" ]
                                    [ Html.text marker.blurb ]
                                ]
                            ]
                        , Html.div [ Html.Attributes.class "flex items-center gap-3" ]
                            [ Html.a
                                [ Html.Attributes.href (as_.basePath ++ "milepost")
                                , Html.Attributes.class "flex-1 rounded-card bg-rust px-4 py-2.5 text-center text-sm font-semibold text-parchment shadow-card"
                                ]
                                [ Html.text "See the Milepost" ]
                            , Html.button
                                [ Html.Events.onClick (AuthMsg DismissMilepostToast)
                                , Html.Attributes.class "rounded-card border border-tan/40 bg-transparent px-4 py-2.5 text-sm font-medium text-tan cursor-pointer"
                                ]
                                [ Html.text "Dismiss" ]
                            ]
                        ]
                    , Html.button
                        [ Html.Events.onClick (AuthMsg DismissMilepostToast)
                        , Html.Attributes.class "absolute right-3 top-3 bg-transparent border-none cursor-pointer text-tan/80"
                        , Html.Attributes.attribute "aria-label" "Dismiss"
                        ]
                        [ UI.Icons.close "w-4 h-4" ]
                    ]
                ]


{-| The parchment stamp carrying the family icon — a larger, light-on-dark
cousin of `UI.Milepost`'s in-card icon badge, reusing the same accent fill so
the celebration matches the collection screen.
-}
badge : Milepost.Family -> Html msg
badge family =
    Html.div
        [ Html.Attributes.classList
            [ ( "flex h-14 w-14 shrink-0 items-center justify-center rounded-full shadow-card", True )
            , ( (UI.Milepost.familyAccent family).badge, True )
            ]
        , Html.Attributes.attribute "aria-hidden" "true"
        ]
        [ UI.Milepost.familyGlyph family ]
