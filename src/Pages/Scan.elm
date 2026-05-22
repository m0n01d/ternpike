module Pages.Scan exposing (viewTab)

import Data.Category as Category
import Data.Flock exposing (Flock)
import Data.Flocks
import Data.Money as Money
import Data.Navigation exposing (Tab(..))
import Data.Scan exposing (OcrData, ScanItem, ScanStatus(..))
import Data.ScanItemId as ScanItemId
import Data.Tier
import Data.Trip as Trip exposing (Trip)
import Data.Trips
import Dict
import File exposing (File)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Routing
import Types exposing (AuthState, Msg(..))
import UI.Button
import UI.FlockBadge
import UI.Icons


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = []
    , body = viewBodyWithContext as_
    , hero = viewHero as_
    }


viewBodyWithContext : AuthState -> Html Msg
viewBodyWithContext as_ =
    Html.div []
        [ viewFlockContextStrip (activeFlockContext as_)
        , viewBody as_
        , viewTierAffordances as_
        ]


{-| Tier-derived footnote under the scan body — surfaces whether the
trip's scans go through the Ternpike-hosted proxy (paid) or the
user's BYO Anthropic key (Fledgling). Inside a flock owned by a paid
member, free members see the paid footnote because
`Trip.effectiveTier` resolves to the owner's tier (#61).
-}
viewTierAffordances : AuthState -> Html Msg
viewTierAffordances as_ =
    case ( Routing.routeTripId as_.route, as_.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded loadedTrips ) ->
            case Data.Trips.findTrip tripId loadedTrips of
                Just trip ->
                    viewTierLabel trip as_

                Nothing ->
                    Html.text ""

        _ ->
            Html.text ""


viewTierLabel : Trip -> AuthState -> Html Msg
viewTierLabel trip as_ =
    let
        label =
            -- `effectiveTier` is the source of truth for "how does this
            -- trip route OCR?"; the boolean wrappers below are cheap
            -- predicates over the same answer. Spelling out the case
            -- match (rather than collapsing to `if canUseProxiedOCR …`)
            -- forces the compiler to flag missing tiers when #19 adds
            -- more, and keeps the per-tier label easy to evolve.
            case Trip.effectiveTier trip as_ of
                Data.Tier.Fledgling ->
                    "BYO key"

                Data.Tier.Fly ->
                    paidOcrLabel trip as_

                Data.Tier.Trailblazer ->
                    paidOcrLabel trip as_
    in
    Html.p
        [ Html.Attributes.class "mt-4 text-center text-[11px] font-mono uppercase tracking-widest text-moss" ]
        [ Html.text label ]


paidOcrLabel : Trip -> AuthState -> String
paidOcrLabel trip as_ =
    if Trip.canUseProxiedOCR trip as_ && Trip.canBatchScan trip as_ then
        "Hosted OCR · parallel"

    else
        "Hosted OCR"


{-| The active trip's flock context, if any. `Nothing` for personal
trips and for trips whose flock meta hasn't synced yet.
-}
activeFlockContext : AuthState -> Maybe ( Trip, Flock )
activeFlockContext model =
    case ( Routing.routeTripId model.route, model.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded loadedTrips ) ->
            case Data.Trips.findTrip tripId loadedTrips of
                Just trip ->
                    trip.flockId
                        |> Maybe.andThen (\fid -> Data.Flocks.get fid model.flocks)
                        |> Maybe.map (\flock -> ( trip, flock ))

                Nothing ->
                    Nothing

        _ ->
            Nothing


