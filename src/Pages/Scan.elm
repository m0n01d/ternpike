module Pages.Scan exposing (viewTab)

import Data.Category as Category
import Dict
import File exposing (File)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Routing
import Types exposing (AuthState, Msg(..), OcrData, ScanItem, ScanStatus(..), Tab(..))
import UI.Button
import UI.Icons


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = []
    , body = viewBody as_
    , hero = viewHero
    }


viewHero : Html Msg
viewHero =
    Html.label
        [ Html.Attributes.class "block w-full py-12 px-6 text-center border-2 border-dashed border-tan rounded-card bg-cream-deep cursor-pointer hover:bg-tan/30 transition-colors" ]
        [ Html.div [ Html.Attributes.class "flex justify-center mb-3 text-moss" ]
            [ UI.Icons.camera "w-12 h-12" ]
        , Html.div [ Html.Attributes.class "font-display text-xl text-forest" ]
            [ Html.text "Tap to add receipts" ]
        , Html.div [ Html.Attributes.class "mt-1 text-sm text-muted" ]
            [ Html.text "Stack them up \u{2014} Ternpike processes in parallel." ]
        , Html.input
            [ Html.Attributes.type_ "file"
            , Html.Attributes.accept "image/*"
            , Html.Attributes.attribute "multiple" "true"
            , Html.Attributes.class "hidden"
            , Html.Events.on "change" (Json.Decode.map FilesSelected (Json.Decode.at [ "target", "files" ] fileListDecoder))
            ]
            []
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
                [ Html.text "Fill in manually \u{2192}" ]
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
            [ Html.text ("EXIF dump \u{2014} photo " ++ String.fromInt (idx + 1)) ]
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
                [ Html.div [ Html.Attributes.class "text-moss text-xs mb-1.5" ] [ Html.text "Queued\u{2026}" ]
                , viewProgressBar "w-1/4"
                ]

        ScanProcessing ->
            Html.div []
                [ Html.div [ Html.Attributes.class "text-rust text-xs mb-1.5" ] [ Html.text "Reading\u{2026}" ]
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
                    [ Html.Events.onClick (ReviewScanItem item.id)
                    , Html.Attributes.class "w-full py-1.5 rounded-lg bg-rust text-parchment text-xs font-bold cursor-pointer border-none"
                    ]
                    [ Html.text "Review \u{2192}" ]
                ]

        ScanSubmitted ->
            Html.div [ Html.Attributes.class "text-moss text-xs text-center py-1" ]
                [ Html.text "\u{2713} Submitted" ]


viewOcrSummary : OcrData -> Html Msg
viewOcrSummary ocr =
    Html.div [ Html.Attributes.class "mb-2" ]
        [ Html.div [ Html.Attributes.class "text-rust font-mono text-sm font-bold" ]
            [ Html.text (ocr.amount |> Maybe.map (\a -> "$" ++ String.fromFloat a) |> Maybe.withDefault "\u{2014}") ]
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
