module Http.NestPreviewApi exposing (resolve, scanGuest)

{-| HTTP client for `POST /invite/resolve` — the unauthenticated endpoint
that returns the redacted teaser for a Nest invite funnel (`RouteNestPreview`).

No credentials are required; the share token (a signed JWT minted by
`POST /sharedtrips/:id/share-link`) is sent in the request body and the
server verifies it there.

The response is decoded into `Data.NestPreview.NestPreview`; see that
module and §C of `docs/nest-invite-funnel.md` for the field documentation.

-}

import Data.NestPreview as NestPreview
import Data.Scan as Scan
import Http
import Json.Decode
import Json.Encode


{-| POST the share token to `{backendUrl}/invite/resolve` and decode the
redacted teaser.

`shareToken` is the JWT string from the `RouteNestPreview` URL parameter.
`backendUrl` is `AppConfig.backendUrl` (e.g. `"https://api.ternpike.com"`).

-}
resolve : String -> String -> (Result Http.Error NestPreview.NestPreview -> msg) -> Cmd msg
resolve backendUrl shareToken toMsg =
    Http.post
        { url = backendUrl ++ "/invite/resolve"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ ( "token", Json.Encode.string shareToken ) ]
                )
        , expect = Http.expectJson toMsg NestPreview.decoder
        }


{-| POST a receipt image to `{backendUrl}/scan-guest` and decode the parsed
`OcrData` from the response's `ocr` field.

`shareToken` authorizes the (unauthenticated) guest scan; `base64`/`mimeType`
are the receipt image. The server proxies to Ternpike's Anthropic key and
returns `{ ok, ocr, remaining }` — we decode only `ocr`. The result is shown
in the preview (S3) and discarded on conversion under the default gate.

-}
scanGuest : String -> String -> String -> String -> (Result Http.Error Scan.OcrData -> msg) -> Cmd msg
scanGuest backendUrl shareToken base64 mimeType toMsg =
    Http.post
        { url = backendUrl ++ "/scan-guest"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ ( "token", Json.Encode.string shareToken )
                    , ( "base64", Json.Encode.string base64 )
                    , ( "mimeType", Json.Encode.string mimeType )
                    ]
                )
        , expect = Http.expectJson toMsg (Json.Decode.field "ocr" Scan.ocrDataDecoder)
        }
