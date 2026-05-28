module UI.TripPicker exposing (viewMove)

{-| Modal picker for choosing a destination trip when moving an expense.

Passive view component, mirroring `UI.Layout.viewDeleteConfirmModal`:
the caller owns the open/close state on `AuthState.movePicker` and the
picker only renders. Each candidate trip is a `<button>` that dispatches
`MoveEntry expense t.id` directly — no intermediate "selected" state.

-}

import Data.DateField as DateField
import Data.Expense exposing (Expense)
import Data.SharedTrip
import Data.SharedTrips exposing (SharedTrips)
import Data.Trip exposing (Trip)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Extra
import Types exposing (AuthMsg_(..), Msg(..))
import UI.Avatar
import UI.DateView
import UI.Icons
import UI.MoneyView
import UI.SharedTripBadge


{-| Render the move-expense trip picker. The expense's current trip is
filtered out — only candidate destinations are shown. Caller is
responsible for not rendering this when the destinations list is empty
(the row menu hides the "Move to trip…" entry in that case).
-}
viewMove : { expense : Expense, flocks : SharedTrips, trips : List Trip } -> Html Msg
viewMove { expense, flocks, trips } =
    let
        candidates =
            List.filter (\t -> t.id /= expense.tripId) trips
    in
    Html.div
        [ Html.Attributes.class "fixed inset-0 bg-black/60 backdrop-blur-sm z-[9998] flex items-center justify-center p-6" ]
        [ Html.div
            [ Html.Attributes.class "w-full max-w-sm border bg-parchment dark:bg-cream border-tan rounded-2xl shadow-panel bg-[image:var(--bg-grain)] overflow-hidden" ]
            [ Html.div [ Html.Attributes.class "p-6 pb-3" ]
                [ Html.p [ Html.Attributes.class "mb-1 text-lg font-bold text-ink font-display" ]
                    [ Html.text "Move to trip" ]
                , Html.p [ Html.Attributes.class "text-sm leading-relaxed text-muted" ]
                    (rowLabel expense)
                ]
            , Html.div [ Html.Attributes.class "max-h-72 overflow-y-auto border-t border-tan/60" ]
                (List.map (viewCandidate expense flocks) candidates)
            , Html.div [ Html.Attributes.class "p-4 border-t border-tan/60 flex justify-end" ]
                [ Html.button
                    [ Html.Attributes.type_ "button"
                    , Html.Attributes.class "text-sm text-muted px-3 py-2 hover:text-ink"
                    , Html.Events.onClick (AuthMsg CloseMovePicker)
                    ]
                    [ Html.text "Cancel" ]
                ]
            ]
        ]


viewCandidate : Expense -> SharedTrips -> Trip -> Html Msg
viewCandidate expense flocks trip =
    let
        maybeFlock =
            trip.flockId |> Maybe.andThen (\fid -> Data.SharedTrips.get fid flocks)
    in
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Attributes.class "w-full text-left px-6 py-3 border-b border-dashed border-tan/60 last:border-b-0 hover:bg-cream-deep flex items-center justify-between gap-3"
        , Html.Events.onClick (AuthMsg (MoveEntry expense trip.id))
        ]
        [ Html.div [ Html.Attributes.class "min-w-0 flex-1" ]
            [ Html.Extra.viewMaybe
                (\flock ->
                    Html.div [ Html.Attributes.class "mb-1" ]
                        [ UI.SharedTripBadge.view flock ]
                )
                maybeFlock
            , Html.div [ Html.Attributes.class "text-sm text-ink font-body truncate" ]
                [ Html.text trip.name ]
            , Html.div [ Html.Attributes.class "flex items-center gap-2 mt-1" ]
                [ Html.span [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-wider text-moss" ]
                    (dateRange trip)
                , Html.Extra.viewMaybe
                    (\flock -> UI.Avatar.viewStack (Data.SharedTrip.members flock))
                    maybeFlock
                ]
            ]
        , Html.span [ Html.Attributes.class "text-rust shrink-0" ]
            [ UI.Icons.move "w-4 h-4" ]
        ]


rowLabel : Expense -> List (Html Msg)
rowLabel expense =
    let
        head =
            if expense.merchant /= "" then
                expense.merchant

            else if expense.note /= "" then
                expense.note

            else
                "this expense"
    in
    [ Html.text (head ++ " · ")
    , UI.MoneyView.amount expense.amount
    ]


dateRange : Trip -> List (Html Msg)
dateRange trip =
    let
        hasStart =
            not (isEpochDate trip.startDate)

        hasEnd =
            not (isEpochDate trip.endDate)
    in
    if hasStart && hasEnd then
        [ UI.DateView.short trip.startDate
        , Html.text " → "
        , UI.DateView.short trip.endDate
        ]

    else if hasStart then
        [ UI.DateView.short trip.startDate ]

    else if hasEnd then
        [ UI.DateView.short trip.endDate ]

    else
        []


{-| True when a `DateField` is the epoch sentinel (`1970-01-01`).
After R2, trip dates that were stored as the legacy `""` empty-string
sentinel parse to the epoch via `DateField.decoder`'s built-in
fallback. The view code treats the epoch as "no date set" — same as
the pre-R2 `== ""` check.
-}
isEpochDate : DateField.DateField -> Bool
isEpochDate d =
    DateField.toIso d == "1970-01-01"
