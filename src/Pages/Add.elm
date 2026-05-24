module Pages.Add exposing (viewTab)

import Data.Category as Category exposing (Category)
import Data.GeoPoint as GeoPoint
import Data.Location exposing (LocationSource(..), LocationState(..))
import Data.Navigation exposing (Route(..), Tab(..))
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod(..))
import Data.PendingEntry exposing (AddPageMode(..), PendingEntry, PendingForm(..))
import Data.ScanItemId as ScanItemId
import Data.SharedTrip exposing (SharedTrip)
import Data.SharedTrips
import Data.Trip exposing (Trip)
import Data.Trips
import Data.UserId as UserId
import Dict
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Routing
import Types exposing (AuthState, Msg(..))
import UI.Button
import UI.Card
import UI.Layout
import UI.Mascot
import UI.Rule
import UI.SharedTripBadge
import UI.Skeleton


viewTab : AuthState -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewTab as_ =
    case addPageMode as_.route as_.form of
        AddPageLoading ->
            { actions = []
            , body = viewLoadingBody
            , hero = viewLoadingHero
            }

        AddPageNew ->
            let
                pending =
                    formPending as_.form
            in
            { actions = viewNewActions as_
            , body = viewBody as_ pending False
            , hero = viewHero pending
            }

        AddPageEditing ->
            let
                pending =
                    formPending as_.form
            in
            { actions = viewEditingActions as_
            , body = viewBody as_ pending True
            , hero = viewHero pending
            }


addPageMode : Route -> PendingForm -> AddPageMode
addPageMode route form =
    case route of
        RouteEditEntry _ id ->
            case form of
                EditForm formId _ ->
                    if formId == id then
                        AddPageEditing

                    else
                        AddPageLoading

                FreshForm _ ->
                    AddPageLoading

        _ ->
            AddPageNew


formPending : PendingForm -> PendingEntry
formPending form =
    case form of
        EditForm _ p ->
            p

        FreshForm p ->
            p


viewNewActions : AuthState -> List (Html Msg)
viewNewActions model =
    if model.activeScanItemId /= Nothing then
        [ UI.Button.ghost { label = "← queue", onClick = BackToQueue } ]

    else
        []


viewEditingActions : AuthState -> List (Html Msg)
viewEditingActions model =
    [ UI.Button.ghostLink
        { href = Routing.pathForCurrentTab model LedgerTab
        , label = "← cancel"
        }
    ]


