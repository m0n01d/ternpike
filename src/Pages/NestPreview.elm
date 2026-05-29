module Pages.NestPreview exposing (view)

{-| The redacted-teaser preview page for the Nest invite funnel
(`docs/nest-invite-funnel.md` §B/§C, state S1 / S6 / empty-trip).

A signed-out guest who opens a share link lands on `RouteNestPreview token`;
the resolve fetch fires automatically (see `Main.elm`) and the decoded
`Data.NestPreview.NestPreview` lands in `GuestState.nestPreview`. This module
renders that `RemoteData` read-only — there are no interactions yet, so `view`
is polymorphic in `msg`. The guest scan affordance (#336) and the
Join/convert CTA (#337) add their own controls later.

The view branches over the `RemoteData` exactly once (NotAsked / Loading /
Failure / Success — no wildcard, per CLAUDE.md):

  - **NotAsked / Loading** → S0 spinner card.
  - **Success** → S1 teaser (trip name, inviter, totals, date range, stat
    chips, placeholder map). When `entryCount == 0`, the empty-trip copy
    replaces the stats + map block.
  - **Failure** → S6 dead-invite card, with copy keyed off the HTTP status.

-}

import Data.NestPreview exposing (NestPreview)
import Html exposing (Html)
import Html.Attributes
import Http
import RemoteData exposing (RemoteData)
import UI.Card
import UI.DateView
import UI.MoneyView


{-| Render the Nest invite preview for a guest.

The view is display-only today, so it takes just the resolve `RemoteData`. The
guest-preview gate (`Data.GuestPreviewGate`) that decides whether the scan
affordance is shown rides on the decoded teaser (`NestPreview.gate`); the first
consumer that branches on it is the scan dropzone in #336, which adds it as a
parameter then.

-}
view : RemoteData Http.Error NestPreview -> Html msg
view remote =
    Html.div
        [ Html.Attributes.class "min-h-dvh flex flex-col items-center justify-center px-6 bg-[image:var(--bg-topo-atlas)] bg-no-repeat bg-[size:2400px_2000px] bg-[position:-960px_-540px]" ]
        [ Html.div [ Html.Attributes.class "max-w-sm w-full" ]
            [ case remote of
                RemoteData.NotAsked ->
                    viewLoading

                RemoteData.Loading ->
                    viewLoading

                RemoteData.Failure err ->
                    viewDeadInvite err

                RemoteData.Success teaser ->
                    viewTeaser teaser
            ]
        ]


{-| S0 — the resolve fetch is in flight (or hasn't started yet).
-}
viewLoading : Html msg
viewLoading =
    UI.Card.subCard
        [ Html.div [ Html.Attributes.class "flex flex-col items-center gap-3 py-6" ]
            [ Html.div
                [ Html.Attributes.class "w-8 h-8 rounded-full border-2 border-tan border-t-forest animate-spin"
                , Html.Attributes.attribute "role" "status"
                , Html.Attributes.attribute "aria-label" "Loading the trip"
                ]
                []
            , Html.p [ Html.Attributes.class "text-sm text-moss font-mono uppercase tracking-widest" ]
                [ Html.text "Loading the trip…" ]
            ]
        ]


{-| S1 — the redacted teaser. Empty trips (`entryCount == 0`) swap the
stats + placeholder-map block for the scan-nudge empty-state copy.
-}
viewTeaser : NestPreview -> Html msg
viewTeaser teaser =
    UI.Card.subCard
        [ Html.div [ Html.Attributes.class "flex flex-col gap-4" ]
            [ Html.p [ Html.Attributes.class "text-sm text-moss" ]
                [ Html.text (teaser.inviterName ++ " invited you to…") ]
            , Html.h1 [ Html.Attributes.class "font-display text-3xl font-black tracking-tight text-forest" ]
                [ Html.text teaser.tripName ]
            , Html.div [ Html.Attributes.class "flex items-baseline gap-2" ]
                [ Html.span [ Html.Attributes.class "text-2xl font-bold text-ink" ]
                    [ UI.MoneyView.amount teaser.totalSpent ]
                , Html.span [ Html.Attributes.class "text-xs text-muted font-mono uppercase tracking-widest" ]
                    [ Html.text "total" ]
                ]
            , Html.div [ Html.Attributes.class "flex items-center gap-1.5 text-sm text-moss" ]
                [ UI.DateView.short teaser.startDate
                , Html.span [ Html.Attributes.class "text-muted" ] [ Html.text "–" ]
                , UI.DateView.short teaser.endDate
                ]
            , if teaser.entryCount == 0 then
                viewEmptyTrip

              else
                viewStatsAndMap teaser
            , viewWhatsNext
            ]
        ]


{-| The stat chips + placeholder map shown for a non-empty trip. The teaser
carries no coordinates, so the "map" is a deliberate placeholder describing the
trip's shape ("N stops across M days") rather than a real Leaflet render.
-}
viewStatsAndMap : NestPreview -> Html msg
viewStatsAndMap teaser =
    Html.div [ Html.Attributes.class "flex flex-col gap-4" ]
        [ Html.div [ Html.Attributes.class "flex flex-wrap gap-2" ]
            [ viewStatChip (String.fromInt teaser.entryCount) (pluralize teaser.entryCount "expense" "expenses")
            , viewStatChip (String.fromInt teaser.dayCount) (pluralize teaser.dayCount "day" "days")
            , viewStatChip (String.fromInt teaser.memberCount) (pluralize teaser.memberCount "member" "members")
            ]
        , Html.div
            [ Html.Attributes.class "rounded-card bg-cream-deep border border-tan/60 px-4 py-6 flex flex-col items-center gap-1 text-center" ]
            [ Html.p [ Html.Attributes.class "text-sm font-medium text-forest" ]
                [ Html.text
                    (String.fromInt teaser.entryCount
                        ++ " "
                        ++ pluralize teaser.entryCount "stop" "stops"
                        ++ " across "
                        ++ String.fromInt teaser.dayCount
                        ++ " "
                        ++ pluralize teaser.dayCount "day" "days"
                    )
                ]
            , Html.p [ Html.Attributes.class "text-xs text-muted font-mono uppercase tracking-widest" ]
                [ Html.text "Map unlocks when you join" ]
            ]
        ]


{-| Empty-trip copy — the trip has no expenses yet. Nudges toward the scan
value hook (the actual scan dropzone arrives in #336).
-}
viewEmptyTrip : Html msg
viewEmptyTrip =
    Html.div
        [ Html.Attributes.class "rounded-card bg-cream-deep border border-tan/60 px-4 py-6 flex flex-col items-center gap-1 text-center" ]
        [ Html.p [ Html.Attributes.class "text-sm font-medium text-forest" ]
            [ Html.text "No expenses yet" ]
        , Html.p [ Html.Attributes.class "text-xs text-muted" ]
            [ Html.text "Be the first to add one once you join." ]
        ]


{-| A single labelled stat chip — big number over a small caption.
-}
viewStatChip : String -> String -> Html msg
viewStatChip value caption =
    Html.div
        [ Html.Attributes.class "flex flex-col items-center px-3 py-2 rounded-card bg-cream-deep border border-tan/60 min-w-16" ]
        [ Html.span [ Html.Attributes.class "text-lg font-bold text-forest leading-none" ]
            [ Html.text value ]
        , Html.span [ Html.Attributes.class "text-[11px] text-muted font-mono uppercase tracking-wide mt-1" ]
            [ Html.text caption ]
        ]


{-| Non-interactive "what's next" hint. The real Join/convert CTA is #337;
this is copy only so no Msg constructor is needed here.
-}
viewWhatsNext : Html msg
viewWhatsNext =
    Html.p [ Html.Attributes.class "text-xs text-moss text-center" ]
        [ Html.text "Join to save this trip and see the full ledger." ]


{-| S6 — dead invite. Copy is keyed off the resolve failure status, mirroring
the tone of `Pages.JoinSharedTrip.joinErrorMessage`.
-}
viewDeadInvite : Http.Error -> Html msg
viewDeadInvite err =
    UI.Card.subCard
        [ Html.div [ Html.Attributes.class "flex flex-col items-center gap-2 py-4 text-center" ]
            [ Html.h2 [ Html.Attributes.class "font-display text-xl font-bold text-forest" ]
                [ Html.text "Invite unavailable" ]
            , Html.p [ Html.Attributes.class "text-sm text-rust" ]
                [ Html.text (deadInviteMessage err) ]
            ]
        ]


{-| Map a resolve failure to dead-invite copy.

  - `403` → revoked / unavailable trip.
  - `410` → expired link.
  - anything else → generic failure.

-}
deadInviteMessage : Http.Error -> String
deadInviteMessage err =
    case err of
        Http.BadStatus 403 ->
            "This invite was revoked or the trip is unavailable."

        Http.BadStatus 410 ->
            "This link has expired — ask for a fresh one."

        _ ->
            "We couldn't load this invite. Ask the inviter for a fresh link."


{-| Pick the singular or plural noun for a count.
-}
pluralize : Int -> String -> String -> String
pluralize n singular plural =
    if n == 1 then
        singular

    else
        plural
