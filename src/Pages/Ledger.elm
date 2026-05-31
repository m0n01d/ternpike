module Pages.Ledger exposing (viewTab)

import Data.Category as Category
import Data.Currency exposing (Currency)
import Data.DateField as DateField exposing (DateField)
import Data.Entry as Entry
import Data.ExpenseId as ExpenseId
import Data.FuelDetail exposing (FuelDetail)
import Data.FuelGrade as FuelGrade
import Data.Gallons as Gallons
import Data.Ledger exposing (LedgerMode(..))
import Data.Liters as Liters
import Data.Milepost as Milepost
import Data.Money as Money exposing (Money)
import Data.PricePerGallon as PricePerGallon
import Data.PricePerLiter as PricePerLiter
import Data.SharedTrip
import Data.SharedTrips
import Data.TripId as TripId
import Data.Trips
import Data.UserId as UserId exposing (UserId)
import Dict exposing (Dict)
import Helpers exposing (effectiveEntryToExpense, encodeWaypoints)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Extra
import Html.Keyed as Keyed
import Routing
import Set
import Types exposing (AuthMsg_(..), AuthState, Msg(..))
import UI.Avatar
import UI.BudgetBar
import UI.Button
import UI.DateView
import UI.Gate
import UI.Icons
import UI.Mascot
import UI.Milepost
import UI.MoneyView


{-| `earned` is the list of `Milepost.Earned` states for the active trip,
pre-computed at the call site in `Main.viewAuth` via `milepostInputsForTrip`.
Only `Earned` values are passed — `Locked` ones are filtered out before the
call.
-}
viewTab : List Milepost.MarkerState -> AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab earned as_ =
    let
        mode =
            ledgerMode as_
    in
    { actions = viewActions as_
    , body = viewBody as_ mode
    , hero = viewHero earned (activeBudget as_) mode
    }


activeBudget : AuthState -> Money
activeBudget as_ =
    case ( Routing.routeTripId as_.route, as_.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded trips ) ->
            Data.Trips.findTrip tripId trips
                |> Maybe.map .budget
                |> Maybe.withDefault Money.zero

        _ ->
            Money.zero



-- LedgerLoading until the current trip's bulk fetch has completed; then
-- LedgerReady with the resolved entries derived from the cache.


ledgerMode : AuthState -> LedgerMode
ledgerMode as_ =
    case Routing.routeTripId as_.route of
        Just tripId ->
            if Set.member (TripId.toString tripId) as_.tripLoaded then
                LedgerReady
                    (Entry.resolve
                        (as_.expenses |> Dict.get (TripId.toString tripId) |> Maybe.withDefault Dict.empty |> Dict.values)
                        (Dict.values as_.amendments)
                        (Dict.values as_.voids)
                        tripId
                    )

            else
                LedgerLoading

        Nothing ->
            LedgerLoading


viewActions : AuthState -> List (Html Msg)
viewActions model =
    let
        mapToggle =
            UI.Button.iconButton
                { icon = UI.Icons.map "w-4 h-4"
                , onClick = AuthMsg ToggleLedgerMap
                , title =
                    if model.showLedgerMap then
                        "Hide map"

                    else
                        "Show map"
                }

        expandToggle =
            if model.ledgerMapExpanded then
                UI.Button.iconButton
                    { icon = UI.Icons.collapse "w-4 h-4"
                    , onClick = AuthMsg ToggleLedgerMapExpanded
                    , title = "Shrink map"
                    }

            else
                UI.Button.iconButton
                    { icon = UI.Icons.expand "w-4 h-4"
                    , onClick = AuthMsg ToggleLedgerMapExpanded
                    , title = "Expand map"
                    }

        refresh =
            UI.Button.iconButton
                { icon = UI.Icons.chevronRight "w-4 h-4"
                , onClick = AuthMsg RefreshClicked
                , title = "Refresh"
                }

        exportButton =
            Html.Extra.viewMaybe
                (\tripId ->
                    if UI.Gate.requiresPaid model.tier then
                        UI.Button.iconButton
                            { icon = UI.Icons.download "w-4 h-4"
                            , onClick = AuthMsg (ExportCsv tripId)
                            , title = "Export CSV"
                            }

                    else
                        Html.a
                            [ Html.Attributes.href "/settings#billing"
                            , Html.Attributes.class "inline-flex items-center gap-1 px-2 py-1 text-xs font-mono text-moss hover:text-forest transition-colors"
                            , Html.Attributes.title "CSV export requires Osprey"
                            ]
                            [ UI.Icons.download "w-4 h-4"
                            ]
                )
                (Routing.routeTripId model.route)
    in
    if model.showLedgerMap then
        [ mapToggle, expandToggle, refresh ]

    else
        [ exportButton, mapToggle, refresh ]


