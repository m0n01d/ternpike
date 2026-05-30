module Pages.Scan exposing (viewTab)

import Data.AnthropicKey as AnthropicKey
import Data.Category as Category
import Data.Money as Money
import Data.Navigation exposing (Tab(..))
import Data.OcrPath as OcrPath exposing (OcrPath(..))
import Data.Scan exposing (DraftFields, OcrData, ScanItem, ScanStatus(..), needsReview)
import Data.ScanItemId as ScanItemId
import Data.SharedTrip exposing (SharedTrip)
import Data.SharedTrips
import Data.Sync
import Data.Trip as Trip exposing (Trip)
import Data.Trips
import Dict
import File exposing (File)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Extra
import Json.Decode
import List.Extra
import Msg.Scan
import Routing
import Types exposing (AuthMsg_(..), AuthState, Msg(..), SharedMsg_(..))
import UI.Button
import UI.DateView
import UI.Gate
import UI.Icons
import UI.MoneyView
import UI.SharedTripBadge


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
user's BYO Anthropic key (Tern). Inside a flock owned by a paid
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
                    Html.Extra.nothing

        _ ->
            Html.Extra.nothing


viewTierLabel : Trip -> AuthState -> Html Msg
viewTierLabel trip as_ =
    case OcrPath.resolve as_.config.anthropicKey as_.tier of
        ByoPath key ->
            -- Paid user with their own key: show key indicator + button to switch back to hosted
            Html.div [ Html.Attributes.class "mt-4 flex flex-col items-center gap-2" ]
                [ Html.p
                    [ Html.Attributes.class "text-center text-[11px] font-mono uppercase tracking-widest text-moss" ]
                    [ Html.text ("Using your key ···" ++ AnthropicKey.lastFour key) ]
                , UI.Gate.paidOnly as_.tier
                    { paidView =
                        Html.button
                            [ Html.Attributes.type_ "button"
                            , Html.Events.onClick (SharedMsg (ApiKeyChanged ""))
                            , Html.Attributes.class "text-[11px] font-mono uppercase tracking-widest text-muted underline underline-offset-2 cursor-pointer"
                            ]
                            [ Html.text "Switch to hosted key" ]
                    , upgradePrompt = Html.Extra.nothing
                    }
                ]

        HostedPath ->
            -- Paid user with no BYO key (hosted path): show hosted indicator + link to Settings to add own key
            Html.div [ Html.Attributes.class "mt-4 flex flex-col items-center gap-2" ]
                [ Html.p
                    [ Html.Attributes.class "text-center text-[11px] font-mono uppercase tracking-widest text-moss" ]
                    [ Html.text (paidOcrLabel trip as_) ]
                , Html.a
                    [ Html.Attributes.href (as_.basePath ++ "settings")
                    , Html.Attributes.class "text-[11px] font-mono uppercase tracking-widest text-muted underline underline-offset-2"
                    ]
                    [ Html.text "Use my own key →" ]
                ]

        Unscannable ->
            -- Tern user with no key: point them at Settings to add a key
            Html.p
                [ Html.Attributes.class "mt-4 text-center text-[11px] font-mono uppercase tracking-widest text-moss" ]
                [ Html.text "Add an Anthropic API key to scan" ]


paidOcrLabel : Trip -> AuthState -> String
paidOcrLabel trip as_ =
    if UI.Gate.requiresPaid (Trip.effectiveTier trip as_) && Trip.canBatchScan trip as_ then
        "Hosted OCR · parallel"

    else
        "Hosted OCR"


{-| The active trip's flock context, if any. `Nothing` for personal
trips and for trips whose flock meta hasn't synced yet.
-}
activeFlockContext : AuthState -> Maybe ( Trip, SharedTrip )
activeFlockContext model =
    case ( Routing.routeTripId model.route, model.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded loadedTrips ) ->
            case Data.Trips.findTrip tripId loadedTrips of
                Just trip ->
                    trip.flockId
                        |> Maybe.andThen (\fid -> Data.SharedTrips.get fid model.sharedTrips)
                        |> Maybe.map (\flock -> ( trip, flock ))

                Nothing ->
                    Nothing

        _ ->
            Nothing


