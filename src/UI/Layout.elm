module UI.Layout exposing
    ( formField
    , page
    , textInputStyle
    , viewBottomNav
    , viewDeleteConfirmModal
    , viewErrorBanner
    , viewHeader
    , viewOfflineBanner
    , viewToast
    , viewUpdateToast
    )

import Data.Navigation exposing (Route(..), Tab(..))
import Data.SwUpdate as SwUpdate
import Data.Sync exposing (SyncState(..))
import Data.Trip exposing (Trip)
import Data.Trips as Trips exposing (TripsState(..))
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Extra
import Routing
import Svg
import Types exposing (AuthMsg_(..), AuthState, Msg(..))
import UI.Button
import UI.Icons
import UI.Mascot
import Verify.Contract
import Verify.Specs.UpdateToast


viewHeader : AuthState -> Html Msg
viewHeader as_ =
    let
        settingsHref =
            if Routing.routeToTab as_.route == SettingsTab then
                Routing.pathForCurrentTab as_ LedgerTab

            else
                as_.basePath ++ "settings"
    in
    Html.div
        [ -- `transform-gpu` for the same iOS 26 paint-offset reason as the
          -- bottom nav (see `viewBottomNav`) — sticky drifts the same way.
          Html.Attributes.class "sticky top-0 z-10 transform-gpu h-[calc(env(safe-area-inset-top)+3.5rem)] pt-[env(safe-area-inset-top)] flex items-center justify-between px-5 border-b bg-cream border-moss/25"
        ]
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
                , viewTripKicker as_.trips
                ]
            ]
        , Html.div [ Html.Attributes.class "flex items-center gap-3" ]
            [ viewSyncBadge { networkOffline = Data.Sync.isOffline as_.network, syncState = as_.syncState }
            , Html.a
                [ Html.Attributes.href (as_.basePath ++ "milepost")
                , Html.Attributes.attribute "aria-label" "The Milepost"
                , Html.Attributes.class
                    ("inline-flex items-center px-2 py-1 "
                        ++ (if as_.route == RouteMilepost then
                                "text-rust"

                            else
                                "text-muted"
                           )
                    )
                ]
                [ UI.Icons.flag "w-5 h-5" ]
            , Html.a
                [ Html.Attributes.href settingsHref
                , Html.Attributes.class
                    ("inline-flex items-center px-2 py-1 "
                        ++ (if Routing.routeToTab as_.route == SettingsTab then
                                "text-rust"

                            else
                                "text-muted"
                           )
                    )
                ]
                [ UI.Icons.settings "w-5 h-5" ]
            ]
        ]


viewTripKicker : TripsState -> Html Msg
viewTripKicker state =
    let
        kicker label =
            Html.span
                [ Html.Attributes.class "text-[11px] text-muted ml-2.5 tracking-widest" ]
                [ Html.text label ]
    in
    case state of
        NoTripsYet ->
            kicker "No trips yet"

        TripsLoaded trips ->
            kicker (Trips.selectedTrip trips).name

        TripsLoading _ _ ->
            Html.Extra.nothing


viewSyncBadge : { networkOffline : Bool, syncState : SyncState } -> Html Msg
viewSyncBadge { networkOffline, syncState } =
    if networkOffline then
        Html.span
            [ Html.Attributes.class "text-xs text-muted"
            , Html.Attributes.title "Offline"
            ]
            [ Html.text "●" ]

    else
        case syncState of
            AuthExpired ->
                Html.Extra.nothing

            NotEnabled ->
                Html.Extra.nothing

            SyncError ->
                Html.span
                    [ Html.Attributes.class "text-xs text-rust"
                    , Html.Attributes.title "Sync error"
                    ]
                    [ Html.text "⚠" ]

            Synced ->
                Html.span
                    [ Html.Attributes.class "text-xs text-moss"
                    , Html.Attributes.title "Synced"
                    ]
                    [ Html.text "●" ]

            Syncing ->
                Html.span
                    [ Html.Attributes.class "text-xs text-rust animate-pulse"
                    , Html.Attributes.title "Syncing"
                    ]
                    [ Html.text "●" ]