viewHero : List Milepost.MarkerState -> Money -> LedgerMode -> Html Msg
viewHero earned budget mode =
    case mode of
        LedgerReady entries ->
            viewLedgerHero earned budget entries

        LedgerLoading ->
            Html.div [ Html.Attributes.class "font-mono text-[22px] text-muted" ]
                [ Html.text "—" ]


viewLedgerHero : List Milepost.MarkerState -> Money -> List Entry.EffectiveEntry -> Html Msg
viewLedgerHero earned budget entries =
    let
        total =
            Money.sum (List.map .amount entries)

        entryCount =
            List.length entries

        dayCount =
            List.length (Entry.uniqueDates entries)

        kickerText =
            if dayCount > 0 then
                String.fromInt entryCount
                    ++ " ENTRIES · "
                    ++ String.fromInt dayCount
                    ++ (if dayCount == 1 then
                            " DAY"

                        else
                            " DAYS"
                       )

            else
                String.fromInt entryCount ++ " ENTRIES"

        earnedCount =
            List.length earned

        moreCount =
            earnedCount - 4

        visibleChips =
            List.take 4 earned
    in
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div
            [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "RUNNING TOTAL" ]
        , Html.div
            [ Html.Attributes.class "font-display text-5xl font-black text-forest tracking-tight leading-none" ]
            [ UI.MoneyView.totals (Entry.totalsByCurrency entries) ]
        , Html.div
            [ Html.Attributes.class "mt-2 text-xs text-muted font-mono tracking-wide" ]
            [ Html.text kickerText ]
        , Html.Extra.viewIf (not (Money.isZero budget)) <|
            UI.BudgetBar.viewSubtle { budget = budget, spent = total }
        , Html.Extra.viewIf (earnedCount > 0) <|
            viewMarkerStrip visibleChips moreCount
        ]


{-| A compact row of earned marker chips in the Ledger header.

Shows up to four icon-only chips. When more than four are earned, appends a
"+N more →" link to the full Milepost screen. Renders `Html.Extra.nothing`
when the earned list is empty — guarded by the `viewIf` at the call site.

-}
viewMarkerStrip : List Milepost.MarkerState -> Int -> Html Msg
viewMarkerStrip chips moreCount =
    Html.div
        [ Html.Attributes.class "mt-3 flex items-center gap-1.5 flex-wrap" ]
        (List.map UI.Milepost.markerChipSmall chips
            ++ (if moreCount > 0 then
                    [ Html.a
                        [ Html.Attributes.href "/milepost"
                        , Html.Attributes.class "text-[10px] font-mono text-moss hover:text-forest transition-colors whitespace-nowrap"
                        ]
                        [ Html.text ("+" ++ String.fromInt moreCount ++ " more →") ]
                    ]

                else
                    []
               )
        )


viewBody : AuthState -> LedgerMode -> Html Msg
viewBody model mode =
    case mode of
        LedgerLoading ->
            viewSkeleton

        LedgerReady [] ->
            viewEmptyState

        LedgerReady entries ->
            if model.showLedgerMap && model.ledgerMapExpanded then
                viewLedgerMap model entries

            else
                Html.div []
                    [ viewLedgerMap model entries
                    , viewEntries
                        { basePath = model.basePath
                        , canMove = hasOtherTrips model
                        , members = membersForActiveTrip model
                        , openMenu = model.openLedgerMenu
                        , readOnly = isActiveTripReadOnly model
                        , showIntensity = model.showDayIntensity
                        }
                        entries
                    ]


hasOtherTrips : AuthState -> Bool
hasOtherTrips model =
    case model.trips of
        Data.Trips.TripsLoaded loadedTrips ->
            not (List.isEmpty (Data.Trips.otherTrips loadedTrips))

        _ ->
            False


{-| One member of the active flock, indexed by stringified `UserId`.

`displayName` is the `@handle` form (or `@handle#hash` on collision) so
the author chip stays short on narrow rows. The full email is still
the source of truth in `userId`.

-}
type alias FlockMember =
    { displayName : String
    , userId : UserId
    }


