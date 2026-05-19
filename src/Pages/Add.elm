module Pages.Add exposing (viewAddTab)

import Data.Category as Category exposing (Category(..))
import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Types exposing (..)
import UI.Layout exposing (formField, sectionHead, textInputStyle)
import Helpers exposing (formatCoord)


viewAddTab : AuthState -> Html Msg
viewAddTab model =
    let
        p =
            model.pendingEntry

        isEditing =
            model.editingEntry /= Nothing
    in
    div [ style "padding" "24px 20px" ]
        [ div
            [ style "display" "flex"
            , style "align-items" "center"
            , style "justify-content" "space-between"
            , style "margin-bottom" "20px"
            ]
            [ h2 [ sectionHead ]
                [ text
                    (if isEditing then
                        "EDIT EXPENSE"

                     else if model.activeScanItemId /= Nothing then
                        "REVIEW SCAN"

                     else
                        "ADD EXPENSE"
                    )
                ]
            , if model.activeScanItemId /= Nothing then
                button
                    [ onClick BackToQueue
                    , class "bg-transparent border-none text-[#7a8a80] text-sm cursor-pointer p-1 font-[inherit]"
                    ]
                    [ text "← queue" ]

              else if isEditing then
                button
                    [ onClick CancelEdit
                    , class "bg-transparent border-none text-[#7a8a80] text-sm cursor-pointer p-1 font-[inherit]"
                    ]
                    [ text "← cancel" ]

              else
                text ""
            ]
        , case model.activeScanItemId of
            Nothing ->
                text ""

            Just id ->
                case Dict.get id model.scanQueue of
                    Just item ->
                        img
                            [ src item.imageUrl
                            , class "w-full rounded-xl object-contain mb-4"
                            , style "max-height" "240px"
                            , style "background" "#1a2420"
                            ]
                            []

                    Nothing ->
                        text ""
        , formField "AMOUNT"
            (div [ style "position" "relative" ]
                [ span
                    [ style "position" "absolute"
                    , style "left" "14px"
                    , style "top" "50%"
                    , style "transform" "translateY(-50%)"
                    , style "color" "#e8a020"
                    , style "font-size" "20px"
                    , style "font-family" "monospace"
                    ]
                    [ text "$" ]
                , input
                    [ type_ "number"
                    , attribute "inputmode" "decimal"
                    , value p.amount
                    , onInput AmountChanged
                    , placeholder "0.00"
                    , style "width" "100%"
                    , style "background" "#1e2220"
                    , style "border" "1px solid #3a4240"
                    , style "color" "#c8d0c8"
                    , style "border-radius" "8px"
                    , style "padding" "16px 14px 16px 36px"
                    , style "font-size" "24px"
                    , style "font-family" "monospace"
                    ]
                    []
                ]
            )
        , formField "CATEGORY"
            (div [ class "grid grid-cols-4 gap-2" ]
                (List.map (viewCategoryBtn p.category) Category.all)
            )
        , formField "NOTE"
            (input
                [ type_ "text"
                , value p.note
                , onInput NoteChanged
                , placeholder "brief (50 chars)"
                , attribute "maxlength" "50"
                , textInputStyle
                ]
                []
            )
        , formField "DETAILS"
            (textarea
                [ value p.longNote
                , onInput LongNoteChanged
                , placeholder "optional — what happened, where, any context (280 chars)"
                , attribute "maxlength" "280"
                , attribute "rows" "3"
                , class "w-full p-3 bg-[#1e2220] border border-[#3a4240] text-[#c8d0c8] rounded-lg font-[inherit] text-base resize-none leading-snug"
                , style "outline" "none"
                ]
                []
            )
        , formField "MERCHANT"
            (input
                [ type_ "text"
                , value p.merchant
                , onInput MerchantChanged
                , placeholder "optional"
                , textInputStyle
                ]
                []
            )
        , formField "DATE"
            (input
                [ type_ "date"
                , value p.date
                , onInput DateChanged
                , textInputStyle
                ]
                []
            )
        , viewLocationWidget model
        , button
            [ onClick SubmitEntry
            , disabled model.submitting
            , style "width" "100%"
            , style "background" "#e8a020"
            , style "color" "#0d0f0e"
            , style "border" "none"
            , style "border-radius" "8px"
            , style "padding" "18px"
            , style "font-size" "18px"
            , style "font-weight" "700"
            , style "letter-spacing" "0.05em"
            , style "cursor" (if model.submitting then "not-allowed" else "pointer")
            , style "margin-top" "8px"
            , style "min-height" "56px"
            , style "opacity" (if model.submitting then "0.6" else "1")
            ]
            [ text
                (if model.submitting then
                    "SAVING..."

                 else if isEditing then
                    "UPDATE EXPENSE"

                 else
                    "SAVE EXPENSE"
                )
            ]
        ]


