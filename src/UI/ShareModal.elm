module UI.ShareModal exposing (view)

{-| In-app share modal.

Shows a big QR pointing at `ternpike.com/qr/user-<shortHash>` so a
friend can scan it directly off the user's phone screen. The on-screen
QR _is_ the share — there's no OS share-sheet handoff. Print is the
only secondary action (sends the QR to AirPrint at sticker size).

The slug is derived inline from `as_.currentUser` via
`Data.UserId.shortHash` — no async fetch, no loading state.

-}

import Data.UserId as UserId
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Types exposing (AuthMsg_(..), AuthState, Msg(..))
import UI.Button


view : AuthState -> Html Msg
view as_ =
    if as_.shareModalOpen then
        viewOpen as_

    else
        Html.text ""


viewOpen : AuthState -> Html Msg
viewOpen as_ =
    let
        slug =
            "user-" ++ UserId.shortHash as_.currentUser

        qrUrl =
            as_.config.backendUrl
                ++ "/qr/"
                ++ slug
                ++ "/sticker.svg?template=share"

        -- Direct link to the server-rendered 4x6 PDF. The browser print
        -- stack is unreliable here — iOS Safari "Save to PDF" ignores
        -- `@page size` and falls back to Letter, leaving a tiny sticker on
        -- a big page — so we ship the asset pre-sized. iOS opens the PDF
        -- inline in Safari/Files, where Share → Print → AirPrint or
        -- Share → Munbyn app both get a correctly-sized 4x6 vector.
        --
        -- Three sizes share the same 4x6 page; only the grid changes
        -- (1 large / 6 medium / 12 small), so the printer setup stays
        -- identical across choices.
        --
        -- shareLocation comes from `navigator.geolocation` (kicked off by
        -- OpenShareModal). When present, lat/lon are appended so each
        -- sticker is stamped with the user's actual GPS — not cf's IP geo,
        -- which routes through the nearest CDN edge and can be off by
        -- hundreds of miles on mobile data. When absent (permission
        -- denied, slow fix, etc), the sticker omits the coord stamp.
        coordsParam =
            case as_.shareLocation of
                Just loc ->
                    "&lat=" ++ String.fromFloat loc.lat ++ "&lon=" ++ String.fromFloat loc.lon

                Nothing ->
                    ""

        printUrl size =
            as_.config.backendUrl
                ++ "/qr/"
                ++ slug
                ++ "/sticker.pdf?size="
                ++ size
                ++ coordsParam
    in
    Html.div
        [ Html.Attributes.class "fixed inset-0 bg-black/60 backdrop-blur-sm z-[9998] flex items-center justify-center p-6" ]
        [ Html.div
            [ Html.Attributes.class "w-full max-w-sm p-6 bg-parchment dark:bg-cream border border-tan rounded-2xl shadow-panel relative"
            , Html.Attributes.attribute "role" "dialog"
            ]
            [ Html.button
                [ Html.Attributes.class "absolute top-3 right-3 text-muted hover:text-ink text-2xl leading-none w-8 h-8 flex items-center justify-center"
                , Html.Attributes.attribute "aria-label" "Close"
                , Html.Events.onClick (AuthMsg CloseShareModal)
                ]
                [ Html.text "×" ]
            , Html.h2
                [ Html.Attributes.class "text-2xl font-bold text-ink font-display text-center mb-2" ]
                [ Html.text "Share Ternpike" ]
            , Html.p
                [ Html.Attributes.class "text-sm text-muted text-center mb-5" ]
                [ Html.text "Have a friend scan this with their phone camera." ]
            , Html.div
                [ Html.Attributes.class "rounded-card overflow-hidden shadow-card mb-5" ]
                [ Html.img
                    [ Html.Attributes.src qrUrl
                    , Html.Attributes.alt "Personal Ternpike QR code"
                    , Html.Attributes.class "block w-full"
                    ]
                    []
                ]
            , Html.p
                [ Html.Attributes.class "text-[10px] uppercase tracking-widest text-muted text-center mb-2 font-mono" ]
                [ Html.text "Print on a 4×6 label" ]
            , Html.div
                [ Html.Attributes.class "flex flex-col gap-2" ]
                [ UI.Button.secondaryLink
                    { href = printUrl "large"
                    , label = "1 big sticker"
                    , newTab = True
                    }
                , UI.Button.secondaryLink
                    { href = printUrl "medium"
                    , label = "6 medium stickers"
                    , newTab = True
                    }
                , UI.Button.secondaryLink
                    { href = printUrl "small"
                    , label = "12 small stickers"
                    , newTab = True
                    }
                , Html.button
                    [ Html.Attributes.class "text-sm text-muted hover:text-ink py-2"
                    , Html.Events.onClick (AuthMsg CloseShareModal)
                    ]
                    [ Html.text "Done" ]
                ]
            ]
        ]
