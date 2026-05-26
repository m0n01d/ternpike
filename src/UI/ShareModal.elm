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
import Types exposing (AuthState, Msg(..))
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

        -- Print opens the existing /qr/print page in a new tab rather than
        -- calling window.print() from inside the PWA. iOS drops user-
        -- activation across Elm's port hop, so an in-app window.print() is
        -- a silent no-op on iPhone; opening the print page is reliable.
        -- Uses the `share` template + its 4x6 default for full-label fill
        -- on standard shipping-label printers (Munbyn RW403B, etc).
        printUrl =
            as_.config.backendUrl
                ++ "/qr/print?slugs="
                ++ slug
                ++ "&template=share"
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
                , Html.Events.onClick CloseShareModal
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
            , Html.div
                [ Html.Attributes.class "flex flex-col gap-2" ]
                [ UI.Button.secondaryLink
                    { href = printUrl
                    , label = "Print"
                    , newTab = True
                    }
                , Html.button
                    [ Html.Attributes.class "text-sm text-muted hover:text-ink py-2"
                    , Html.Events.onClick CloseShareModal
                    ]
                    [ Html.text "Done" ]
                ]
            ]
        ]
