module UI.Layout exposing
    ( formField
    , page
    , sectionHead
    , textInputStyle
    , viewBottomNav
    , viewDeleteConfirmModal
    , viewErrorBanner
    , viewHeader
    , viewNavTab
    , viewToast
    )

import Data.Trip exposing (Trip)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import List.NonEmpty.Zipper as Zipper
import Routing
import Types exposing (..)
import UI.Mascot


viewHeader : AuthState -> Html Msg
viewHeader as_ =
    Html.div
        [ Html.Attributes.class "sticky top-0 z-10 flex items-center justify-between px-5 py-3 border-b bg-cream border-tan" ]
        [ Html.div [ Html.Attributes.class "flex items-center gap-2" ]
            [ UI.Mascot.ternSvg "w-7 shrink-0"
            , Html.div []
                [ Html.span
                    [ Html.Attributes.class "text-xl font-black tracking-tight font-display text-forest" ]
                    [ Html.text "Tern"
                    , Html.span [ Html.Attributes.class "text-rust" ] [ Html.text "pike" ]
                    ]
                , Html.span
                    [ Html.Attributes.class "text-[11px] text-muted ml-2.5 tracking-widest" ]
                    [ Html.text (Zipper.current as_.trips).name ]
                ]
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
                [ Html.span [ Html.Attributes.class "flex-1 text-sm text-ink" ] [ Html.text message ]
                , Html.button
                    [ Html.Events.onClick ToastExpired
                    , Html.Attributes.class "p-0 text-lg leading-none bg-transparent border-none cursor-pointer text-muted shrink-0"
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
                [ Html.Attributes.class "flex items-center justify-between px-4 py-3 mx-5 mb-4 text-sm border-l-4 rounded-r-lg bg-rust-tint border-rust text-rust" ]
                [ Html.text err
                , Html.button
                    [ Html.Events.onClick DismissError
                    , Html.Attributes.class "p-0 pl-3 text-lg bg-transparent border-none cursor-pointer text-rust"
                    ]
                    [ Html.text "✕" ]
                ]


viewDeleteConfirmModal : Trip -> Html Msg
viewDeleteConfirmModal trip =
    Html.div
        [ Html.Attributes.class "fixed inset-0 bg-forest/65 z-[9998] flex items-center justify-center p-6" ]
        [ Html.div
            [ Html.Attributes.class "w-full max-w-sm p-6 border bg-parchment border-tan rounded-2xl shadow-panel" ]
            [ Html.p [ Html.Attributes.class "mb-2 text-lg font-bold text-ink font-display" ]
                [ Html.text ("Delete \u{201C}" ++ trip.name ++ "\u{201D}?") ]
            , Html.p [ Html.Attributes.class "mb-6 text-sm leading-relaxed text-muted" ]
                [ Html.text "This will permanently delete the trip and all its expense data." ]
            , Html.div [ Html.Attributes.class "flex gap-3" ]
                [ Html.button
                    [ Html.Events.onClick CancelDeleteTrip
                    , Html.Attributes.class "flex-1 py-3 text-sm bg-transparent border rounded-lg cursor-pointer border-tan text-muted"
                    ]
                    [ Html.text "Cancel" ]
                , Html.button
                    [ Html.Events.onClick (DeleteTrip trip)
                    , Html.Attributes.class "flex-1 py-3 text-sm font-bold border-none rounded-lg cursor-pointer bg-danger text-parchment"
                    ]
                    [ Html.text "Delete trip" ]
                ]
            ]
        ]


formField : String -> Html Msg -> Html Msg
formField label_ input_ =
    Html.div [ Html.Attributes.class "mb-5" ]
        [ Html.div [ Html.Attributes.class "text-xs tracking-[0.1em] text-moss mb-2 font-mono" ]
            [ Html.text label_ ]
        , input_
        ]


page : { actions : List (Html Msg), body : Html Msg, hero : Html Msg, route : Route } -> Html Msg
page { actions, body, hero, route } =
    Html.div [ Html.Attributes.class "p-5" ]
        [ Html.div [ Html.Attributes.class "p-4 mb-5 bg-cream rounded-xl" ]
            [ Html.div
                [ Html.Attributes.class "flex justify-between mb-3 gap-3 min-h-7" ]
                [ Html.span [ sectionHead ] [ Html.text (Routing.routeTitle route) ]
                , Html.div [ Html.Attributes.class "flex gap-2" ] actions
                ]
            , hero
            ]
        , body
        ]


sectionHead : Html.Attribute Msg
sectionHead =
    Html.Attributes.class "text-xs font-semibold tracking-widest uppercase text-moss"


textInputStyle : Html.Attribute Msg
textInputStyle =
    Html.Attributes.class "w-full"
