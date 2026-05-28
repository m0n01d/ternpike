module UI.TripFormModal exposing (view)

{-| The create/edit-trip form, rendered as a modal overlay.

`Types.AuthState.tripForm` is the open/closed flag: `Just` renders the
modal, `Nothing` renders nothing. Opened by `OpenNewTripForm` (the
"New trip" button on the Trips page) or `OpenEditTripForm trip` (the
pencil icon next to the active trip).

The form fields and helpers (`viewTargetPicker`, `viewNewFlockInline`,
`viewInviteeChips`, etc.) used to live inline in `Pages/Trips.elm`;
they were lifted here so editing surfaces a clearly-modal UI instead
of an inline panel that scrolled into view below the trip list.

-}

import Data.SharedTrip exposing (SharedTrip)
import Data.SharedTripUi
import Data.SharedTrips
import Data.Tier as Tier
import Data.Trip as Trip exposing (TripField(..), TripForm)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode
import RemoteData
import Types exposing (AuthMsg_(..), AuthState, Msg(..))
import UI.Layout


view : AuthState -> Html Msg
view as_ =
    case as_.tripForm of
        Nothing ->
            Html.text ""

        Just form ->
            viewOpen as_ form


viewOpen : AuthState -> TripForm -> Html Msg
viewOpen as_ form =
    let
        isNew =
            form.editing == Nothing

        title =
            if isNew then
                "New Trip"

            else
                "Edit Trip"
    in
    Html.div
        [ Html.Attributes.class "fixed inset-0 bg-black/60 backdrop-blur-sm z-[9998] flex items-center justify-center p-6"
        , Html.Attributes.attribute "role" "dialog"
        , Html.Attributes.attribute "aria-modal" "true"
        , Html.Attributes.attribute "aria-label" title
        ]
        [ Html.div
            [ Html.Attributes.class "w-full max-w-md bg-parchment dark:bg-cream border border-tan rounded-2xl shadow-panel relative max-h-[90vh] overflow-y-auto" ]
            [ Html.button
                [ Html.Attributes.type_ "button"
                , Html.Attributes.class "absolute top-3 right-3 text-muted hover:text-ink text-2xl leading-none w-8 h-8 flex items-center justify-center"
                , Html.Attributes.attribute "aria-label" "Close"
                , Html.Events.onClick (AuthMsg CloseTripForm)
                ]
                [ Html.text "×" ]
            , viewForm as_ form title
            ]
        ]