viewCategoryBtn : Category -> Category -> Html Msg
viewCategoryBtn selected cat =
    let
        active =
            selected == cat
    in
    button
        [ onClick (CategorySelected cat)
        , style "background" (if active then Category.color cat else "#1e2220")
        , style "color" (if active then "#0d0f0e" else "#c8d0c8")
        , style "border" ("1px solid " ++ (if active then Category.color cat else "#3a4240"))
        , style "border-radius" "8px"
        , style "padding" "12px 8px"
        , style "font-size" "14px"
        , style "font-weight" (if active then "700" else "400")
        , style "cursor" "pointer"
        , style "display" "flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "gap" "4px"
        , style "min-height" "64px"
        ]
        [ span [ style "font-size" "20px" ] [ text (Category.icon cat) ]
        , text (Category.label cat)
        ]


viewLocationWidget : AuthState -> Html Msg
viewLocationWidget model =
    div [ style "margin-bottom" "16px" ]
        [ viewLocationStatus model.pendingEntry.locationState
        , if model.showMapPicker then
            Html.node "map-picker"
                [ attribute "lat"
                    (case model.pendingEntry.locationState of
                        LocationGot la _ _ ->
                            String.fromFloat la

                        _ ->
                            "64.2008"
                    )
                , attribute "lon"
                    (case model.pendingEntry.locationState of
                        LocationGot _ lo _ ->
                            String.fromFloat lo

                        _ ->
                            "-153.4937"
                    )
                , on "confirm"
                    (D.map2 MapPickerConfirmed
                        (D.at [ "detail", "lat" ] D.float)
                        (D.at [ "detail", "lon" ] D.float)
                    )
                , on "dismiss" (D.succeed DismissMapPicker)
                ]
                []

          else
            text ""
        ]


viewLocationStatus : LocationState -> Html Msg
viewLocationStatus ls =
    case ls of
        LocationFetching ->
            div
                [ style "color" "#4a5a50"
                , style "font-size" "13px"
                , style "padding" "8px 0"
                ]
                [ text "📍 Getting location…" ]

        LocationCheckingExif ->
            div [ class "text-[#4a5a50] text-sm py-2" ]
                [ text "📍 Reading photo…" ]

        LocationNoExifGps ->
            div [ class "flex items-center gap-3 py-2" ]
                [ span [ class "text-[#4a5a50] text-sm" ] [ text "No GPS in photo" ]
                , button [ onClick OpenMapPicker
                         , class "bg-transparent border-none text-[#4a5a50] text-xs cursor-pointer p-0 font-[inherit]" ]
                    [ text "pin manually" ]
                ]

        LocationGot lat lon source ->
            let
                sourceLabel =
                    case source of
                        ExifGps    -> "📍 from photo"
                        BrowserGeo -> "📍 GPS"
                        ManualPin  -> "📍 pinned"
            in
            div [ class "flex items-center gap-3 py-2" ]
                [ span [ class "text-[#4090e0] text-sm" ]
                    [ text (sourceLabel ++ " — " ++ formatCoord lat lon) ]
                , button
                    [ onClick OpenMapPicker
                    , class "bg-transparent border-none text-[#4a5a50] text-xs cursor-pointer p-0 font-[inherit]"
                    ]
                    [ text "adjust" ]
                , button
                    [ onClick SkipLocation
                    , class "bg-transparent border-none text-[#4a5a50] text-xs cursor-pointer p-0 font-[inherit]"
                    ]
                    [ text "remove" ]
                ]

        LocationSkipped ->
            div
                [ style "display" "flex"
                , style "align-items" "center"
                , style "gap" "12px"
                , style "padding" "8px 0"
                ]
                [ span [ style "color" "#4a5a50", style "font-size" "13px" ] [ text "no location" ]
                , button
                    [ onClick OpenMapPicker
                    , style "background" "none"
                    , style "border" "none"
                    , style "color" "#4a5a50"
                    , style "font-size" "12px"
                    , style "cursor" "pointer"
                    , style "padding" "0"
                    , style "font-family" "inherit"
                    ]
                    [ text "pin manually" ]
                ]

        LocationIdle ->
            div
                [ style "display" "flex"
                , style "gap" "12px"
                , style "align-items" "center"
                ]
                [ button
                    [ onClick OpenMapPicker
                    , style "background" "#1e2220"
                    , style "border" "1px solid #3a4240"
                    , style "color" "#c8d0c8"
                    , style "border-radius" "8px"
                    , style "padding" "12px 16px"
                    , style "font-size" "14px"
                    , style "cursor" "pointer"
                    , style "flex" "1"
                    , style "font-family" "inherit"
                    ]
                    [ text "📍 Pin manually" ]
                , button
                    [ onClick SkipLocation
                    , style "background" "none"
                    , style "border" "none"
                    , style "color" "#4a5a50"
                    , style "font-size" "13px"
                    , style "cursor" "pointer"
                    , style "padding" "8px"
                    , style "font-family" "inherit"
                    ]
                    [ text "Skip location" ]
                ]
