module UI.DateView exposing (monthDay, short)

{-| Elm-side wrappers around the `<relative-time>` web component.

`<relative-time>` is the `@github/relative-time-element` package, registered
in `src/elements/relative-time.js`. It extends `<time>` with
`Intl.DateTimeFormat` for absolute renders and `Intl.RelativeTimeFormat` for
relative renders; assistive tech can pick up the underlying `<time datetime>`
semantics and offer "open in calendar" / localised speech.

Both helpers in this module set:

  - `datetime` to the ISO `YYYY-MM-DD` shape, so assistive tech sees a real
    machine-readable date.
  - `format="datetime"` to force absolute rendering — the date itself, not
    "3 days ago".
  - `no-title=""` because the element's default `title` attribute is
    inaccessible to screen-reader and keyboard users (see the library's own
    a11y docs).

This module is the only place in the codebase that should construct
`<relative-time>` nodes — keep new date-rendering sites going through here
so the a11y attributes never drift.

-}

import Data.DateField as DateField exposing (DateField)
import Html exposing (Html)
import Html.Attributes


{-| Long absolute shape — "May 21, 2024" in en-US, locale-adapted elsewhere.

Replaces `Html.text (DateField.formatDisplay df)` on the DOM-render path.

Note: `weekday=""` is explicit. When `format="datetime"` and no `weekday`
attribute is present, the library falls back to `formatStyle` (default
"short") and prefixes the rendered text with the weekday — so the empty
string is the documented way to suppress it.

-}
short : DateField -> Html msg
short df =
    Html.node "relative-time"
        [ Html.Attributes.attribute "datetime" (DateField.toIso df)
        , Html.Attributes.attribute "format" "datetime"
        , Html.Attributes.attribute "weekday" ""
        , Html.Attributes.attribute "day" "numeric"
        , Html.Attributes.attribute "month" "short"
        , Html.Attributes.attribute "year" "numeric"
        , Html.Attributes.attribute "no-title" ""
        ]
        []


{-| Short month + day shape — "May 21" in en-US, locale-adapted elsewhere.

Replaces `Html.text (DateField.formatMonthDay df)` on the DOM-render path
(Scan card date row, multi-day map day-pill provenance).

Sets `year=""` so the library's "year auto-suffix when not current year"
behavior is suppressed — this helper is the canonical month+day shape.

-}
monthDay : DateField -> Html msg
monthDay df =
    Html.node "relative-time"
        [ Html.Attributes.attribute "datetime" (DateField.toIso df)
        , Html.Attributes.attribute "format" "datetime"
        , Html.Attributes.attribute "weekday" ""
        , Html.Attributes.attribute "day" "numeric"
        , Html.Attributes.attribute "month" "short"
        , Html.Attributes.attribute "year" ""
        , Html.Attributes.attribute "no-title" ""
        ]
        []
