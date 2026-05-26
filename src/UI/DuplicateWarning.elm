module UI.DuplicateWarning exposing (view)

{-| Inline soft warning shown when a submitted expense looks like a likely
duplicate of an existing one in the same trip.

The warning is non-blocking — the submit button label changes to "Add anyway"
and a single click still proceeds. This component is used by both `Pages.Add`
and `Pages.Scan`.

-}

import Data.DateField as DateField
import Data.Expense exposing (Expense)
import Data.Iso8601 as Iso8601
import Data.Money as Money
import Html exposing (Html)
import Html.Attributes


{-| Render the duplicate-warning banner above the submit button.

Shows the matching expense's amount, merchant, date, and how long ago it was
created (via the `<relative-time>` web component).

-}
view : Expense -> Html msg
view match =
    Html.div
        [ Html.Attributes.class "mb-3 rounded-card border border-rust/40 bg-rust-tint px-4 py-3" ]
        [ Html.p
            [ Html.Attributes.class "text-[11px] font-mono uppercase tracking-widest text-rust font-bold mb-1" ]
            [ Html.text "Looks like a duplicate" ]
        , Html.p
            [ Html.Attributes.class "text-sm text-ink" ]
            [ Html.text "You entered "
            , Html.span [ Html.Attributes.class "font-mono font-bold" ]
                [ Html.text (Money.format match.amount) ]
            , Html.text
                (if String.isEmpty match.merchant then
                    ""

                 else
                    " at " ++ match.merchant
                )
            , Html.text " on "
            , Html.node "relative-time"
                [ Html.Attributes.attribute "datetime" (DateField.toIso match.date)
                , Html.Attributes.attribute "format" "datetime"
                , Html.Attributes.attribute "weekday" ""
                , Html.Attributes.attribute "day" "numeric"
                , Html.Attributes.attribute "month" "short"
                , Html.Attributes.attribute "year" ""
                , Html.Attributes.attribute "no-title" ""
                ]
                []
            , Html.text " ("
            , Html.node "relative-time"
                [ Html.Attributes.attribute "datetime" (Iso8601.fromPosix match.createdAt)
                , Html.Attributes.attribute "format" "relative"
                , Html.Attributes.attribute "no-title" ""
                ]
                []
            , Html.text ")"
            ]
        ]
