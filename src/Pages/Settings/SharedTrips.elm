module Pages.Settings.SharedTrips exposing (view, viewModal)

{-| The "Flocks" subsection of the Settings page (#62).

Renders one card per shared trip the user belongs to plus a "Create flock"
button at the top with a Tern-friendly upgrade hint. Owner cards
get Invite / Transfer-ownership / Leave buttons; member cards only
get Leave. A "View members" toggle expands the inline avatar stack
into a full email list.

Modals (create / invite / transfer / leave-confirm) are rendered
separately by `viewModal` — they sit at the page root rather than
inside the card so they overlay everything. Each modal carries its
own `request : RemoteData Http.Error _` so the button busy state +
error chip are derived from one exhaustive `case` per CLAUDE.md's
RemoteData rule.

-}

import Data.SharedTrip as SharedTrip exposing (SharedTrip)
import Data.SharedTripUi as SharedTripUi
import Data.SharedTrips as SharedTrips
import Data.Tier as Tier
import Data.UserId as UserId exposing (UserId)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Extra
import Http
import RemoteData exposing (RemoteData)
import Types exposing (AuthMsg_(..), AuthState, Msg(..))
import UI.Avatar
import UI.BillingBanner
import UI.Button
import UI.Card
import UI.Rule
import UI.SharedTripBadge


view : AuthState -> Html Msg
view as_ =
    let
        currentUser =
            UserId.fromString as_.creds.email

        joined =
            SharedTrips.joinedBy currentUser as_.sharedTrips
    in
    Html.div []
        [ UI.Rule.kicker "SHARED TRIPS"
        , viewCreateRow as_.tier
        , if List.isEmpty joined then
            viewEmptyState

          else
            Html.div [] (List.map (viewSharedTripCard as_ currentUser) joined)
        ]


viewCreateRow : Tier.Tier -> Html Msg
viewCreateRow tier =
    UI.Card.subCard
        [ Html.div [ Html.Attributes.class "flex items-start justify-between gap-3" ]
            [ Html.p [ Html.Attributes.class "text-xs text-muted flex-1" ]
                [ Html.text
                    (if Tier.isPaid tier then
                        "Log expenses together with a partner or household."

                     else
                        "Share a trip with a partner or household so you can log expenses together. Upgrade to Osprey to start one."
                    )
                ]
            , if Tier.isPaid tier then
                UI.Button.primary { label = "Share a trip", onClick = AuthMsg OpenCreateSharedTripModal }

              else
                Html.button
                    [ Html.Attributes.type_ "button"
                    , Html.Attributes.disabled True
                    , Html.Attributes.class "shrink-0 px-3 py-1.5 text-sm font-medium rounded-lg bg-cream-deep text-muted border border-tan cursor-not-allowed"
                    ]
                    [ Html.text "Share a trip" ]
            ]
        ]


viewEmptyState : Html Msg
viewEmptyState =
    UI.Card.subCard
        [ Html.p [ Html.Attributes.class "text-xs text-muted" ]
            [ Html.text "You haven't shared a trip yet. Start a "
            , Html.a
                [ Html.Attributes.href "/trips"
                , Html.Attributes.class "text-rust-deep underline"
                ]
                [ Html.text "shared trip" ]
            , Html.text " from the Trips page, or accept an invite link to join one."
            ]
        ]


viewSharedTripCard : AuthState -> UserId -> SharedTrip -> Html Msg
viewSharedTripCard as_ currentUser sharedTrip =
    let
        owner =
            SharedTrip.isOwner currentUser sharedTrip

        membersExpanded =
            SharedTripUi.isExpanded sharedTrip.id as_.sharedTripUi
    in
    UI.Card.subCard
        [ Html.div [ Html.Attributes.class "flex items-start justify-between gap-3 mb-3" ]
            [ Html.div [ Html.Attributes.class "flex flex-col gap-1.5 min-w-0" ]
                [ UI.SharedTripBadge.view sharedTrip
                , Html.p [ Html.Attributes.class "text-xs text-muted font-mono uppercase tracking-widest" ]
                    [ Html.text
                        (if owner then
                            "Owner"

                         else
                            "Member"
                        )
                    ]
                ]
            , viewMembersStack sharedTrip
            ]
        , UI.BillingBanner.viewInline
            { currentUser = currentUser
            , flock = sharedTrip
            , tier = as_.tier
            , today = as_.today
            }
        , Html.div [ Html.Attributes.class "flex flex-wrap gap-2 mt-3" ]
            (if owner then
                [ UI.Button.secondary { label = "Invite", onClick = AuthMsg (OpenInviteModal sharedTrip.id) }
                , UI.Button.ghost { label = "Transfer ownership", onClick = AuthMsg (OpenTransferModal sharedTrip.id) }
                ]

             else
                [ UI.Button.ghost { label = "Leave", onClick = AuthMsg (OpenLeaveConfirmModal sharedTrip.id) }
                ]
            )
        , Html.button
            [ Html.Attributes.type_ "button"
            , Html.Events.onClick (AuthMsg (ToggleSharedTripMembers sharedTrip.id))
            , Html.Attributes.class "mt-3 text-xs font-mono uppercase tracking-widest text-moss hover:text-forest bg-transparent border-0 cursor-pointer p-0"
            ]
            [ Html.text
                (if membersExpanded then
                    "Hide members"

                 else
                    "View members"
                )
            ]
        , Html.Extra.viewIf membersExpanded (viewMembersList sharedTrip)
        ]


viewMembersStack : SharedTrip -> Html msg
viewMembersStack sharedTrip =
    Html.div [ Html.Attributes.class "shrink-0" ]
        [ UI.Avatar.viewStack (SharedTrip.members sharedTrip) ]


viewMembersList : SharedTrip -> Html msg
viewMembersList sharedTrip =
    let
        members =
            SharedTrip.members sharedTrip
    in
    Html.div [ Html.Attributes.class "mt-3 flex flex-col gap-2" ]
        (members
            |> List.map
                (\u ->
                    Html.div [ Html.Attributes.class "flex items-center gap-2" ]
                        [ UI.Avatar.viewInitial u
                        , Html.span [ Html.Attributes.class "text-sm text-ink" ]
                            [ Html.text (UserId.handleIn u members) ]
                        , Html.Extra.viewIf (SharedTrip.isOwner u sharedTrip)
                            (Html.span [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-rust-deep" ]
                                [ Html.text "Owner" ]
                            )
                        ]
                )
        )



-- MODALS


viewModal : AuthState -> Html Msg
viewModal as_ =
    case as_.sharedTripUi.modal of
        SharedTripUi.NoModal ->
            Html.Extra.nothing

        SharedTripUi.CreateModal { name, request } ->
            modalShell "New shared trip"
                [ Html.p [ Html.Attributes.class "text-sm text-muted mb-3" ]
                    [ Html.text "Give your shared trip a name. You can invite people once it's created." ]
                , formField "NAME"
                    (Html.input
                        [ Html.Attributes.type_ "text"
                        , Html.Attributes.value name
                        , Html.Events.onInput (AuthMsg << CreateSharedTripNameChanged)
                        , Html.Attributes.placeholder "Honeymoon"
                        , textInputStyle
                        ]
                        []
                    )
                , viewModalActions
                    { cancel = ( "Cancel", AuthMsg CloseSharedTripModal )
                    , confirmLabel = "Share a trip"
                    , confirmMsg = AuthMsg SubmitCreateSharedTrip
                    , request = RemoteData.map (\_ -> ()) request
                    }
                ]

        SharedTripUi.InviteModal _ { email, request } ->
            modalShell "Invite to this trip"
                [ Html.p [ Html.Attributes.class "text-sm text-muted mb-3" ]
                    [ Html.text "We'll email them a one-click link to accept." ]
                , formField "EMAIL"
                    (Html.input
                        [ Html.Attributes.type_ "email"
                        , Html.Attributes.value email
                        , Html.Events.onInput (AuthMsg << InviteEmailChanged)
                        , Html.Attributes.placeholder "name@example.com"
                        , textInputStyle
                        ]
                        []
                    )
                , viewModalActions
                    { cancel = ( "Cancel", AuthMsg CloseSharedTripModal )
                    , confirmLabel = "Send invite"
                    , confirmMsg = AuthMsg SubmitInvite
                    , request = request
                    }
                ]

        SharedTripUi.LeaveConfirmModal sharedTripId { request } ->
            let
                sharedTripName =
                    SharedTrips.get sharedTripId as_.sharedTrips
                        |> Maybe.map .name
                        |> Maybe.withDefault "this shared trip"
            in
            modalShell "Leave shared trip?"
                [ Html.p [ Html.Attributes.class "text-sm text-ink mb-3" ]
                    [ Html.text
                        ("Leave the "
                            ++ sharedTripName
                            ++ " shared trip? You'll lose access to its trips on this device, but the shared trip keeps the data."
                        )
                    ]
                , viewModalActions
                    { cancel = ( "Cancel", AuthMsg CloseSharedTripModal )
                    , confirmLabel = "Leave"
                    , confirmMsg = AuthMsg (LeaveSharedTripConfirmed sharedTripId)
                    , request = request
                    }
                ]

        SharedTripUi.TransferModal sharedTripId { request, target } ->
            let
                memberOptions =
                    SharedTrips.get sharedTripId as_.sharedTrips
                        |> Maybe.map
                            (\sharedTrip ->
                                let
                                    others =
                                        sharedTrip.otherMembers
                                in
                                List.map
                                    (\u -> ( UserId.toString u, UserId.handleIn u others ))
                                    others
                            )
                        |> Maybe.withDefault []
            in
            modalShell "Transfer ownership"
                [ Html.p [ Html.Attributes.class "text-sm text-muted mb-3" ]
                    [ Html.text "New owner must be on Osprey or higher. The server will reject Tern targets." ]
                , formField "MEMBER"
                    (Html.select
                        [ Html.Events.onInput (AuthMsg << TransferTargetChanged)
                        , textInputStyle
                        ]
                        (Html.option
                            [ Html.Attributes.value "" ]
                            [ Html.text "Select a member…" ]
                            :: List.map
                                (\( email, displayHandle ) ->
                                    Html.option
                                        [ Html.Attributes.value email
                                        , Html.Attributes.selected (email == target)
                                        ]
                                        [ Html.text displayHandle ]
                                )
                                memberOptions
                        )
                    )
                , viewModalActions
                    { cancel = ( "Cancel", AuthMsg CloseSharedTripModal )
                    , confirmLabel = "Transfer"
                    , confirmMsg = AuthMsg SubmitTransfer
                    , request = request
                    }
                ]


modalShell : String -> List (Html Msg) -> Html Msg
modalShell title children =
    Html.div
        [ Html.Attributes.class "fixed inset-0 z-40 flex items-center justify-center px-5 bg-black/50" ]
        [ Html.div
            [ Html.Attributes.class "w-full max-w-md bg-cream rounded-card shadow-panel p-5" ]
            (Html.p
                [ Html.Attributes.class "text-[15px] font-bold text-rust font-display mb-4" ]
                [ Html.text title ]
                :: children
            )
        ]


{-| Render the error chip (if any) plus the confirm/cancel button pair
for one modal, driven by a single exhaustive `case` over the modal's
`request : RemoteData Http.Error ()`. Per CLAUDE.md, this is the only
match against `request` — no separate `isLoading` boolean or
secondary `case` for the error chip is allowed.

Branches:

  - `NotAsked` — idle. Active confirm button, no chip.
  - `Loading` — request in flight. Busy confirm button, no chip.
  - `Failure err` — show the error chip + a still-active confirm
    button so the user can retry. The HTTP error is rendered via
    `SharedTripUi.errorMessage`.
  - `Success ()` — by the time the view sees this, `update` is
    about to swap `modal = NoModal` in the same step. Render the
    active confirm button (no chip, nothing busy) so the brief
    transition frame isn't disabled.

-}
viewModalActions :
    { cancel : ( String, Msg )
    , confirmLabel : String
    , confirmMsg : Msg
    , request : RemoteData Http.Error ()
    }
    -> Html Msg
viewModalActions { cancel, confirmLabel, confirmMsg, request } =
    let
        ( cancelLabel, cancelMsg ) =
            cancel

        ( chip, confirmButton ) =
            case request of
                RemoteData.NotAsked ->
                    ( Html.Extra.nothing
                    , UI.Button.primary { label = confirmLabel, onClick = confirmMsg }
                    )

                RemoteData.Loading ->
                    ( Html.Extra.nothing
                    , UI.Button.primaryBusy { label = confirmLabel }
                    )

                RemoteData.Failure err ->
                    ( viewErrorChip (SharedTripUi.errorMessage err)
                    , UI.Button.primary { label = confirmLabel, onClick = confirmMsg }
                    )

                RemoteData.Success _ ->
                    ( Html.Extra.nothing
                    , UI.Button.primary { label = confirmLabel, onClick = confirmMsg }
                    )
    in
    Html.div []
        [ chip
        , Html.div [ Html.Attributes.class "flex gap-2 mt-4" ]
            [ confirmButton
            , UI.Button.ghost { label = cancelLabel, onClick = cancelMsg }
            ]
        ]


viewErrorChip : String -> Html msg
viewErrorChip message =
    Html.div [ Html.Attributes.class "bg-rust-tint border border-rust rounded-lg p-2.5 mb-3" ]
        [ Html.p [ Html.Attributes.class "text-sm text-rust" ] [ Html.text message ] ]


formField : String -> Html msg -> Html msg
formField label control =
    Html.div [ Html.Attributes.class "mb-3" ]
        [ Html.p [ Html.Attributes.class "text-xs font-mono uppercase tracking-widest text-moss mb-1.5" ]
            [ Html.text label ]
        , control
        ]


textInputStyle : Html.Attribute msg
textInputStyle =
    Html.Attributes.class "w-full bg-parchment border border-tan rounded-lg px-3 py-2 text-base text-ink focus:outline-none focus:border-rust"
