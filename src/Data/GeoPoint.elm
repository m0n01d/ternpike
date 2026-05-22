module Data.GeoPoint exposing (GeoPoint, decoder, decoderPair, encoder, format, fromDegrees, latDegrees, lonDegrees)

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

@docs GeoPoint, decoder, decoderPair, encoder, format, fromDegrees, latDegrees, lonDegrees

-}

import Angle exposing (Angle)
import Json.Decode
import Json.Encode


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

    format (fromDegrees 45 -90)
    --> "45, -90"

-}
format : GeoPoint -> String
format point =
    String.left 9 (String.fromFloat (latDegrees point))
        ++ ", "
        ++ String.left 9 (String.fromFloat (lonDegrees point))


{-| Decode the legacy wire form `{ "lat": Float, "lon": Float }` (degrees)
into a `GeoPoint`. Both fields are required.
-}
decoder : Json.Decode.Decoder GeoPoint
decoder =
    Json.Decode.map2 fromDegrees
        (Json.Decode.field "lat" Json.Decode.float)
        (Json.Decode.field "lon" Json.Decode.float)


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


{-| Emit a `GeoPoint` as the legacy wire form `{ "lat": Float, "lon": Float }`
in degrees.
-}
encoder : GeoPoint -> Json.Encode.Value
encoder point =
    Json.Encode.object
        [ ( "lat", Json.Encode.float (latDegrees point) )
        , ( "lon", Json.Encode.float (lonDegrees point) )
        ]