{-| The "ADDING TO / Trip Name" strip at the top of the Scan screen.
Same pattern as `Pages.Add`; on personal trips the screen renders
without flock chrome.
-}
viewFlockContextStrip : Maybe ( Trip, Flock ) -> Html Msg
viewFlockContextStrip ctx =
    case ctx of
        Just ( trip, flock ) ->
            Html.div
                [ Html.Attributes.class "mb-4 flex items-center gap-3 bg-cream-deep border border-tan rounded-card px-4 py-3" ]
                [ UI.FlockBadge.view flock
                , Html.div [ Html.Attributes.class "flex flex-col leading-tight min-w-0" ]
                    [ Html.span
                        [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss" ]
                        [ Html.text "Scanning into" ]
                    , Html.span
                        [ Html.Attributes.class "text-sm font-semibold text-forest truncate" ]
                        [ Html.text trip.name ]
                    ]
                ]

        Nothing ->
            Html.text ""


viewHero : AuthState -> Html Msg
viewHero as_ =
    if as_.networkOffline then
        viewOfflineHero

    else if isActiveTripReadOnly as_ then
        viewReadOnlyHero

    else
        Html.label
            [ Html.Attributes.class "block w-full py-12 px-6 text-center border-2 border-dashed border-tan rounded-card bg-cream-deep cursor-pointer hover:bg-tan/30 transition-colors" ]
            [ Html.div [ Html.Attributes.class "flex justify-center mb-3 text-moss" ]
                [ UI.Icons.camera "w-12 h-12" ]
            , Html.div [ Html.Attributes.class "font-display text-xl text-forest" ]
                [ Html.text "Tap to add receipts" ]
            , Html.div [ Html.Attributes.class "mt-1 text-sm text-muted" ]
                [ Html.text "Stack them up, or lay them out — Ternpike processes in parallel." ]
            , Html.input
                [ Html.Attributes.type_ "file"
                , Html.Attributes.accept "image/*"
                , Html.Attributes.attribute "multiple" "true"
                , Html.Attributes.class "hidden"
                , Html.Events.on "change" (Json.Decode.map FilesSelected (Json.Decode.at [ "target", "files" ] fileListDecoder))
                ]
                []
            ]


viewReadOnlyHero : Html Msg
viewReadOnlyHero =
    Html.div
        [ Html.Attributes.class "block w-full py-12 px-6 text-center border-2 border-dashed border-tan rounded-card bg-cream-deep opacity-70"
        , Html.Attributes.title "This flock is read-only."
        ]
        [ Html.div [ Html.Attributes.class "flex justify-center mb-3 text-muted" ]
            [ UI.Icons.camera "w-12 h-12" ]
        , Html.div [ Html.Attributes.class "font-display text-xl text-forest" ]
            [ Html.text "Scanning is paused" ]
        , Html.div [ Html.Attributes.class "mt-1 text-sm text-muted" ]
            [ Html.text "This flock is read-only while billing is sorted out." ]
        ]


{-| Mirror of the predicate used on Add / Ledger — single source of
truth lives in `Data.Flock.isReadOnly`.
-}
isActiveTripReadOnly : AuthState -> Bool
isActiveTripReadOnly model =
    case ( Routing.routeTripId model.route, model.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded trips ) ->
            Data.Trips.findTrip tripId trips
                |> Maybe.andThen .flockId
                |> Maybe.andThen (\fid -> Data.Flocks.get fid model.flocks)
                |> Maybe.map Data.Flock.isReadOnly
                |> Maybe.withDefault False

        _ ->
            False


viewOfflineHero : Html Msg
viewOfflineHero =
    Html.div
        [ Html.Attributes.class "block w-full py-12 px-6 text-center border-2 border-dashed border-tan rounded-card bg-cream-deep opacity-70" ]
        [ Html.div [ Html.Attributes.class "flex justify-center mb-3 text-muted" ]
            [ UI.Icons.camera "w-12 h-12" ]
        , Html.div [ Html.Attributes.class "font-display text-xl text-forest" ]
            [ Html.text "Connect to scan receipts" ]
        , Html.div [ Html.Attributes.class "mt-1 text-sm text-muted" ]
            [ Html.text "Scanning needs the network. We'll be ready when you're back." ]
        ]


viewBody : AuthState -> Html Msg
viewBody model =
    if Dict.isEmpty model.scanQueue then
        Html.div [ Html.Attributes.class "py-8 text-center" ]
            [ Html.p [ Html.Attributes.class "font-display italic text-lg text-moss" ]
                [ Html.text "Stack's empty." ]
            , Html.p [ Html.Attributes.class "mt-1 text-sm text-muted" ]
                [ Html.text "Snap a receipt to begin." ]
            , Html.a
                [ Html.Attributes.href (Routing.pathForCurrentTab model AddTab)
                , Html.Attributes.class "mt-4 inline-block py-2 px-4 rounded-lg border border-tan text-muted text-sm cursor-pointer"
                ]
                [ Html.text "Fill in manually →" ]
            ]

    else
        let
            items =
                Dict.values model.scanQueue

            hasSubmitted =
                List.any (\i -> i.status == ScanSubmitted) items

            debugItems =
                List.filter (\i -> i.exifDebug /= "") items
        in
        Html.div []
            [ Html.div [ Html.Attributes.class "grid grid-cols-2 gap-3 mb-4" ]
                (List.map viewScanCard items)
            , if hasSubmitted then
                Html.div [ Html.Attributes.class "mb-4 flex justify-center" ]
                    [ UI.Button.ghost { label = "Clear submitted", onClick = ClearDoneItems } ]

              else
                Html.text ""
            , if List.isEmpty debugItems then
                Html.text ""

              else
                Html.details
                    [ Html.Attributes.class "mt-6 text-xs font-mono text-muted" ]
                    (Html.summary
                        [ Html.Attributes.class "cursor-pointer hover:text-forest" ]
                        [ Html.text "Show debug info" ]
                        :: List.indexedMap viewExifDebugBlock debugItems
                    )
            ]


viewExifDebugBlock : Int -> ScanItem -> Html Msg
viewExifDebugBlock idx item =
    Html.div [ Html.Attributes.class "mb-3 mt-2 rounded-lg bg-cream p-3" ]
        [ Html.div [ Html.Attributes.class "text-moss text-xs mb-1" ]
            [ Html.text ("EXIF dump — photo " ++ String.fromInt (idx + 1)) ]
        , Html.div
            [ Html.Attributes.class "font-mono text-[10px] text-muted break-all whitespace-pre-wrap max-h-40 overflow-y-auto" ]
            [ Html.text item.exifDebug ]
        ]


viewScanCard : ScanItem -> Html Msg
viewScanCard item =
    Html.div [ Html.Attributes.class "bg-cream rounded-xl overflow-hidden shadow-card" ]
        [ if item.imageUrl /= "" then
            Html.img [ Html.Attributes.src item.imageUrl, Html.Attributes.class "w-full h-28 object-cover" ] []

          else
            Html.div [ Html.Attributes.class "w-full h-28 bg-cream-deep flex items-center justify-center text-tan" ]
                [ UI.Icons.camera "w-8 h-8" ]
        , Html.div [ Html.Attributes.class "p-2" ]
            [ viewScanCardStatus item ]
        ]


viewScanCardStatus : ScanItem -> Html Msg
viewScanCardStatus item =
    case item.status of
        ScanQueued ->
            Html.div []
                [ Html.div [ Html.Attributes.class "text-moss text-xs mb-1.5" ] [ Html.text "Queued…" ]
                , viewProgressBar "w-1/4"
                ]

        ScanProcessing ->
            Html.div []
                [ Html.div [ Html.Attributes.class "text-rust text-xs mb-1.5" ] [ Html.text "Reading…" ]
                , viewProgressBar "w-2/3"
                ]

        ScanReady ->
            Html.div []
                [ case item.ocrData of
                    Just ocr ->
                        viewOcrSummary ocr

                    Nothing ->
                        Html.div [ Html.Attributes.class "text-muted text-xs mb-2" ] [ Html.text "Fill manually" ]
                , Html.button
                    [ Html.Events.onClick (ReviewScanItem (ScanItemId.toString item.id))
                    , Html.Attributes.class "w-full py-1.5 rounded-lg bg-rust text-parchment text-xs font-bold cursor-pointer border-none"
                    ]
                    [ Html.text "Review →" ]
                ]

        ScanSubmitted ->
            Html.div [ Html.Attributes.class "text-moss text-xs text-center py-1" ]
                [ Html.text "✓ Submitted" ]


viewOcrSummary : OcrData -> Html Msg
viewOcrSummary ocr =
    Html.div [ Html.Attributes.class "mb-2" ]
        [ Html.div [ Html.Attributes.class "text-rust font-mono text-sm font-bold" ]
            [ Html.text (ocr.amount |> Maybe.map Money.format |> Maybe.withDefault "—") ]
        , Html.div [ Html.Attributes.class "text-muted text-xs truncate" ]
            [ Html.text
                (ocr.merchant
                    |> Maybe.withDefault
                        (ocr.category |> Maybe.map Category.label |> Maybe.withDefault "receipt")
                )
            ]
        ]


viewProgressBar : String -> Html Msg
viewProgressBar widthClass =
    Html.div [ Html.Attributes.class "h-1 bg-cream-deep rounded-full overflow-hidden" ]
        [ Html.div [ Html.Attributes.class ("h-full bg-rust animate-pulse-soft " ++ widthClass) ] [] ]


fileListDecoder : Json.Decode.Decoder (List File)
fileListDecoder =
    Json.Decode.field "length" Json.Decode.int
        |> Json.Decode.andThen
            (\n ->
                List.range 0 (n - 1)
                    |> List.map (\i -> Json.Decode.field (String.fromInt i) File.decoder)
                    |> List.foldr (Json.Decode.map2 (::)) (Json.Decode.succeed [])
            )
