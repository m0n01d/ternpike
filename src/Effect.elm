module Effect exposing (Effect(..), perform)

{-| The `Effect` seam for `Page.Scan` (#369).

`Page.Scan.update` returns a description of the side effects it wants
(`Effect`) rather than an opaque `Cmd Types.Msg`. The production runtime
interprets that description with [`perform`](#perform); tests interpret it
with `simulate` (in `tests/PageScanEffectTest.elm`, which mirrors
`perform` effect-for-effect) so the stateful offline-scan flows become
drivable under `avh4/elm-program-test`.

`simulate` lives in the test tree rather than here because
`avh4/elm-program-test` is a _test_ dependency — importing its
`SimulatedEffect.*` modules from `src/` would drag the whole test harness
into the production build. The `Effect(..)` constructors are exposed so
the test-side interpreter can pattern-match them.

`Effect` carries no `Nav.Key` (the key cannot be hand-constructed, which
is the whole reason `AuthState` resisted being driven under test).
`perform` takes the runtime `Nav.Key` as its first argument; `simulate`
needs none.

Only the variants with a real construction site in `Page.Scan.update`
live here (`NoUnused.CustomTypeConstructors` requires a caller per
variant). Persistence/merge effects (`SaveScanItem`, `DeleteScanItem`,
`MintIdsThen`) arrive with their callers in later issues.

@docs Effect, perform

-}

import Browser.Navigation as Nav
import Data.AnthropicKey as AnthropicKey exposing (AnthropicKey)
import Data.Auth exposing (Creds)
import Data.OcrPath exposing (OcrPath(..))
import File exposing (File)
import Http
import Http.GeocodeApi
import Json.Decode
import Json.Encode
import Msg.Scan
import Ports
import Task
import Types


{-| A description of the side effects `Page.Scan.update` wants performed.

  - `Batch` — run several effects (mirrors `Cmd.batch`).
  - `ExtractExifGps` — outbound port: pull EXIF GPS for a queued image.
  - `FetchFileUrl` — `File.toUrl` task, tagged back as `GotFileUrl`.
  - `Geocode` — `POST /geocode` for an OCR-extracted address.
  - `MakeOcrCall` — the OCR request: direct Anthropic HTTP (`ByoPath`),
    the hosted proxy port (`HostedPath`), or nothing (`Unscannable`).
  - `Navigate` — `Nav.pushUrl` to a new route (the `BackToQueue` path).
  - `NoEffect` — do nothing (mirrors `Cmd.none`).
  - `PrepareOcrImage` — outbound port: downscale an image before OCR.

-}
type Effect
    = Batch (List Effect)
    | ExtractExifGps { dataUrl : String, id : String }
    | FetchFileUrl String File
    | Geocode Creds String String
    | MakeOcrCall { backendUrl : String, body : Json.Encode.Value, itemId : String, path : OcrPath }
    | Navigate String
    | NoEffect
    | PrepareOcrImage { dataUrl : String, id : String, maxBytes : Int }


{-| Interpret an `Effect` as the production `Cmd Types.Msg` it describes.
Takes the runtime `Nav.Key` for the navigation effect. This is the source
of truth for the wire behavior; the test-side `simulate` mirrors it.
-}
perform : Nav.Key -> Effect -> Cmd Types.Msg
perform key effect =
    case effect of
        Batch effects ->
            Cmd.batch (List.map (perform key) effects)

        ExtractExifGps payload ->
            Ports.extractExifGps payload

        FetchFileUrl itemId file ->
            Task.perform (scanMsg << Msg.Scan.GotFileUrl itemId) (File.toUrl file)

        Geocode creds itemId address ->
            Http.GeocodeApi.geocode creds { address = address } (scanMsg << Msg.Scan.GotGeocodeResult itemId)

        MakeOcrCall { backendUrl, body, itemId, path } ->
            case path of
                ByoPath byoKey ->
                    Http.request
                        { method = "POST"
                        , headers = anthropicHeaders byoKey
                        , url = anthropicUrl
                        , body = Http.jsonBody body
                        , expect = Http.expectStringResponse (scanMsg << Msg.Scan.GotOcrResult itemId) ocrResponseToResult
                        , timeout = Nothing
                        , tracker = Nothing
                        }

                HostedPath ->
                    Ports.scanProxyOut { backendUrl = backendUrl, body = body, itemId = itemId }

                Unscannable ->
                    Cmd.none

        Navigate url ->
            Nav.pushUrl key url

        NoEffect ->
            Cmd.none

        PrepareOcrImage payload ->
            Ports.prepareOcrImage payload



-- SHARED HELPERS (used by `perform` and the test-side `simulate`)


{-| The Anthropic `/v1/messages` endpoint. Exposed shape kept identical
between `perform` and the test interpreter via this single constant.
-}
anthropicUrl : String
anthropicUrl =
    "https://api.anthropic.com/v1/messages"


anthropicHeaders : AnthropicKey -> List Http.Header
anthropicHeaders key =
    [ Http.header "x-api-key" (AnthropicKey.toHeader key)
    , Http.header "anthropic-version" "2023-06-01"
    , Http.header "anthropic-dangerous-direct-browser-access" "true"
    ]


{-| Lift a `Msg.Scan.Msg` to the top-level `Types.Msg` the runtime
dispatches. Identical to the `Types.AuthMsg << Types.ScanMsg` chain the
raw Cmds used in #368.
-}
scanMsg : Msg.Scan.Msg -> Types.Msg
scanMsg m =
    Types.AuthMsg (Types.ScanMsg m)


{-| Convert an Anthropic HTTP response into a human-readable error string
or the raw success body. Shared by `perform` and the test-side `simulate`
so both interpret OCR responses identically (moved here from `Page.Scan`
in #369; formerly `Page.Scan.ocrResponseToResult`). Uses
`expectStringResponse` so non-2xx responses keep their body — Anthropic's
real error message lives there.
-}
ocrResponseToResult : Http.Response String -> Result String String
ocrResponseToResult response =
    case response of
        Http.BadUrl_ url ->
            Err ("Bad URL: " ++ url)

        Http.Timeout_ ->
            Err "OCR request timed out — try again"

        Http.NetworkError_ ->
            Err "Network error — check your connection and try again"

        Http.BadStatus_ meta body ->
            Err (formatAnthropicError meta.statusCode body)

        Http.GoodStatus_ _ body ->
            Ok body


formatAnthropicError : Int -> String -> String
formatAnthropicError status body =
    case Json.Decode.decodeString (Json.Decode.field "error" (Json.Decode.field "message" Json.Decode.string)) body of
        Ok msg ->
            "Anthropic error (HTTP " ++ String.fromInt status ++ "): " ++ msg

        Err _ ->
            "OCR request failed (HTTP " ++ String.fromInt status ++ ")"
