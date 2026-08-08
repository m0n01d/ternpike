module UI.Layout exposing
    ( formField
    , page
    , textInputStyle
    , viewBottomStack
    , viewDeleteConfirmModal
    , viewErrorBanner
    , viewHeader
    , viewOfflineBanner
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


{-| The whole bottom chrome as ONE `position: sticky` element: the ordinary
toast, the persistent update bar, and the nav, in that order, pinned to the
foot of the scrollport.

Why one sticky wrapper rather than three positioned elements:

  - **Sticky, not fixed.** `position: fixed` resolves against the viewport iOS
    26 standalone corrupts. Measured on device (iOS 26.5.2, installed, right
    after the photo picker closed): `inner/outer/screen/avail/lvh/dvh` all read
    874 while `visualViewport` alone read 566 at `offsetTop` 55 — and the fixed
    nav landed at `navBottom 819`, exactly `874 - vvTop`. On that same device
    in that same state the `sticky top-0` header rendered CORRECTLY. The
    hypothesis this rests on: `sticky` resolves against the SCROLLPORT — the
    layout viewport, healthy at 874 — so it is immune where `fixed` is not.
    That is a hypothesis backed by one strong observation, not a proven fact;
    device verification on staging is the test.
  - **Sticky keeps the document as the scroller**, which `fixed`'s alternative
    in #483 (a fixed-height shell with an inner `overflow-y-auto`) did not.
    iOS tap-the-status-bar-to-scroll-to-top only ever drives the document
    scroller, and losing it is what this change exists to undo.
  - **One wrapper, not three.** Being a single in-flow element means the stack
    settles into its own space at the very end of the document at maximum
    scroll, so nothing is ever permanently hidden behind it and no content
    padding has to guess its height. It also makes the two toasts ordinary flow
    siblings above the nav, which is what retires the hand-computed
    `bottom-[calc(…)]` slots — see `barChrome`.

`z-50` puts the whole stack over page content. Nothing inside reads
`visualViewport`, and the writer that used to feed `--vv-bottom-offset` is gone
from `src/main.js`.

-}
viewBottomStack : AuthState -> Html Msg
viewBottomStack as_ =
    Html.div
        [ Html.Attributes.class "sticky bottom-0 z-50" ]
        [ viewToast as_
        , viewUpdateToast as_
        , viewBottomNav as_
        ]


viewBottomNav : AuthState -> Html Msg
viewBottomNav as_ =
    Html.nav
        [ -- NOT `position: fixed`, deliberately — see `viewBottomStack`, whose
          -- `sticky bottom-0` wrapper is what pins this to the screen edge.
          -- This nav is an ordinary flow element and reads no viewport metric.
          --
          -- `shrink-0` keeps a flex parent from ever compressing it (the stack
          -- itself is block flow today, but the nav has been a flex row of the
          -- app shell before and may be again). `transform-gpu` stays for the
          -- iOS 26 paint-offset reason — its own compositing layer keeps the
          -- paint anchored to the computed position. Width and side borders
          -- come from the shell; repeating `max-w-[480px]`/`sm:border-x` here
          -- would double them.
          Html.Attributes.class "shrink-0 transform-gpu backdrop-blur-sm bg-cream/90 border-t border-moss/25 flex z-10 pb-[env(safe-area-inset-bottom)]"
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

The rule from #477 — the persistent update bar owns the slot nearest the nav
and this toast must never share it, or the undismissable update bar buries
every ordinary toast for the rest of the session — is now enforced by DOM
ORDER rather than by two hand-computed `bottom-[calc(…)]` offsets. Both bars
are ordinary flow children of `viewBottomStack`, and this one is rendered
FIRST, so in a bottom-anchored column it always sits one row above the update
bar and drops down to sit directly on the nav when the update bar is absent.
Two flow siblings cannot occupy the same space, so the regression the offsets
guarded against is now structurally impossible rather than arithmetically
avoided.

It still takes the whole `AuthState` (not a bare `Maybe String`) because
`Verify.Specs.UpdateToast` reads `as_.toast` alongside `as_.swUpdate` to report
both slots.

-}
viewToast : AuthState -> Html Msg
viewToast as_ =
    Html.Extra.viewMaybe
        (\message ->
            Html.div
                [ Html.Attributes.class (barChrome ++ " animate-fade-up") ]
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
        [ Html.Attributes.class (barChrome ++ " " ++ keyboardSuppressed) ]
        [ Html.span [ Html.Attributes.class "flex-1 text-sm text-ink" ]
            [ Html.text "New version available" ]
        , Html.div [ Html.Attributes.class "shrink-0" ] [ action ]
        ]


{-| Chrome shared by both bottom bars.

NOT positioned — no `fixed`, no `absolute`, and no `bottom-[calc(…)]` slot.
Both bars are ordinary flow children of `viewBottomStack`, stacked above the
nav by the wrapper's single `sticky bottom-0`. That is what deleted the pair
of hand-computed slot offsets this used to carry: their whole job was to place
two out-of-flow bars above a nav of known height without colliding, and flow
does that for free and cannot get the arithmetic wrong when the nav's height
changes.

`mb-3` is the gap to whatever sits below (the other bar, or the nav). The
left/right margins use `max(1rem, env(safe-area-inset-*))` so a landscape
notch can't run the Reload button under the Dynamic Island column; the 480px
cap comes from the shell, so there is no `max-w`/`mx-auto` to repeat here.

-}
barChrome : String
barChrome =
    "ml-[max(1rem,env(safe-area-inset-left))] mr-[max(1rem,env(safe-area-inset-right))] mb-3 flex items-center gap-3 rounded-xl px-4 py-3 bg-cream border border-rust shadow-panel bg-[image:var(--bg-grain)]"


{-| Hide the bar while a text field is focused.

In standalone iOS the software keyboard shrinks the viewport, which drags the
bottom of the scrollport up with it — and a `sticky bottom-0` stack follows the
scrollport, so the bar lands over the form fields mid-screen exactly as the
`fixed` and fixed-height-shell versions did. Moving the bars between `fixed`,
`absolute` and `sticky` never addressed this; what moves is the scrollport
itself. `keyboardLikelyOpen()` also makes the viewport heal bail while typing,
so nothing corrects it. An undismissable bar parked over the Add form is the
worst outcome in this design; suppressing it while the keyboard is up
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
