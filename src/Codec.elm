module Codec exposing (credsDecoder, encodeCreds)

{-| JSON codecs for the `Creds` blob that the auth server returns and
that we persist to IndexedDB under `auth_creds`. Extracted from `Main.elm`
(#368) so the flags / credentials wire format lives in one small module.

@docs credsDecoder, encodeCreds

-}

import Data.Auth exposing (Creds)
import Data.SubscriptionStatus as SubscriptionStatus exposing (SubscriptionStatus)
import Data.Tier as Tier exposing (Tier)
import Json.Decode
import Json.Encode


{-| Decode a `Creds` from either the auth server's verify-code response
or the IndexedDB-stored `auth_creds` blob.
-}
credsDecoder : Json.Decode.Decoder Creds
credsDecoder =
    Json.Decode.map6 Creds
        (Json.Decode.field "dbName" Json.Decode.string)
        (Json.Decode.field "email" Json.Decode.string)
        (Json.Decode.field "password" Json.Decode.string)
        subscriptionStatusField
        tierField
        trailblazerNumberField


{-| Decode tier from either the auth server's verify-code response or
the IndexedDB-stored `auth_creds` blob. Defaults to `Tern` when the
field is absent (legacy blobs persisted before tier was wired in) or
when the value is unrecognized — fails closed so an unknown tier never
silently grants paid features.
-}
tierField : Json.Decode.Decoder Tier
tierField =
    Json.Decode.oneOf
        [ Json.Decode.field "tier" Json.Decode.string
            |> Json.Decode.map (Tier.fromString >> Maybe.withDefault Tier.Tern)
        , Json.Decode.succeed Tier.Tern
        ]


{-| Decode `subscriptionStatus` from the verify-code response or the
IndexedDB blob. Absent / null / unrecognised → `Nothing` so legacy
`auth_creds` blobs persisted before this field was wired still
deserialise.
-}
subscriptionStatusField : Json.Decode.Decoder (Maybe SubscriptionStatus)
subscriptionStatusField =
    Json.Decode.oneOf
        [ Json.Decode.field "subscriptionStatus" (Json.Decode.nullable SubscriptionStatus.decoder)
        , Json.Decode.succeed Nothing
        ]


{-| Decode `trailblazerNumber` from the verify-code response or the
IndexedDB blob. Absent / null → `Nothing`.
-}
trailblazerNumberField : Json.Decode.Decoder (Maybe Int)
trailblazerNumberField =
    Json.Decode.oneOf
        [ Json.Decode.field "trailblazerNumber" (Json.Decode.nullable Json.Decode.int)
        , Json.Decode.succeed Nothing
        ]


{-| Encode a `Creds` back to the wire / IndexedDB shape.
-}
encodeCreds : Creds -> Json.Encode.Value
encodeCreds c =
    Json.Encode.object
        [ ( "dbName", Json.Encode.string c.dbName )
        , ( "email", Json.Encode.string c.email )
        , ( "password", Json.Encode.string c.password )
        , ( "subscriptionStatus"
          , c.subscriptionStatus
                |> Maybe.map SubscriptionStatus.encoder
                |> Maybe.withDefault Json.Encode.null
          )
        , ( "tier", Json.Encode.string (Tier.toString c.tier) )
        , ( "trailblazerNumber"
          , c.trailblazerNumber
                |> Maybe.map Json.Encode.int
                |> Maybe.withDefault Json.Encode.null
          )
        ]
