module Pages.Add exposing (viewTab)

import Data.Category as Category exposing (Category(..))
import Dict
import Helpers exposing (formatCoord)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Types exposing (..)
import UI.Button
import UI.Card
import UI.Layout
import UI.Rule


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    { actions = viewActions as_
    , body = viewBody as_
    , hero = viewHero as_
    }


viewActions : AuthState -> List (Html Msg)
viewActions model =
    if model.activeScanItemId /= Nothing then
        [ UI.Button.ghost { label = "← queue", onClick = BackToQueue } ]

    else if model.editingEntry /= Nothing then
        [ UI.Button.ghost { label = "← cancel", onClick = CancelEdit } ]

    else
        []


viewHero : AuthState -> Html Msg
viewHero model =
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "AMOUNT" ]
        , Html.div [ Html.Attributes.class "flex items-baseline gap-2" ]
            [ Html.span
                [ Html.Attributes.class "font-display text-5xl font-black text-forest leading-none" ]
                [ Html.text "$" ]
            , Html.input
                [ Html.Attributes.type_ "number"
                , Html.Attributes.attribute "inputmode" "decimal"
                , Html.Attributes.value model.pendingEntry.amount
                , Html.Events.onInput AmountChanged
                , Html.Attributes.placeholder "0.00"
                , Html.Attributes.class "w-full bg-transparent border-0 outline-none font-display text-5xl font-black text-forest tabular-nums tracking-tight leading-none"
                ]
                []
            ]
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
        [ viewScanPreview model
        , UI.Rule.kicker "THE BASICS"
        , UI.Card.subCard
            [ UI.Layout.formField "CATEGORY"
                (Html.div [ Html.Attributes.class "grid grid-cols-4 gap-2" ]
                    (List.map (viewCategoryBtn p.category) Category.all)
                )
            , UI.Layout.formField "DATE"
                (Html.input
                    [ Html.Attributes.type_ "date"
                    , Html.Attributes.value p.date
                    , Html.Events.onInput DateChanged
                    , Html.Attributes.class "w-full bg-transparent border-0 outline-none font-mono text-sm text-forest"
                    ]
                    []
                )
            , UI.Layout.formField "MERCHANT"
                (Html.input
                    [ Html.Attributes.type_ "text"
                    , Html.Attributes.value p.merchant
                    , Html.Events.onInput MerchantChanged
                    , Html.Attributes.placeholder "where did you spend this?"
                    , Html.Attributes.class "w-full bg-transparent border-0 outline-none text-sm text-forest placeholder:text-muted/60"
                    ]
                    []
                )
            , UI.Layout.formField "NOTE"
                (Html.input
                    [ Html.Attributes.type_ "text"
                    , Html.Attributes.value p.note
                    , Html.Events.onInput NoteChanged
                    , Html.Attributes.placeholder "brief description (50 chars)"
                    , Html.Attributes.maxlength 50
                    , Html.Attributes.class "w-full bg-transparent border-0 outline-none text-sm text-forest placeholder:text-muted/60"
                    ]
                    []
                )
            , UI.Layout.formField "DETAILS"
                (Html.textarea
                    [ Html.Attributes.value p.longNote
                    , Html.Events.onInput LongNoteChanged
                    , Html.Attributes.placeholder "longer notes, context, itemized breakdown..."
                    , Html.Attributes.rows 3
                    , Html.Attributes.class "w-full bg-transparent border-0 outline-none text-sm text-forest placeholder:text-muted/60 resize-none"
                    ]
                    []
                )
            ]
        , viewLocationSection model
        , viewSubmitSection model isEditing
        ]


viewScanPreview : AuthState -> Html Msg
viewScanPreview model =
    case model.activeScanItemId of
        Nothing ->
            Html.text ""

        Just itemId ->
            case Dict.get itemId model.scanQueue of
                Nothing ->
                    Html.text ""

                Just item ->
                    Html.div [ Html.Attributes.class "mb-4" ]
                        [ Html.img
                            [ Html.Attributes.src item.imageUrl
                            , Html.Attributes.class "w-full max-h-48 object-contain rounded-lg border border-tan"
                            ]
                            []
                        ]


