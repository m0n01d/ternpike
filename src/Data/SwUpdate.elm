module Data.SwUpdate exposing (UpdateState(..), applyReady, isShowing)

{-| The service-worker update lifecycle as the UI sees it (#477).

`public/sw.js` parks a newly-installed worker in `waiting` instead of calling
`skipWaiting()`, and `src/main.js` reports that through the `swUpdateReady`
port. Tapping **Reload** posts `SKIP_WAITING` and waits for the new worker to
take control — which, on a suspended iOS app, is not instantaneous.

A `Bool` cannot express "the user tapped, activation is in flight": it would
leave a live, re-tappable button with no feedback. The three states here keep
"nothing to install", "an install is offered", and "an install is running"
distinct, so the view's `case` is exhaustive and the compiler catches a missed
branch.

@docs UpdateState, applyReady, isShowing

-}


{-| Where the app is in the update lifecycle.

  - `Applying` — the user tapped Reload; `SKIP_WAITING` is posted and the page
    is waiting on `controllerchange` (or the JS-side reload fallback).
  - `NoUpdate` — nothing is waiting; the update bar renders nothing.
  - `UpdateWaiting` — a new worker is installed and parked; the bar offers
    Reload.

-}
type UpdateState
    = Applying
    | NoUpdate
    | UpdateWaiting


{-| Fold a `swUpdateReady` port event into the current state.

`True` means JS is holding a waiting worker, `False` retracts it (the worker
went `redundant`, so a failed activation can't leave a permanent bar).

The port re-emits `True` on every resume tick — JS holds the waiting state
because `Main.updateAuth` drops every `AuthMsg` while the login screen is
mounted. That re-emit must not un-busy a Reload the user already tapped, so
`Applying` absorbs it.

    applyReady True NoUpdate
    --> UpdateWaiting

    applyReady True UpdateWaiting
    --> UpdateWaiting

    applyReady True Applying
    --> Applying

    applyReady False Applying
    --> NoUpdate

    applyReady False UpdateWaiting
    --> NoUpdate

-}
applyReady : Bool -> UpdateState -> UpdateState
applyReady ready current =
    if not ready then
        NoUpdate

    else
        case current of
            Applying ->
                Applying

            NoUpdate ->
                UpdateWaiting

            UpdateWaiting ->
                UpdateWaiting


{-| Is the update bar occupying the lower toast slot?

This is the single branch decision shared by `UI.Layout.viewUpdateToast` (does
the bar render?), `UI.Layout.viewToast` (does the ordinary toast shift up?),
and `Verify.Specs.UpdateToast` (the offset invariant). `Applying` still holds
the slot — the bar stays on screen, busy, while the new worker activates.

    isShowing UpdateWaiting
    --> True

    isShowing Applying
    --> True

    isShowing NoUpdate
    --> False

-}
isShowing : UpdateState -> Bool
isShowing state =
    case state of
        Applying ->
            True

        NoUpdate ->
            False

        UpdateWaiting ->
            True
