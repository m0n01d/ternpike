module Verify.Contract exposing (Surface, verifyAttrs)

{-| The contract layer: a `Surface` is the single source of truth that drives
_both_ the rendered DOM (via `data-verify-*` attributes) and the verification
checks. A view emits `verifyAttrs` from the same surface value the invariants
read, so there is no second schema to drift out of sync.

@docs Surface, verifyAttrs

-}

import Html
import Html.Attributes


{-| A surface is a flat list of key/value observations about a unit's state.
Keys become `data-verify-<key>` attributes; the verifiers read the same pairs.
-}
type alias Surface =
    List ( String, String )


{-| Render a surface as `data-verify-*` attributes on an element, tagged with
the unit name via `data-verify-unit`. The DOM tier reads these back off the
live element; the pure tier reads the same surface directly.
-}
verifyAttrs : String -> Surface -> List (Html.Attribute msg)
verifyAttrs unit surface =
    Html.Attributes.attribute "data-verify-unit" unit
        :: List.map
            (\( key, value ) -> Html.Attributes.attribute ("data-verify-" ++ key) value)
            surface
