module Analytics exposing
    ( convertRequested
    , joinSucceeded
    , nestPreviewViewed
    , scanTrySucceeded
    )

{-| Cookie-free funnel analytics for the Nest invite funnel (#340).

Stage-name constants for the four funnel events tracked via the `trackFunnel`
outbound port (declared in `Main.elm`, wired in `src/main.js`). Keeping them
here prevents typos and documents the full stage allowlist in one place.

The `trackFunnel` port fires a fire-and-forget `POST /invite/track` beacon.
NO PII is sent — the payload is `{ stage : String, flockId : String }` only.
The `flockId` value is the share token (for guest-side events) or a
`SharedTripId` string (for `joinSucceeded`); the server resolves or discards it
server-side. Validated against an allowlist; unknown stages are silently ignored.

-}


{-| S4 conversion wall — the magic-link email was sent successfully.
-}
convertRequested : String
convertRequested =
    "convert_requested"


{-| S5 — the join POST succeeded and the user is now a trip member.
-}
joinSucceeded : String
joinSucceeded =
    "join_succeeded"


{-| S1 — the `/invite/resolve` teaser fetch returned a success response.
-}
nestPreviewViewed : String
nestPreviewViewed =
    "nest_preview_viewed"


{-| S3 — the guest receipt scan returned parsed OCR data.
-}
scanTrySucceeded : String
scanTrySucceeded =
    "scan_try_succeeded"
