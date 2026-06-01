module Data.UserSettings exposing
    ( UserSettings
    , decoder
    , encoder
    )

{-| The per-user **settings singleton** — a single synced PouchDB document
holding cross-device preferences. Today it carries just the exchange-rate
table for the spend estimate (#448); it's the first synced-preference doc and
is shaped to grow (manual rate overrides, and eventually moving `colorScheme`
off device-local storage).

Unlike the collection docs (`expense::`, `amend::`, `trip::`), this is a
**singleton**: one well-known id (`user:settings`) updated in place. The
write path threads the doc's `_rev` exactly like the milepost-progress
singleton (`Data.MilepostProgress`) so repeated updates don't 409 — that
`_rev` lives on `AuthState`, not in this record, so the encoder here emits
the first-write shape and `Main` adds `_rev` on subsequent writes.

The encoder adds `"type": "userSettings"` so the live-changes feed in
`pouch.js` routes incoming docs to this decoder.

-}

import Data.DateField as DateField
import Data.ExchangeRate exposing (RateTable)
import Dict
import Json.Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode


{-| The synced settings doc. `exchangeRates` is the cached, auto-fetched FX
table (see `Data.ExchangeRate`).
-}
type alias UserSettings =
    { exchangeRates : RateTable }


{-| The fixed singleton document id.
-}
docId : String
docId =
    "user:settings"


{-| Decode the stored doc. `rates` is a lowercase-keyed object of
home-per-foreign factors; `ratesAsOf` is the ISO date they were published.
Both default to "absent" so a partial or legacy doc still loads.
-}
decoder : Json.Decode.Decoder UserSettings
decoder =
    Json.Decode.succeed (\rates asOf -> { exchangeRates = { asOf = asOf, rates = rates } })
        |> Pipeline.optional "rates" (Json.Decode.dict Json.Decode.float) Dict.empty
        |> Pipeline.optional "ratesAsOf" (Json.Decode.maybe DateField.decoder) Nothing


{-| Encode the doc (`_id`, `type`, `rates`, `ratesAsOf`), threading `_rev`
when given so an in-place update doesn't 409 (the milepost-singleton
pattern). Pass `Nothing` for the first write.
-}
encoder : Maybe String -> UserSettings -> Json.Encode.Value
encoder maybeRev settings =
    Json.Encode.object
        ([ ( "_id", Json.Encode.string docId )
         , ( "type", Json.Encode.string "userSettings" )
         , ( "rates", Json.Encode.dict identity Json.Encode.float settings.exchangeRates.rates )
         ]
            ++ (case maybeRev of
                    Just rev ->
                        [ ( "_rev", Json.Encode.string rev ) ]

                    Nothing ->
                        []
               )
            ++ (case settings.exchangeRates.asOf of
                    Just date ->
                        [ ( "ratesAsOf", DateField.encoder date ) ]

                    Nothing ->
                        []
               )
        )
