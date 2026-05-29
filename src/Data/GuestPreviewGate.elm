module Data.GuestPreviewGate exposing
    ( GuestPreviewGate(..)
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


{-| The three guest-preview modes.

Alphabetized by constructor name per repo style guide.

-}
type GuestPreviewGate
    = TempSession
    | ViewOnly
    | ViewScanPreview


{-| Wire-format label for a `GuestPreviewGate`. Inverse of the wire
decoder that lands in issue #335 alongside `Data.NestPreview`.

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
