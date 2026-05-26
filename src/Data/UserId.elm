module Data.UserId exposing (UserId, decoder, encode, fromString, handle, handleIn, shortHash, toString, unknown)

{-| Opaque wrapper around a user identifier.

Today the underlying string is the user's verified email; tomorrow it may be
an opaque UUID. Wrapping it stops a raw `String` from being passed where a
`UserId` is expected, and keeps the wire format swappable without touching
call sites.

`unknown` is a single sentinel value (empty-string-backed) used by decoders
to fill in `createdBy` on legacy documents that predate the field. UI that
sees `unknown` should hide attribution or render a dash rather than show an
empty author.

Author integrity is server-enforced by CouchDB `validate_doc_update`; this
module is the client-side type.

-}

import Bitwise
import Json.Decode
import Json.Encode


type UserId
    = UserId String


{-| Decode a `UserId` from a JSON string.
-}
decoder : Json.Decode.Decoder UserId
decoder =
    Json.Decode.map UserId Json.Decode.string


{-| Encode a `UserId` to a JSON string.
-}
encode : UserId -> Json.Encode.Value
encode (UserId s) =
    Json.Encode.string s


{-| Wrap a raw string as a `UserId`.

    toString (fromString "alice@example.com")
    --> "alice@example.com"

-}
fromString : String -> UserId
fromString =
    UserId


{-| `@`-prefixed local-part of the email, suitable for user-facing display.
Falls back to `"@unknown"` for the `unknown` sentinel or any value with no
`@`.

    handle (fromString "alice@example.com")
    --> "@alice"

    handle (fromString "dwight.j.doane@gmail.com")
    --> "@dwight.j.doane"

    handle unknown
    --> "@unknown"

-}
handle : UserId -> String
handle (UserId s) =
    case String.split "@" s of
        local :: _ ->
            if String.isEmpty local then
                "@unknown"

            else
                "@" ++ local

        [] ->
            "@unknown"


{-| Same as `handle`, but appends `#<4-char-hash>` when another member of
the provided scope renders to the same handle — disambiguating
`alice@gmail.com` from `alice@yahoo.com` without exposing domains.

In the common case (no collision) the result is identical to `handle`.

    handleIn (fromString "alice@gmail.com") [ fromString "alice@gmail.com", fromString "bob@example.com" ]
    --> "@alice"

-}
handleIn : UserId -> List UserId -> String
handleIn userId scope =
    let
        h =
            handle userId

        collision =
            List.any (\u -> u /= userId && handle u == h) scope
    in
    if collision then
        h ++ "#" ++ shortHash userId

    else
        h


{-| FNV-1a 32-bit hash of the full email string, formatted as 8-char lowercase
hex, sliced to 4 chars. Used by `handleIn` as the collision discriminator.
Exposed so tests can pin the value and prevent silent drift.
-}
shortHash : UserId -> String
shortHash (UserId s) =
    let
        fnvOffsetBasis : Int
        fnvOffsetBasis =
            2166136261

        fnvPrime : Int
        fnvPrime =
            16777619

        -- FNV-1a: for each byte XOR then multiply
        step : Int -> Int -> Int
        step byte acc =
            modBy 4294967296 (Bitwise.xor acc byte * fnvPrime)

        hash =
            String.foldl (\c acc -> step (Char.toCode c) acc) fnvOffsetBasis s

        padded =
            String.padLeft 8 '0' (toHex hash)
    in
    String.left 4 padded


{-| Unwrap a `UserId` to its raw string.

    toString (fromString "bob@example.com")
    --> "bob@example.com"

    toString unknown
    --> ""

-}
toString : UserId -> String
toString (UserId s) =
    s


{-| Sentinel for documents whose author is unknown — typically legacy docs
written before `createdBy` existed on the wire.

    toString unknown
    --> ""

-}
unknown : UserId
unknown =
    UserId ""



-- INTERNAL


toHex : Int -> String
toHex n =
    let
        digits =
            "0123456789abcdef"

        go : Int -> String -> String
        go remaining acc =
            if remaining == 0 then
                if String.isEmpty acc then
                    "0"

                else
                    acc

            else
                let
                    digit =
                        String.slice (modBy 16 remaining) (modBy 16 remaining + 1) digits
                in
                go (remaining // 16) (digit ++ acc)
    in
    go n ""
