module Data.SharedTripId exposing (SharedTripId, decoder, encode, fromString, toString)

{-| Opaque wrapper around a shared trip identifier.

The underlying representation is a 12-character lowercase hex nonce.
`fromString` validates that shape and returns `Maybe SharedTripId`; the
constructor is not exposed so the only way to obtain a `SharedTripId` from a
raw string is through this validator (or `decoder`, which fails the
decode if the value doesn't match the same shape).

Used as the outer key for `Data.SharedTrips` and as the `sharedTripId` field on
`Data.SharedTrip` and on the in-memory `Trip` record (where it is populated
at the port boundary, not stored on disk — see `Data.Trip`).

-}

import Json.Decode
import Json.Encode


type SharedTripId
    = SharedTripId String


{-| Decode a `SharedTripId` from a JSON string, failing the decode when the
value isn't a valid 12-char hex nonce.
-}
decoder : Json.Decode.Decoder SharedTripId
decoder =
    Json.Decode.string
        |> Json.Decode.andThen
            (\s ->
                case fromString s of
                    Just id ->
                        Json.Decode.succeed id

                    Nothing ->
                        Json.Decode.fail ("Invalid SharedTripId: " ++ s)
            )


{-| Encode a `SharedTripId` to a JSON string.
-}
encode : SharedTripId -> Json.Encode.Value
encode (SharedTripId s) =
    Json.Encode.string s


{-| Wrap a raw string as a `SharedTripId` after validating the wire format
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
fromString : String -> Maybe SharedTripId
fromString s =
    if String.length s == 12 && String.all isLowerHex s then
        Just (SharedTripId s)

    else
        Nothing


{-| Unwrap a `SharedTripId` to its raw string.

    fromString "abcdef012345" |> Maybe.map toString
    --> Just "abcdef012345"

-}
toString : SharedTripId -> String
toString (SharedTripId s) =
    s


isLowerHex : Char -> Bool
isLowerHex c =
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