viewOfflineBanner : Bool -> Html Msg
viewOfflineBanner networkOffline =
    Html.Extra.viewIf networkOffline <|
        Html.div
            [ Html.Attributes.class "sticky top-[calc(env(safe-area-inset-top)+3.5rem)] z-10 px-5 py-1.5 text-xs text-center font-mono tracking-wide bg-tan/50 text-forest border-b border-moss/25" ]
            [ Html.text "You're offline · changes will sync when you reconnect" ]


viewBottomNav : AuthState -> Html Msg
viewBottomNav as_ =
    Html.nav
        [ -- `transform-gpu` promotes the nav to its own compositing layer:
          -- iOS 26 WebKit can paint `fixed` elements offset from their
          -- computed position during body scroll, and an owned layer keeps
          -- the paint anchored to the real viewport.
          -- `bottom` is driven by `--vv-bottom-offset`, set from
          -- `visualViewport` in `src/main.js`. `position: fixed` resolves
          -- against the LAYOUT viewport, which iOS standalone can leave stuck
          -- short after a keyboard — parking this bar a keyboard-height above
          -- the screen. The custom property is the gap between the layout
          -- viewport's bottom and the visible one, so the bar lands on the
          -- real screen edge. It computes to `0px` whenever the two agree,
          -- which is every healthy browser, so this cannot regress them.
          Html.Attributes.class "fixed bottom-[var(--vv-bottom-offset,0px)] left-1/2 -translate-x-1/2 transform-gpu w-full max-w-[480px] backdrop-blur-sm bg-cream/90 border-t border-moss/25 flex z-10 pb-[env(safe-area-inset-bottom)] sm:border-x sm:border-tan/40 sm:dark:border-moss/20"
        ]
        (List.map (viewNavTab as_)
            [ ( ScanTab, UI.Icons.camera, "Scan" )
            , ( AddTab, UI.Icons.plus, "Add" )
            , ( LedgerTab, UI.Icons.journal, "Ledger" )
            , ( StatsTab, UI.Icons.chart, "Stats" )
            , ( TripsTab, UI.Icons.map, "Trips" )
            ]
        )


viewNavTab : AuthState -> ( Tab, String -> Svg.Svg Msg, String ) -> Html Msg
viewNavTab as_ ( tab, iconFn, label_ ) =
    let
        isActive =
            Routing.routeToTab as_.route == tab

        indicator =
            if isActive then
                [ Html.span
                    [ Html.Attributes.class "absolute top-0 left-1/2 -translate-x-1/2 w-8 h-[2px] bg-rust" ]
                    []
                ]

            else
                []
    in
    Html.a
        [ Html.Attributes.href (Routing.pathForCurrentTab as_ tab)
        , Html.Attributes.class
            ("relative flex-1 py-2.5 px-1 flex flex-col items-center gap-0.5 cursor-pointer min-h-[56px] "
                ++ (if isActive then
                        "text-rust"

                    else
                        "text-muted"
                   )
            )
        ]
        (indicator
            ++ [ Html.span [ Html.Attributes.class "leading-none" ] [ iconFn "w-6 h-6" ]
               , Html.span [ Html.Attributes.class "text-[10px] tracking-wide font-mono uppercase" ] [ Html.text label_ ]
               ]
        )


