module Pages.NestPreview exposing (view)

{-| The redacted-teaser preview page for the Nest invite funnel
(`docs/nest-invite-funnel.md` §B/§C, states S1 / S2 / S3 / S6 / empty-trip).

A signed-out guest who opens a share link lands on `RouteNestPreview token`;
the resolve fetch fires automatically (see `Main.elm`) and the decoded
`Data.NestPreview.NestPreview` lands in `GuestState.nestPreview`. This module
renders that `RemoteData` read-only, and — when the gate is `ViewScanPreview`
— offers a single guest receipt scan (S2 → S3), reusing the `/scan-guest`
endpoint. The scanned result is shown but not saved; the Join/convert CTA is
finished in #337.

The view branches over the `RemoteData` exactly once (NotAsked / Loading /
Failure / Success — no wildcard, per CLAUDE.md):

  - **NotAsked / Loading** → S0 spinner card.
  - **Success** → S1 teaser; below it the scan affordance (S2/S3) when the
    gate allows, else the static Join hint. Empty trips swap the stats + map
    block for empty-state copy.
  - **Failure** → S6 dead-invite card, with copy keyed off the HTTP status.

-}

import Data.GuestPreviewGate exposing (GuestPreviewGate(..))
import Data.NestPreview exposing (NestPreview)
import Data.Scan exposing (OcrData)
import Html exposing (Html)
import Html.Attributes
import Http
import RemoteData exposing (RemoteData)
import Types exposing (GuestMsg_(..), GuestScanState(..), Msg(..))
import UI.Button
import UI.Card
import UI.DateView
import UI.MoneyView


{-| Render the Nest invite preview for a guest. Takes the guest scan state (so
S2/S3 can render) and the resolve `RemoteData`.
-}
view : GuestScanState -> RemoteData Http.Error NestPreview -> Html Msg
view scan remote =
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
                    viewTeaser scan teaser
            ]
        ]


{-| S0 — the resolve fetch is in flight (or hasn't started yet).
-}
viewLoading : Html msg
viewLoading =
    UI.Card.subCard
        [ Html.div [ Html.Attributes.class "flex flex-col items-center gap-3 py-6" ]
            [ spinner "Loading the trip"
            , Html.p [ Html.Attributes.class "text-sm text-moss font-mono uppercase tracking-widest" ]
                [ Html.text "Loading the trip…" ]
            ]
        ]


{-| A small spinning status indicator with an accessible label.
-}
spinner : String -> Html msg
spinner label =
    Html.div
        [ Html.Attributes.class "w-8 h-8 rounded-full border-2 border-tan border-t-forest animate-spin"
        , Html.Attributes.attribute "role" "status"
        , Html.Attributes.attribute "aria-label" label
        ]
        []


{-| S1 — the redacted teaser. Empty trips (`entryCount == 0`) swap the
stats + placeholder-map block for the scan-nudge empty-state copy.
-}
viewTeaser : GuestScanState -> NestPreview -> Html Msg
viewTeaser scan teaser =
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
            , viewScanOrHint scan teaser.gate
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
value hook.
-}
viewEmptyTrip : Html msg
viewEmptyTrip =
    Html.div
        [ Html.Attributes.class "rounded-card bg-cream-deep border border-tan/60 px-4 py-6 flex flex-col items-center gap-1 text-center" ]
        [ Html.p [ Html.Attributes.class "text-sm font-medium text-forest" ]
            [ Html.text "No expenses yet" ]
        , Html.p [ Html.Attributes.class "text-xs text-muted" ]
            [ Html.text "Try a scan below, then join to start tracking." ]
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


{-| Below the teaser: the guest scan affordance (S2/S3) when the gate is
`ViewScanPreview`, otherwise the static Join hint. The interactive Join CTA is
finished in #337.
-}
viewScanOrHint : GuestScanState -> GuestPreviewGate -> Html Msg
viewScanOrHint scan gate =
    case gate of
        ViewScanPreview ->
            viewScanSection scan

        ViewOnly ->
            viewJoinHint

        TempSession ->
            viewScanSection scan


{-| S2 / S3 — the scan dropzone, the in-flight spinner, and the parsed result.
-}
viewScanSection : GuestScanState -> Html Msg
viewScanSection scan =
    case scan of
        NoScan ->
            Html.div [ Html.Attributes.class "flex flex-col items-center gap-2 rounded-card bg-cream-deep border border-tan/60 px-4 py-5 text-center" ]
                [ Html.p [ Html.Attributes.class "text-sm font-medium text-forest" ]
                    [ Html.text "Try scanning a receipt" ]
                , UI.Button.primary { label = "Scan a receipt", onClick = GuestMsg GuestScanPick }
                , Html.p [ Html.Attributes.class "text-[11px] text-muted" ]
                    [ Html.text "1 free try · not saved until you join" ]
                ]

        Scanning ->
            Html.div [ Html.Attributes.class "flex flex-col items-center gap-3 rounded-card bg-cream-deep border border-tan/60 px-4 py-6" ]
                [ spinner "Reading your receipt"
                , Html.p [ Html.Attributes.class "text-sm text-moss font-mono uppercase tracking-widest" ]
                    [ Html.text "Reading…" ]
                ]

        Scanned ocr ->
            viewScanResult ocr


{-| S3 — the parsed receipt fields, with the Join hint. Result is not saved.
-}
viewScanResult : OcrData -> Html Msg
viewScanResult ocr =
    Html.div [ Html.Attributes.class "flex flex-col gap-3 rounded-card bg-cream-deep border border-tan/60 px-4 py-4" ]
        [ Html.p [ Html.Attributes.class "text-xs text-moss font-mono uppercase tracking-widest" ]
            [ Html.text "We read your receipt" ]
        , Html.div [ Html.Attributes.class "flex flex-col gap-1.5 text-sm" ]
            [ viewScanRow "Merchant" (Html.text (Maybe.withDefault "—" ocr.merchant))
            , viewScanRow "Amount"
                (case ocr.amount of
                    Just amount ->
                        UI.MoneyView.amount amount

                    Nothing ->
                        Html.text "—"
                )
            , viewScanRow "Date"
                (case ocr.date of
                    Just date ->
                        UI.DateView.short date

                    Nothing ->
                        Html.text "—"
                )
            ]
        , viewJoinHint
        , UI.Button.ghost { label = "Scan another", onClick = GuestMsg GuestScanPick }
        ]


{-| A label/value row in the parsed-receipt card.
-}
viewScanRow : String -> Html Msg -> Html Msg
viewScanRow label value =
    Html.div [ Html.Attributes.class "flex items-baseline justify-between gap-3" ]
        [ Html.span [ Html.Attributes.class "text-xs text-muted font-mono uppercase tracking-wide" ]
            [ Html.text label ]
        , Html.span [ Html.Attributes.class "font-medium text-ink" ] [ value ]
        ]


{-| Static Join hint. The interactive Join/convert CTA is #337.
-}
viewJoinHint : Html msg
viewJoinHint =
    Html.p [ Html.Attributes.class "text-xs text-moss text-center" ]
        [ Html.text "Join to save this and see the full ledger." ]


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
