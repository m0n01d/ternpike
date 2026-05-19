module Pages.Add exposing (viewTab)

import Data.Category as Category exposing (Category(..))
import Dict
import Helpers exposing (formatCoord)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Types exposing (..)
import UI.Layout


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = viewActions as_
    , body = viewBody as_
    , hero = viewHero as_
    }


viewActions : AuthState -> List (Html Msg)
viewActions model =
    if model.activeScanItemId /= Nothing then
        [ Html.button
            [ Html.Events.onClick BackToQueue
            , Html.Attributes.class "bg-transparent border-none text-muted text-sm cursor-pointer p-1"
            ]
            [ Html.text "← queue" ]
        ]

    else if model.editingEntry /= Nothing then
        [ Html.button
            [ Html.Events.onClick CancelEdit
            , Html.Attributes.class "bg-transparent border-none text-muted text-sm cursor-pointer p-1"
            ]
            [ Html.text "← cancel" ]
        ]

    else
        []


viewHero : AuthState -> Html Msg
viewHero model =
    Html.div [ Html.Attributes.class "relative" ]
        [ Html.span
            [ Html.Attributes.class "absolute left-3.5 top-1/2 -translate-y-1/2 text-rust text-xl font-mono pointer-events-none" ]
            [ Html.text "$" ]
        , Html.input
            [ Html.Attributes.type_ "number"
            , Html.Attributes.attribute "inputmode" "decimal"
            , Html.Attributes.value model.pendingEntry.amount
            , Html.Events.onInput AmountChanged
            , Html.Attributes.placeholder "0.00"
            , Html.Attributes.class "w-full pl-9 text-2xl font-mono bg-transparent border-tan"
            ]
            []
        ]


