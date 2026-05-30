module Data.SharedTripUi exposing
    ( SharedTripModal(..)
    , SharedTripUiState
    , empty
    , errorMessage
    , isExpanded
    , mapShareDraft
    , openShareTrip
    , setModalRequest
    , toggleExpanded
    )

{-| Ephemeral UI state for the Settings → SharedTrips section (#62).

`SharedTripUiState` lives on `AuthState.sharedTripUi` and tracks every transient
piece of state for the shared-trip-management UX: which modal is open and which
shared trip cards have their member list expanded.

It is deliberately a single record so opening one modal closes any
others — that mirrors the design (only one modal at a time) and saves
us from writing a "close all" helper at every transition.

This module owns the state shape and small predicates; the messages
that mutate it live alongside the rest of `Msg` in `Types.elm`.

Each modal carries its own `request : RemoteData Http.Error <Response>`
so the four HTTP calls (create / invite / leave / transfer) each get
their own spinner + error chip independent of the other three. The
shared `inFlight : Bool` that used to live at the parent level is gone.

-}

import Data.SharedTripId exposing (SharedTripId)
import Data.Trip exposing (NewFlockDraft)
import Data.TripId exposing (TripId)
import Http
import Http.SharedTripApi
import RemoteData exposing (RemoteData)
import Set exposing (Set)


{-| The transient UI state for the SharedTrips section. None of these
fields ever sync — they exist for the lifetime of one navigation.

  - `expanded` — the set of `SharedTripId.toString` whose "View members"
    accordion is open.
  - `modal` — which modal (if any) is open. Each modal variant carries
    its own per-call `request : RemoteData`.

-}
type alias SharedTripUiState =
    { expanded : Set String
    , modal : SharedTripModal
    }


{-| The set of modal surfaces the SharedTrips section can put up. At most
one is shown at a time. Each variant carries the form input(s) plus a
`request : RemoteData` tracking that modal's HTTP call.

The `request` field is `NotAsked` when the modal first opens, `Loading`
while the request is in flight, `Failure` after a server/network error
(the chip + retry button branch off the error), and `Success` for the
brief moment between the request returning and `update` closing the
modal.

-}
type SharedTripModal
    = InviteModal
        SharedTripId
        { email : String
        , request : RemoteData Http.Error ()
        }
    | InviteCrewModal
        SharedTripId
        { request : RemoteData Http.Error Http.SharedTripApi.ShareLinkResponse
        }
    | LeaveConfirmModal
        SharedTripId
        { request : RemoteData Http.Error ()
        }
    | NoModal
    | ResetLinksConfirmModal
        SharedTripId
        { request : RemoteData Http.Error ()
        }
    | ShareTripModal
        TripId
        { draft : NewFlockDraft
        , request : RemoteData Http.Error ()
        }
    | TransferModal
        SharedTripId
        { request : RemoteData Http.Error ()
        , target : String
        }


empty : SharedTripUiState
empty =
    { expanded = Set.empty
    , modal = NoModal
    }


{-| Open the "Share this trip" modal for a personal trip, seeding the
group-name draft from the trip's name (the user can override it under
"Advanced"). Replaces any currently-open modal.
-}
openShareTrip : TripId -> String -> SharedTripUiState -> SharedTripUiState
openShareTrip tripId tripName state =
    { state
        | modal =
            ShareTripModal tripId
                { draft =
                    { groupName = tripName
                    , invitees = []
                    , inviteesDraft = ""
                    }
                , request = RemoteData.NotAsked
                }
    }


{-| Map the draft of the open `ShareTripModal` (group name + invitee chips).
No-op when a different modal — or none — is open.
-}
mapShareDraft :
    (NewFlockDraft -> NewFlockDraft)
    -> SharedTripUiState
    -> SharedTripUiState
mapShareDraft f state =
    case state.modal of
        ShareTripModal tripId data ->
            { state | modal = ShareTripModal tripId { data | draft = f data.draft } }

        _ ->
            state


{-| True when the given shared trip's "View members" accordion is open.
-}
isExpanded : SharedTripId -> SharedTripUiState -> Bool
isExpanded id state =
    Set.member (Data.SharedTripId.toString id) state.expanded


{-| Toggle the expanded state for one shared trip's member list.
-}
toggleExpanded : SharedTripId -> SharedTripUiState -> SharedTripUiState
toggleExpanded id state =
    let
        key =
            Data.SharedTripId.toString id
    in
    { state
        | expanded =
            if Set.member key state.expanded then
                Set.remove key state.expanded

            else
                Set.insert key state.expanded
    }


{-| Render an `Http.Error` from one of the modal HTTP calls as a
user-facing message. Shared between the modal failure chips and the
Trips-page conversion flow's inline error.

`Http.BadBody` is reserved for client-side validation strings
(e.g. "Name is required.") stuffed into the modal's `request` by
the dispatch branch so the view can render validation and server
errors through the same Failure branch — the message is passed
through verbatim.

-}
errorMessage : Http.Error -> String
errorMessage err =
    case err of
        Http.BadBody message ->
            message

        Http.BadStatus 403 ->
            "Not allowed. Refresh and try again."

        Http.BadStatus 404 ->
            "That shared trip wasn't found."

        Http.BadStatus 409 ->
            "Already a member."

        Http.BadStatus 422 ->
            "Request rejected. Check the details and try again."

        Http.NetworkError ->
            "Network error. Try again."

        Http.Timeout ->
            "Took too long. Try again."

        _ ->
            "Something went wrong. Try again."


{-| Replace the currently-open modal's `request` field, leaving every
other field (name, email, target) and the modal variant itself
unchanged. No-op on `NoModal` — there's no request to update.

Used by the dispatch branches (`Loading` on submit) and the result
branches (`Failure`/`Success` on response) to advance the per-modal
RemoteData through its lifecycle without re-encoding the modal's
form fields at every call site.

-}
setModalRequest :
    (SharedTripModal -> Maybe SharedTripModal)
    -> SharedTripUiState
    -> SharedTripUiState
setModalRequest f state =
    case f state.modal of
        Just newModal ->
            { state | modal = newModal }

        Nothing ->
            state