{-| The "ADDING TO / Trip Name" strip at the top of the Scan screen.
Same pattern as `Pages.Add`; on personal trips the screen renders
without flock chrome.
-}
viewFlockContextStrip : Maybe ( Trip, SharedTrip ) -> Html Msg
viewFlockContextStrip ctx =
    Html.Extra.viewMaybe
        (\( trip, flock ) ->
            Html.div
                [ Html.Attributes.class "mb-4 flex items-center gap-3 bg-cream-deep border border-tan rounded-card px-4 py-3" ]
                [ UI.SharedTripBadge.view flock
                , Html.div [ Html.Attributes.class "flex flex-col leading-tight min-w-0" ]
                    [ Html.span
                        [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss" ]
                        [ Html.text "Scanning into" ]
                    , Html.span
                        [ Html.Attributes.class "text-sm font-semibold text-forest truncate" ]
                        [ Html.text trip.name ]
                    ]
                ]
        )
        ctx


viewHero : AuthState -> Html Msg
viewHero as_ =
    if isActiveTripReadOnly as_ then
        -- The shared-trip read-only lock is a hard product constraint and
        -- wins over connectivity — never let capture proceed here.
        viewReadOnlyHero

    else if Data.Sync.isOffline as_.network then
        viewOfflineHero as_.storageAvailable

    else
        viewCaptureHero
            { copy = "Stack them up, or lay them out — Ternpike processes in parallel."
            , title = "Tap to add receipts"
            }


{-| The live capture dropzone — a `<label>` wrapping a hidden file input.
Shared by the online hero and the offline (deferred-capture) hero so the
file input stays wired the same way in both.
-}
viewCaptureHero : { copy : String, title : String } -> Html Msg
viewCaptureHero { copy, title } =
    Html.label
        [ Html.Attributes.class "block w-full py-12 px-6 text-center border-2 border-dashed border-tan rounded-card bg-cream-deep cursor-pointer hover:bg-tan/30 transition-colors" ]
        [ Html.div [ Html.Attributes.class "flex justify-center mb-3 text-moss" ]
            [ UI.Icons.camera "w-12 h-12" ]
        , Html.div [ Html.Attributes.class "font-display text-xl text-forest" ]
            [ Html.text title ]
        , Html.div [ Html.Attributes.class "mt-1 text-sm text-muted" ]
            [ Html.text copy ]
        , Html.input
            [ Html.Attributes.type_ "file"
            , Html.Attributes.accept "image/*"
            , Html.Attributes.attribute "multiple" "true"
            , Html.Attributes.class "hidden"
            , Html.Events.on "change" (Json.Decode.map (AuthMsg << ScanMsg << Msg.Scan.FilesSelected) (Json.Decode.at [ "target", "files" ] fileListDecoder))
            ]
            []
        ]


viewReadOnlyHero : Html Msg
viewReadOnlyHero =
    Html.div
        [ Html.Attributes.class "block w-full py-12 px-6 text-center border-2 border-dashed border-tan rounded-card bg-cream-deep opacity-70"
        , Html.Attributes.title "This shared trip is read-only."
        ]
        [ Html.div [ Html.Attributes.class "flex justify-center mb-3 text-muted" ]
            [ UI.Icons.camera "w-12 h-12" ]
        , Html.div [ Html.Attributes.class "font-display text-xl text-forest" ]
            [ Html.text "Scanning is paused" ]
        , Html.div [ Html.Attributes.class "mt-1 text-sm text-muted" ]
            [ Html.text "This shared trip is read-only while billing is sorted out." ]
        ]


{-| Mirror of the predicate used on Add / Ledger — single source of
truth lives in `Data.SharedTrip.isReadOnly`.
-}
isActiveTripReadOnly : AuthState -> Bool
isActiveTripReadOnly model =
    case ( Routing.routeTripId model.route, model.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded trips ) ->
            Data.Trips.findTrip tripId trips
                |> Maybe.andThen .flockId
                |> Maybe.andThen (\fid -> Data.SharedTrips.get fid model.sharedTrips)
                |> Maybe.map Data.SharedTrip.isReadOnly
                |> Maybe.withDefault False

        _ ->
            False


{-| Offline hero. With durable storage available, capture stays LIVE —
the receipt is saved and read once the network returns (the deferred
flow). Without it (Private Browsing / Lockdown Mode, from #371) we can't
honor the durability promise, so we refuse capture rather than silently
lose the image on reload.
-}
viewOfflineHero : Bool -> Html Msg
viewOfflineHero storageAvailable =
    if storageAvailable then
        viewCaptureHero
            { copy = "Snap now — we'll read it when you're back online."
            , title = "Tap to capture receipts"
            }

    else
        Html.div
            [ Html.Attributes.class "block w-full py-12 px-6 text-center border-2 border-dashed border-tan rounded-card bg-cream-deep opacity-70"
            , Html.Attributes.title "This browser mode can't save receipts offline."
            ]
            [ Html.div [ Html.Attributes.class "flex justify-center mb-3 text-muted" ]
                [ UI.Icons.camera "w-12 h-12" ]
            , Html.div [ Html.Attributes.class "font-display text-xl text-forest" ]
                [ Html.text "Can't save offline here" ]
            , Html.div [ Html.Attributes.class "mt-1 text-sm text-muted" ]
                [ Html.text "This browser mode can't store receipts. Reconnect, or turn off Private Browsing, to scan." ]
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

            needsReviewItem i =
                i.status == ScanReady && Maybe.map needsReview i.ocrData == Just True

            sortedItems =
                List.filter needsReviewItem items ++ List.Extra.removeWhen needsReviewItem items

            hasSubmitted =
                List.any (\i -> i.status == ScanSubmitted) items

            debugItems =
                List.filter (\i -> i.exifDebug /= "") items
        in
        Html.div []
            [ Html.div [ Html.Attributes.class "flex flex-col gap-3 mb-4" ]
                (List.map viewScanCard sortedItems)
            , Html.Extra.viewIf hasSubmitted <|
                Html.div [ Html.Attributes.class "mb-4 flex justify-center" ]
                    [ UI.Button.ghost { label = "Clear submitted", onClick = AuthMsg (ScanMsg Msg.Scan.ClearDoneItems) } ]
            , Html.Extra.viewIf (not (List.isEmpty debugItems)) <|
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
    Html.div
        [ Html.Attributes.class "flex bg-cream rounded-xl overflow-hidden shadow-card" ]
        [ viewScanThumbnail item
        , Html.div [ Html.Attributes.class "flex-1 min-w-0 p-3" ]
            [ viewScanCardBody item ]
        ]


viewScanThumbnail : ScanItem -> Html Msg
viewScanThumbnail item =
    if item.imageUrl /= "" then
        Html.img
            [ Html.Attributes.src item.imageUrl
            , Html.Attributes.class "w-24 h-24 flex-shrink-0 object-cover"
            ]
            []

    else
        Html.div
            [ Html.Attributes.class "w-24 h-24 flex-shrink-0 bg-cream-deep flex items-center justify-center text-tan" ]
            [ UI.Icons.camera "w-8 h-8" ]


viewScanCardBody : ScanItem -> Html Msg
viewScanCardBody item =
    case item.status of
        ScanDeferred ->
            -- Captured offline; no OCR has run yet. The user can fill the
            -- fields by hand now via "Add details" (#372) — those edits
            -- persist to the item's draft and survive a reload. A draft
            -- summary shows when one exists so the card isn't blank.
            Html.div [ Html.Attributes.class "flex flex-col gap-2 h-full justify-center" ]
                [ Html.div [ Html.Attributes.class "text-moss text-xs" ] [ Html.text "Saved offline" ]
                , viewDeferredDraftSummary item.draft
                , viewDeferredButton item.id
                ]

        ScanQueued ->
            Html.div [ Html.Attributes.class "flex flex-col gap-2 h-full justify-center" ]
                [ Html.div [ Html.Attributes.class "text-moss text-xs" ] [ Html.text "Queued…" ]
                , viewProgressBar "w-1/4"
                ]

        ScanProcessing ->
            Html.div [ Html.Attributes.class "flex flex-col gap-2 h-full justify-center" ]
                [ Html.div [ Html.Attributes.class "text-rust text-xs" ] [ Html.text "Reading…" ]
                , viewSkeletonBars
                , viewProgressBar "w-2/3"
                ]

        ScanReady ->
            case item.ocrData of
                Just ocr ->
                    Html.div [ Html.Attributes.class "flex flex-col gap-1.5" ]
                        [ Html.Extra.viewIf (needsReview ocr) viewNeedsReviewBadge
                        , viewOcrSummary ocr
                        , viewReviewButton item.id
                        ]

                Nothing ->
                    Html.div [ Html.Attributes.class "flex flex-col gap-2" ]
                        [ viewOcrFailure item.ocrError
                        , viewReviewButton item.id
                        ]

        ScanSubmitted ->
            Html.div [ Html.Attributes.class "flex items-center h-full text-moss text-xs" ]
                [ Html.text "✓ Submitted"
                , Html.Extra.viewMaybe
                    (\date ->
                        Html.span
                            [ Html.Attributes.class "ml-2 text-muted" ]
                            [ Html.text "· "
                            , UI.DateView.monthDay date
                            ]
                    )
                    (Maybe.andThen .date item.ocrData)
                ]


{-| Badge shown on cards where the OCR result is missing amount,
merchant, or date. Signals that the user must fill in these fields
before the expense can be filed.
-}
viewNeedsReviewBadge : Html Msg
viewNeedsReviewBadge =
    Html.span
        [ Html.Attributes.class "self-start px-2 py-0.5 rounded-full bg-rust-tint border border-rust/30 text-[10px] uppercase tracking-wider text-rust font-mono" ]
        [ Html.text "Needs review" ]


{-| Render the "OCR didn't produce usable data" block on a Scan card.
Shows the captured failure reason when we have one (HTTP error,
unparseable model output, no receipts detected, etc.) so the user can
tell why they're being asked to fill the form manually instead of
guessing. Falls back to the generic message if no reason was captured.
-}
viewOcrFailure : Maybe String -> Html Msg
viewOcrFailure maybeReason =
    case maybeReason of
        Just reason ->
            Html.div [ Html.Attributes.class "flex flex-col gap-1" ]
                [ Html.div [ Html.Attributes.class "text-rust text-xs font-bold" ]
                    [ Html.text "OCR failed — fill manually" ]
                , Html.div [ Html.Attributes.class "text-muted text-xs italic whitespace-pre-wrap break-words" ]
                    [ Html.text reason ]
                ]

        Nothing ->
            Html.div [ Html.Attributes.class "text-rust text-xs italic" ]
                [ Html.text "OCR failed — fill manually" ]


viewReviewButton : ScanItemId.ScanItemId -> Html Msg
viewReviewButton id =
    Html.button
        [ Html.Events.onClick (AuthMsg (ScanMsg (Msg.Scan.ReviewScanItem (ScanItemId.toString id))))
        , Html.Attributes.class "self-start py-1.5 px-3 rounded-lg bg-rust text-parchment text-xs font-bold cursor-pointer border-none"
        ]
        [ Html.text "Review →" ]


{-| Offline-edit entry point on a deferred card. Reuses `ReviewScanItem`
to open the Add form pre-seeded from the item's draft; the label reads
"Add details" / "Edit details" depending on whether a draft exists yet.
-}
viewDeferredButton : ScanItemId.ScanItemId -> Html Msg
viewDeferredButton id =
    Html.button
        [ Html.Events.onClick (AuthMsg (ScanMsg (Msg.Scan.ReviewScanItem (ScanItemId.toString id))))
        , Html.Attributes.class "self-start py-1.5 px-3 rounded-lg border border-rust/40 text-rust text-xs font-bold cursor-pointer bg-transparent"
        ]
        [ Html.text "Add details →" ]


{-| Compact summary of a deferred item's typed draft (merchant, amount,
date), so a saved-offline card reflects what the user has already filled
in. Renders nothing until the user has set at least one field.
-}
viewDeferredDraftSummary : Maybe DraftFields -> Html Msg
viewDeferredDraftSummary maybeDraft =
    case maybeDraft of
        Nothing ->
            Html.Extra.nothing

        Just draft ->
            let
                merchantRow : Html Msg
                merchantRow =
                    Html.Extra.viewMaybe
                        (\m -> Html.div [ Html.Attributes.class "text-sm text-forest truncate" ] [ Html.text m ])
                        draft.merchant

                amountRow : Html Msg
                amountRow =
                    Html.Extra.viewMaybe
                        (\amt -> Html.div [ Html.Attributes.class "text-rust font-mono text-sm font-bold" ] [ UI.MoneyView.amount amt ])
                        (draft.amount |> Maybe.andThen Money.fromDollarString)

                dateRow : Html Msg
                dateRow =
                    Html.Extra.viewMaybe
                        (\date -> Html.div [ Html.Attributes.class "text-xs text-forest" ] [ Html.text "📅 ", UI.DateView.monthDay date ])
                        draft.date
            in
            Html.div [ Html.Attributes.class "flex flex-col gap-0.5" ]
                [ amountRow
                , merchantRow
                , dateRow
                ]


viewSkeletonBars : Html Msg
viewSkeletonBars =
    Html.div [ Html.Attributes.class "flex flex-col gap-1.5" ]
        [ Html.div [ Html.Attributes.class "h-3 w-1/2 bg-cream-deep rounded animate-pulse-soft" ] []
        , Html.div [ Html.Attributes.class "h-3 w-3/4 bg-cream-deep rounded animate-pulse-soft" ] []
        , Html.div [ Html.Attributes.class "h-3 w-1/3 bg-cream-deep rounded animate-pulse-soft" ] []
        ]


viewOcrSummary : OcrData -> Html Msg
viewOcrSummary ocr =
    let
        merchantLabel : Html Msg
        merchantLabel =
            case ocr.merchant of
                Just m ->
                    Html.div [ Html.Attributes.class "text-sm text-forest truncate" ]
                        [ Html.text m ]

                Nothing ->
                    Html.div [ Html.Attributes.class "text-sm text-muted italic truncate" ]
                        [ Html.text "Receipt" ]

        dateRow : Html Msg
        dateRow =
            case ocr.date of
                Just date ->
                    Html.div [ Html.Attributes.class "text-xs text-forest" ]
                        [ Html.text "📅 "
                        , UI.DateView.monthDay date
                        ]

                Nothing ->
                    Html.div [ Html.Attributes.class "text-xs text-muted italic" ]
                        [ Html.text "📅 Today · no date on receipt" ]

        addressRow : Html Msg
        addressRow =
            Html.Extra.viewMaybe
                (\addr ->
                    Html.div [ Html.Attributes.class "text-xs text-muted truncate" ]
                        [ Html.text ("📍 " ++ addr) ]
                )
                ocr.address
    in
    Html.div [ Html.Attributes.class "flex flex-col gap-1" ]
        [ Html.div [ Html.Attributes.class "flex items-baseline gap-2" ]
            [ Html.div [ Html.Attributes.class "text-rust font-mono text-base font-bold" ]
                [ case ocr.amount of
                    Just amt ->
                        UI.MoneyView.amount amt

                    Nothing ->
                        Html.text "—"
                ]
            , viewCategoryPill ocr.category
            ]
        , merchantLabel
        , dateRow
        , addressRow
        ]


viewCategoryPill : Maybe Category.Category -> Html Msg
viewCategoryPill maybeCat =
    Html.Extra.viewMaybe
        (\cat ->
            Html.span
                [ Html.Attributes.class "px-2 py-0.5 rounded-full bg-tan/40 text-[10px] uppercase tracking-wider text-forest font-mono" ]
                [ Html.text (Category.label cat) ]
        )
        maybeCat


viewProgressBar : String -> Html Msg
viewProgressBar widthClass =
    Html.div [ Html.Attributes.class "h-1 bg-cream-deep rounded-full overflow-hidden" ]
        [ Html.div
            [ Html.Attributes.class ("relative h-full bg-rust overflow-hidden transition-all duration-700 ease-out " ++ widthClass) ]
            [ Html.div
                [ Html.Attributes.class "absolute inset-0 bg-linear-to-r from-transparent via-parchment/60 to-transparent animate-scan-sweep" ]
                []
            ]
        ]


fileListDecoder : Json.Decode.Decoder (List File)
fileListDecoder =
    Json.Decode.field "length" Json.Decode.int
        |> Json.Decode.andThen
            (\n ->
                List.range 0 (n - 1)
                    |> List.map (\i -> Json.Decode.field (String.fromInt i) File.decoder)
                    |> List.foldr (Json.Decode.map2 (::)) (Json.Decode.succeed [])
            )
