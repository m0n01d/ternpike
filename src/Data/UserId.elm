module Data.UserId exposing (UserId, decoder, encode, fromString, toString, unknown)

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