{-| The transient toast ("Link copied", share errors, every `toastFor` site).

Takes the whole `AuthState` rather than a bare `Maybe String` because its
vertical slot now depends on `as_.swUpdate`: the persistent update bar
(`viewUpdateToast`) owns the lower slot, and this toast shifts one slot up
whenever that bar is showing. Sharing an offset would make every ordinary
toast invisible for the rest of the session — the update bar has no dismiss
and renders later in the DOM (#477).

The old hard-coded 72px offset predated the safe-area nav and overlapped it. Both
bars now anchor to the nav's real height — `min-h-[56px]` tabs plus
`pb-[env(safe-area-inset-bottom)]` — and match its
`max-w-[480px]` gutters so the action never lands under the Dynamic Island in
landscape.

-}
viewToast : AuthState -> Html Msg
viewToast as_ =
    let
        shifted : Bool
        shifted =
            SwUpdate.isShowing as_.swUpdate
    in
    Html.Extra.viewMaybe
        (\message ->
            Html.div
                [ Html.Attributes.classList
                    [ ( barChrome, True )
                    , ( "animate-fade-up", True )
                    , ( lowerSlot, not shifted )
                    , ( upperSlot, shifted )
                    ]
                ]
                [ Html.span [ Html.Attributes.class "flex-1 text-sm text-ink" ] [ Html.text message ]
                , Html.button
                    [ Html.Events.onClick (AuthMsg ToastExpired)
                    , Html.Attributes.class "p-0 leading-none bg-transparent border-none cursor-pointer text-muted shrink-0"
                    ]
                    [ UI.Icons.close "w-4 h-4" ]
                ]
        )
        as_.toast


{-| The persistent "New version available · Reload" bar (#477).

Always renders its wrapper — that is where `Verify.Contract.verifyAttrs` and
the `role="status"` live region hang. `NoUpdate` leaves the wrapper empty
rather than removing it, so `/verify/UpdateToast/hidden` resolves its selector
instead of hanging, and the live region exists before the announcement lands.

There is deliberately no dismiss control (the ask is to force the update) and
no `animate-fade-up`: `healViewport` toggles `document.body.style.display`,
which restarts CSS animations, and on the Add page the heal runs on every
`focusout` — a persistent animated bar would re-slide on every field blur.

-}
viewUpdateToast : AuthState -> Html Msg
viewUpdateToast as_ =
    let
        input : Verify.Specs.UpdateToast.Input
        input =
            Verify.Specs.UpdateToast.honest
                { swUpdate = as_.swUpdate
                , toastPresent = as_.toast /= Nothing
                }
    in
    Html.div
        (Html.Attributes.attribute "role" "status"
            :: Html.Attributes.attribute "aria-live" "polite"
            :: Verify.Contract.verifyAttrs "UpdateToast" (Verify.Specs.UpdateToast.surface input)
        )
        [ case as_.swUpdate of
            SwUpdate.Applying ->
                updateBar (UI.Button.primaryBusy { label = "Reload" })

            SwUpdate.NoUpdate ->
                Html.Extra.nothing

            SwUpdate.UpdateWaiting ->
                updateBar
                    (UI.Button.primaryDescribed
                        { ariaLabel = "Reload to install the new version"
                        , label = "Reload"
                        , onClick = AuthMsg ApplySwUpdate
                        }
                    )
        ]


updateBar : Html Msg -> Html Msg
updateBar action =
    Html.div
        [ Html.Attributes.class (barChrome ++ " " ++ lowerSlot ++ " " ++ keyboardSuppressed) ]
        [ Html.span [ Html.Attributes.class "flex-1 text-sm text-ink" ]
            [ Html.text "New version available" ]
        , Html.div [ Html.Attributes.class "shrink-0" ] [ action ]
        ]


{-| Chrome shared by both bottom bars, minus the vertical slot.

`left`/`right` use `max(1rem, env(safe-area-inset-*))` and the nav's
`max-w-[480px] mx-auto` so a landscape notch can't run the Reload button under
the Dynamic Island column.

-}
barChrome : String
barChrome =
    "fixed left-[max(1rem,env(safe-area-inset-left))] right-[max(1rem,env(safe-area-inset-right))] mx-auto max-w-[480px] z-50 flex items-center gap-3 rounded-xl px-4 py-3 bg-cream border border-rust shadow-panel bg-[image:var(--bg-grain)]"


{-| The slot immediately above the bottom nav.

Computed, not guessed: the nav is `fixed bottom-0` with `min-h-[56px]` tabs
_plus_ `pb-[env(safe-area-inset-bottom)]` (~34px on a home-indicator iPhone),
so it occupies roughly 0–90px. `4.5rem` (72px) above the inset clears it. The
old hard-coded 72px offset spanned 72–118px — straight through `viewNavTab`'s active
indicator and icon tops — and at `z-50` against the nav's `z-10` it won
hit-testing, eating taps across the whole nav.

-}
lowerSlot : String
lowerSlot =
    "bottom-[calc(env(safe-area-inset-bottom)+4.5rem+var(--vv-bottom-offset,0px))]"


{-| One slot up: clears the ~70px update bar plus a gap.
-}
upperSlot : String
upperSlot =
    "bottom-[calc(env(safe-area-inset-bottom)+10rem+var(--vv-bottom-offset,0px))]"


{-| Hide the bar while a text field is focused.

In standalone iOS the software keyboard shrinks the layout viewport, so a
`fixed bottom-…` element is lifted to sit _over_ the form fields mid-screen —
and `keyboardLikelyOpen()` makes the viewport heal deliberately bail while
typing, so nothing corrects it. An undismissable bar parked over the Add form
is the worst outcome in this design; suppressing it while the keyboard is up
preserves "no dismiss" without the pathology.

The `group` anchor is the `viewAuth` root. Only the tags that raise the
keyboard are matched — `group-focus-within` would also fire on the Reload
button itself and hide the bar the instant it was tapped.

-}
keyboardSuppressed : String
keyboardSuppressed =
    "group-has-[input:focus]:hidden group-has-[textarea:focus]:hidden group-has-[select:focus]:hidden"


viewErrorBanner : Maybe String -> Html Msg
viewErrorBanner maybeErr =
    Html.Extra.viewMaybe
        (\err ->
            Html.div
                [ Html.Attributes.class "flex items-stretch mx-5 mb-4 overflow-hidden rounded-r-lg bg-rust-tint text-rust" ]
                [ Html.span [ Html.Attributes.class "block w-1.5 self-stretch bg-rust rounded-r" ] []
                , Html.div [ Html.Attributes.class "flex items-center justify-between flex-1 px-4 py-3 text-sm" ]
                    [ Html.text err
                    , Html.button
                        [ Html.Events.onClick (AuthMsg DismissError)
                        , Html.Attributes.class "p-0 pl-3 bg-transparent border-none cursor-pointer text-rust"
                        ]
                        [ UI.Icons.close "w-4 h-4" ]
                    ]
                ]
        )
        maybeErr


viewDeleteConfirmModal : Trip -> Html Msg
viewDeleteConfirmModal trip =
    Html.div
        [ Html.Attributes.class "fixed inset-0 bg-black/60 backdrop-blur-sm z-[9998] flex items-center justify-center p-6" ]
        [ Html.div
            [ Html.Attributes.class "w-full max-w-sm p-6 border bg-parchment dark:bg-cream border-tan rounded-2xl shadow-panel bg-[image:var(--bg-grain)]" ]
            [ Html.p [ Html.Attributes.class "mb-2 text-lg font-bold text-ink font-display" ]
                [ Html.text ("Delete “" ++ trip.name ++ "”?") ]
            , Html.p [ Html.Attributes.class "mb-6 text-sm leading-relaxed text-muted" ]
                [ Html.text "This will permanently delete the trip and all its expense data." ]
            , Html.div [ Html.Attributes.class "flex gap-3" ]
                [ UI.Button.secondary { label = "Cancel", onClick = AuthMsg CancelDeleteTrip }
                , UI.Button.danger { label = "Delete trip", onClick = AuthMsg (DeleteTrip trip) }
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

        RouteJoinSharedTrip _ ->
            "bg-[position:-1280px_-80px]"

        RouteLedger _ ->
            "bg-[position:-640px_-30px]"

        RouteMagicLink _ _ ->
            "bg-[position:-1280px_-80px]"

        RouteMilepost ->
            "bg-[position:-1700px_-1380px]"

        RouteNestPreview _ ->
            "bg-[position:-580px_-1100px]"

        RouteScan _ ->
            "bg-[position:-40px_-60px]"

        RouteSettings ->
            "bg-[position:-1280px_-80px]"

        RouteStats _ ->
            "bg-[position:-1700px_-1380px]"

        RouteTrips ->
            "bg-[position:-580px_-1100px]"

        RouteVerify _ _ ->
            "bg-[position:-1280px_-80px]"

        RouteVerifyIndex ->
            "bg-[position:-1280px_-80px]"
