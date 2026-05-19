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
import Html exposing (Html)
import Html.Attributes
import Html.Events
import List.NonEmpty.Zipper as Zipper
import Types exposing (..)


viewHeader : AuthState -> Html Msg
viewHeader as_ =
    Html.div
        [ Html.Attributes.class "bg-cream border-b border-tan px-5 py-3 flex items-center justify-between sticky top-0 z-10" ]
        [ Html.div []
            [ Html.span
                [ Html.Attributes.class "text-xl font-bold text-rust font-display tracking-tight" ]
                [ Html.text "Ternpike" ]
            , Html.span
                [ Html.Attributes.class "text-[11px] text-muted ml-2.5 tracking-widest" ]
                [ Html.text (Zipper.current as_.trips).name ]
            ]
        , Html.button
            [ Html.Events.onClick
                (if as_.tab == SettingsTab then
                    TabChanged LedgerTab
                 else
                    TabChanged SettingsTab
                )
            , Html.Attributes.class
                ("bg-transparent border-none text-2xl cursor-pointer px-2 py-1 "
                    ++ (if as_.tab == SettingsTab then "text-rust" else "text-muted")
                )
            ]
            [ Html.text "⚙" ]
        ]


viewBottomNav : Tab -> Html Msg
viewBottomNav currentTab =
    Html.nav
        [ Html.Attributes.class "fixed bottom-0 left-1/2 -translate-x-1/2 w-full max-w-[480px] bg-cream border-t border-tan flex z-10" ]
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
    Html.button
        [ Html.Events.onClick (TabChanged tab)
        , Html.Attributes.class
            ("flex-1 bg-transparent border-none py-2.5 px-1 flex flex-col items-center gap-0.5 cursor-pointer min-h-[56px] "
                ++ (if currentTab == tab then "text-rust" else "text-muted")
            )
        ]
        [ Html.span [ Html.Attributes.class "text-xl leading-none" ] [ Html.text icon ]
        , Html.span [ Html.Attributes.class "text-[10px] tracking-wide" ] [ Html.text label_ ]
        ]


viewToast : Maybe String -> Html Msg
viewToast toast =
    case toast of
        Nothing ->
            Html.text ""

        Just message ->
            Html.div
                [ Html.Attributes.class "fixed bottom-[72px] left-4 right-4 z-50 flex items-center gap-3 rounded-xl px-4 py-3 bg-cream border border-rust shadow-panel" ]
                [ Html.span [ Html.Attributes.class "text-ink text-sm flex-1" ] [ Html.text message ]
                , Html.button
                    [ Html.Events.onClick ToastExpired
                    , Html.Attributes.class "bg-transparent border-none text-muted text-lg leading-none cursor-pointer p-0 shrink-0"
                    ]
                    [ Html.text "✕" ]
                ]


viewErrorBanner : Maybe String -> Html Msg
viewErrorBanner maybeErr =
    case maybeErr of
        Nothing ->
            Html.text ""

        Just err ->
            Html.div
                [ Html.Attributes.class "bg-[#fdf0ea] border-l-4 border-rust text-rust px-4 py-3 mx-5 mb-4 rounded-r-lg text-sm flex justify-between items-center" ]
                [ Html.text err
                , Html.button
                    [ Html.Events.onClick DismissError
                    , Html.Attributes.class "bg-transparent border-none text-rust cursor-pointer text-lg p-0 pl-3"
                    ]
                    [ Html.text "✕" ]
                ]


viewDeleteConfirmModal : Trip -> Html Msg
viewDeleteConfirmModal trip =
    Html.div
        [ Html.Attributes.class "fixed inset-0 bg-forest/65 z-[9998] flex items-center justify-center p-6" ]
        [ Html.div
            [ Html.Attributes.class "bg-parchment border border-tan rounded-2xl p-6 w-full max-w-sm shadow-panel" ]
            [ Html.p [ Html.Attributes.class "text-lg font-bold text-ink font-display mb-2" ]
                [ Html.text ("Delete \u{201C}" ++ trip.name ++ "\u{201D}?") ]
            , Html.p [ Html.Attributes.class "text-sm text-muted mb-6 leading-relaxed" ]
                [ Html.text "This will permanently delete the trip and all its expense data." ]
            , Html.div [ Html.Attributes.class "flex gap-3" ]
                [ Html.button
                    [ Html.Events.onClick CancelDeleteTrip
                    , Html.Attributes.class "flex-1 py-3 rounded-lg border border-tan bg-transparent text-muted text-sm cursor-pointer"
                    ]
                    [ Html.text "Cancel" ]
                , Html.button
                    [ Html.Events.onClick (DeleteTrip trip)
                    , Html.Attributes.class "flex-1 py-3 rounded-lg border-none bg-[#a83020] text-parchment text-sm font-bold cursor-pointer"
                    ]
                    [ Html.text "Delete trip" ]
                ]
            ]
        ]


viewSettingsPanel : AppConfig -> Bool -> String -> Html Msg
viewSettingsPanel cfg isSignedIn version =
    Html.div [ Html.Attributes.class "px-5 py-6" ]
        [ Html.h2 [ sectionHead ] [ Html.text "SETTINGS" ]
        , formField "ANTHROPIC API KEY"
            (Html.input
                [ Html.Attributes.type_ "password"
                , Html.Attributes.value cfg.anthropicKey
                , Html.Events.onInput ApiKeyChanged
                , Html.Attributes.placeholder "sk-ant-..."
                , textInputStyle
                ]
                []
            )
        , if isSignedIn then
            Html.div [ Html.Attributes.class "mt-8" ]
                [ Html.button
                    [ Html.Events.onClick SignOutClicked
                    , Html.Attributes.class "w-full bg-transparent border border-rust text-rust rounded-lg py-3.5 text-[15px] cursor-pointer"
                    ]
                    [ Html.text "SIGN OUT" ]
                ]
          else
            Html.text ""
        , Html.div [ Html.Attributes.class "mt-2" ]
            [ Html.button
                [ Html.Events.onClick ResetSettingsClicked
                , Html.Attributes.class "w-full bg-transparent border border-tan text-muted rounded-lg py-3.5 text-sm cursor-pointer"
                ]
                [ Html.text "Reset all settings" ]
            ]
        , if version /= "" then
            Html.p [ Html.Attributes.class "text-[#c4b898] text-[11px] text-center mt-6 font-mono" ]
                [ Html.text version ]
          else
            Html.text ""
        ]


formField : String -> Html Msg -> Html Msg
formField label_ input_ =
    Html.div [ Html.Attributes.class "mb-5" ]
        [ Html.div [ Html.Attributes.class "text-xs tracking-[0.1em] text-moss mb-2 font-mono" ]
            [ Html.text label_ ]
        , input_
        ]


sectionHead : Html.Attribute Msg
sectionHead =
    Html.Attributes.class "text-xs tracking-widest text-moss uppercase font-semibold mb-5"


textInputStyle : Html.Attribute Msg
textInputStyle =
    Html.Attributes.class "w-full"
