module Data.FlockId exposing (FlockId, decoder, encode, fromString, toString)

{-| Opaque wrapper around a flock identifier.

The underlying representation is a 12-character lowercase hex nonce.
`fromString` validates that shape and returns `Maybe FlockId`; the
constructor is not exposed so the only way to obtain a `FlockId` from a
raw string is through this validator (or `decoder`, which fails the
decode if the value doesn't match the same shape).

Used as the outer key for `Data.Flocks` and as the `flockId` field on
`Data.Flock` and on the in-memory `Trip` record (where it is populated
at the port boundary, not stored on disk — see `Data.Trip`).

-}

import Json.Decode
import Json.Encode


type FlockId
    = FlockId String


{-| Decode a `FlockId` from a JSON string, failing the decode when the
value isn't a valid 12-char hex nonce.
-}
decoder : Json.Decode.Decoder FlockId
decoder =
    Json.Decode.string
        |> Json.Decode.andThen
            (\s ->
                case fromString s of
                    Just id ->
                        Json.Decode.succeed id

                    Nothing ->
                        Json.Decode.fail ("Invalid FlockId: " ++ s)
            )


{-| Encode a `FlockId` to a JSON string.
-}
encode : FlockId -> Json.Encode.Value
encode (FlockId s) =
    Json.Encode.string s


{-| Wrap a raw string as a `FlockId` after validating the wire format
(12 lowercase hex characters).

    fromString "0123456789ab" |> Maybe.map toString
    --> Just "0123456789ab"

    fromString "TOO-SHORT"
    --> Nothing

    fromString "0123456789ab0"
    --> Nothing

    fromString "0123456789AB"
    --> Nothing

-}
fromString : String -> Maybe FlockId
fromString s =
    if String.length s == 12 && String.all isLowerHex s then
        Just (FlockId s)

    else
        Nothing


{-| Unwrap a `FlockId` to its raw string.

    fromString "abcdef012345" |> Maybe.map toString
    --> Just "abcdef012345"

-}
toString : FlockId -> String
toString (FlockId s) =
    s


isLowerHex : Char -> Bool
isLowerHex c =
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
