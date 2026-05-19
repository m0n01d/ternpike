module UI.Layout exposing
    ( formField
    , sectionHead
    , textInputStyle
    , viewBottomNav
    , viewDeleteConfirmModal
    , viewErrorBanner
    , viewHeader
    , viewNavTab
    , viewSettingsPanel
    , viewToast
    )

import Data.Trip exposing (Trip)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import List.NonEmpty.Zipper as Zipper
import Types exposing (..)


viewHeader : AuthState -> Html Msg
viewHeader as_ =
    div
        [ style "background" "#161918"
        , style "border-bottom" "1px solid #2a3230"
        , style "padding" "12px 20px"
        , style "display" "flex"
        , style "align-items" "center"
        , style "justify-content" "space-between"
        , style "position" "sticky"
        , style "top" "0"
        , style "z-index" "10"
        ]
        [ div []
            [ span
                [ style "font-size" "18px"
                , style "font-weight" "700"
                , style "color" "#e8a020"
                , style "letter-spacing" "0.08em"
                ]
                [ text "ALASKA" ]
            , span
                [ style "font-size" "11px"
                , style "color" "#7a8a80"
                , style "margin-left" "8px"
                ]
                [ text (Zipper.current as_.trips).name ]
            ]
        , button
            [ onClick
                (if as_.tab == SettingsTab then
                    TabChanged LedgerTab
                 else
                    TabChanged SettingsTab
                )
            , style "background" "none"
            , style "border" "none"
            , style "font-size" "22px"
            , style "cursor" "pointer"
            , style "padding" "4px 8px"
            , style "color" (if as_.tab == SettingsTab then "#e8a020" else "#7a8a80")
            ]
            [ text "⚙" ]
        ]


viewBottomNav : Tab -> Html Msg
viewBottomNav currentTab =
    nav
        [ style "position" "fixed"
        , style "bottom" "0"
        , style "left" "50%"
        , style "transform" "translateX(-50%)"
        , style "width" "100%"
        , style "max-width" "480px"
        , style "background" "#161918"
        , style "border-top" "1px solid #2a3230"
        , style "display" "flex"
        , style "z-index" "10"
        ]
        (List.map (viewNavTab currentTab)
            [ ( ScanTab,   "📷", "Scan" )
            , ( AddTab,    "+",  "Add" )
            , ( LedgerTab, "☰",  "Ledger" )
            , ( StatsTab,  "▦",  "Stats" )
            , ( TripsTab,  "🗺", "Trips" )
            ]
        )


viewNavTab : Tab -> ( Tab, String, String ) -> Html Msg
viewNavTab currentTab ( tab, icon, label_ ) =
    let
        active =
            currentTab == tab
    in
    button
        [ onClick (TabChanged tab)
        , style "flex" "1"
        , style "background" "none"
        , style "border" "none"
        , style "padding" "10px 4px"
        , style "display" "flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "gap" "2px"
        , style "cursor" "pointer"
        , style "color" (if active then "#e8a020" else "#7a8a80")
        , style "min-height" "56px"
        ]
        [ span [ style "font-size" "20px" ] [ text icon ]
        , span [ style "font-size" "10px", style "letter-spacing" "0.05em" ] [ text label_ ]
        ]


viewToast : Maybe String -> Html Msg
viewToast toast =
    case toast of
        Nothing ->
            text ""

        Just message ->
            div [ class "fixed bottom-16 left-4 right-4 z-50 flex items-center gap-3 rounded-xl px-4 py-3 bg-[#1e2220] border border-[#e85030] shadow-lg" ]
                [ span [ class "text-[#e8c080] text-sm flex-1" ] [ text message ]
                , button
                    [ onClick ToastExpired
                    , class "bg-transparent border-none text-[#7a8a80] text-lg leading-none cursor-pointer p-0 flex-shrink-0"
                    ]
                    [ text "✕" ]
                ]


viewErrorBanner : Maybe String -> Html Msg
viewErrorBanner maybeErr =
    case maybeErr of
        Nothing ->
            text ""

        Just err ->
            div
                [ style "background" "#2a1510"
                , style "border-left" "4px solid #e85030"
                , style "color" "#e8a020"
                , style "padding" "12px 16px"
                , style "margin" "0 20px 16px"
                , style "border-radius" "0 6px 6px 0"
                , style "font-size" "14px"
                , style "display" "flex"
                , style "justify-content" "space-between"
                , style "align-items" "center"
                ]
                [ text err
                , button
                    [ onClick DismissError
                    , style "background" "none"
                    , style "border" "none"
                    , style "color" "#e85030"
                    , style "cursor" "pointer"
                    , style "font-size" "18px"
                    , style "padding" "0 0 0 12px"
                    ]
                    [ text "✕" ]
                ]