{-| The member dictionary the ledger rows look up `entry.createdBy`
in. Empty on personal trips so the author chip never renders. Populated
from the active trip's flock when present.
-}
membersForActiveTrip : AuthState -> Dict String FlockMember
membersForActiveTrip model =
    case ( Routing.routeTripId model.route, model.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded loadedTrips ) ->
            case Data.Trips.findTrip tripId loadedTrips of
                Just trip ->
                    case trip.flockId of
                        Just fid ->
                            case Data.SharedTrips.get fid model.sharedTrips of
                                Just flock ->
                                    membersDict (Data.SharedTrip.members flock)

                                Nothing ->
                                    Dict.empty

                        Nothing ->
                            Dict.empty

                Nothing ->
                    Dict.empty

        _ ->
            Dict.empty


membersDict : List UserId -> Dict String FlockMember
membersDict users =
    users
        |> List.map
            (\u ->
                ( UserId.toString u
                , { displayName = UserId.handleIn u users
                  , userId = u
                  }
                )
            )
        |> Dict.fromList


{-| `True` when the route's active trip belongs to a flock whose
billing status is `Grace` or `Frozen`. Personal trips, unloaded
trips, and active flocks all return `False`. Mirrors the predicate
used on the Add page so the disable rules stay aligned.
-}
isActiveTripReadOnly : AuthState -> Bool
isActiveTripReadOnly model =
    case ( Routing.routeTripId model.route, model.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded trips ) ->
            Data.Trips.findTrip tripId trips
                |> Maybe.andThen .flockId
                |> Maybe.andThen (\fid -> Data.SharedTrips.get fid model.sharedTrips)
                |> Maybe.map Data.SharedTrip.isReadOnly
                |> Maybe.withDefault False

        _ ->
            False


viewEntries :
    { basePath : String
    , canMove : Bool
    , members : Dict String FlockMember
    , openMenu : Maybe ExpenseId.ExpenseId
    , readOnly : Bool
    , showIntensity : Bool
    }
    -> List Entry.EffectiveEntry
    -> Html Msg
viewEntries opts entries =
    let
        dates =
            Entry.uniqueDates entries

        indexedDates =
            List.indexedMap
                (\i d -> ( d, List.length dates - i ))
                dates

        totals =
            Entry.dailyTotals entries

        median =
            Entry.tripMedian totals

        bandFor date =
            if opts.showIntensity then
                Just (Entry.spendBand median (Dict.get date totals |> Maybe.withDefault Money.zero))

            else
                Nothing

        groupBlock ( date, dayN ) =
            let
                dateIso =
                    DateField.toIso date

                dayEntries =
                    List.filter (\e -> DateField.compare e.date date == EQ) entries
            in
            ( dateIso
            , Html.div [ Html.Attributes.class "mt-6 mb-4" ]
                [ viewDayKicker (bandFor dateIso) dayN date
                , Keyed.node "div"
                    [ Html.Attributes.class "animate-stagger-row" ]
                    (List.map
                        (\e -> ( ExpenseId.toString e.id, viewEntryRow opts e ))
                        dayEntries
                    )
                , Html.Extra.viewIf (List.length dayEntries > 1) <|
                    viewDayTotal (Entry.primaryCurrency dayEntries)
                        (Dict.get dateIso totals |> Maybe.withDefault Money.zero)
                ]
            )
    in
    Keyed.node "div" [] (List.map groupBlock indexedDates)


viewDayTotal : Currency -> Money -> Html Msg
viewDayTotal currency total =
    Html.div
        [ Html.Attributes.class "mt-3 pt-2 text-center font-mono text-xs tracking-widest text-forest" ]
        [ Html.text "DAY TOTAL  "
        , UI.MoneyView.amount currency total
        ]


viewDayKicker : Maybe Entry.Band -> Int -> DateField -> Html Msg
viewDayKicker maybeBand dayN date =
    Html.div [ Html.Attributes.class "sticky top-14 z-[9] bg-parchment dark:bg-cream border-t border-tan/40 -mx-5 px-5 py-3 flex items-center gap-3" ]
        [ Html.span
            [ Html.Attributes.class "text-xs font-mono uppercase tracking-widest text-rust" ]
            [ Html.text ("DAY " ++ String.fromInt dayN) ]
        , Html.span [ Html.Attributes.class (railClass maybeBand) ] []
        , Html.span
            [ Html.Attributes.class "text-xs font-mono uppercase tracking-widest text-moss" ]
            [ UI.DateView.short date ]
        ]


railClass : Maybe Entry.Band -> String
railClass maybeBand =
    case maybeBand of
        Nothing ->
            "h-px flex-1 bg-tan"

        Just band ->
            "flex-1 h-0.5 " ++ bandColor band


