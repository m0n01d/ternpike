module Pages.Settings.Flocks exposing (view, viewModal)

{-| The "Flocks" subsection of the Settings page (#62).

Renders one card per flock the user belongs to plus a "Create flock"
button at the top with a Fledgling-friendly upgrade hint. Owner cards
get Invite / Transfer-ownership / Leave buttons; member cards only
get Leave. A "View members" toggle expands the inline avatar stack
into a full email list.

Modals (create / invite / transfer / leave-confirm) are rendered
separately by `viewModal` — they sit at the page root rather than
inside the card so they overlay everything.

-}

import Data.Flock as Flock exposing (Flock)
import Data.FlockUi as FlockUi
import Data.Flocks as Flocks
import Data.Tier as Tier
import Data.UserId as UserId exposing (UserId)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Types exposing (AuthState, Msg(..))
import UI.Avatar
import UI.BillingBanner
import UI.Button
import UI.Card
import UI.FlockBadge
import UI.Rule


view : AuthState -> Html Msg
view as_ =
    let
        currentUser =
            UserId.fromString as_.creds.email

        joined =
            Flocks.joinedBy currentUser as_.flocks
    in
    Html.div []
        [ UI.Rule.kicker "FLOCKS"
        , if List.isEmpty joined then
            viewEmptyState

          else
            Html.div [] (List.map (viewFlockCard as_ currentUser) joined)
        ]


viewEmptyState : Html Msg
viewEmptyState =
    UI.Card.subCard
        [ Html.p [ Html.Attributes.class "text-xs text-muted" ]
            [ Html.text "You're not in any flocks yet. Start a "
            , Html.a
                [ Html.Attributes.href "/trips"
                , Html.Attributes.class "text-rust-deep underline"
                ]
                [ Html.text "shared trip" ]
            , Html.text " on the Trips page to create one, or accept an invite link to join."
            ]
        ]


viewFlockCard : AuthState -> UserId -> Flock -> Html Msg
viewFlockCard as_ currentUser flock =
    let
        owner =
            Flock.isOwner currentUser flock

        membersExpanded =
            FlockUi.isExpanded flock.id as_.flockUi
    in
    UI.Card.subCard
        [ Html.div [ Html.Attributes.class "flex items-start justify-between gap-3 mb-3" ]
            [ Html.div [ Html.Attributes.class "flex flex-col gap-1.5 min-w-0" ]
                [ UI.FlockBadge.view flock
                , Html.p [ Html.Attributes.class "text-xs text-muted font-mono uppercase tracking-widest" ]
                    [ Html.text
                        (if owner then
                            "Owner"

                         else
                            "Member"
                        )
                    ]
                ]
            , viewMembersStack flock
            ]
        , UI.BillingBanner.viewInline
            { currentUser = currentUser
            , flock = flock
            , tier = as_.tier
            , today = as_.today
            }
        , Html.div [ Html.Attributes.class "flex flex-wrap gap-2 mt-3" ]
            (if owner then
                [ UI.Button.secondary { label = "Invite", onClick = OpenInviteModal flock.id }
                , UI.Button.ghost { label = "Transfer ownership", onClick = OpenTransferModal flock.id }
                ]

             else
                [ UI.Button.ghost { label = "Leave", onClick = OpenLeaveConfirmModal flock.id }
                ]
            )
        , Html.button
            [ Html.Attributes.type_ "button"
            , Html.Events.onClick (ToggleFlockMembers flock.id)
            , Html.Attributes.class "mt-3 text-xs font-mono uppercase tracking-widest text-moss hover:text-forest bg-transparent border-0 cursor-pointer p-0"
            ]
            [ Html.text
                (if membersExpanded then
                    "Hide members"

                 else
                    "View members"
                )
            ]
        , if membersExpanded then
            viewMembersList flock

          else
            Html.text ""
        ]


viewMembersStack : Flock -> Html msg
viewMembersStack flock =
    Html.div [ Html.Attributes.class "shrink-0" ]
        [ UI.Avatar.viewStack (Flock.members flock) ]


viewMembersList : Flock -> Html msg
viewMembersList flock =
    Html.div [ Html.Attributes.class "mt-3 flex flex-col gap-2" ]
        (Flock.members flock
            |> List.map
                (\u ->
                    Html.div [ Html.Attributes.class "flex items-center gap-2" ]
                        [ UI.Avatar.viewInitial u
                        , Html.span [ Html.Attributes.class "text-sm text-ink" ]
                            [ Html.text (UserId.toString u) ]
                        , if Flock.isOwner u flock then
                            Html.span [ Html.Attributes.class "text-[10px] font-mono uppercase tracking-widest text-rust-deep" ]
                                [ Html.text "Owner" ]

                          else
                            Html.text ""
                        ]
                )
        )



-- MODALS


viewModal : AuthState -> Html Msg
viewModal as_ =
    case as_.flockUi.modal of
        FlockUi.NoModal ->
            Html.text ""

        FlockUi.InviteModal _ { email, error } ->
            modalShell "Invite to flock"
                [ Html.p [ Html.Attributes.class "text-sm text-muted mb-3" ]
                    [ Html.text "We'll email them a one-click link to accept." ]
                , formField "EMAIL"
                    (Html.input
                        [ Html.Attributes.type_ "email"
                        , Html.Attributes.value email
                        , Html.Events.onInput InviteEmailChanged
                        , Html.Attributes.placeholder "name@example.com"
                        , textInputStyle
                        ]
                        []
                    )
                , viewError error
                , modalActions
                    { confirm = ( "Send invite", SubmitInvite )
                    , cancel = ( "Cancel", CloseFlockModal )
                    , inFlight = as_.flockUi.inFlight
                    }
                ]

        FlockUi.LeaveConfirmModal flockId { error } ->
            let
                flockName =
                    Flocks.get flockId as_.flocks
                        |> Maybe.map .name
                        |> Maybe.withDefault "this flock"
            in
            modalShell "Leave flock?"
                [ Html.p [ Html.Attributes.class "text-sm text-ink mb-3" ]
                    [ Html.text
                        ("Leave the "
                            ++ flockName
                            ++ " flock? You'll lose access to its trips on this device, but the flock keeps the data."
                        )
                    ]
                , viewError error
                , modalActions
                    { confirm = ( "Leave", LeaveFlockConfirmed flockId )
                    , cancel = ( "Cancel", CloseFlockModal )
                    , inFlight = as_.flockUi.inFlight
                    }
                ]

        FlockUi.TransferModal flockId { error, target } ->
            let
                memberOptions =
                    Flocks.get flockId as_.flocks
                        |> Maybe.map
                            (\flock ->
                                flock.otherMembers
                                    |> List.map UserId.toString
                            )
                        |> Maybe.withDefault []
            in
            modalShell "Transfer ownership"
                [ Html.p [ Html.Attributes.class "text-sm text-muted mb-3" ]
                    [ Html.text "New owner must be on Fly or higher. The server will reject Fledgling targets." ]
                , formField "MEMBER"
                    (Html.select
                        [ Html.Events.onInput TransferTargetChanged
                        , textInputStyle
                        ]
                        (Html.option
                            [ Html.Attributes.value "" ]
                            [ Html.text "Select a member…" ]
                            :: List.map
                                (\email ->
                                    Html.option
                                        [ Html.Attributes.value email
                                        , Html.Attributes.selected (email == target)
                                        ]
                                        [ Html.text email ]
                                )
                                memberOptions
                        )
                    )
                , viewError error
                , modalActions
                    { confirm = ( "Transfer", SubmitTransfer )
                    , cancel = ( "Cancel", CloseFlockModal )
                    , inFlight = as_.flockUi.inFlight
                    }
                ]


modalShell : String -> List (Html Msg) -> Html Msg
modalShell title children =
    Html.div
        [ Html.Attributes.class "fixed inset-0 z-40 flex items-center justify-center px-5 bg-ink/40" ]
        [ Html.div
            [ Html.Attributes.class "w-full max-w-md bg-cream rounded-card shadow-panel p-5" ]
            (Html.p
                [ Html.Attributes.class "text-[15px] font-bold text-rust font-display mb-4" ]
                [ Html.text title ]
                :: children
            )
        ]


modalActions :
    { cancel : ( String, Msg )
    , confirm : ( String, Msg )
    , inFlight : Bool
    }
    -> Html Msg
modalActions { cancel, confirm, inFlight } =
    let
        ( confirmLabel, confirmMsg ) =
            confirm

        ( cancelLabel, cancelMsg ) =
            cancel
    in
    Html.div [ Html.Attributes.class "flex gap-2 mt-4" ]
        [ if inFlight then
            UI.Button.primaryBusy { label = confirmLabel }

          else
            UI.Button.primary { label = confirmLabel, onClick = confirmMsg }
        , UI.Button.ghost { label = cancelLabel, onClick = cancelMsg }
        ]


viewError : Maybe String -> Html msg
viewError maybeError =
    case maybeError of
        Just err ->
            Html.div [ Html.Attributes.class "bg-rust-tint border border-rust rounded-lg p-2.5 mb-3" ]
                [ Html.p [ Html.Attributes.class "text-sm text-rust" ] [ Html.text err ] ]

        Nothing ->
            Html.text ""


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
