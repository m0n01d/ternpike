module Data.Location exposing (LocationSource(..), LocationState(..))

{-| State machine for where an expense's lat/lon comes from.

Four sources feed the location field, in this order of preference:

1.  Server geocode of the OCR-extracted merchant address — paid tier
    only (#152). The receipt's printed address is the truth of where
    the _transaction_ happened. For a receipt-scanning app this is the
    most useful signal, even when EXIF GPS is also available — EXIF
    captures where the photo was _taken_, which for batch-scanned
    receipts is usually the user's kitchen, not the merchant.
2.  EXIF GPS embedded in the receipt photo — falls through when the
    receipt has no resolvable address (free tier, scan-time photo of a
    one-off vendor, or geocode miss).
3.  Browser geolocation — fired when the user lands on the Add tab,
    for manually-entered expenses.
4.  Manual map pin — the user's final say; trumps all of the above.

`LocationState` is the form-facing type displayed on the Add page. The
Scan queue tracks the underlying EXIF and geocode phases separately
(see `Data.Scan.ExifPhase` and `Data.Scan.GeocodePhase`) and projects
into a `LocationState` via `Data.Scan.effectiveLocation` when the user
opens a scanned item for review — that's where the priority above is
enforced.

-}

import Data.GeoPoint exposing (GeoPoint)


{-| Where the captured lat/lon came from. Surfaced in the UI as a small
provenance label ("from photo", "GPS", "from address", "pinned") so the
user knows whether to trust it.

`Geocoded` is set when the paid-tier `POST /geocode` Worker endpoint
resolved an OCR'd merchant address to coordinates — receipt-printed
address wins over EXIF (see module-level doc for priority).

-}
type LocationSource
    = BrowserGeo
    | ExifGps
    | Geocoded
    | ManualPin


{-| Stages of the location lookup.

  - `LocationIdle` — nothing requested yet; the form shows "pin manually
    / skip" buttons.
  - `LocationResolving` — async work in flight (EXIF parse, browser
    geolocation, or address geocode). Used for any "we're trying to
    figure out a location, don't show the manual prompt yet" state.
  - `LocationNoExifGps` — EXIF returned no GPS and no other source
    succeeded; user can still pin.
  - `LocationGot point source` — terminal success state, ready to be
    stamped onto the expense. `point` is the resolved `GeoPoint`;
    "lat without lon" is no longer representable.
  - `LocationSkipped` — user explicitly opted out; don't keep retrying.

-}
type LocationState
    = LocationGot GeoPoint LocationSource
    | LocationIdle
    | LocationNoExifGps
    | LocationResolving
    | LocationSkipped
