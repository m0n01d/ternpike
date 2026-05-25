module Data.GeoPoint exposing (GeoPoint, decoderPair, format, fromDegrees, latDegrees, lonDegrees)

{-| A single geographic point — latitude and longitude as `Angle` values
from `ianmackenzie/elm-units` — wrapped in an opaque constructor so that
"lat without lon is meaningless" is a type error rather than a convention.

Replaces the previous pair of `Maybe Float` fields (`expense.lat` /
`expense.lon`) and the `Float Float` payload of `Data.Location.LocationGot`
(both migrated; the latter now carries a `GeoPoint` directly).
Callers that only need a quick degrees value out for display or serialisation
use `latDegrees` / `lonDegrees`; the rest of the module is a thin shim around
the legacy `{ lat, lon }` wire format.

`format` is byte-for-byte compatible with the previous `Helpers.formatCoord`
so the Ledger row layout doesn't shift when call sites migrate.

@docs GeoPoint, decoderPair, format, fromDegrees, latDegrees, lonDegrees


## Stable invariants (PINNED-KEEP)

  - `format` always returns `"lat, lon"` with a comma-space separator.
  - `format` truncates each component to at most 9 characters of
    `String.fromFloat` output — this controls Ledger row alignment and is
    a permanent structural invariant unrelated to locale.
  - See `tests/Data/GeoPointTest.elm` for the canonical pinned assertions.


## Open for evolution under #38

  - `format` is not directly used for DOM-facing display; it feeds Leaflet
    popup label strings (`src/Helpers.elm:encodeWaypoints`) and chart label
    closures. No #38 changes are expected for this helper.

-}

import Angle exposing (Angle)
import Json.Decode


{-| A geographic point. Opaque — build with `fromDegrees` or one of the
decoders, read with `latDegrees` / `lonDegrees`.
-}
type GeoPoint
    = GeoPoint { latitude : Angle, longitude : Angle }


{-| Build a `GeoPoint` from latitude and longitude in degrees.
-}
fromDegrees : Float -> Float -> GeoPoint
fromDegrees lat lon =
    GeoPoint
        { latitude = Angle.degrees lat
        , longitude = Angle.degrees lon
        }


{-| Latitude as a `Float` in degrees.

Stored internally as an `Angle` in radians, so values that aren't exact
multiples of small integer degrees may round-trip with a few ULPs of
float error — that's fine for display (`format` truncates to 9 chars)
and round-trip serialisation.

    latDegrees (fromDegrees 45 -90)
    --> 45

-}
latDegrees : GeoPoint -> Float
latDegrees (GeoPoint { latitude }) =
    Angle.inDegrees latitude


{-| Longitude as a `Float` in degrees. See `latDegrees` for the
radian round-trip caveat.

    lonDegrees (fromDegrees 45 -90)
    --> -90

-}
lonDegrees : GeoPoint -> Float
lonDegrees (GeoPoint { longitude }) =
    Angle.inDegrees longitude


{-| Render a `GeoPoint` as `"lat, lon"`, truncated to the first 9 characters
of each `String.fromFloat` for display alignment. Matches the previous
`Helpers.formatCoord` byte-for-byte.

PINNED-KEEP: the `"lat, lon"` shape and 9-char truncation are stable invariants
(tested in `tests/Data/GeoPointTest.elm`). This helper is used for non-HTML
contexts (Leaflet popup labels, chart closures) so no #38 Intl changes apply.

    format (fromDegrees 45 -90)
    --> "45, -90"

-}
format : GeoPoint -> String
format point =
    String.left 9 (String.fromFloat (latDegrees point))
        ++ ", "
        ++ String.left 9 (String.fromFloat (lonDegrees point))


{-| Pull sibling `"lat"` and `"lon"` fields out of a parent object and lift
them into a `Maybe GeoPoint`. Succeeds with `Just` only when both fields are
present and decode as floats; missing-or-null on either side yields `Nothing`.
Use from a parent decoder via `Json.Decode.andThen` or a pipeline `custom`.
-}
decoderPair : Json.Decode.Decoder (Maybe GeoPoint)
decoderPair =
    Json.Decode.map2
        (\maybeLat maybeLon ->
            case ( maybeLat, maybeLon ) of
                ( Just lat, Just lon ) ->
                    Just (fromDegrees lat lon)

                _ ->
                    Nothing
        )
        (Json.Decode.maybe (Json.Decode.field "lat" Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field "lon" Json.Decode.float))
