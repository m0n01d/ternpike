module Pages.Scan exposing (viewScanTab)

import Data.Category as Category
import Dict
import File exposing (File)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Types exposing (..)
import UI.Layout exposing (sectionHead)


viewScanTab : AuthState -> Html Msg
viewScanTab model =
    div [ class "px-5 pt-6 pb-4" ]
        [ h2 [ sectionHead ] [ text "SCAN RECEIPTS" ]
        , label [ class "flex flex-col items-center justify-center bg-[#1e2220] border-2 border-dashed border-[#3a4240] rounded-xl py-10 px-6 cursor-pointer mb-5" ]
            [ div [ class "text-5xl mb-3" ] [ text "📷" ]
            , p [ class "text-[#7a8a80] text-base text-center" ] [ text "Tap to add photos" ]
            , p [ class "text-[#4a5a50] text-xs mt-1 text-center" ] [ text "Select multiple for batch upload" ]
            , input
                [ type_ "file"
                , accept "image/*"
                , attribute "multiple" "true"
                , class "hidden"
                , on "change" (D.map FilesSelected (D.at [ "target", "files" ] fileListDecoder))
                ]
                []
            ]
        , if Dict.isEmpty model.scanQueue then
            button
                [ onClick (TabChanged AddTab)
                , class "w-full py-3.5 rounded-lg border border-[#3a4240] text-[#7a8a80] text-sm cursor-pointer bg-transparent font-[inherit]"
                ]
                [ text "Fill in manually →" ]

          else
            div []
                [ div [ class "grid grid-cols-2 gap-3 mb-4" ]
                    (Dict.values model.scanQueue |> List.map viewScanCard)
                , if Dict.values model.scanQueue |> List.any (\i -> i.status == ScanSubmitted) then
                    button
                        [ onClick ClearDoneItems
                        , class "w-full py-2 rounded-lg border border-[#3a4240] text-[#4a5a50] text-xs cursor-pointer bg-transparent font-[inherit] mb-4"
                        ]
                        [ text "Clear submitted" ]

                  else
                    text ""
                , let
                    debugItems =
                        Dict.values model.scanQueue |> List.filter (\i -> i.exifDebug /= "")
                  in
                  if List.isEmpty debugItems then
                    text ""

                  else
                    div [ class "mt-2" ]
                        (List.indexedMap
                            (\idx item ->
                                div [ class "mb-3 rounded-lg bg-[#161918] p-3" ]
                                    [ div [ class "text-[#4a5a50] text-xs mb-1" ]
                                        [ text ("EXIF dump — photo " ++ String.fromInt (idx + 1)) ]
                                    , div
                                        [ class "font-mono text-[10px] text-[#7a8a80] break-all whitespace-pre-wrap max-h-40 overflow-y-auto" ]
                                        [ text item.exifDebug ]
                                    ]
                            )
                            debugItems
                        )
                ]
        ]


viewScanCard : ScanItem -> Html Msg
viewScanCard item =
    div [ class "bg-[#161918] rounded-xl overflow-hidden" ]
        [ if item.imageUrl /= "" then
            img [ src item.imageUrl, class "w-full h-28 object-cover" ] []

          else
            div [ class "w-full h-28 bg-[#1e2220] flex items-center justify-center text-3xl text-[#3a4240]" ]
                [ text "📷" ]
        , div [ class "p-2" ]
            [ viewScanCardStatus item ]
        ]


viewScanCardStatus : ScanItem -> Html Msg
viewScanCardStatus item =
    case item.status of
        ScanQueued ->
            div [ class "text-[#4a5a50] text-xs py-1" ] [ text "Queued…" ]

        ScanProcessing ->
            div [ class "text-[#e8a020] text-xs py-1" ] [ text "⏳ Reading…" ]

        ScanReady ->
            div []
                [ case item.ocrData of
                    Just ocr ->
                        div [ class "mb-2" ]
                            [ div [ class "text-[#e8a020] font-mono text-sm font-bold" ]
                                [ text (ocr.amount |> Maybe.map (\a -> "$" ++ String.fromFloat a) |> Maybe.withDefault "—") ]
                            , div [ class "text-[#7a8a80] text-xs truncate" ]
                                [ text
                                    (ocr.merchant
                                        |> Maybe.withDefault
                                            (ocr.category |> Maybe.map Category.label |> Maybe.withDefault "receipt")
                                    )
                                ]
                            ]

                    Nothing ->
                        div [ class "text-[#7a8a80] text-xs mb-2" ] [ text "Fill manually" ]
                , button
                    [ onClick (ReviewScanItem item.id)
                    , class "w-full py-1.5 rounded-lg bg-[#e8a020] text-[#0d0f0e] text-xs font-bold cursor-pointer border-none font-[inherit]"
                    ]
                    [ text "Review →" ]
                ]

        ScanSubmitted ->
            div [ class "text-[#4a5a50] text-xs text-center py-1" ] [ text "✓ Submitted" ]


fileListDecoder : D.Decoder (List File)
fileListDecoder =
    D.field "length" D.int
        |> D.andThen
            (\n ->
                List.range 0 (n - 1)
                    |> List.map (\i -> D.field (String.fromInt i) File.decoder)
                    |> List.foldr (D.map2 (::)) (D.succeed [])
            )
