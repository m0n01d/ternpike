module Http.GeocodeApi exposing (GeocodeResponse, geocode)

{-| HTTP client for the paid-tier `POST /geocode` endpoint introduced in
#152. Sends the OCR-extracted merchant address; the Worker resolves it
via Nominatim (with KV caching + per-user rate limiting) and returns
`{lat, lon}` — `null` for both when the address didn't match.

Tern callers are rejected server-side with 403 `paid_tier_required`;
the call site in `Main.elm` `GotOcrResult` is responsible for not
firing the request at all on the free tier.

-}

import Data.Auth exposing (Creds)
import Http
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode


{-| Same base URL as `Http.SharedTripApi`. Both endpoints live on the
auth Worker at `api.ternpike.com`.
-}
baseUrl : String
baseUrl =
    "https://api.ternpike.com"


{-| `{lat, lon}` from Nominatim. Both are `Nothing` when the address
returned no match — the server still 200s in that case so the client
decodes successfully and the call site can decide what to do
("address-only fallback, ask user to pin manually").
-}
type alias GeocodeResponse =
    { lat : Maybe Float
    , lon : Maybe Float
    }


geocodeResponseDecoder : Json.Decode.Decoder GeocodeResponse
geocodeResponseDecoder =
    Json.Decode.succeed GeocodeResponse
        |> Pipeline.optional "lat" (Json.Decode.nullable Json.Decode.float) Nothing
        |> Pipeline.optional "lon" (Json.Decode.nullable Json.Decode.float) Nothing


{-| `POST /geocode` — request lat/lon for a merchant address. The
server validates paid tier, rate-limits to 1 req/min/user, and caches
the result for 30 days.
-}
geocode :
    Creds
    -> { address : String }
    -> (Result Http.Error GeocodeResponse -> msg)
    -> Cmd msg
geocode creds { address } toMsg =
    Http.request
        { method = "POST"
        , headers = [ authHeader creds ]
        , url = baseUrl ++ "/geocode"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ ( "address", Json.Encode.string address ) ]
                )
        , expect = Http.expectJson toMsg geocodeResponseDecoder
        , timeout = Nothing
        , tracker = Nothing
        }



-- INTERNAL


{-| HTTP Basic header from `Creds`. Duplicates `Http.SharedTripApi`'s
private helper — future cleanup is to extract both copies into a shared
`Http.BasicAuth` module; deliberately scoped out of this PR to keep the
diff focused on the new endpoint.
-}
authHeader : Creds -> Http.Header
authHeader creds =
    Http.header "Authorization" ("Basic " ++ encodeBasic (creds.email ++ ":" ++ creds.password))


encodeBasic : String -> String
encodeBasic input =
    let
        chars =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

        charAt i =
            String.slice i (i + 1) chars

        bytes =
            String.toList input |> List.map Char.toCode

        encodeTriple b1 b2 b3 =
            let
                n =
                    b1 * 65536 + b2 * 256 + b3
            in
            charAt (n // 262144 |> modBy 64)
                ++ charAt (n // 4096 |> modBy 64)
                ++ charAt (n // 64 |> modBy 64)
                ++ charAt (modBy 64 n)

        go xs =
            case xs of
                a :: b :: c :: rest ->
                    encodeTriple a b c ++ go rest

                [ a, b ] ->
                    let
                        n =
                            a * 65536 + b * 256
                    in
                    charAt (n // 262144 |> modBy 64)
                        ++ charAt (n // 4096 |> modBy 64)
                        ++ charAt (n // 64 |> modBy 64)
                        ++ "="

                [ a ] ->
                    let
                        n =
                            a * 65536
                    in
                    charAt (n // 262144 |> modBy 64)
                        ++ charAt (n // 4096 |> modBy 64)
                        ++ "=="

                [] ->
                    ""
    in
    go bytes
