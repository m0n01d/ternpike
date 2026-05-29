module Data.GuestPreviewGate exposing
    ( GuestPreviewGate(..)
    , decoder
    , label
    )

{-| The server-configured flag that controls how much of the Nest invite
funnel a guest can access before converting.

Three values, in ascending order of permissiveness:

  - `TempSession` — (future) full scan + scan-result replay on join.
  - `ViewOnly` — teaser card visible, scan affordance hidden. The safe
    default for any unknown server value (new server, old client).
  - `ViewScanPreview` — teaser card + one guest scan attempt. The
    current shipped default (`GUEST_PREVIEW_GATE = 'view_scan_preview'`
    on the server).

The gate is returned verbatim in the `/invite/resolve` 200 body as the
`"gate"` field. Any unrecognised value decodes to `ViewOnly` so that
adding new server variants never crashes older clients. The Elm view
branches on this value exactly once — to show or hide the scan dropzone.

Wire format: `"temp_session"`, `"view_only"`, `"view_scan_preview"`
(snake\_case, matching the server constant).

-}

import Json.Decode


{-| The three guest-preview modes.

Alphabetized by constructor name per repo style guide.

-}
type GuestPreviewGate
    = TempSession
    | ViewOnly
    | ViewScanPreview


{-| Decode the `"gate"` field from an `/invite/resolve` 200 response.
Maps `"view_scan_preview"` → `ViewScanPreview`, `"view_only"` → `ViewOnly`,
`"temp_session"` → `TempSession`. Any unrecognised string decodes to
`ViewOnly` — the safe, most-restrictive default — so that new server
variants never crash older clients.
-}
decoder : Json.Decode.Decoder GuestPreviewGate
decoder =
    Json.Decode.string
        |> Json.Decode.map
            (\s ->
                case s of
                    "temp_session" ->
                        TempSession

                    "view_scan_preview" ->
                        ViewScanPreview

                    _ ->
                        ViewOnly
            )


{-| Wire-format label for a `GuestPreviewGate`. Inverse of `decoder`.

    label TempSession
    --> "temp_session"

    label ViewOnly
    --> "view_only"

    label ViewScanPreview
    --> "view_scan_preview"

-}
label : GuestPreviewGate -> String
label gate =
    case gate of
        TempSession ->
            "temp_session"

        ViewOnly ->
            "view_only"

        ViewScanPreview ->
            "view_scan_preview"