viewDeleteConfirmModal : Trip -> Html Msg
viewDeleteConfirmModal trip =
    div
        [ style "position" "fixed"
        , style "inset" "0"
        , style "background" "rgba(0,0,0,0.75)"
        , style "z-index" "9998"
        , style "display" "flex"
        , style "align-items" "center"
        , style "justify-content" "center"
        , style "padding" "24px"
        ]
        [ div
            [ style "background" "#1e2220"
            , style "border" "1px solid #3a4240"
            , style "border-radius" "12px"
            , style "padding" "24px"
            , style "width" "100%"
            , style "max-width" "360px"
            ]
            [ p [ style "font-size" "18px", style "font-weight" "700", style "margin-bottom" "8px" ]
                [ text ("Delete \u{201C}" ++ trip.name ++ "\u{201D}?") ]
            , p [ style "font-size" "14px", style "color" "#7a8a80", style "margin-bottom" "24px", style "line-height" "1.5" ]
                [ text "This will permanently delete the trip and all its expense data." ]
            , div [ style "display" "flex", style "gap" "12px" ]
                [ button
                    [ onClick CancelDeleteTrip
                    , style "flex" "1"
                    , style "padding" "12px"
                    , style "border-radius" "8px"
                    , style "border" "1px solid #3a4240"
                    , style "background" "none"
                    , style "color" "#7a8a80"
                    , style "font-size" "14px"
                    , style "cursor" "pointer"
                    , style "font-family" "inherit"
                    ]
                    [ text "Cancel" ]
                , button
                    [ onClick (DeleteTrip trip)
                    , style "flex" "1"
                    , style "padding" "12px"
                    , style "border-radius" "8px"
                    , style "border" "none"
                    , style "background" "#b82020"
                    , style "color" "#ffffff"
                    , style "font-size" "14px"
                    , style "font-weight" "700"
                    , style "cursor" "pointer"
                    , style "font-family" "inherit"
                    ]
                    [ text "Delete trip" ]
                ]
            ]
        ]


viewSettingsPanel : AppConfig -> Bool -> String -> Html Msg
viewSettingsPanel cfg isSignedIn version =
    div [ style "padding" "24px 20px" ]
        [ h2 [ sectionHead ] [ text "SETTINGS" ]
        , formField "ANTHROPIC API KEY"
            (input
                [ type_ "password"
                , value cfg.anthropicKey
                , onInput ApiKeyChanged
                , placeholder "sk-ant-..."
                , textInputStyle
                ]
                []
            )
        , if isSignedIn then
            div [ style "margin-top" "32px" ]
                [ button
                    [ onClick SignOutClicked
                    , style "width" "100%"
                    , style "background" "none"
                    , style "border" "1px solid #e85030"
                    , style "color" "#e85030"
                    , style "border-radius" "8px"
                    , style "padding" "14px"
                    , style "font-size" "15px"
                    , style "cursor" "pointer"
                    ]
                    [ text "SIGN OUT" ]
                ]
          else
            text ""
        , div [ style "margin-top" "8px" ]
            [ button
                [ onClick ResetSettingsClicked
                , class "w-full py-3.5 rounded-lg border border-red-900/60 text-red-400/80 text-sm cursor-pointer bg-transparent font-[inherit] hover:border-red-700 hover:text-red-300 transition-colors"
                ]
                [ text "Reset all settings" ]
            ]
        , if version /= "" then
            p [ class "text-[#3a4a40] text-xs text-center mt-6 font-mono" ]
                [ text version ]
          else
            text ""
        ]


formField : String -> Html Msg -> Html Msg
formField label_ input_ =
    div [ style "margin-bottom" "20px" ]
        [ div
            [ style "font-size" "11px"
            , style "letter-spacing" "0.1em"
            , style "color" "#7a8a80"
            , style "margin-bottom" "8px"
            ]
            [ text label_ ]
        , input_
        ]


sectionHead : Attribute Msg
sectionHead =
    style "font-size" "13px"


textInputStyle : Attribute Msg
textInputStyle =
    style "width" "100%"