viewCategoryBtn : Category.Category -> Category.Category -> Html Msg
viewCategoryBtn selected cat =
    let
        isSelected =
            cat == selected

        color =
            Category.color cat
    in
    Html.button
        [ Html.Events.onClick (CategorySelected cat)
        , Html.Attributes.class
            ("flex flex-col items-center gap-1 p-2 rounded-lg border cursor-pointer text-center transition-all "
                ++ (if isSelected then
                        "border-transparent text-parchment"

                    else
                        "border-tan bg-transparent text-muted hover:border-moss"
                   )
            )
        , if isSelected then
            Html.Attributes.style "background-color" color

          else
            Html.Attributes.class ""
        ]
        [ Html.span [ Html.Attributes.class "text-lg leading-none" ] [ Html.text (Category.icon cat) ]
        , Html.span [ Html.Attributes.class "text-[9px] font-mono uppercase tracking-wide leading-none" ] [ Html.text (Category.label cat) ]
        ]


viewLocationSection : AuthState -> Html Msg
viewLocationSection model =
    let
        ls =
            model.pendingEntry.locationState
    in
    Html.div [ Html.Attributes.class "mt-4 mb-2" ]
        [ UI.Rule.kicker "LOCATION"
        , UI.Card.subCard
            [ case ls of
                LocationIdle ->
                    Html.div [ Html.Attributes.class "text-xs text-muted font-mono" ]
                        [ Html.text "No location set" ]

                LocationFetching ->
                    Html.div [ Html.Attributes.class "text-xs text-muted font-mono animate-pulse" ]
                        [ Html.text "Getting location..." ]

                LocationCheckingExif ->
                    Html.div [ Html.Attributes.class "text-xs text-muted font-mono animate-pulse" ]
                        [ Html.text "Checking photo for GPS..." ]

                LocationNoExifGps ->
                    Html.div [ Html.Attributes.class "text-xs text-muted font-mono" ]
                        [ Html.text "No GPS in photo" ]

                LocationGot lat lon source ->
                    Html.div [ Html.Attributes.class "flex items-center justify-between gap-2" ]
                        [ Html.div [ Html.Attributes.class "text-xs font-mono text-forest" ]
                            [ Html.text (locationSourceLabel source ++ " ")
                            , Html.span [ Html.Attributes.class "text-muted" ]
                                [ Html.text (formatCoord lat ++ ", " ++ formatCoord lon) ]
                            ]
                        , Html.button
                            [ Html.Events.onClick OpenMapPicker
                            , Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss hover:text-forest bg-transparent border-none cursor-pointer p-0"
                            ]
                            [ Html.text "Change" ]
                        ]

                LocationSkipped ->
                    Html.div [ Html.Attributes.class "text-xs text-muted font-mono" ]
                        [ Html.text "Location skipped" ]
            , Html.div [ Html.Attributes.class "flex gap-3 mt-3" ]
                (locationActions ls)
            ]
        ]


locationSourceLabel : LocationSource -> String
locationSourceLabel source =
    case source of
        ExifGps    -> "Photo GPS"
        BrowserGeo -> "Device GPS"
        ManualPin  -> "Pin"


locationActions : LocationState -> List (Html Msg)
locationActions ls =
    case ls of
        LocationGot _ _ _ ->
            [ Html.button
                [ Html.Events.onClick SkipLocation
                , Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-muted hover:text-rust bg-transparent border-none cursor-pointer p-0"
                ]
                [ Html.text "Remove" ]
            ]

        LocationSkipped ->
            []

        _ ->
            [ Html.button
                [ Html.Events.onClick OpenMapPicker
                , Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss hover:text-forest bg-transparent border-none cursor-pointer p-0"
                ]
                [ Html.text "Pin on map" ]
            , Html.button
                [ Html.Events.onClick SkipLocation
                , Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-muted hover:text-rust bg-transparent border-none cursor-pointer p-0"
                ]
                [ Html.text "Skip" ]
            ]


viewSubmitSection : AuthState -> Bool -> Html Msg
viewSubmitSection model isEditing =
    let
        label_ =
            if isEditing then "Save changes" else "Add expense"
    in
    Html.div [ Html.Attributes.class "mt-6 mb-2" ]
        [ UI.Button.primary { label = label_, onClick = SubmitEntry }
        ]


decodeKey : Json.Decode.Decoder Msg
decodeKey =
    Json.Decode.field "key" Json.Decode.string
        |> Json.Decode.andThen
            (\key ->
                if key == "Enter" then
                    Json.Decode.succeed SubmitEntry

                else
                    Json.Decode.fail "not enter"
            )