viewBody : AuthState -> Html Msg
viewBody model =
    let
        p =
            model.pendingEntry

        isEditing =
            model.editingEntry /= Nothing
    in
    Html.div []
        [ case model.activeScanItemId of
            Nothing ->
                Html.text ""

            Just id ->
                case Dict.get id model.scanQueue of
                    Just item ->
                        Html.img
                            [ Html.Attributes.src item.imageUrl
                            , Html.Attributes.class "w-full rounded-xl object-contain mb-4 max-h-60 bg-cream"
                            ]
                            []

                    Nothing ->
                        Html.text ""
        , UI.Layout.formField "CATEGORY"
            (Html.div [ Html.Attributes.class "grid grid-cols-4 gap-2" ]
                (List.map (viewCategoryBtn p.category) Category.all)
            )
        , UI.Layout.formField "NOTE"
            (Html.input
                [ Html.Attributes.type_ "text"
                , Html.Attributes.value p.note
                , Html.Events.onInput NoteChanged
                , Html.Attributes.placeholder "brief (50 chars)"
                , Html.Attributes.attribute "maxlength" "50"
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "DETAILS"
            (Html.textarea
                [ Html.Attributes.value p.longNote
                , Html.Events.onInput LongNoteChanged
                , Html.Attributes.placeholder "optional — what happened, where, any context (280 chars)"
                , Html.Attributes.attribute "maxlength" "280"
                , Html.Attributes.attribute "rows" "3"
                , Html.Attributes.class "w-full"
                ]
                []
            )
        , UI.Layout.formField "MERCHANT"
            (Html.input
                [ Html.Attributes.type_ "text"
                , Html.Attributes.value p.merchant
                , Html.Events.onInput MerchantChanged
                , Html.Attributes.placeholder "optional"
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "DATE"
            (Html.input
                [ Html.Attributes.type_ "date"
                , Html.Attributes.value p.date
                , Html.Events.onInput DateChanged
                , UI.Layout.textInputStyle
                ]
                []
            )
        , viewLocationWidget model
        , Html.button
            [ Html.Events.onClick SubmitEntry
            , Html.Attributes.disabled model.submitting
            , Html.Attributes.class
                ("w-full bg-rust text-parchment border-none rounded-lg py-[18px] text-lg font-bold tracking-wide cursor-pointer mt-2 min-h-[56px] "
                    ++ (if model.submitting then "opacity-60 cursor-not-allowed" else "")
                )
            ]
            [ Html.text
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
    Html.button
        [ Html.Events.onClick (CategorySelected cat)
        , Html.Attributes.class
            ("rounded-lg py-3 px-2 text-sm cursor-pointer flex flex-col items-center gap-1 min-h-[64px] text-ink "
                ++ (if active then "font-bold" else "border border-tan bg-cream")
            )
        -- dynamic color from data; cannot express as a Tailwind class
        , Html.Attributes.style "background" (if active then Category.color cat else "")
        , Html.Attributes.style "border-color" (if active then Category.color cat else "")
        ]
        [ Html.span [ Html.Attributes.class "text-xl leading-none" ] [ Html.text (Category.icon cat) ]
        , Html.text (Category.label cat)
        ]


viewLocationWidget : AuthState -> Html Msg
viewLocationWidget model =
    Html.div [ Html.Attributes.class "mb-4" ]
        [ viewLocationStatus model.pendingEntry.locationState
        , if model.showMapPicker then
            Html.node "map-picker"
                [ Html.Attributes.attribute "lat"
                    (case model.pendingEntry.locationState of
                        LocationGot la _ _ ->
                            String.fromFloat la

                        _ ->
                            "64.2008"
                    )
                , Html.Attributes.attribute "lon"
                    (case model.pendingEntry.locationState of
                        LocationGot _ lo _ ->
                            String.fromFloat lo

                        _ ->
                            "-153.4937"
                    )
                , Html.Events.on "confirm"
                    (Json.Decode.map2 MapPickerConfirmed
                        (Json.Decode.at [ "detail", "lat" ] Json.Decode.float)
                        (Json.Decode.at [ "detail", "lon" ] Json.Decode.float)
                    )
                , Html.Events.on "dismiss" (Json.Decode.succeed DismissMapPicker)
                ]
                []

          else
            Html.text ""
        ]


viewLocationStatus : LocationState -> Html Msg
viewLocationStatus ls =
    case ls of
        LocationFetching ->
            Html.div [ Html.Attributes.class "text-moss text-sm py-2" ]
                [ Html.text "📍 Getting location…" ]

        LocationCheckingExif ->
            Html.div [ Html.Attributes.class "text-moss text-sm py-2" ]
                [ Html.text "📍 Reading photo…" ]

        LocationNoExifGps ->
            Html.div [ Html.Attributes.class "flex items-center gap-3 py-2" ]
                [ Html.span [ Html.Attributes.class "text-moss text-sm" ] [ Html.text "No GPS in photo" ]
                , Html.button
                    [ Html.Events.onClick OpenMapPicker
                    , Html.Attributes.class "bg-transparent border-none text-moss text-xs cursor-pointer p-0"
                    ]
                    [ Html.text "pin manually" ]
                ]

        LocationGot lat lon source ->
            let
                sourceLabel =
                    case source of
                        ExifGps    -> "📍 from photo"
                        BrowserGeo -> "📍 GPS"
                        ManualPin  -> "📍 pinned"
            in
            Html.div [ Html.Attributes.class "flex items-center gap-3 py-2" ]
                [ Html.span [ Html.Attributes.class "text-moss text-sm" ]
                    [ Html.text (sourceLabel ++ " — " ++ formatCoord lat lon) ]
                , Html.button
                    [ Html.Events.onClick OpenMapPicker
                    , Html.Attributes.class "bg-transparent border-none text-moss text-xs cursor-pointer p-0"
                    ]
                    [ Html.text "adjust" ]
                , Html.button
                    [ Html.Events.onClick SkipLocation
                    , Html.Attributes.class "bg-transparent border-none text-moss text-xs cursor-pointer p-0"
                    ]
                    [ Html.text "remove" ]
                ]

        LocationSkipped ->
            Html.div [ Html.Attributes.class "flex items-center gap-3 py-2" ]
                [ Html.span [ Html.Attributes.class "text-moss text-sm" ] [ Html.text "no location" ]
                , Html.button
                    [ Html.Events.onClick OpenMapPicker
                    , Html.Attributes.class "bg-transparent border-none text-moss text-xs cursor-pointer p-0"
                    ]
                    [ Html.text "pin manually" ]
                ]

        LocationIdle ->
            Html.div [ Html.Attributes.class "flex gap-3 items-center" ]
                [ Html.button
                    [ Html.Events.onClick OpenMapPicker
                    , Html.Attributes.class "flex-1 bg-cream border border-tan text-ink rounded-lg py-3 px-4 text-sm cursor-pointer"
                    ]
                    [ Html.text "📍 Pin manually" ]
                , Html.button
                    [ Html.Events.onClick SkipLocation
                    , Html.Attributes.class "bg-transparent border-none text-moss text-sm cursor-pointer py-2"
                    ]
                    [ Html.text "Skip location" ]
                ]
