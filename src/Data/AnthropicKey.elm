module Data.AnthropicKey exposing
    ( AnthropicKey
    , decoder
    , fromInput
    , lastFour
    , toHeader
    )

{-| Opaque newtype wrapping the user's BYO Anthropic API key.

Replaces the bare `String` that `AppConfig.anthropicKey` used to carry, eliminating
the empty-string sentinel. The three states ("user has a key", "user has no key",
"user cleared the key") are now expressed as `Maybe AnthropicKey` at every call site.

This module provides a wire-compatible decoder and encoder so the existing
IndexedDB round-trip (`ai_config` key) keeps working without a data migration.

-}

import Json.Decode


{-| An Anthropic API key. Opaque — construct via `fromInput`.
-}
type AnthropicKey
    = AnthropicKey String


{-| Parse raw user input (from a Settings text field or startup flags) into a key.
Strips leading/trailing whitespace and rejects empty results.

    fromInput "" |> Maybe.map toHeader
    --> Nothing

    fromInput "   " |> Maybe.map toHeader
    --> Nothing

    fromInput "sk-ant-abc123" |> Maybe.map toHeader
    --> Just "sk-ant-abc123"

    fromInput "  sk-ant-abc123  " |> Maybe.map toHeader
    --> Just "sk-ant-abc123"

-}
fromInput : String -> Maybe AnthropicKey
fromInput raw =
    case String.trim raw of
        "" ->
            Nothing

        trimmed ->
            Just (AnthropicKey trimmed)


{-| The raw key string, for use as the `x-api-key` HTTP header.
-}
toHeader : AnthropicKey -> String
toHeader (AnthropicKey s) =
    s


{-| The last four characters of the key, for masked UI display (e.g. "sk-ant-…abcd").

    fromInput "sk-ant-api03-abcd1234" |> Maybe.map lastFour
    --> Just "1234"

    fromInput "abcd" |> Maybe.map lastFour
    --> Just "abcd"

-}
lastFour : AnthropicKey -> String
lastFour (AnthropicKey s) =
    String.right 4 s


{-| Wire-compatible decoder.

Accepts the legacy IDB shape: `null`, a missing field, and `""` all decode to
`Nothing`. A non-empty string decodes to `Just (AnthropicKey s)`.

-}
decoder : Json.Decode.Decoder (Maybe AnthropicKey)
decoder =
    Json.Decode.oneOf
        [ Json.Decode.null Nothing
        , Json.Decode.string
            |> Json.Decode.map fromInput
        ]
