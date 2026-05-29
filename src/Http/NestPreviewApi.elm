module Http.NestPreviewApi exposing (resolve)

{-| HTTP client for `POST /invite/resolve` — the unauthenticated endpoint
that returns the redacted teaser for a Nest invite funnel (`RouteNestPreview`).

No credentials are required; the share token (a signed JWT minted by
`POST /sharedtrips/:id/share-link`) is sent in the request body and the
server verifies it there.

The response is decoded into `Data.NestPreview.NestPreview`; see that
module and §C of `docs/nest-invite-funnel.md` for the field documentation.

-}

import Data.NestPreview as NestPreview
import Http
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
