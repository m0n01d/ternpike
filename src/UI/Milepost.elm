module UI.Milepost exposing (Accent, familyAccent, familyGlyph, markerChip)

{-| Shared presentation for milepost achievement markers (#409).

This module is the single source of truth for how a marker renders — both the
full collection screen (`Pages.Milepost`) and the compact reuse on the Ledger /
Trips chrome (#411) call into here so the chip styling can't drift between the
two surfaces.

Each `Family` carries a colour accent (`familyAccent`), now also reused by the
earn-toast plaque (`UI.MilepostToast`, #410); the family tokens (`brown`,
`amber`) live in `src/theme.css`
alongside the pre-existing `rust` and `forest-light`. The accent is a record of
**literal** Tailwind class strings (not a token to concatenate) — Tailwind v4
only emits utilities it finds verbatim in source, and the styling guide bans
class string-concatenation.

Any `Money` rendered for a dollar goal goes through `UI.MoneyView` (the
`<tp-amount>` web component), never a hand-formatted string.

The compact icon-only `markerChipSmall` variant is deferred to #411 (its first
consumer) — `NoUnused.Exports` forbids exporting it before a construction site
exists, so it lands alongside that reuse rather than dead here.

@docs Accent, familyAccent, familyGlyph, markerChip

-}

import Data.Milepost as Milepost
import Html exposing (Html)
import Html.Attributes
import Html.Extra
import UI.MoneyView


{-| The literal Tailwind classes a family's accent contributes, kept whole so
the scanner sees each utility verbatim.

  - `badge` — earned icon-badge fill + text.
  - `bar` — locked progress-bar fill.
  - `border` — earned card's left rule.
  - `stamp` — the "Reached" pill's tinted background + text.

-}
type alias Accent =
    { badge : String
    , bar : String
    , border : String
    , stamp : String
    }


{-| The accent class bundle for a family.

  - `TrailDiscipline` → forest-light
  - `MileMarkers` → brown
  - `Odometer` → rust
  - `CautionSigns` → amber

-}
familyAccent : Milepost.Family -> Accent
familyAccent family =
    case family of
        Milepost.CautionSigns ->
            { badge = "bg-amber text-parchment"
            , bar = "bg-amber"
            , border = "border-amber"
            , stamp = "bg-amber/15 text-amber"
            }

        Milepost.MileMarkers ->
            { badge = "bg-brown text-parchment"
            , bar = "bg-brown"
            , border = "border-brown"
            , stamp = "bg-brown/15 text-brown"
            }

        Milepost.Odometer ->
            { badge = "bg-rust text-parchment"
            , bar = "bg-rust"
            , border = "border-rust"
            , stamp = "bg-rust/15 text-rust"
            }

        Milepost.TrailDiscipline ->
            { badge = "bg-forest-light text-parchment"
            , bar = "bg-forest-light"
            , border = "border-forest-light"
            , stamp = "bg-forest-light/15 text-forest-light"
            }


{-| The full achievement card: family-tinted icon badge, name, blurb, and either
a "Reached" stamp (earned) or a faded, dashed-border progress bar (locked).
-}
markerChip : Milepost.MarkerState -> Html msg
markerChip state =
    case state of
        Milepost.Earned { marker } ->
            let
                accent : Accent
                accent =
                    familyAccent marker.family
            in
            Html.div
                [ Html.Attributes.classList
                    [ ( "relative flex gap-3 p-4 rounded-card bg-cream shadow-card border-l-4", True )
                    , ( accent.border, True )
                    ]
                ]
                [ iconBadge marker.family True
                , Html.div [ Html.Attributes.class "flex-1 min-w-0" ]
                    [ Html.div [ Html.Attributes.class "flex items-center justify-between gap-2" ]
                        [ Html.h3 [ Html.Attributes.class "font-display text-lg font-bold text-forest truncate" ]
                            [ Html.text marker.name ]
                        , reachedStamp accent
                        ]
                    , Html.p [ Html.Attributes.class "text-sm text-muted mt-0.5" ]
                        [ Html.text marker.blurb ]
                    , goalTarget marker.goal
                    ]
                ]

        Milepost.Locked { label, marker, progress } ->
            Html.div
                [ Html.Attributes.class
                    "relative flex gap-3 p-4 rounded-card bg-cream/60 border border-dashed border-tan opacity-70"
                ]
                [ iconBadge marker.family False
                , Html.div [ Html.Attributes.class "flex-1 min-w-0" ]
                    [ Html.h3 [ Html.Attributes.class "font-display text-lg font-bold text-moss truncate" ]
                        [ Html.text marker.name ]
                    , Html.p [ Html.Attributes.class "text-sm text-muted mt-0.5" ]
                        [ Html.text marker.blurb ]
                    , goalTarget marker.goal
                    , progressBar marker.family progress label
                    ]
                ]


iconBadge : Milepost.Family -> Bool -> Html msg
iconBadge family earned =
    Html.div
        [ Html.Attributes.class "flex items-center justify-center w-10 h-10 shrink-0 rounded-full font-display font-black text-lg"
        , Html.Attributes.classList
            [ ( (familyAccent family).badge, earned )
            , ( "bg-tan/40 text-muted", not earned )
            ]
        , Html.Attributes.attribute "aria-hidden" "true"
        ]
        [ Html.text (familyGlyph family) ]


{-| A single-character glyph standing in for the family's marker icon.
-}
familyGlyph : Milepost.Family -> String
familyGlyph family =
    case family of
        Milepost.CautionSigns ->
            "!"

        Milepost.MileMarkers ->
            "M"

        Milepost.Odometer ->
            "0"

        Milepost.TrailDiscipline ->
            "T"


reachedStamp : Accent -> Html msg
reachedStamp accent =
    Html.span
        [ Html.Attributes.classList
            [ ( "shrink-0 text-[10px] font-mono uppercase tracking-widest px-2 py-0.5 rounded-full", True )
            , ( accent.stamp, True )
            ]
        ]
        [ Html.text "Reached" ]


{-| When the goal is a dollar threshold, surface the target amount through
`<tp-amount>`. All other goal shapes render nothing here (the threshold is baked
into the blurb / locked label).
-}
goalTarget : Milepost.Goal -> Html msg
goalTarget goal =
    case goal of
        Milepost.Dollars target ->
            Html.div [ Html.Attributes.class "mt-1 text-xs text-muted font-mono flex items-center gap-1" ]
                [ Html.text "Target:"
                , UI.MoneyView.wholeDollars target
                ]

        Milepost.Count _ ->
            Html.Extra.nothing

        Milepost.Flag ->
            Html.Extra.nothing

        Milepost.Streak _ ->
            Html.Extra.nothing


progressBar : Milepost.Family -> Float -> String -> Html msg
progressBar family progress label =
    let
        pct : Int
        pct =
            clamp 0 100 (round (progress * 100))
    in
    Html.div [ Html.Attributes.class "mt-2" ]
        [ Html.div [ Html.Attributes.class "h-1.5 w-full rounded-full bg-tan/40 overflow-hidden" ]
            [ Html.div
                -- dynamic percentage width; cannot be expressed as a static
                -- Tailwind class (mirrors UI.BudgetBar's bar fill).
                [ Html.Attributes.classList
                    [ ( "h-full rounded-full", True )
                    , ( (familyAccent family).bar, True )
                    ]
                , Html.Attributes.style "width" (String.fromInt pct ++ "%")
                ]
                []
            ]
        , Html.p [ Html.Attributes.class "mt-1 text-xs text-muted font-mono" ]
            [ Html.text label ]
        ]
