module Data.Location exposing (LocationSource(..), LocationState(..))

{-| State machine for where an expense's lat/lon comes from.

Three sources feed the location field, in this order of preference:

1.  EXIF GPS embedded in the receipt photo — captured at the moment the
    receipt was taken, so it's the most accurate.
2.  Browser geolocation — fired when the user lands on the Add tab.
3.  Manual map pin — the fallback when the first two miss or the user
    wants to correct them.

`LocationState` models the lifecycle of trying those sources in turn.
The Add page and the Scan queue both reuse this type — see
`Data.PendingEntry.PendingEntry.locationState` and
`Data.Scan.ScanItem.locationState`.

-}

import Data.GeoPoint exposing (GeoPoint)


{-| Where the captured lat/lon came from. Surfaced in the UI as a small
provenance label ("from photo", "GPS", "pinned") so the user knows
whether to trust it.
-}
type LocationSource
    = BrowserGeo
    | ExifGps
    | ManualPin


{-| Stages of the location lookup.

  - `LocationIdle` — nothing requested yet; the form shows "pin manually
    / skip" buttons.
  - `LocationCheckingExif` / `LocationFetching` — async work in flight
    (EXIF parse or browser geolocation).
  - `LocationNoExifGps` — EXIF returned no GPS; user can still pin.
  - `LocationGot point source` — terminal success state, ready to be
    stamped onto the expense. `point` is the resolved `GeoPoint`;
    "lat without lon" is no longer representable.
  - `LocationSkipped` — user explicitly opted out; don't keep retrying.

-}
type LocationState
    = LocationCheckingExif
    | LocationFetching
    | LocationGot GeoPoint LocationSource
    | LocationIdle
    | LocationNoExifGps
    | LocationSkipped
