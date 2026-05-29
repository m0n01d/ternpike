module Data.NestPreview exposing
    ( NestPreview
    , decoder
    )

{-| The redacted teaser payload returned by `POST /invite/resolve` (§C of the
Nest invite funnel spec).

The server deliberately omits per-line amounts, merchant names, notes,
exact GPS coordinates, and member emails. Only aggregate statistics and
metadata are included so a prospective member gets a genuine value preview
without exposing the trip's full ledger.

Full ledger data (`Data.Expense`, `Data.Amendment`, `Data.Void`) arrives only
after joining the shared trip inside `AuthModel`.

-}

import Data.DateField
import Data.GuestPreviewGate
import Data.Money
import Json.Decode
import Json.Decode.Pipeline as Pipeline


{-| Redacted teaser for a shared trip, decoded from the `/invite/resolve`
200 response body. Fields are alphabetized per repo style guide.
-}
type alias NestPreview =
    { dayCount : Int
    , endDate : Data.DateField.DateField
    , entryCount : Int
    , gate : Data.GuestPreviewGate.GuestPreviewGate
    , inviterName : String
    , memberCount : Int
    , startDate : Data.DateField.DateField
    , totalSpent : Data.Money.Money
    , tripName : String
    }


{-| Decode a `NestPreview` from the `/invite/resolve` 200 response body.

Wire shape (§C of `docs/nest-invite-funnel.md`):

    {
      "ok": true,
      "gate": "view_scan_preview",
      "tripName": "Honeymoon",
      "inviterName": "Alice",
      "totalSpent": 1234.56,
      "entryCount": 18,
      "dayCount": 6,
      "startDate": "2026-05-21",
      "endDate": "2026-05-27",
      "memberCount": 2
    }

`totalSpent` reuses `Data.Money.decoder` (reads `Float` dollars → `Money` cents).
`startDate` / `endDate` reuse `Data.DateField.decoder` (reads `"YYYY-MM-DD"` string).
`gate` reuses `Data.GuestPreviewGate.decoder` (unknown strings → `ViewOnly`).

-}
decoder : Json.Decode.Decoder NestPreview
decoder =
    Json.Decode.succeed NestPreview
        |> Pipeline.required "dayCount" Json.Decode.int
        |> Pipeline.required "endDate" Data.DateField.decoder
        |> Pipeline.required "entryCount" Json.Decode.int
        |> Pipeline.required "gate" Data.GuestPreviewGate.decoder
        |> Pipeline.required "inviterName" Json.Decode.string
        |> Pipeline.required "memberCount" Json.Decode.int
        |> Pipeline.required "startDate" Data.DateField.decoder
        |> Pipeline.required "totalSpent" Data.Money.decoder
        |> Pipeline.required "tripName" Json.Decode.string
