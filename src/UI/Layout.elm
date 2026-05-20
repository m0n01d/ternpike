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
import Data.TripId as TripId
import Dict
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Routing
import Svg
import Types exposing (..)
import UI.Button
import UI.Icons
import UI.Mascot


viewHeader : AuthState -> Html Msg
viewHeader as_ =
    Html.div
        [ Html.Attributes.class "sticky top-0 z-10 h-14 flex items-center justify-between px-5 border-b bg-cream border-moss/25" ]
        [ Html.div [ Html.Attributes.class "flex items-center gap-2" ]
            [ Html.span
                [ Html.Attributes.class "inline-block hover:rotate-[-3deg] transition-transform duration-200" ]
                [ UI.Mascot.ternSvg "w-7 h-auto shrink-0" ]
            , Html.div []
                [ Html.span
                    [ Html.Attributes.class "text-xl font-black tracking-tight font-display text-forest" ]
                    [ Html.text "Tern"
                    , Html.span [ Html.Attributes.class "text-rust" ] [ Html.text "pike" ]
                    ]
                , Html.span
                    [ Html.Attributes.class "text-[11px] text-muted ml-2.5 tracking-widest" ]
                    [ Html.text
                        (Dict.get (TripId.toString as_.currentTripId) as_.trips
                            |> Maybe.map .name
                            |> Maybe.withDefault "Loading..."
                        )
                    ]
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
                ("bg-transparent border-none cursor-pointer px-2 py-1 "
                    ++ (if as_.tab == SettingsTab then "text-rust" else "text-muted")
                )
            ]
            [ UI.Icons.settings "w-5 h-5" ]
        ]


viewBottomNav : Tab -> Html Msg
viewBottomNav currentTab =
    Html.nav
        [ Html.Attributes.class "fixed bottom-0 left-1/2 -translate-x-1/2 w-full max-w-[480px] backdrop-blur-sm bg-cream/90 border-t border-moss/25 flex z-10" ]
        (List.map (viewNavTab currentTab)
            [ ( ScanTab, UI.Icons.camera, "Scan" )
            , ( AddTab, UI.Icons.plus, "Add" )
            , ( LedgerTab, UI.Icons.journal, "Ledger" )
            , ( StatsTab, UI.Icons.chart, "Stats" )
            , ( TripsTab, UI.Icons.map, "Trips" )
            ]
        )


viewNavTab : Tab -> ( Tab, String -> Svg.Svg Msg, String ) -> Html Msg
viewNavTab currentTab ( tab, iconFn, label_ ) =
    let
        isActive =
            currentTab == tab

        indicator =
            if isActive then
                [ Html.span
                    [ Html.Attributes.class "absolute top-0 left-1/2 -translate-x-1/2 w-8 h-[2px] bg-rust" ]
                    []
                ]
            else
                []
    in
    Html.button
        [ Html.Events.onClick (TabChanged tab)
        , Html.Attributes.class
            ("relative flex-1 bg-transparent border-none py-2.5 px-1 flex flex-col items-center gap-0.5 cursor-pointer min-h-[56px] "
                ++ (if isActive then "text-rust" else "text-muted")
            )
        ]
        (indicator
            ++ [ Html.span [ Html.Attributes.class "leading-none" ] [ iconFn "w-6 h-6" ]
               , Html.span [ Html.Attributes.class "text-[10px] tracking-wide font-mono uppercase" ] [ Html.text label_ ]
               ]
        )


viewToast : Maybe String -> Html Msg
viewToast toast =
    case toast of
        Nothing ->
            Html.text ""

        Just message ->
            Html.div
                [ Html.Attributes.class "fixed bottom-[72px] left-4 right-4 z-50 flex items-center gap-3 rounded-xl px-4 py-3 bg-cream border border-rust shadow-panel animate-fade-up bg-[image:var(--bg-grain)]" ]
                [ Html.span [ Html.Attributes.class "flex-1 text-sm text-ink" ] [ Html.text message ]
                , Html.button
                    [ Html.Events.onClick ToastExpired
                    , Html.Attributes.class "p-0 leading-none bg-transparent border-none cursor-pointer text-muted shrink-0"
                    ]
                    [ UI.Icons.close "w-4 h-4" ]
                ]


viewErrorBanner : Maybe String -> Html Msg
viewErrorBanner maybeErr =
    case maybeErr of
        Nothing ->
            Html.text ""

        Just err ->
            Html.div
                [ Html.Attributes.class "flex items-stretch mx-5 mb-4 overflow-hidden rounded-r-lg bg-rust-tint text-rust" ]
                [ Html.span [ Html.Attributes.class "block w-1.5 self-stretch bg-rust rounded-r" ] []
                , Html.div [ Html.Attributes.class "flex items-center justify-between flex-1 px-4 py-3 text-sm" ]
                    [ Html.text err
                    , Html.button
                        [ Html.Events.onClick DismissError
                        , Html.Attributes.class "p-0 pl-3 bg-transparent border-none cursor-pointer text-rust"
                        ]
                        [ UI.Icons.close "w-4 h-4" ]
                    ]
                ]


viewDeleteConfirmModal : Trip -> Html Msg
viewDeleteConfirmModal trip =
    Html.div
        [ Html.Attributes.class "fixed inset-0 bg-forest/60 backdrop-blur-sm z-[9998] flex items-center justify-center p-6" ]
        [ Html.div
            [ Html.Attributes.class "w-full max-w-sm p-6 border bg-parchment border-tan rounded-2xl shadow-panel bg-[image:var(--bg-grain)]" ]
            [ Html.p [ Html.Attributes.class "mb-2 text-lg font-bold text-ink font-display" ]
                [ Html.text ("Delete \u{201C}" ++ trip.name ++ "\u{201D}?") ]
            , Html.p [ Html.Attributes.class "mb-6 text-sm leading-relaxed text-muted" ]
                [ Html.text "This will permanently delete the trip and all its expense data." ]
            , Html.div [ Html.Attributes.class "flex gap-3" ]
                [ UI.Button.secondary { label = "Cancel", onClick = CancelDeleteTrip }
                , UI.Button.danger { label = "Delete trip", onClick = DeleteTrip trip }
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
        [ Html.div
            [ Html.Attributes.class
                ("animate-fade-up relative overflow-hidden p-5 mb-5 bg-cream rounded-card shadow-card "
                    ++ "bg-[image:var(--bg-topo-atlas)] bg-no-repeat bg-[size:2400px_2000px] "
                    ++ "transition-[background-position] delay-150 duration-700 ease-out "
                    ++ topoPosClass route
                )
            ]
            [ Html.div
                [ Html.Attributes.class "flex items-start justify-between mb-4 gap-3 min-h-9" ]
                [ Html.h1 [ Html.Attributes.class "text-2xl font-black tracking-tight font-display text-forest" ]
                    [ Html.text (Routing.routeTitle route) ]
                , Html.div [ Html.Attributes.class "flex items-center gap-2" ] actions
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


topoPosClass : Route -> String
topoPosClass route =
    case route of
        RouteAdd _ ->
            "bg-[position:-1820px_-440px]"

        RouteAddReviewScan ->
            "bg-[position:-1820px_-440px]"

        RouteEditEntry _ _ ->
            "bg-[position:-1820px_-440px]"

        RouteLedger _ ->
            "bg-[position:-640px_-30px]"

        RouteScan _ ->
            "bg-[position:-40px_-60px]"

        RouteSettings ->
            "bg-[position:-1280px_-80px]"

        RouteStats _ ->
            "bg-[position:-1700px_-1380px]"

        RouteTrips ->
            "bg-[position:-580px_-1100px]"
