module Data.Tier exposing
    ( Tier(..)
    , fromString
    , isPaid
    , toString
    )

{-| The user's subscription tier.

Three tiers, matching the pricing in `CLAUDE.md`:

  - `Tern` — free. BYO key only. Named after the seabird that "Ternpike"
    takes its name from.
  - `Osprey` — $2.99/mo or $24/yr. Hosted OCR + batch scanning. Named for
    a more capable bird, signalling the paid tier.
  - `Trailblazer` — $79 one-time, capped at first 500 users. Feature-equivalent
    to `Osprey`; the distinction is billing mechanics (no recurring charge, all
    1.x updates included, loyalty discount on v2).

`isPaid` collapses the three into the binary capability question: does this
tier unlock paid features? Use `isPaid` for "can I do X?" predicates; branch
on the full type when rendering tier-specific UI (badges, billing screen) so
the compiler forces all three to be handled.

Wire format: `"tern"`, `"osprey"`, `"trailblazer"` (lowercase). Constructors
are Elm-internal identity; wire strings are the persisted/server-canonical form.
The two are intentionally decoupled so constructor renames don't break stored
data.

This module is the minimal stub required to land `Trip.effectiveTier` (#61).
The full subscription-tier track (#16–#22) will flesh out JSON codecs and the
billing wire format when the server starts persisting tier — they're omitted
here to keep the surface area minimal and avoid `NoUnused.Exports` noise.

Tier is server-authoritative: populated from the session at login + refreshed
via `/me`, never cached in PouchDB (would sync stale state across devices on
upgrade). See `CLAUDE.md` "Storage tiers" for the full rule.

-}


type Tier
    = Osprey
    | Tern
    | Trailblazer


{-| True when the tier unlocks paid features (hosted OCR, batch scanning,
etc.). `Tern` returns False; `Osprey` and `Trailblazer` return True.

    isPaid Tern
    --> False

    isPaid Osprey
    --> True

    isPaid Trailblazer
    --> True

-}
isPaid : Tier -> Bool
isPaid tier =
    case tier of
        Tern ->
            False

        Osprey ->
            True

        Trailblazer ->
            True


{-| Wire form: the lowercase canonical name.

    toString Tern
    --> "tern"

    toString Osprey
    --> "osprey"

    toString Trailblazer
    --> "trailblazer"

-}
toString : Tier -> String
toString tier =
    case tier of
        Tern ->
            "tern"

        Osprey ->
            "osprey"

        Trailblazer ->
            "trailblazer"


{-| Parse the lowercase wire form. Returns `Nothing` for any other input;
callers decide whether to default (typically to `Tern`) or fail.

    fromString "tern"
    --> Just Tern

    fromString "osprey"
    --> Just Osprey

    fromString "trailblazer"
    --> Just Trailblazer

    fromString "unknown"
    --> Nothing

-}
fromString : String -> Maybe Tier
fromString s =
    case s of
        "tern" ->
            Just Tern

        "osprey" ->
            Just Osprey

        "trailblazer" ->
            Just Trailblazer

        _ ->
            Nothing
