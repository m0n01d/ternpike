module Data.Location exposing (LocationSource(..), LocationState(..))

{-| State machine for where an expense's lat/lon comes from.

Four sources feed the location field, in this order of preference:

1.  EXIF GPS embedded in the receipt photo — captured at the moment the
    receipt was taken, so it's the most accurate.
2.  Server geocode of the OCR-extracted merchant address — paid tier
    only (#152). Wins over browser geo / manual when EXIF is absent;
    EXIF always trumps it.
3.  Browser geolocation — fired when the user lands on the Add tab.
4.  Manual map pin — the fallback when the others miss or the user
    wants to correct them.

`LocationState` models the lifecycle of trying those sources in turn.
The Add page and the Scan queue both reuse this type — see
`Data.PendingEntry.PendingEntry.locationState` and
`Data.Scan.ScanItem.locationState`.

-}

import Data.GeoPoint exposing (GeoPoint)


{-| Where the captured lat/lon came from. Surfaced in the UI as a small
provenance label ("from photo", "GPS", "from address", "pinned") so the
user knows whether to trust it.

`Geocoded` is set when the paid-tier `POST /geocode` Worker endpoint
resolved an OCR'd merchant address to coordinates. The client-side
handler only promotes a `ScanItem` to `Geocoded` when no EXIF source is
already present — EXIF wins over geocode.

-}
type LocationSource
    = BrowserGeo
    | ExifGps
    | Geocoded
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
