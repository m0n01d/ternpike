module UI.Avatar exposing (viewInitial, viewStack)

{-| Tiny circular avatars for flock-member attribution.

The visual language: an 18×18 circle, a single uppercase initial in
parchment on a deterministic background colour. The colour is hashed
from `UserId.toString` so Alice is the same colour on Alice's phone,
Bob's phone, and the trip-card avatar stack on every member's device.

Two surfaces use this:

  - `viewInitial` — one circle. Used in the Ledger row's author chip
    and anywhere a single author's avatar appears inline.
  - `viewStack` — overlapping circles for the trip-card and trip-picker
    member cluster. Long member lists collapse to two initials + a
    `+ N` chip on the right rather than rendering a wall of circles.

The palette is hand-picked from `theme.css` tokens — `bg-rust`,
`bg-forest-mid`, `bg-moss`, `bg-rust-deep`, `bg-tan` — so avatars feel
like they belong on the same page as the rest of the chrome. The
`bg-tan` slot uses `text-forest` rather than `text-parchment` because
tan is too light to carry a parchment-coloured initial legibly.

The initial is the first character of the email's local-part (the
substring left of `@`), upper-cased. This works for both `UserId`s
that wrap an email and the empty `unknown` sentinel (which falls
through to `?`).

@docs viewInitial, viewStack

-}

import Data.UserId as UserId exposing (UserId)
import Html exposing (Html)
import Html.Attributes


{-| An 18px avatar circle with a single initial.
-}
viewInitial : UserId -> Html msg
viewInitial userId =
    Html.span
        [ Html.Attributes.class
            (String.join " "
                [ "inline-flex"
                , "items-center"
                , "justify-center"
                , "w-[18px]"
                , "h-[18px]"
                , "rounded-full"
                , "text-[10px]"
                , "font-bold"
                , "leading-none"
                , "shrink-0"
                , colourClass userId
                ]
            )
        , Html.Attributes.title (UserId.toString userId)
        ]
        [ Html.text (initial userId) ]


{-| A horizontal stack of overlapping member avatars.

Lists with more than three members render two initials followed by a
`+ N` parchment-bordered chip so the visual doesn't grow without
bound. Each circle gets a parchment ring so adjacent circles remain
visually separated on the cream backdrop.

-}
viewStack : List UserId -> Html msg
viewStack users =
    let
        pills =
            if List.length users <= 3 then
                List.map borderedAvatar users

            else
                List.map borderedAvatar (List.take 2 users)
                    ++ [ overflowChip (List.length users - 2) ]
    in
    Html.span [ Html.Attributes.class "inline-flex items-center" ] pills



-- INTERNAL


borderedAvatar : UserId -> Html msg
borderedAvatar userId =
    Html.span
        [ Html.Attributes.class
            (String.join " "
                [ "inline-flex"
                , "items-center"
                , "justify-center"
                , "w-[18px]"
                , "h-[18px]"
                , "rounded-full"
                , "text-[10px]"
                , "font-bold"
                , "leading-none"
                , "shrink-0"
                , "ring-2"
                , "ring-parchment"
                , "-ml-1.5"
                , "first:ml-0"
                , colourClass userId
                ]
            )
        , Html.Attributes.title (UserId.toString userId)
        ]
        [ Html.text (initial userId) ]


overflowChip : Int -> Html msg
overflowChip n =
    Html.span
        [ Html.Attributes.class
            (String.join " "
                [ "inline-flex"
                , "items-center"
                , "justify-center"
                , "h-[18px]"
                , "px-1.5"
                , "rounded-full"
                , "text-[10px]"
                , "font-bold"
                , "leading-none"
                , "shrink-0"
                , "ring-2"
                , "ring-parchment"
                , "-ml-1.5"
                , "bg-cream-deep"
                , "text-moss"
                ]
            )
        ]
        [ Html.text ("+" ++ String.fromInt n) ]


initial : UserId -> String
initial userId =
    case String.uncons (localPart (UserId.toString userId)) of
        Just ( c, _ ) ->
            String.fromChar (Char.toUpper c)

        Nothing ->
            "?"


localPart : String -> String
localPart s =
    case String.split "@" s of
        head :: _ ->
            head

        [] ->
            s


{-| Deterministic Tailwind background class for a user, hashed off the
raw `UserId` string. Five-slot palette mapped via sum-of-char-codes mod
5 — small, stable, and dependency-free. Exposed so tests and the
overflow chip can pin the algorithm down.

    colourClass (Data.UserId.fromString "alice@example.com")
    --> "bg-moss text-parchment"

    colourClass (Data.UserId.fromString "bob@example.com")
    --> "bg-tan text-forest"

    colourClass (Data.UserId.fromString "")
    --> "bg-rust text-parchment"

-}
colourClass : UserId -> String
colourClass userId =
    let
        hash =
            UserId.toString userId
                |> String.toList
                |> List.map Char.toCode
                |> List.sum
    in
    case modBy 5 hash of
        0 ->
            "bg-rust text-parchment"

        1 ->
            "bg-forest-mid text-parchment"

        2 ->
            "bg-moss text-parchment"

        3 ->
            "bg-rust-deep text-parchment"

        _ ->
            "bg-tan text-forest"
