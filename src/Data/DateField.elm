module Data.DateField exposing
    ( DateField
    , compare
    , decoder
    , diffDays
    , encoder
    , formatDisplay
    , fromIso
    , fromIsoOr
    , toIso
    , today
    )

{-| Opaque wrapper around `Date.Date` for the calendar-date concept used by
`expense.date`, `trip.startDate` / `trip.endDate`, `amendment.date`,
`ocrData.date`, and `AuthState.today`.

Today every date in this repo is a `String` ISO-8601, parsed by ad-hoc helpers
(`Helpers.isoToDayCount`, `Helpers.formatDateDisplay`) and compared with
lexicographic `<` / `>=` ops. Wrapping the concept gives us:

  - A single decode site that fails loudly on malformed input rather than
    silently doing the wrong thing later.
  - Native `Date.compare`, `Date.diff`, `Date.add` instead of string comparison
    and the hand-rolled `isoToDayCount`.
  - Compiler-enforced separation between calendar dates and the ISO-timestamp
    `createdAt` field, which conceptually is a `Time.Posix` instant and will
    move there in R3.

The wire format stays the canonical ISO `YYYY-MM-DD` String so PouchDB /
CouchDB sync compatibility is unchanged. `decoder` is the migration shim — it
reads the existing `String` shape from pre-R1 documents so callers in R1–R5
can flip their field types one at a time without coordinated wire-format
changes.

Unknown / malformed input falls back to `Date.fromOrdinalDate 1970 1` (epoch),
mirroring the silent-default pattern in `Data.Category` for unknown wire
values. The opaque constructor means downstream code can't accidentally
fabricate a DateField from a raw `String`; the only routes in are `decoder`,
`fromIso`, `fromIsoOr`, and `today`.

-}

import Date
import Json.Decode
import Json.Encode
import Time


{-| The wrapped calendar date. Opaque so callers must go through `decoder`,
`fromIso`, `fromIsoOr`, or `today` to construct one.
-}
type DateField
    = DateField Date.Date


{-| Compare two dates chronologically. Delegates to `Date.compare`.

    import Data.DateField

    Maybe.map2 Data.DateField.compare
        (fromIso "2024-05-21")
        (fromIso "2024-06-01")
    --> Just LT

    Maybe.map2 Data.DateField.compare
        (fromIso "2024-05-21")
        (fromIso "2024-05-21")
    --> Just EQ

    Maybe.map2 Data.DateField.compare
        (fromIso "2024-06-01")
        (fromIso "2024-05-21")
    --> Just GT

-}
compare : DateField -> DateField -> Order
compare (DateField a) (DateField b) =
    Date.compare a b


{-| JSON decoder for the legacy `"YYYY-MM-DD"` wire shape. Existing PouchDB
documents written before R1 stored dates as plain ISO strings; this decoder
reads that shape and promotes to a `DateField` so callers can flip their
record types one at a time.

If the string fails to parse, falls back to `Date.fromOrdinalDate 1970 1`
(1970-01-01) — same silent-default pattern `Data.Category` uses for unknown
wire values. R1's migration step will rewrite stored docs so this fallback
becomes unreachable in practice, but it keeps old documents loadable in the
meantime.

-}
decoder : Json.Decode.Decoder DateField
decoder =
    Json.Decode.string
        |> Json.Decode.map fromIsoOrEpoch


{-| The number of whole days from `a` to `b`. Positive when `b` is after `a`,
negative when before, zero when equal. Delegates to `Date.diff Date.Days`.

    Maybe.map2 diffDays (fromIso "2024-05-21") (fromIso "2024-05-24")
    --> Just 3

    Maybe.map2 diffDays (fromIso "2024-05-24") (fromIso "2024-05-21")
    --> Just -3

    Maybe.map2 diffDays (fromIso "2024-05-21") (fromIso "2024-05-21")
    --> Just 0

-}
diffDays : DateField -> DateField -> Int
diffDays (DateField a) (DateField b) =
    Date.diff Date.Days a b


{-| JSON encoder. Emits the ISO `YYYY-MM-DD` String so the wire format stays
identical to the pre-R1 shape and CouchDB sync continues to work across
clients still on the old code.
-}
encoder : DateField -> Json.Encode.Value
encoder df =
    Json.Encode.string (toIso df)


{-| Human-readable display format, e.g. `"May 21, 2024"`. Replaces
`Helpers.formatDateDisplay`. Uses `Date.format "MMM d, yyyy"`.

    Maybe.map formatDisplay (fromIso "2024-05-21")
    --> Just "May 21, 2024"

    Maybe.map formatDisplay (fromIso "2024-01-01")
    --> Just "Jan 1, 2024"

    Maybe.map formatDisplay (fromIso "2024-12-31")
    --> Just "Dec 31, 2024"

-}
formatDisplay : DateField -> String
formatDisplay (DateField d) =
    Date.format "MMM d, yyyy" d


{-| Parse a calendar date from an ISO `YYYY-MM-DD` String. Returns `Nothing`
if the input is malformed; callers decide whether to surface an error or
default. For the legacy-document fallback behavior, use `fromIsoOr` (or rely
on `decoder`'s built-in fallback).
-}
fromIso : String -> Maybe DateField
fromIso s =
    case Date.fromIsoString s of
        Ok d ->
            Just (DateField d)

        Err _ ->
            Nothing


{-| Parse a calendar date from an ISO `YYYY-MM-DD` String, returning the
provided default when the input is malformed. Useful when a caller has a
sensible fallback in hand (e.g. "today") and would rather not propagate a
`Maybe` further.
-}
fromIsoOr : DateField -> String -> DateField
fromIsoOr fallback s =
    Maybe.withDefault fallback (fromIso s)


{-| The current calendar date in the given timezone. Wraps `Date.fromPosix`.
-}
today : Time.Zone -> Time.Posix -> DateField
today zone posix =
    DateField (Date.fromPosix zone posix)


{-| Render the wire form: ISO `YYYY-MM-DD`. Use for encoders, URL params, and
any other place the on-disk shape is required.
-}
toIso : DateField -> String
toIso (DateField d) =
    Date.toIsoString d



-- INTERNAL


{-| Parse an ISO String, falling back to the epoch (1970-01-01) if the input
is malformed. Used by `decoder` for the migration-shim behavior described in
the module doc.
-}
fromIsoOrEpoch : String -> DateField
fromIsoOrEpoch =
    fromIsoOr epoch


epoch : DateField
epoch =
    DateField (Date.fromOrdinalDate 1970 1)
