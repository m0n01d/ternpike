module Pages.Scan exposing (viewScanTab)

import Data.Category as Category
import Dict
import File exposing (File)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Types exposing (..)
import UI.Layout exposing (sectionHead)


viewScanTab : AuthState -> Html Msg
viewScanTab model =
    Html.div [ Html.Attributes.class "px-5 pt-6 pb-4" ]
        [ Html.h2 [ sectionHead ] [ Html.text "SCAN RECEIPTS" ]
        , Html.label
            [ Html.Attributes.class "flex flex-col items-center justify-center bg-cream border-2 border-dashed border-tan rounded-xl py-10 px-6 cursor-pointer mb-5" ]
            [ Html.div [ Html.Attributes.class "text-5xl mb-3" ] [ Html.text "📷" ]
            , Html.p [ Html.Attributes.class "text-muted text-base text-center" ] [ Html.text "Tap to add photos" ]
            , Html.p [ Html.Attributes.class "text-moss text-xs mt-1 text-center" ] [ Html.text "Select multiple for batch upload" ]
            , Html.input
                [ Html.Attributes.type_ "file"
                , Html.Attributes.accept "image/*"
                , Html.Attributes.attribute "multiple" "true"
                , Html.Attributes.class "hidden"
                , Html.Events.on "change" (Json.Decode.map FilesSelected (Json.Decode.at [ "target", "files" ] fileListDecoder))
                ]
                []
            ]
        , if Dict.isEmpty model.scanQueue then
            Html.button
                [ Html.Events.onClick (TabChanged AddTab)
                , Html.Attributes.class "w-full py-3.5 rounded-lg border border-tan text-muted text-sm cursor-pointer bg-transparent"
                ]
                [ Html.text "Fill in manually →" ]

          else
            Html.div []
                [ Html.div [ Html.Attributes.class "grid grid-cols-2 gap-3 mb-4" ]
                    (Dict.values model.scanQueue |> List.map viewScanCard)
                , if Dict.values model.scanQueue |> List.any (\i -> i.status == ScanSubmitted) then
                    Html.button
                        [ Html.Events.onClick ClearDoneItems
                        , Html.Attributes.class "w-full py-2 rounded-lg border border-tan text-moss text-xs cursor-pointer bg-transparent mb-4"
                        ]
                        [ Html.text "Clear submitted" ]

                  else
                    Html.text ""
                , let
                    debugItems =
                        Dict.values model.scanQueue |> List.filter (\i -> i.exifDebug /= "")
                  in
                  if List.isEmpty debugItems then
                    Html.text ""

                  else
                    Html.div [ Html.Attributes.class "mt-2" ]
                        (List.indexedMap
                            (\idx item ->
                                Html.div [ Html.Attributes.class "mb-3 rounded-lg bg-cream p-3" ]
                                    [ Html.div [ Html.Attributes.class "text-moss text-xs mb-1" ]
                                        [ Html.text ("EXIF dump — photo " ++ String.fromInt (idx + 1)) ]
                                    , Html.div
                                        [ Html.Attributes.class "font-mono text-[10px] text-muted break-all whitespace-pre-wrap max-h-40 overflow-y-auto" ]
                                        [ Html.text item.exifDebug ]
                                    ]
                            )
                            debugItems
                        )
                ]
        ]


viewScanCard : ScanItem -> Html Msg
viewScanCard item =
    Html.div [ Html.Attributes.class "bg-cream rounded-xl overflow-hidden" ]
        [ if item.imageUrl /= "" then
            Html.img [ Html.Attributes.src item.imageUrl, Html.Attributes.class "w-full h-28 object-cover" ] []

          else
            Html.div [ Html.Attributes.class "w-full h-28 bg-[#ebe5d4] flex items-center justify-center text-3xl text-tan" ]
                [ Html.text "📷" ]
        , Html.div [ Html.Attributes.class "p-2" ]
            [ viewScanCardStatus item ]
        ]


viewScanCardStatus : ScanItem -> Html Msg
viewScanCardStatus item =
    case item.status of
        ScanQueued ->
            Html.div [ Html.Attributes.class "text-moss text-xs py-1" ] [ Html.text "Queued…" ]

        ScanProcessing ->
            Html.div [ Html.Attributes.class "text-rust text-xs py-1" ] [ Html.text "⏳ Reading…" ]

        ScanReady ->
            Html.div []
                [ case item.ocrData of
                    Just ocr ->
                        Html.div [ Html.Attributes.class "mb-2" ]
                            [ Html.div [ Html.Attributes.class "text-rust font-mono text-sm font-bold" ]
                                [ Html.text (ocr.amount |> Maybe.map (\a -> "$" ++ String.fromFloat a) |> Maybe.withDefault "—") ]
                            , Html.div [ Html.Attributes.class "text-muted text-xs truncate" ]
                                [ Html.text
                                    (ocr.merchant
                                        |> Maybe.withDefault
                                            (ocr.category |> Maybe.map Category.label |> Maybe.withDefault "receipt")
                                    )
                                ]
                            ]

                    Nothing ->
                        Html.div [ Html.Attributes.class "text-muted text-xs mb-2" ] [ Html.text "Fill manually" ]
                , Html.button
                    [ Html.Events.onClick (ReviewScanItem item.id)
                    , Html.Attributes.class "w-full py-1.5 rounded-lg bg-rust text-parchment text-xs font-bold cursor-pointer border-none"
                    ]
                    [ Html.text "Review →" ]
                ]

        ScanSubmitted ->
            Html.div [ Html.Attributes.class "text-moss text-xs text-center py-1" ] [ Html.text "✓ Submitted" ]


fileListDecoder : Json.Decode.Decoder (List File)
fileListDecoder =
    Json.Decode.field "length" Json.Decode.int
        |> Json.Decode.andThen
            (\n ->
                List.range 0 (n - 1)
                    |> List.map (\i -> Json.Decode.field (String.fromInt i) File.decoder)
                    |> List.foldr (Json.Decode.map2 (::)) (Json.Decode.succeed [])
            )
