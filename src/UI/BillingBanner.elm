module UI.BillingBanner exposing (view, viewInline)

{-| Rust-tinted lapsed-billing banner for flock-scoped pages and the
Settings flock card.

The server enforces `Grace` (read-only with countdown) and `Frozen`
(read-only indefinite) at the CouchDB `validate_doc_update` layer
(#57); this module is the UX side. Two variants:

  - `view` — full-bleed banner inserted once at the top of every
    flock-scoped tab (Ledger/Stats/Add/Scan). Owner / Osprey+ member /
    Tern member each see different copy and CTAs per the matrix
    in #64's body.
  - `viewInline` — smaller chrome variant for the Settings flock card
    so the same status is visible without opening the flock's trip.

Days-remaining for the countdown derives from
`(billingLapsedAt + 14 days) - today`, floored at 0. The 14-day window
is set by the server; if it changes there, change `graceWindowDays`
below to match.

`Active` flocks render `Html.text ""` for both variants — call sites
don't need to gate, but doing so saves a DOM node.

@docs view, viewInline

-}

import Data.DateField as DateField exposing (DateField)
import Data.SharedTrip as SharedTrip exposing (BillingStatus(..), SharedTrip)
import Data.Tier as Tier exposing (Tier)
import Data.UserId as UserId exposing (UserId)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Types exposing (Msg(..))


{-| Days the server keeps a lapsed flock in `Grace` before flipping it
to `Frozen`. Mirrors the server-side constant; see #57.
-}
graceWindowDays : Int
graceWindowDays =
    14


{-| Full-bleed banner for flock-scoped trip pages. Takes the
current-user `UserId` so role (owner / member) can be derived, the
viewer's own `Tier` so the Osprey+ vs Tern member split can render
the right CTA, and `today` (calendar date) so the countdown can be
computed.

Returns `Html.text ""` when the flock is `Active` — the common case.

-}
view : { currentUser : UserId, flock : SharedTrip, tier : Tier, today : DateField } -> Html Msg
view opts =
    let
        role =
            roleFor opts.currentUser opts.flock opts.tier
    in
    case opts.flock.billingStatus of
        Active ->
            Html.text ""

        Grace ->
            viewBanner
                { copy = graceCopy role (daysRemaining opts.today opts.flock)
                , cta = ctaFor role opts.flock
                , tone = Warning
                }

        Frozen ->
            viewBanner
                { copy = frozenCopy role opts.flock
                , cta = ctaFor role opts.flock
                , tone = Danger
                }


{-| Inline variant for the Settings flock card. Same copy matrix, less
chrome — sits inside an already-padded card. Returns `Html.text ""`
when the flock is `Active`.
-}
viewInline : { currentUser : UserId, flock : SharedTrip, tier : Tier, today : DateField } -> Html Msg
viewInline opts =
    let
        role =
            roleFor opts.currentUser opts.flock opts.tier
    in
    case opts.flock.billingStatus of
        Active ->
            Html.text ""

        Grace ->
            viewInlineBanner
                { copy = graceCopy role (daysRemaining opts.today opts.flock)
                , cta = ctaFor role opts.flock
                , tone = Warning
                }

        Frozen ->
            viewInlineBanner
                { copy = frozenCopy role opts.flock
                , cta = ctaFor role opts.flock
                , tone = Danger
                }



-- ROLE / CTA


type Role
    = Owner
    | PaidMember
    | FledglingMember


type Tone
    = Warning
    | Danger


type Cta
    = NoCta
    | Renew
    | TransferToMe SharedTrip


roleFor : UserId -> SharedTrip -> Tier -> Role
roleFor user flock tier =
    if SharedTrip.isOwner user flock then
        Owner

    else if Tier.isPaid tier then
        PaidMember

    else
        FledglingMember


ctaFor : Role -> SharedTrip -> Cta
ctaFor role flock =
    case role of
        Owner ->
            Renew

        PaidMember ->
            TransferToMe flock

        FledglingMember ->
            NoCta



-- COPY


graceCopy : Role -> Int -> String
graceCopy role days =
    let
        n =
            String.fromInt days
    in
    case role of
        Owner ->
            "Your subscription lapsed. Renew within " ++ n ++ " days or this flock becomes read-only."

        PaidMember ->
            "Owner's subscription lapsed. Read-only in " ++ n ++ " days. You can take over billing now."

        FledglingMember ->
            "Owner's subscription lapsed. This flock becomes read-only in " ++ n ++ " days."


frozenCopy : Role -> SharedTrip -> String
frozenCopy role flock =
    case role of
        Owner ->
            "Flock is read-only. Renew to restore writes."

        PaidMember ->
            "Flock is read-only. You can take over billing."

        FledglingMember ->
            "Flock is read-only. Ask "
                ++ UserId.toString flock.billingOwner
                ++ " to renew, or upgrade and take over billing yourself."



-- COUNTDOWN


{-| Floor-at-zero days remaining in the grace window. Falls back to 0
when `billingLapsedAt` is missing or unparseable (the server should
always set it for Grace, but we don't crash if it doesn't).
`billingLapsedAt` is the legacy `"YYYY-MM-DDTHH:MM:SSZ"` ISO timestamp
on `Data.SharedTrip.SharedTrip`; we only care about the calendar-day portion for
the countdown, so we trim to the date and parse with `DateField.fromIso`.
-}
daysRemaining : DateField -> SharedTrip -> Int
daysRemaining today flock =
    case Maybe.andThen (\iso -> DateField.fromIso (String.left 10 iso)) flock.billingLapsedAt of
        Nothing ->
            0

        Just lapsedDate ->
            let
                remaining =
                    graceWindowDays - DateField.diffDays lapsedDate today
            in
            if remaining < 0 then
                0

            else
                remaining



-- RENDER


type alias BannerConfig =
    { copy : String
    , cta : Cta
    , tone : Tone
    }


viewBanner : BannerConfig -> Html Msg
viewBanner cfg =
    Html.div
        [ Html.Attributes.class (bannerWrapperClass cfg.tone)
        , Html.Attributes.attribute "role" "alert"
        ]
        [ Html.div [ Html.Attributes.class "flex items-start gap-3" ]
            [ Html.span
                [ Html.Attributes.class "shrink-0 w-1.5 h-1.5 mt-2 rounded-full bg-rust-deep" ]
                []
            , Html.div [ Html.Attributes.class "flex-1 min-w-0" ]
                [ Html.p
                    [ Html.Attributes.class "text-xs font-mono uppercase tracking-widest text-rust-deep mb-1" ]
                    [ Html.text (toneLabel cfg.tone) ]
                , Html.p
                    [ Html.Attributes.class "text-sm text-ink leading-snug" ]
                    [ Html.text cfg.copy ]
                , viewCta cfg.cta
                ]
            ]
        ]


viewInlineBanner : BannerConfig -> Html Msg
viewInlineBanner cfg =
    Html.div
        [ Html.Attributes.class (inlineWrapperClass cfg.tone)
        , Html.Attributes.attribute "role" "alert"
        ]
        [ Html.p
            [ Html.Attributes.class "text-xs text-rust-deep leading-snug" ]
            [ Html.text cfg.copy ]
        , viewCta cfg.cta
        ]


viewCta : Cta -> Html Msg
viewCta cta =
    case cta of
        NoCta ->
            Html.text ""

        Renew ->
            Html.a
                [ Html.Attributes.href "/settings#billing"
                , Html.Attributes.class "inline-block mt-2 text-xs font-mono uppercase tracking-widest text-rust-deep hover:text-rust underline cursor-pointer"
                ]
                [ Html.text "Renew" ]

        TransferToMe flock ->
            Html.button
                [ Html.Attributes.type_ "button"
                , Html.Events.onClick (TakeOverBilling flock.id)
                , Html.Attributes.class "inline-block mt-2 text-xs font-mono uppercase tracking-widest text-rust-deep hover:text-rust bg-transparent border-0 underline cursor-pointer p-0"
                ]
                [ Html.text "Transfer billing to me" ]


toneLabel : Tone -> String
toneLabel tone =
    case tone of
        Warning ->
            "Billing lapsed"

        Danger ->
            "Flock frozen"


bannerWrapperClass : Tone -> String
bannerWrapperClass tone =
    case tone of
        Warning ->
            "bg-rust-tint border-l-4 border-rust px-4 py-3"

        Danger ->
            "bg-rust-tint border-l-4 border-danger px-4 py-3"


inlineWrapperClass : Tone -> String
inlineWrapperClass tone =
    case tone of
        Warning ->
            "bg-rust-tint border border-rust/40 rounded-card px-3 py-2 mt-1"

        Danger ->
            "bg-rust-tint border border-danger/40 rounded-card px-3 py-2 mt-1"
