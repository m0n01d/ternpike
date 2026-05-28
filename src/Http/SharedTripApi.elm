module Http.SharedTripApi exposing
    ( CreateSharedTripResponse
    , JoinSharedTripResponse
    , authHeader
    , createSharedTrip
    , inviteToSharedTrip
    , joinSharedTrip
    , leaveSharedTrip
    , notifyActivity
    , transferOwnership
    )

{-| HTTP client for the five shared-trip-membership endpoints served by
`api.ternpike.com`.

These wrap the endpoints introduced in #57:

  - `POST /sharedtrips` — create.
  - `POST /sharedtrips/:id/invite` — invite a user by email.
  - `POST /sharedtrips/join` — redeem an invite JWT.
  - `POST /sharedtrips/:id/leave` — leave a shared trip (non-owner only).
  - `POST /sharedtrips/:id/transfer` — transfer ownership to another member.

Every request uses HTTP Basic with the per-user CouchDB credentials
already stored in `Data.Auth.Creds` — same shape the app uses to talk
to CouchDB directly. The server validates the password against the
HMAC-derived value it issued at login.

All response shapes are kept minimal — the new `flock:meta` doc lands
through the live CouchDB changes feed, so the HTTP response only needs
to confirm the action and (for create / join) hand back the shared trip id.

-}

import Data.Auth exposing (Creds)
import Data.SharedTripId as SharedTripId exposing (SharedTripId)
import Http
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode


{-| The base URL all shared trip endpoints sit beneath. Kept in one place so
swapping environments only touches this module.
-}
baseUrl : String
baseUrl =
    "https://api.ternpike.com"


{-| Build the HTTP Basic `Authorization` header from `Creds`. Mirrors
the password the auth server hands back at login — same scheme PouchDB
already uses against CouchDB.

The server (#57) accepts `Basic base64(email:password)` against the same
credentials the auth flow handed back, then verifies the password using
the HMAC-derived comparison documented in `CLAUDE.md`.

-}
authHeader : Creds -> Http.Header
authHeader creds =
    Http.header "Authorization" ("Basic " ++ encodeBasic (creds.email ++ ":" ++ creds.password))


{-| Tiny RFC 4648 base64 encoder. We only base64 short ASCII strings
(email + token) so we don't need elm/bytes; this stays inside the
module rather than dragging in a dependency.
-}
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


{-| Response from `POST /sharedtrips`: just the new shared trip's id. The full
`sharedtrip:meta` document lands separately through the live changes feed.
-}
type alias CreateSharedTripResponse =
    { sharedTripId : SharedTripId
    }


{-| Response from `POST /sharedtrips/join`: enough to render a success
toast (the name) and navigate (the id). The full membership update
lands through the live changes feed.
-}
type alias JoinSharedTripResponse =
    { name : String
    , sharedTripId : SharedTripId
    }


createSharedTripResponseDecoder : Json.Decode.Decoder CreateSharedTripResponse
createSharedTripResponseDecoder =
    Json.Decode.succeed CreateSharedTripResponse
        |> Pipeline.required "flockId" SharedTripId.decoder


joinSharedTripResponseDecoder : Json.Decode.Decoder JoinSharedTripResponse
joinSharedTripResponseDecoder =
    Json.Decode.succeed JoinSharedTripResponse
        |> Pipeline.required "name" Json.Decode.string
        |> Pipeline.required "flockId" SharedTripId.decoder


{-| `POST /sharedtrips` — create a shared trip. The server is responsible for
checking the tier (Osprey+) and rejecting Tern creators.
-}
createSharedTrip :
    Creds
    -> { name : String }
    -> (Result Http.Error CreateSharedTripResponse -> msg)
    -> Cmd msg
createSharedTrip creds { name } toMsg =
    Http.request
        { method = "POST"
        , headers = [ authHeader creds ]
        , url = baseUrl ++ "/sharedtrips"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ ( "name", Json.Encode.string name ) ]
                )
        , expect = Http.expectJson toMsg createSharedTripResponseDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| `POST /sharedtrips/:id/invite` — owner-only invite by email. Server
sends the JWT-bearing invite email via Resend and returns `204`.
-}
inviteToSharedTrip :
    Creds
    -> SharedTripId
    -> { email : String }
    -> (Result Http.Error () -> msg)
    -> Cmd msg
inviteToSharedTrip creds sharedTripId { email } toMsg =
    Http.request
        { method = "POST"
        , headers = [ authHeader creds ]
        , url = baseUrl ++ "/sharedtrips/" ++ SharedTripId.toString sharedTripId ++ "/invite"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ ( "inviteeEmail", Json.Encode.string email ) ]
                )
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| `POST /sharedtrips/join` — redeem an invite JWT. The server validates
the token's recipient against the calling user's email and 403s on
mismatch.
-}
joinSharedTrip :
    Creds
    -> { token : String }
    -> (Result Http.Error JoinSharedTripResponse -> msg)
    -> Cmd msg
joinSharedTrip creds { token } toMsg =
    Http.request
        { method = "POST"
        , headers = [ authHeader creds ]
        , url = baseUrl ++ "/sharedtrips/join"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ ( "token", Json.Encode.string token ) ]
                )
        , expect = Http.expectJson toMsg joinSharedTripResponseDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| `POST /sharedtrips/:id/leave` — leave a shared trip. The server rejects the
billing owner attempting to leave while other members remain (must
`transferOwnership` first).
-}
leaveSharedTrip :
    Creds
    -> SharedTripId
    -> (Result Http.Error () -> msg)
    -> Cmd msg
leaveSharedTrip creds sharedTripId toMsg =
    Http.request
        { method = "POST"
        , headers = [ authHeader creds ]
        , url = baseUrl ++ "/sharedtrips/" ++ SharedTripId.toString sharedTripId ++ "/leave"
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| `POST /sharedtrips/:id/notify-activity` — fire push notifications to
co-travelers when an expense is added, edited, or voided. Fire-and-forget
— the response is handled by a no-op `Msg` branch; any delivery failure
is logged server-side and does not affect UI state.

Called after the PouchDB write succeeds so the notification emits in
the same user action without blocking the local write.

-}
notifyActivity :
    Creds
    -> SharedTripId
    -> { action : String, amount : Float, note : Maybe String }
    -> (Result Http.Error () -> msg)
    -> Cmd msg
notifyActivity creds sharedTripId { action, amount, note } toMsg =
    Http.request
        { method = "POST"
        , headers = [ authHeader creds ]
        , url = baseUrl ++ "/sharedtrips/" ++ SharedTripId.toString sharedTripId ++ "/notify-activity"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    ([ ( "action", Json.Encode.string action )
                     , ( "amount", Json.Encode.float amount )
                     ]
                        ++ (case note of
                                Just n ->
                                    [ ( "note", Json.Encode.string n ) ]

                                Nothing ->
                                    []
                           )
                    )
                )
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| `POST /sharedtrips/:id/transfer` — transfer ownership to another member
by email. The server re-checks that the target is a current member
and is on Osprey+ before accepting.
-}
transferOwnership :
    Creds
    -> SharedTripId
    -> { newOwnerEmail : String }
    -> (Result Http.Error () -> msg)
    -> Cmd msg
transferOwnership creds sharedTripId { newOwnerEmail } toMsg =
    Http.request
        { method = "POST"
        , headers = [ authHeader creds ]
        , url = baseUrl ++ "/sharedtrips/" ++ SharedTripId.toString sharedTripId ++ "/transfer"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ ( "newOwnerEmail", Json.Encode.string newOwnerEmail ) ]
                )
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }
