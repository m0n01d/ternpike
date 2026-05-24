module Data.SharedTripUi exposing
    ( SharedTripModal(..)
    , SharedTripUiState
    , empty
    , isExpanded
    , toggleExpanded
    )

{-| Ephemeral UI state for the Settings → SharedTrips section (#62).

`SharedTripUiState` lives on `AuthState.sharedTripUi` and tracks every transient
piece of state for the shared-trip-management UX: which modal is open, which
shared trip cards have their member list expanded, and whether an HTTP call
is in flight.

It is deliberately a single record so opening one modal closes any
others — that mirrors the design (only one modal at a time) and saves
us from writing a "close all" helper at every transition.

This module owns the state shape and small predicates; the messages
that mutate it live alongside the rest of `Msg` in `Types.elm`.

-}

import Data.SharedTripId exposing (SharedTripId)
import Set exposing (Set)


{-| The transient UI state for the SharedTrips section. None of these
fields ever sync — they exist for the lifetime of one navigation.

  - `modal` — which modal (if any) is open.
  - `expanded` — the set of `SharedTripId.toString` whose "View members"
    accordion is open.
  - `inFlight` — `True` while an `Http.SharedTripApi` request is pending,
    so the relevant action buttons can render in a busy state.

-}
type alias SharedTripUiState =
    { expanded : Set String
    , inFlight : Bool
    , modal : SharedTripModal
    }


{-| The set of modal surfaces the SharedTrips section can put up. At most
one is shown at a time. Each variant carries the input/error state
specific to its form.
-}
type SharedTripModal
    = CreateModal { error : Maybe String, name : String }
    | InviteModal SharedTripId { email : String, error : Maybe String }
    | LeaveConfirmModal SharedTripId { error : Maybe String }
    | NoModal
    | TransferModal SharedTripId { error : Maybe String, target : String }


empty : SharedTripUiState
empty =
    { expanded = Set.empty
    , inFlight = False
    , modal = NoModal
    }


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
