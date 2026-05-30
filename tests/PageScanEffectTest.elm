module PageScanEffectTest exposing (suite)

{-| Program-test coverage for the `Page.Scan` `Effect` seam (#369).

Proves the seam works end-to-end: we drive the _real_
`Page.Scan.update` under `avh4/elm-program-test`, interpreting its
returned `Effect` with the test-side `simulate` (the mirror of the
production `Effect.perform`). The whole point of #F2 is that this is now
possible at all — `Page.Scan.update` takes a narrow `Page.Scan.Model`
slice rather than the full `AuthState`, so the seed state is
hand-constructible without a `Nav.Key`.

`simulate` lives here (not in `src/Effect.elm`) because
`avh4/elm-program-test` is a test-only dependency; importing its
`SimulatedEffect.*` modules from `src/` would drag the harness into the
production build.

-}

import Data.DateField as DateField exposing (DateField)
import Data.Navigation exposing (Route(..))
import Data.PendingEntry as PendingEntry exposing (PendingForm(..))
import Data.Scan exposing (ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Data.SharedTrips
import Data.Sync
import Data.Tier as Tier
import Data.TripId as TripId
import Data.Trips exposing (TripsState(..))
import Data.UserId as UserId
import Dict
import Effect exposing (Effect(..))
import Html exposing (Html)
import Html.Attributes
import Json.Decode
import Json.Encode
import Msg.Scan exposing (Msg(..))
import Page.Scan
import ProgramTest exposing (ProgramTest, SimulatedEffect)
import Set
import SimulatedEffect.Cmd
import SimulatedEffect.Http
import SimulatedEffect.Navigation
import SimulatedEffect.Ports
import SimulatedEffect.Task
import Test exposing (Test, describe, test)
import Test.Html.Selector
import Time
import Types



-- TEST-SIDE EFFECT INTERPRETER (mirror of Effect.perform)


{-| The `avh4/elm-program-test` twin of `Effect.perform`. Interprets each
`Effect` variant as a `SimulatedEffect Types.Msg`, mirroring the
production `Cmd`s effect-for-effect so the driven `update` exercises the
same branching the runtime would.
-}
simulate : Effect -> SimulatedEffect Types.Msg
simulate effect =
    case effect of
        Batch effects ->
            SimulatedEffect.Cmd.batch (List.map simulate effects)

        ExtractExifGps payload ->
            SimulatedEffect.Ports.send "extractExifGps"
                (Json.Encode.object
                    [ ( "dataUrl", Json.Encode.string payload.dataUrl )
                    , ( "id", Json.Encode.string payload.id )
                    ]
                )

        FetchFileUrl itemId _ ->
            SimulatedEffect.Task.perform (scanMsg << Msg.Scan.GotFileUrl itemId)
                (SimulatedEffect.Task.succeed "data:image/jpeg;base64,SIMULATED")

        Geocode _ itemId _ ->
            SimulatedEffect.Http.post
                { url = "https://api.ternpike.com/geocode"
                , body = SimulatedEffect.Http.emptyBody
                , expect =
                    SimulatedEffect.Http.expectJson
                        (scanMsg << Msg.Scan.GotGeocodeResult itemId)
                        geocodeResponseDecoder
                }

        MakeOcrCall { itemId } ->
            SimulatedEffect.Http.post
                { url = "https://api.anthropic.com/v1/messages"
                , body = SimulatedEffect.Http.emptyBody
                , expect =
                    SimulatedEffect.Http.expectString
                        (scanMsg << Msg.Scan.GotOcrResult itemId << Result.mapError (always "network"))
                }

        Navigate url ->
            SimulatedEffect.Navigation.pushUrl url

        NoEffect ->
            SimulatedEffect.Cmd.none

        PrepareOcrImage payload ->
            SimulatedEffect.Ports.send "prepareOcrImage"
                (Json.Encode.object
                    [ ( "dataUrl", Json.Encode.string payload.dataUrl )
                    , ( "id", Json.Encode.string payload.id )
                    , ( "maxBytes", Json.Encode.int payload.maxBytes )
                    ]
                )

        SaveScanItem value ->
            SimulatedEffect.Ports.send "saveScanItem" value

        StampCapture files ->
            SimulatedEffect.Task.perform
                (\now -> scanMsg (Msg.Scan.FilesStamped now files))
                (SimulatedEffect.Task.succeed (Time.millisToPosix 0))


geocodeResponseDecoder : Json.Decode.Decoder { lat : Maybe Float, lon : Maybe Float }
geocodeResponseDecoder =
    Json.Decode.map2 (\lat lon -> { lat = lat, lon = lon })
        (Json.Decode.maybe (Json.Decode.field "lat" Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field "lon" Json.Decode.float))


scanMsg : Msg.Scan.Msg -> Types.Msg
scanMsg m =
    Types.AuthMsg (Types.ScanMsg m)



-- MINIMAL VIEW (so the program is drivable; renders queue state to assert on)


view : Page.Scan.Model -> Html Types.Msg
view model =
    Html.ul []
        (model.scanQueue
            |> Dict.toList
            |> List.map viewItem
        )


viewItem : ( String, ScanItem ) -> Html Types.Msg
viewItem ( id, item ) =
    Html.li [ Html.Attributes.id id ]
        [ Html.span [] [ Html.text (statusLabel item.status) ]
        , Html.span [] [ Html.text (Maybe.withDefault "" item.ocrError) ]
        , Html.span [] [ Html.text (Maybe.withDefault "" (Maybe.andThen .merchant item.ocrData)) ]
        ]


statusLabel : ScanStatus -> String
statusLabel status =
    case status of
        ScanDeferred ->
            "deferred"

        ScanProcessing ->
            "processing"

        ScanQueued ->
            "queued"

        ScanReady ->
            "ready"

        ScanSubmitted ->
            "submitted"



-- SEED + DRIVER


seedDate : DateField
seedDate =
    DateField.today Time.utc (Time.millisToPosix 0)


seedModel : Page.Scan.Model
seedModel =
    { activeScanItemId = Nothing
    , basePath = "/"
    , config =
        { anthropicKey = Nothing
        , backendUrl = "https://api.ternpike.com"
        , vapidPublicKey = ""
        }
    , creds =
        { dbName = "ternpike"
        , email = "alice@example.com"
        , password = "pw"
        , subscriptionStatus = Nothing
        , tier = Tier.Tern
        , trailblazerNumber = Nothing
        }
    , currentUser = UserId.fromString "alice@example.com"
    , duplicateWarning = Nothing
    , error = Nothing
    , form = FreshForm (PendingEntry.defaultPendingEntry seedDate)
    , network = Data.Sync.Online
    , ocrInFlight = Set.empty
    , route = RouteScan (TripId.fromString "trip::2026-05-30::abc")
    , scanQueue = Dict.singleton "scan-0" processingItem
    , scanSeq = 0
    , sharedTrips = Data.SharedTrips.empty
    , storageAvailable = True
    , tier = Tier.Tern
    , today = seedDate
    , trips = NoTripsYet
    }


processingItem : ScanItem
processingItem =
    { draft = Nothing
    , exif = Data.Scan.ExifChecking
    , exifDebug = ""
    , expectedExpenseId = Nothing
    , geocode = Data.Scan.GeocodeNotAttempted
    , id = ScanItemId.fromString "scan-0"
    , imageUrl = "data:image/jpeg;base64,xxx"
    , lastError = Nothing
    , ocrData = Nothing
    , ocrError = Nothing
    , persistError = False
    , retryCount = 0
    , schemaVersion = Data.Scan.currentSchemaVersion
    , status = ScanProcessing
    }


start : ProgramTest Page.Scan.Model Types.Msg Effect
start =
    ProgramTest.createElement
        { init = \() -> ( seedModel, NoEffect )
        , update = programUpdate
        , view = view
        }
        |> ProgramTest.withSimulatedEffects simulate
        |> ProgramTest.start ()


{-| The program dispatches `Types.Msg`, but `Page.Scan.update` is keyed by
`Msg.Scan.Msg`. Unwrap the nested Scan message and run the _real_
`Page.Scan.update`; anything that isn't a Scan message is a no-op (the
test only ever sends Scan messages). This keeps the production code path
exact — no shim logic, just routing.
-}
programUpdate : Types.Msg -> Page.Scan.Model -> ( Page.Scan.Model, Effect )
programUpdate msg model =
    case msg of
        Types.AuthMsg (Types.ScanMsg scan) ->
            Page.Scan.update scan model

        _ ->
            ( model, NoEffect )


anthropicBody : String -> String
anthropicBody merchant =
    Json.Encode.encode 0
        (Json.Encode.object
            [ ( "content"
              , Json.Encode.list identity
                    [ Json.Encode.object
                        [ ( "text"
                          , Json.Encode.string
                                ("[{\"amount\": 12.5, \"category\": \"food\", \"merchant\": \""
                                    ++ merchant
                                    ++ "\", \"note\": \"lunch\"}]"
                                )
                          )
                        ]
                    ]
              )
            ]
        )


suite : Test
suite =
    describe "Page.Scan Effect seam (#369)"
        [ test "GotOcrResult Ok flips the queued item to ready with parsed OCR data" <|
            \() ->
                start
                    |> ProgramTest.update (scanMsg (GotOcrResult "scan-0" (Ok (anthropicBody "Denali Cafe"))))
                    |> ProgramTest.expectViewHas
                        [ Test.Html.Selector.tag "li"
                        , Test.Html.Selector.text "ready"
                        , Test.Html.Selector.text "Denali Cafe"
                        ]
        , test "GotOcrResult Err with a permanent (non-flap) reason surfaces it and marks ready" <|
            \() ->
                -- A parse/refusal error is terminal: retrying won't help, so
                -- the card goes to `ScanReady` with the error shown.
                start
                    |> ProgramTest.update (scanMsg (GotOcrResult "scan-0" (Err "Couldn't parse receipt JSON: bad token")))
                    |> ProgramTest.expectViewHas
                        [ Test.Html.Selector.tag "li"
                        , Test.Html.Selector.text "ready"
                        , Test.Html.Selector.text "Couldn't parse receipt JSON: bad token"
                        ]
        ]
