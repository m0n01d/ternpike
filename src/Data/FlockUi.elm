module Data.FlockUi exposing
    ( FlockModal(..)
    , FlockUiState
    , empty
    , isExpanded
    , toggleExpanded
    )

{-| Ephemeral UI state for the Settings → Flocks section (#62).

`FlockUiState` lives on `AuthState.flockUi` and tracks every transient
piece of state for the flock-management UX: which modal is open, which
flock cards have their member list expanded, and whether an HTTP call
is in flight.

It is deliberately a single record so opening one modal closes any
others — that mirrors the design (only one modal at a time) and saves
us from writing a "close all" helper at every transition.

This module owns the state shape and small predicates; the messages
that mutate it live alongside the rest of `Msg` in `Types.elm`.

-}

import Data.FlockId exposing (FlockId)
import Set exposing (Set)


{-| The transient UI state for the Flocks section. None of these
fields ever sync — they exist for the lifetime of one navigation.

  - `modal` — which modal (if any) is open.
  - `expanded` — the set of `FlockId.toString` whose "View members"
    accordion is open.
  - `inFlight` — `True` while an `Http.FlockApi` request is pending,
    so the relevant action buttons can render in a busy state.

-}
type alias FlockUiState =
    { expanded : Set String
    , inFlight : Bool
    , modal : FlockModal
    }


{-| The set of modal surfaces the Flocks section can put up. At most
one is shown at a time. Each variant carries the input/error state
specific to its form.
-}
type FlockModal
    = InviteModal FlockId { email : String, error : Maybe String }
    | LeaveConfirmModal FlockId { error : Maybe String }
    | NoModal
    | TransferModal FlockId { error : Maybe String, target : String }


empty : FlockUiState
empty =
    { expanded = Set.empty
    , inFlight = False
    , modal = NoModal
    }


{-| True when the given flock's "View members" accordion is open.
-}
isExpanded : FlockId -> FlockUiState -> Bool
isExpanded id state =
    Set.member (Data.FlockId.toString id) state.expanded


{-| Toggle the expanded state for one flock's member list.
-}
toggleExpanded : FlockId -> FlockUiState -> FlockUiState
toggleExpanded id state =
    let
        key =
            Data.FlockId.toString id
    in
    { state
        | expanded =
            if Set.member key state.expanded then
                Set.remove key state.expanded

            else
                Set.insert key state.expanded
    }