viewForm : AuthState -> TripForm -> String -> Html Msg
viewForm as_ form title =
    let
        ownedFlocks =
            Data.SharedTrips.ownedBy as_.currentUser as_.sharedTrips

        isNew =
            form.editing == Nothing
    in
    Html.form
        [ Html.Attributes.class "p-5"
        , Html.Events.onSubmit (AuthMsg SaveTripForm)
        ]
        [ Html.p [ Html.Attributes.class "text-[15px] font-bold text-rust font-display mb-4 pr-8" ]
            [ Html.text title ]
        , viewSharedTripRequestErrors form
        , if not (List.isEmpty form.errors) then
            Html.div [ Html.Attributes.class "bg-rust-tint border border-rust rounded-lg p-2.5 mb-3" ]
                (List.map
                    (\e -> Html.p [ Html.Attributes.class "text-sm text-rust" ] [ Html.text e ])
                    form.errors
                )

          else
            Html.text ""
        , UI.Layout.formField "TRIP NAME"
            (Html.input
                [ Html.Attributes.type_ "text"
                , Html.Attributes.value form.name
                , Html.Events.onInput (AuthMsg << TripFieldChanged TripName)
                , Html.Attributes.placeholder "Alaska 2026"
                , UI.Layout.textInputStyle
                ]
                []
            )
        , if isNew then
            viewTargetPicker as_ form ownedFlocks

          else
            Html.text ""
        , UI.Layout.formField "DESCRIPTION"
            (Html.input
                [ Html.Attributes.type_ "text"
                , Html.Attributes.value form.description
                , Html.Events.onInput (AuthMsg << TripFieldChanged TripDescription)
                , Html.Attributes.placeholder "Optional"
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "START DATE"
            (Html.input
                [ Html.Attributes.type_ "date"
                , Html.Attributes.value form.startDate
                , Html.Events.onInput (AuthMsg << TripFieldChanged TripStartDate)
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "END DATE"
            (Html.input
                [ Html.Attributes.type_ "date"
                , Html.Attributes.value form.endDate
                , Html.Events.onInput (AuthMsg << TripFieldChanged TripEndDate)
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "BUDGET ($)"
            (Html.input
                [ Html.Attributes.type_ "number"
                , Html.Attributes.value form.budget
                , Html.Events.onInput (AuthMsg << TripFieldChanged TripBudget)
                , Html.Attributes.placeholder "0 = no budget"
                , UI.Layout.textInputStyle
                ]
                []
            )
        , UI.Layout.formField "COVER PHOTO URL"
            (Html.input
                [ Html.Attributes.type_ "url"
                , Html.Attributes.value form.coverPhotoUrl
                , Html.Events.onInput (AuthMsg << TripFieldChanged TripCoverPhoto)
                , Html.Attributes.placeholder "https://..."
                , UI.Layout.textInputStyle
                ]
                []
            )
        , Html.div [ Html.Attributes.class "flex gap-2.5 mt-4" ]
            [ Html.button
                [ Html.Attributes.type_ "submit"
                , Html.Attributes.disabled (saveBlocked as_ form)
                , Html.Attributes.classList
                    [ ( "flex-1 bg-rust text-parchment border-none rounded-lg py-3 text-[15px] font-bold cursor-pointer", True )
                    , ( "opacity-50 cursor-not-allowed", saveBlocked as_ form )
                    ]
                ]
                [ Html.text (submitLabel isNew form) ]
            , Html.button
                [ Html.Attributes.type_ "button"
                , Html.Events.onClick (AuthMsg CloseTripForm)
                , Html.Attributes.class "flex-1 bg-transparent text-muted border border-tan rounded-lg py-3 text-[15px] cursor-pointer"
                ]
                [ Html.text "Cancel" ]
            ]
        ]


{-| Segmented control that asks "where does this trip live?" — Personal
or one of the user-owned flocks. Only shown on the create path with
at least one owned flock; the spec is to collapse the single-option
case to the implicit Personal default so the user never sees a
segmented control with one tile.
-}
viewTargetPicker : AuthState -> TripForm -> List SharedTrip -> Html Msg
viewTargetPicker as_ form ownedFlocks =
    let
        selected =
            form.target

        personalTile =
            viewTargetTile
                { active = selected == Trip.ToPersonal
                , label = "Just me"
                , sub = "PERSONAL"
                , onSelect = AuthMsg (TripTargetSelected Trip.ToPersonal)
                }

        flockTiles =
            List.map
                (\flock ->
                    viewTargetTile
                        { active = selected == Trip.ToExistingFlock flock.id
                        , label = flock.name
                        , sub = flockTileSub flock
                        , onSelect = AuthMsg (TripTargetSelected (Trip.ToExistingFlock flock.id))
                        }
                )
                ownedFlocks

        newSharedTile =
            viewTargetTile
                { active = isToNewFlock selected
                , label = "+ New shared trip"
                , sub = "INVITE PEOPLE"
                , onSelect = AuthMsg (TripTargetSelected (Trip.ToNewFlock Trip.defaultNewFlockDraft))
                }
    in
    UI.Layout.formField "WHO'S ON THIS TRIP?"
        (Html.div []
            [ Html.div [ Html.Attributes.class "flex gap-2 flex-wrap" ]
                (personalTile :: flockTiles ++ [ newSharedTile ])
            , viewNewFlockInline as_ form
            , Html.p [ Html.Attributes.class "mt-2 text-[11px] text-muted font-mono tracking-wide italic" ]
                [ Html.text "This can't be changed later." ]
            ]
        )


{-| Submit blocked while a save is in flight OR when a Tern user
has the "+ New shared trip" tile selected (the inline upgrade prompt
is shown instead).
-}
saveBlocked : AuthState -> TripForm -> Bool
saveBlocked as_ form =
    let
        sharedTripInFlight =
            form.sharedTripRequest == RemoteData.Loading
    in
    form.submitting
        || sharedTripInFlight
        || (isToNewFlock form.target && not (Tier.isPaid as_.tier))


{-| True when the form's currently-selected target is the "+ New shared
trip" tile, regardless of the draft's contents.
-}
isToNewFlock : Trip.CreateTarget -> Bool
isToNewFlock target =
    case target of
        Trip.ToNewFlock _ ->
            True

        _ ->
            False


{-| The inline panel that appears under the picker when the user has
selected "+ New shared trip". For Osprey+ it exposes the chip-input for
invitee emails and an optional Group Name override. For Tern it
swaps in an upgrade prompt and the submit button is blocked elsewhere.
-}
viewNewFlockInline : AuthState -> TripForm -> Html Msg
viewNewFlockInline as_ form =
    case form.target of
        Trip.ToNewFlock draft ->
            if Tier.isPaid as_.tier then
                viewNewFlockFields form draft

            else
                viewFledglingUpgradePrompt

        _ ->
            Html.text ""


viewFledglingUpgradePrompt : Html Msg
viewFledglingUpgradePrompt =
    Html.div [ Html.Attributes.class "mt-3 bg-rust-tint border border-rust/30 rounded-lg px-3 py-2.5" ]
        [ Html.p [ Html.Attributes.class "text-[13px] text-rust-deep" ]
            [ Html.text "Sharing requires Osprey. "
            , Html.a
                [ Html.Attributes.href "/settings#billing"
                , Html.Attributes.class "underline font-semibold"
                ]
                [ Html.text "Upgrade to Osprey →" ]
            ]
        ]


viewNewFlockFields : TripForm -> Trip.NewFlockDraft -> Html Msg
viewNewFlockFields form draft =
    let
        effectiveGroupName =
            if form.groupNameOverridden then
                draft.groupName

            else
                form.name
    in
    Html.div [ Html.Attributes.class "mt-3 space-y-3" ]
        [ UI.Layout.formField "INVITE EMAILS"
            (viewInviteeChips draft)
        , Html.details []
            [ Html.summary
                [ Html.Attributes.class "text-[11px] font-mono uppercase tracking-widest text-moss cursor-pointer" ]
                [ Html.text "Advanced — group name" ]
            , Html.div [ Html.Attributes.class "mt-2" ]
                [ Html.input
                    [ Html.Attributes.type_ "text"
                    , Html.Attributes.value effectiveGroupName
                    , Html.Events.onInput (AuthMsg << TripGroupNameChanged)
                    , Html.Attributes.placeholder "Defaults to trip name"
                    , UI.Layout.textInputStyle
                    ]
                    []
                , Html.p [ Html.Attributes.class "mt-1 text-[11px] text-muted font-mono italic" ]
                    [ Html.text "Name the group to reuse it for future trips." ]
                ]
            ]
        ]


viewInviteeChips : Trip.NewFlockDraft -> Html Msg
viewInviteeChips draft =
    Html.div [ Html.Attributes.class "flex flex-wrap items-center gap-1.5" ]
        (List.indexedMap viewInviteeChip draft.invitees
            ++ [ Html.input
                    [ Html.Attributes.type_ "email"
                    , Html.Attributes.value draft.inviteesDraft
                    , Html.Events.onInput (AuthMsg << TripInviteeDraftChanged)
                    , Html.Events.preventDefaultOn "keydown" inviteeKeyDecoder
                    , Html.Attributes.placeholder
                        (if List.isEmpty draft.invitees then
                            "name@example.com"

                         else
                            "add another…"
                        )
                    , Html.Attributes.class "flex-1 min-w-[140px] bg-parchment dark:bg-cream border border-tan rounded-lg px-2 py-1.5 text-[13px] focus:outline-none focus:border-moss"
                    ]
                    []
               ]
        )


viewInviteeChip : Int -> String -> Html Msg
viewInviteeChip index email =
    Html.span
        [ Html.Attributes.class "inline-flex items-center gap-1 rounded-full bg-rust-tint border border-rust/30 px-2 py-0.5 text-[12px] text-rust-deep" ]
        [ Html.text email
        , Html.button
            [ Html.Attributes.type_ "button"
            , Html.Attributes.attribute "aria-label" ("Remove " ++ email)
            , Html.Events.onClick (AuthMsg (TripInviteeRemoved index))
            , Html.Attributes.class "text-rust-deep/70 hover:text-rust-deep cursor-pointer"
            ]
            [ Html.text "×" ]
        ]


{-| Commit the in-progress invitee-draft input on Enter, Tab, or comma —
matches the chip-input idiom common to email forms. Returns
`(Msg, preventDefault)` so the Enter key adds a chip without bubbling
up to the parent `<form>` and submitting the trip.
-}
inviteeKeyDecoder : Json.Decode.Decoder ( Msg, Bool )
inviteeKeyDecoder =
    Json.Decode.field "key" Json.Decode.string
        |> Json.Decode.andThen
            (\k ->
                if k == "Enter" || k == "Tab" || k == "," then
                    Json.Decode.succeed ( AuthMsg TripInviteeAdded, True )

                else
                    Json.Decode.fail "ignored"
            )


viewTargetTile :
    { active : Bool, label : String, onSelect : Msg, sub : String }
    -> Html Msg
viewTargetTile opts =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Events.onClick opts.onSelect
        , Html.Attributes.classList
            [ ( "flex-1 min-w-[120px] rounded-lg border px-3 py-2 text-left cursor-pointer", True )
            , ( "bg-rust-tint border-rust-deep text-rust-deep", opts.active )
            , ( "bg-parchment dark:bg-cream border-tan text-ink hover:border-moss", not opts.active )
            ]
        ]
        [ Html.div [ Html.Attributes.class "text-[13px] font-semibold leading-tight" ]
            [ Html.text opts.label ]
        , Html.div [ Html.Attributes.class "mt-1 text-[10px] font-mono uppercase tracking-widest text-moss" ]
            [ Html.text opts.sub ]
        ]


{-| Render an error chip when the shared-trip creation HTTP call fails.
One exhaustive `case` so the compiler forces us to handle every
`RemoteData` state; no layered checks or wildcards.
-}
viewSharedTripRequestErrors : TripForm -> Html Msg
viewSharedTripRequestErrors form =
    case form.sharedTripRequest of
        RemoteData.NotAsked ->
            Html.text ""

        RemoteData.Loading ->
            Html.text ""

        RemoteData.Failure err ->
            Html.div [ Html.Attributes.class "bg-rust-tint border border-rust rounded-lg p-2.5 mb-3" ]
                [ Html.p [ Html.Attributes.class "text-sm text-rust" ]
                    [ Html.text (Data.SharedTripUi.errorMessage err) ]
                ]

        RemoteData.Success _ ->
            Html.text ""


{-| The submit button label. One exhaustive `case` on `sharedTripRequest`
so the compiler tells us when `RemoteData` grows a new arm.
-}
submitLabel : Bool -> TripForm -> String
submitLabel isNew form =
    case form.sharedTripRequest of
        RemoteData.NotAsked ->
            if form.submitting then
                "Saving…"

            else if isNew then
                "Create trip"

            else
                "Save"

        RemoteData.Loading ->
            "Creating shared trip…"

        RemoteData.Failure _ ->
            if isNew then
                "Create trip"

            else
                "Save"

        RemoteData.Success _ ->
            "Saving…"


{-| The sub-label under a flock tile: "Owner + N more" reads cleaner
than a comma-joined initial list when the flock is large, and short
enough at small flocks to keep the segmented control single-line.
-}
flockTileSub : SharedTrip -> String
flockTileSub flock =
    let
        count =
            List.length (Data.SharedTrip.members flock)
    in
    if count <= 1 then
        "JUST OWNER"

    else
        "OWNER + " ++ String.fromInt (count - 1)