bandColor : Entry.Band -> String
bandColor band =
    case band of
        Entry.Frugal ->
            "bg-moss"

        Entry.Below ->
            "bg-moss/50"

        Entry.Typical ->
            "bg-tan"

        Entry.Above ->
            "bg-rust/60"

        Entry.Splurge ->
            "bg-rust-deep"


viewLedgerMap : AuthState -> List Entry.EffectiveEntry -> Html Msg
viewLedgerMap model entries =
    Html.Extra.viewIf model.showLedgerMap <|
        let
            sizing =
                if model.ledgerMapExpanded then
                    "h-[70vh] mb-0"

                else
                    "h-[260px] mb-5"
        in
        Html.node "waypoint-map"
            [ Html.Attributes.attribute "points" (encodeWaypoints entries)
            , Html.Attributes.class ("block isolate w-full rounded-xl overflow-hidden " ++ sizing)
            ]
            []


viewEntryRow :
    { basePath : String
    , canMove : Bool
    , members : Dict String FlockMember
    , openMenu : Maybe ExpenseId.ExpenseId
    , readOnly : Bool
    , showIntensity : Bool
    }
    -> Entry.EffectiveEntry
    -> Html Msg
viewEntryRow opts entry =
    let
        primaryLabel =
            if entry.merchant /= "" then
                entry.merchant

            else if entry.note /= "" then
                entry.note

            else
                Category.label entry.category

        isOpen =
            opts.openMenu == Just entry.id
    in
    Html.div
        [ Html.Attributes.class "relative border-b border-dashed border-tan/70 flex items-baseline gap-1" ]
        [ Html.a
            [ Html.Attributes.href (Routing.editEntryPath opts.basePath entry.tripId entry.id)
            , Html.Attributes.class "flex-1 min-w-0 text-left py-3 flex items-baseline gap-3 cursor-pointer text-ink"
            ]
            [ Html.div [ Html.Attributes.class "flex-1 min-w-0" ]
                [ Html.div [ Html.Attributes.class "text-sm text-ink font-body truncate" ]
                    [ Html.text primaryLabel ]
                , Html.Extra.viewMaybe viewFuelSummary entry.fuelDetail
                , Html.div [ Html.Attributes.class "mt-1.5 flex items-center gap-2" ]
                    [ Html.span
                        [ Html.Attributes.class "inline-block text-[10px] font-mono uppercase tracking-wider text-moss bg-cream-deep px-2 py-0.5 rounded" ]
                        [ Html.text (Category.label entry.category) ]
                    , Html.span
                        [ Html.Attributes.class "text-xs leading-none"
                        , Html.Attributes.attribute "aria-hidden" "true"
                        ]
                        [ Html.text (Category.icon entry.category) ]
                    , Html.Extra.viewMaybe
                        (\_ ->
                            Html.span
                                [ Html.Attributes.class "text-moss"
                                , Html.Attributes.title "Has GPS coordinates"
                                ]
                                [ UI.Icons.pin "w-3 h-3" ]
                        )
                        entry.geoPoint
                    , viewAuthorChip opts.members entry.createdBy
                    ]
                ]
            , Html.div
                [ Html.Attributes.class "shrink-0" ]
                [ if Money.isZero entry.amount then
                    viewFreeBadge

                  else
                    Html.span
                        [ Html.Attributes.class "font-mono text-base text-forest tabular-nums" ]
                        [ UI.MoneyView.amount entry.currency entry.amount ]
                ]
            ]
        , viewRowMenuButton entry
        , Html.Extra.viewIf isOpen <|
            viewRowMenu opts.canMove opts.readOnly entry
        ]


