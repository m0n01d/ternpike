module UI.ShareModal exposing (view)

{-| In-app share modal.

Two share surfaces, one modal:

  - **Social share** (primary CTA + SMS/Email/Copy row) — drives the
    word-of-mouth growth loop. The share URL embeds `?via=share` so
    QR\_KV analytics can separate scans from social-share clicks.
  - **QR code** (visual + 4×6 PDF sticker links) — the original
    in-person handoff. Friend scans the QR with their camera; the
    sticker PDFs feed AirPrint at the right physical size.

The slug is derived inline from `as_.currentUser` via
`Data.UserId.shortHash` — no async fetch, no loading state.

-}

import Data.GeoPoint as GeoPoint
import Data.Location exposing (LocationState(..))
import Data.UserId as UserId
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Extra
import Svg
import Svg.Attributes
import Types exposing (AuthMsg_(..), AuthState, Msg(..), ShareMode(..))
import UI.Button
import Url


view : AuthState -> Html Msg
view as_ =
    Html.Extra.viewIf as_.shareModalOpen (viewOpen as_)


shareText : String
shareText =
    "I'm using Ternpike to track expenses on the road — it pays for itself. Check it out:"


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

        shareUrl =
            as_.config.backendUrl ++ "/qr/" ++ slug ++ "?via=share"

        smsBody =
            Url.percentEncode (shareText ++ " " ++ shareUrl)

        mailBody =
            Url.percentEncode (shareText ++ "\n\n" ++ shareUrl)

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
        -- `currentLocation` is the shared device-GPS broadcast on
        -- AuthState, populated by `navigator.geolocation` (kicked off by
        -- OpenShareModal AND by Add-page nav — single source). Append
        -- lat/lon when we have a fix; otherwise omit. iOS / Cloudflare
        -- never sees IP-derived coords for the print, so the sticker
        -- either shows your real GPS or no coords at all.
        coordsParam =
            case as_.currentLocation of
                LocationGot point _ ->
                    "&lat="
                        ++ String.fromFloat (GeoPoint.latDegrees point)
                        ++ "&lon="
                        ++ String.fromFloat (GeoPoint.lonDegrees point)

                _ ->
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
            [ Html.Attributes.class "w-full max-w-sm p-6 bg-parchment dark:bg-cream border border-tan rounded-2xl shadow-panel relative max-h-[90vh] overflow-y-auto"
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
                [ Html.text "Send a friend a link, or have them scan the QR below." ]
            , viewSocialShare smsBody mailBody
            , viewQr qrUrl
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


viewSocialShare : String -> String -> Html Msg
viewSocialShare smsBody mailBody =
    Html.div
        [ Html.Attributes.class "mb-5" ]
        [ Html.div
            [ Html.Attributes.class "flex justify-center mb-3" ]
            [ UI.Button.primary
                { label = "Share with a friend"
                , onClick = AuthMsg (ShareViaNative AutoShare)
                }
            ]
        , Html.div
            [ Html.Attributes.class "flex items-center justify-center gap-3" ]
            [ shareLink ("sms:?body=" ++ smsBody) "Share via SMS" iconChat
            , shareLink ("mailto:?subject=Ternpike&body=" ++ mailBody) "Share via email" iconMail
            , copyButton
            ]
        ]


viewQr : String -> Html Msg
viewQr qrUrl =
    Html.div
        [ Html.Attributes.class "rounded-card overflow-hidden shadow-card mb-5" ]
        [ Html.img
            [ Html.Attributes.src qrUrl
            , Html.Attributes.alt "Personal Ternpike QR code"
            , Html.Attributes.class "block w-full"
            ]
            []
        ]


shareLink : String -> String -> Html Msg -> Html Msg
shareLink href title icon =
    Html.a
        [ Html.Attributes.href href
        , Html.Attributes.title title
        , Html.Attributes.attribute "aria-label" title
        , Html.Attributes.class "w-10 h-10 flex items-center justify-center rounded-full bg-cream-deep border border-tan text-moss hover:text-rust hover:border-rust no-underline"
        ]
        [ icon ]


copyButton : Html Msg
copyButton =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Attributes.title "Copy link"
        , Html.Attributes.attribute "aria-label" "Copy link"
        , Html.Events.onClick (AuthMsg (ShareViaNative ForceCopy))
        , Html.Attributes.class "w-10 h-10 flex items-center justify-center rounded-full bg-cream-deep border border-tan text-moss hover:text-rust hover:border-rust cursor-pointer"
        ]
        [ iconLink ]


iconChat : Html msg
iconChat =
    iconFrame
        [ Svg.path
            [ Svg.Attributes.d "M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" ]
            []
        ]


iconMail : Html msg
iconMail =
    iconFrame
        [ Svg.rect
            [ Svg.Attributes.x "3"
            , Svg.Attributes.y "5"
            , Svg.Attributes.width "18"
            , Svg.Attributes.height "14"
            , Svg.Attributes.rx "2"
            ]
            []
        , Svg.path [ Svg.Attributes.d "M3 7l9 6 9-6" ] []
        ]


iconLink : Html msg
iconLink =
    iconFrame
        [ Svg.path [ Svg.Attributes.d "M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 0 0-7.07-7.07l-1.5 1.5" ] []
        , Svg.path [ Svg.Attributes.d "M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 0 0 7.07 7.07l1.5-1.5" ] []
        ]


iconFrame : List (Svg.Svg msg) -> Html msg
iconFrame children =
    Svg.svg
        [ Svg.Attributes.viewBox "0 0 24 24"
        , Svg.Attributes.fill "none"
        , Svg.Attributes.stroke "currentColor"
        , Svg.Attributes.strokeWidth "2"
        , Svg.Attributes.strokeLinecap "round"
        , Svg.Attributes.strokeLinejoin "round"
        , Svg.Attributes.class "w-5 h-5"
        , Html.Attributes.attribute "aria-hidden" "true"
        ]
        children
