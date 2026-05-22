module UI.TripPicker exposing (viewMove)

{-| Modal picker for choosing a destination trip when moving an expense.

Passive view component, mirroring `UI.Layout.viewDeleteConfirmModal`:
the caller owns the open/close state on `AuthState.movePicker` and the
picker only renders. Each candidate trip is a `<button>` that dispatches
`MoveEntry expense t.id` directly — no intermediate "selected" state.

-}

import Data.DateField as DateField
import Data.Expense exposing (Expense)
import Data.Flock
import Data.Flocks exposing (Flocks)
import Data.Money as Money
import Data.Trip exposing (Trip)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Types exposing (Msg(..))
import UI.Avatar
import UI.FlockBadge
import UI.Icons


{-| Render the move-expense trip picker. The expense's current trip is
filtered out — only candidate destinations are shown. Caller is
responsible for not rendering this when the destinations list is empty
(the row menu hides the "Move to trip…" entry in that case).
-}
viewMove : { expense : Expense, flocks : Flocks, trips : List Trip } -> Html Msg
viewMove { expense, flocks, trips } =
    let
        candidates =
            List.filter (\t -> t.id /= expense.tripId) trips
    in
    Html.div
        [ Html.Attributes.class "fixed inset-0 bg-forest/60 backdrop-blur-sm z-[9998] flex items-center justify-center p-6" ]
        [ Html.div
            [ Html.Attributes.class "w-full max-w-sm border bg-parchment border-tan rounded-2xl shadow-panel bg-[image:var(--bg-grain)] overflow-hidden" ]
            [ Html.div [ Html.Attributes.class "p-6 pb-3" ]
                [ Html.p [ Html.Attributes.class "mb-1 text-lg font-bold text-ink font-display" ]
                    [ Html.text "Move to trip" ]
                , Html.p [ Html.Attributes.class "text-sm leading-relaxed text-muted" ]
                    [ Html.text (rowLabel expense) ]
                ]
            , Html.div [ Html.Attributes.class "max-h-72 overflow-y-auto border-t border-tan/60" ]
                (List.map (viewCandidate expense flocks) candidates)
            , Html.div [ Html.Attributes.class "p-4 border-t border-tan/60 flex justify-end" ]
                [ Html.button
                    [ Html.Attributes.type_ "button"
                    , Html.Attributes.class "text-sm text-muted px-3 py-2 hover:text-ink"
                    , Html.Events.onClick CloseMovePicker
                    ]
                    [ Html.text "Cancel" ]
                ]
            ]
        ]


viewCandidate : Expense -> Flocks -> Trip -> Html Msg
viewCandidate expense flocks trip =
    let
        maybeFlock =
            trip.flockId |> Maybe.andThen (\fid -> Data.Flocks.get fid flocks)
    in
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Attributes.class "w-full text-left px-6 py-3 border-b border-dashed border-tan/60 last:border-b-0 hover:bg-cream-deep flex items-center justify-between gap-3"
        , Html.Events.onClick (MoveEntry expense trip.id)
        ]
        [ Html.div [ Html.Attributes.class "min-w-0 flex-1" ]
            [ case maybeFlock of
                Just flock ->
                    Html.div [ Html.Attributes.class "mb-1" ]
                        [ UI.FlockBadge.view flock ]

                Nothing ->
                    Html.text ""
            , Html.div [ Html.Attributes.class "text-sm text-ink font-body truncate" ]
                [ Html.text trip.name ]
            , Html.div [ Html.Attributes.class "flex items-center gap-2 mt-1" ]
                [ Html.span [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-wider text-moss" ]
                    [ Html.text (dateRange trip) ]
                , case maybeFlock of
                    Just flock ->
                        UI.Avatar.viewStack (Data.Flock.members flock)

                    Nothing ->
                        Html.text ""
                ]
            ]
        , Html.span [ Html.Attributes.class "text-rust shrink-0" ]
            [ UI.Icons.move "w-4 h-4" ]
        ]


rowLabel : Expense -> String
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
    head ++ " · " ++ Money.format expense.amount


dateRange : Trip -> String
dateRange trip =
    let
        formatIso iso =
            DateField.fromIso iso
                |> Maybe.map DateField.formatDisplay
                |> Maybe.withDefault iso
    in
    case ( trip.startDate, trip.endDate ) of
        ( "", "" ) ->
            ""

        ( s, "" ) ->
            formatIso s

        ( "", e ) ->
            formatIso e

        ( s, e ) ->
            formatIso s ++ " → " ++ formatIso e