viewHero : PendingEntry -> Html Msg
viewHero pending =
    Html.div [ Html.Attributes.class "py-2" ]
        [ Html.div [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss mb-1" ]
            [ Html.text "AMOUNT" ]
        , Html.div [ Html.Attributes.class "h-[3rem] flex items-start gap-0" ]
            [ Html.span
                [ Html.Attributes.class "font-display text-5xl font-black text-forest leading-none" ]
                [ Html.text "$" ]
            , Html.input
                [ Html.Attributes.type_ "number"
                , Html.Attributes.attribute "inputmode" "decimal"
                , Html.Attributes.value pending.amount
                , Html.Events.onInput AmountChanged
                , Html.Attributes.placeholder "0.00"
                , Html.Attributes.class "h-[3.5rem] -translate-y-1 w-full bg-transparent border-0 outline-none p-0 appearance-none font-display text-5xl font-black text-forest tabular-nums tracking-tight leading-none"
                ]
                []
            ]
        ]


viewLoadingHero : Html Msg
viewLoadingHero =
    UI.Mascot.loading


viewBody : AuthState -> PendingEntry -> Bool -> Html Msg
viewBody model pending isEditing =
    let
        flockContext =
            activeFlockContext model

        readOnly =
            isActiveTripReadOnly model
    in
    Html.div []
        [ viewFlockContextStrip flockContext
        , viewScanPreview model
        , viewVisibleToCaption flockContext
        , UI.Rule.kicker "THE BASICS"
        , UI.Card.subCard
            [ UI.Layout.formField "CATEGORY"
                (Html.div [ Html.Attributes.class "grid grid-cols-4 gap-2" ]
                    (List.map (viewCategoryBtn pending.category) Category.all)
                )
            , UI.Layout.formField "DATE"
                (Html.input
                    [ Html.Attributes.type_ "date"
                    , Html.Attributes.value pending.date
                    , Html.Events.onInput DateChanged
                    , UI.Layout.textInputStyle
                    ]
                    []
                )
            , UI.Layout.formField "PAID WITH"
                (viewPaymentMethodToggle pending.paymentMethod)
            ]
        , UI.Rule.kicker "WHERE & WHO"
        , UI.Card.subCard
            [ UI.Layout.formField "MERCHANT"
                (Html.input
                    [ Html.Attributes.type_ "text"
                    , Html.Attributes.value pending.merchant
                    , Html.Events.onInput MerchantChanged
                    , Html.Attributes.placeholder "optional"
                    , UI.Layout.textInputStyle
                    ]
                    []
                )
            , UI.Layout.formField "ADDRESS"
                (Html.input
                    [ Html.Attributes.type_ "text"
                    , Html.Attributes.value pending.address
                    , Html.Events.onInput AddressChanged
                    , Html.Attributes.placeholder "optional — street, city, state"
                    , UI.Layout.textInputStyle
                    ]
                    []
                )
            , UI.Layout.formField "LOCATION" (viewLocationWidget model pending)
            ]
        , UI.Rule.kicker "NOTES"
        , UI.Card.subCard
            [ UI.Layout.formField "NOTE"
                (Html.input
                    [ Html.Attributes.type_ "text"
                    , Html.Attributes.value pending.note
                    , Html.Events.onInput NoteChanged
                    , Html.Attributes.placeholder "brief (50 chars)"
                    , Html.Attributes.attribute "maxlength" "50"
                    , UI.Layout.textInputStyle
                    ]
                    []
                )
            , UI.Layout.formField "DETAILS"
                (Html.textarea
                    [ Html.Attributes.value pending.longNote
                    , Html.Events.onInput LongNoteChanged
                    , Html.Attributes.placeholder "optional — what happened, where, any context (280 chars)"
                    , Html.Attributes.attribute "maxlength" "280"
                    , Html.Attributes.attribute "rows" "3"
                    , Html.Attributes.class "w-full"
                    ]
                    []
                )
            ]
        , Html.button
            [ Html.Events.onClick SubmitEntry
            , Html.Attributes.disabled (model.submitting || readOnly)
            , Html.Attributes.title
                (if readOnly then
                    "This flock is read-only."

                 else
                    ""
                )
            , Html.Attributes.class
                ("w-full bg-rust hover:bg-rust-deep text-parchment border-none rounded-lg py-[18px] text-lg font-bold tracking-wide cursor-pointer mt-2 min-h-[56px] "
                    ++ (if model.submitting || readOnly then
                            "opacity-60 cursor-not-allowed"

                        else
                            ""
                       )
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


{-| The active trip's flock context, if any. `Nothing` for personal
trips and for trips whose flock meta hasn't synced yet — in either
case the Add page renders without the flock chrome.
-}
activeFlockContext : AuthState -> Maybe ( Trip, SharedTrip )
activeFlockContext model =
    case ( Routing.routeTripId model.route, model.trips ) of
        ( Just tripId, Data.Trips.TripsLoaded loadedTrips ) ->
            case Data.Trips.findTrip tripId loadedTrips of
                Just trip ->
                    trip.flockId
                        |> Maybe.andThen (\fid -> Data.SharedTrips.get fid model.sharedTrips)
                        |> Maybe.map (\flock -> ( trip, flock ))

                Nothing ->
                    Nothing

        _ ->
            Nothing


{-| `True` when the route's active trip belongs to a flock whose
billing status is `Grace` or `Frozen`. Personal trips, unloaded
trips, and active flocks all return `False`.
-}
isActiveTripReadOnly : AuthState -> Bool
isActiveTripReadOnly model =
    case activeFlockContext model of
        Just ( _, flock ) ->
            Data.SharedTrip.isReadOnly flock

        Nothing ->
            False


{-| The "ADDING TO / Trip Name" strip at the top of the Add screen.
Only rendered for flock-scoped trips; on personal trips the form keeps
its current top-of-screen behaviour.
-}
viewFlockContextStrip : Maybe ( Trip, SharedTrip ) -> Html Msg
viewFlockContextStrip ctx =
    case ctx of
        Just ( trip, flock ) ->
            Html.div
                [ Html.Attributes.class "mb-4 flex items-center gap-3 bg-cream-deep border border-tan rounded-card px-4 py-3" ]
                [ UI.SharedTripBadge.view flock
                , Html.div [ Html.Attributes.class "flex flex-col leading-tight min-w-0" ]
                    [ Html.span
                        [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-moss" ]
                        [ Html.text "Adding to" ]
                    , Html.span
                        [ Html.Attributes.class "text-sm font-semibold text-forest truncate" ]
                        [ Html.text trip.name ]
                    ]
                ]

        Nothing ->
            Html.text ""


{-| The "visible to Alice + Bob" caption rendered just under the amount
hero on flock-scoped trips. Lists the flock's members by first name
(email local-part), collapsing to "+ N more" when there are more than
three.
-}
viewVisibleToCaption : Maybe ( Trip, SharedTrip ) -> Html Msg
viewVisibleToCaption ctx =
    case ctx of
        Just ( _, flock ) ->
            Html.p
                [ Html.Attributes.class "-mt-2 mb-4 text-center text-[11px] font-mono uppercase tracking-widest text-moss" ]
                [ Html.text ("Visible to " ++ visibleToLabel flock) ]

        Nothing ->
            Html.text ""


visibleToLabel : SharedTrip -> String
visibleToLabel flock =
    let
        names =
            List.map firstNameFor (Data.SharedTrip.members flock)
    in
    case names of
        [] ->
            "you"

        _ ->
            if List.length names <= 3 then
                String.join ", " names

            else
                String.join ", " (List.take 2 names)
                    ++ ", + "
                    ++ String.fromInt (List.length names - 2)
                    ++ " more"


firstNameFor : UserId.UserId -> String
firstNameFor user =
    case String.split "@" (UserId.toString user) of
        head :: _ ->
            head

        [] ->
            UserId.toString user


viewLoadingBody : Html Msg
viewLoadingBody =
    Html.div []
        [ UI.Rule.kicker "THE BASICS"
        , UI.Card.subCard
            [ UI.Skeleton.card
            , UI.Skeleton.row
            ]
        , UI.Rule.kicker "WHERE & WHO"
        , UI.Card.subCard
            [ UI.Skeleton.row
            , UI.Skeleton.row
            ]
        , UI.Rule.kicker "NOTES"
        , UI.Card.subCard
            [ UI.Skeleton.row
            , UI.Skeleton.row
            ]
        ]


viewScanPreview : AuthState -> Html Msg
viewScanPreview model =
    case model.activeScanItemId of
        Nothing ->
            Html.text ""

        Just id ->
            case Dict.get (ScanItemId.toString id) model.scanQueue of
                Just item ->
                    Html.div [ Html.Attributes.class "sticky top-0 z-10 mb-4" ]
                        [ UI.Card.subCard
                            [ Html.img
                                [ Html.Attributes.src item.imageUrl
                                , Html.Attributes.class "w-full rounded-xl object-contain max-h-60 bg-cream"
                                ]
                                []
                            ]
                        ]

                Nothing ->
                    Html.text ""


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
                ++ (if active then
                        "font-bold"

                    else
                        "border border-tan bg-cream"
                   )
            )

        -- dynamic color from data; cannot express as a Tailwind class
        , Html.Attributes.style "background"
            (if active then
                Category.color cat

             else
                ""
            )
        , Html.Attributes.style "border-color"
            (if active then
                Category.color cat

             else
                ""
            )
        ]
        [ Html.span [ Html.Attributes.class "text-xl leading-none" ] [ Html.text (Category.icon cat) ]
        , Html.text (Category.label cat)
        ]


viewLocationWidget : AuthState -> PendingEntry -> Html Msg
viewLocationWidget model pending =
    Html.div []
        [ viewLocationStatus pending.locationState
        , if model.showMapPicker then
            Html.node "map-picker"
                [ Html.Attributes.attribute "lat"
                    (case pending.locationState of
                        LocationGot point _ ->
                            String.fromFloat (GeoPoint.latDegrees point)

                        _ ->
                            "64.2008"
                    )
                , Html.Attributes.attribute "lon"
                    (case pending.locationState of
                        LocationGot point _ ->
                            String.fromFloat (GeoPoint.lonDegrees point)

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

        LocationGot point source ->
            let
                sourceLabel =
                    case source of
                        ExifGps ->
                            "📍 from photo"

                        BrowserGeo ->
                            "📍 GPS"

                        Geocoded ->
                            "📍 from address"

                        ManualPin ->
                            "📍 pinned"
            in
            Html.div [ Html.Attributes.class "flex items-center gap-3 py-2" ]
                [ Html.span [ Html.Attributes.class "text-moss text-sm" ]
                    [ Html.text (sourceLabel ++ " — " ++ GeoPoint.format point) ]
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


viewPaymentMethodToggle : Maybe PaymentMethod -> Html Msg
viewPaymentMethodToggle selected =
    Html.div [ Html.Attributes.class "flex gap-2 py-1" ]
        (List.map (viewPaymentMethodBtn selected) [ Cash, Credit ])


viewPaymentMethodBtn : Maybe PaymentMethod -> PaymentMethod -> Html Msg
viewPaymentMethodBtn selected pm =
    let
        active =
            selected == Just pm

        nextValue =
            if active then
                Nothing

            else
                Just pm
    in
    Html.button
        [ Html.Events.onClick (PaymentMethodChanged nextValue)
        , Html.Attributes.classList
            [ ( "rounded-lg py-2 px-4 text-sm cursor-pointer border", True )
            , ( "bg-forest text-parchment border-forest font-bold", active )
            , ( "bg-cream text-ink border-tan", not active )
            ]
        ]
        [ Html.text (PaymentMethod.label pm) ]