{-| The celebratory "Free" pill that stands in for `$0.00` on the amount
rail (#1). A free campsite, fee-free park day, or hiker-box score isn't a
blank entry — it's a win worth surfacing, so it gets a filled forest badge
rather than a muted zero.
-}
viewFreeBadge : Html msg
viewFreeBadge =
    Html.span
        [ Html.Attributes.class "inline-block font-mono text-xs uppercase tracking-wider text-cream bg-forest px-2.5 py-1 rounded-full" ]
        [ Html.text "Free" ]


{-| A compact secondary line for fuel expenses: per-gallon price, volume,
and grade, joining only the parts the receipt actually captured (e.g.
`$4.299/gal · 12.345 gal · Regular`). `entry.fuelDetail` is only `Just`
when at least one part is present, so the joined text is never empty.
-}
viewFuelSummary : FuelDetail -> Html Msg
viewFuelSummary fuel =
    let
        parts : List String
        parts =
            List.filterMap identity
                [ Maybe.map (\p -> PricePerGallon.format p ++ "/gal") fuel.pricePerGallon
                , Maybe.map (\g -> Gallons.format g ++ " gal") fuel.gallons
                , Maybe.map (\p -> PricePerLiter.format p ++ "/L") fuel.pricePerLiter
                , Maybe.map (\l -> Liters.format l ++ " L") fuel.liters
                , Maybe.map FuelGrade.display fuel.grade
                ]
    in
    Html.div
        [ Html.Attributes.class "mt-0.5 text-xs text-moss font-mono tabular-nums truncate" ]
        [ Html.text (String.join " · " parts) ]


{-| Variant A author chip — a circle avatar followed by the author's
first name, sitting inside the existing meta row band. Renders to an
empty node on personal trips (members dict is empty) and on flock
trips when the author isn't in the cached membership (e.g. a former
member whose entry survives them).
-}
viewAuthorChip : Dict String FlockMember -> UserId -> Html Msg
viewAuthorChip members userId =
    Html.Extra.viewMaybe
        (\member ->
            Html.span
                [ Html.Attributes.class "inline-flex items-center gap-1 text-xs text-moss italic" ]
                [ UI.Avatar.viewInitial member.userId
                , Html.text member.displayName
                ]
        )
        (Dict.get (UserId.toString userId) members)


viewRowMenuButton : Entry.EffectiveEntry -> Html Msg
viewRowMenuButton entry =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Attributes.attribute "aria-label" "Row actions"
        , Html.Attributes.class "text-muted shrink-0 min-w-[32px] min-h-[32px] flex items-center justify-center"
        , Html.Events.onClick (AuthMsg (OpenLedgerMenu entry.id))
        ]
        [ UI.Icons.kebab "w-4 h-4" ]


viewRowMenu : Bool -> Bool -> Entry.EffectiveEntry -> Html Msg
viewRowMenu canMove readOnly entry =
    let
        expense =
            effectiveEntryToExpense entry

        moveItem =
            if canMove then
                [ menuItem
                    { danger = False
                    , disabled = readOnly
                    , icon = UI.Icons.move "w-4 h-4"
                    , label = "Move to trip…"
                    , onClick = AuthMsg (OpenMovePicker expense)
                    }
                ]

            else
                []

        duplicate =
            menuItem
                { danger = False
                , disabled = readOnly
                , icon = UI.Icons.copy "w-4 h-4"
                , label = "Duplicate"
                , onClick = AuthMsg (DuplicateEntry expense)
                }

        delete =
            menuItem
                { danger = True
                , disabled = readOnly
                , icon = UI.Icons.trash "w-4 h-4"
                , label = "Delete"
                , onClick = AuthMsg (VoidEntry expense)
                }
    in
    Html.div []
        [ Html.button
            [ Html.Attributes.type_ "button"
            , Html.Attributes.attribute "aria-label" "Close menu"
            , Html.Attributes.class "fixed inset-0 z-10 bg-transparent cursor-default"
            , Html.Events.onClick (AuthMsg CloseLedgerMenu)
            ]
            []
        , Html.div
            [ Html.Attributes.class "absolute right-0 top-10 z-20 w-44 bg-cream rounded-card shadow-panel border border-tan/60 py-1" ]
            (duplicate :: moveItem ++ [ delete ])
        ]


menuItem :
    { danger : Bool
    , disabled : Bool
    , icon : Html Msg
    , label : String
    , onClick : Msg
    }
    -> Html Msg
menuItem item =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Attributes.disabled item.disabled
        , Html.Attributes.title
            (if item.disabled then
                "This flock is read-only."

             else
                ""
            )
        , Html.Attributes.classList
            [ ( "w-full text-left px-3 py-2 text-sm flex items-center gap-2 hover:bg-cream-deep", True )
            , ( "text-rust", item.danger && not item.disabled )
            , ( "text-ink", not item.danger && not item.disabled )
            , ( "text-muted opacity-60 cursor-not-allowed", item.disabled )
            ]
        , Html.Events.onClick item.onClick
        ]
        [ item.icon
        , Html.text item.label
        ]


viewEmptyState : Html Msg
viewEmptyState =
    Html.div [ Html.Attributes.class "py-16 text-center" ]
        [ UI.Mascot.ternSvg "w-16 mx-auto opacity-40"
        , Html.p [ Html.Attributes.class "mt-4 font-display italic text-lg text-moss" ]
            [ Html.text "No entries yet." ]
        , Html.p [ Html.Attributes.class "mt-1 text-sm text-muted" ]
            [ Html.text "Snap a receipt to start the log." ]
        ]


viewSkeleton : Html Msg
viewSkeleton =
    UI.Mascot.loading
