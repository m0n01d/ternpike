module Data.Tier exposing
    ( Tier(..)
    , fromString
    , isPaid
    , toString
    )

{-| The user's subscription tier.

Three tiers, matching the pricing in `CLAUDE.md`:

  - `Fledgling` — free. BYO key only.
  - `Fly` — $2.99/mo or $24/yr. Hosted OCR + batch scanning.
  - `Trailblazer` — $79 one-time, capped at first 500 users. Feature-equivalent
    to `Fly`; the distinction is billing mechanics (no recurring charge, all
    1.x updates included, loyalty discount on v2).

`isPaid` collapses the three into the binary capability question: does this
tier unlock paid features? Use `isPaid` for "can I do X?" predicates; branch
on the full type when rendering tier-specific UI (badges, billing screen) so
the compiler forces all three to be handled.

This module is the minimal stub introduced alongside `Trip.effectiveTier`
(#61) and the Settings → Flocks gate (#62), giving both callers a `Tier`
to consult. The full subscription-tier track (#16–#22) will flesh out
JSON codecs and the billing wire format when the server starts persisting
tier — they're omitted here to keep the surface area minimal and avoid
`NoUnused.Exports` noise. For now the wire form is the lowercase
constructor name; that may be revisited when the server starts persisting
tier.

Tier is server-authoritative: populated from the session at login + refreshed
via `/me`, never cached in PouchDB (would sync stale state across devices on
upgrade). See `CLAUDE.md` "Storage tiers" for the full rule.

-}


type Tier
    = Fledgling
    | Fly
    | Trailblazer


{-| True when the tier unlocks paid features (hosted OCR, batch scanning,
etc.). `Fledgling` returns False; `Fly` and `Trailblazer` return True.

    isPaid Fledgling
    --> False

    isPaid Fly
    --> True

    isPaid Trailblazer
    --> True

-}
isPaid : Tier -> Bool
isPaid tier =
    case tier of
        Fledgling ->
            False

        Fly ->
            True

        Trailblazer ->
            True


{-| Wire form: the lowercase constructor name.

    toString Fledgling
    --> "fledgling"

    toString Fly
    --> "fly"

    toString Trailblazer
    --> "trailblazer"

-}
toString : Tier -> String
toString tier =
    case tier of
        Fledgling ->
            "fledgling"

        Fly ->
            "fly"

        Trailblazer ->
            "trailblazer"


{-| Parse the lowercase wire form. Returns `Nothing` for any other input;
callers decide whether to default (typically to `Fledgling`) or fail.

    fromString "fledgling"
    --> Just Fledgling

    fromString "fly"
    --> Just Fly

    fromString "trailblazer"
    --> Just Trailblazer

    fromString "unknown"
    --> Nothing

-}
fromString : String -> Maybe Tier
fromString s =
    case s of
        "fledgling" ->
            Just Fledgling

        "fly" ->
            Just Fly

        "trailblazer" ->
            Just Trailblazer

        _ ->
            Nothing
