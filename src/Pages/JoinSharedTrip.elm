module Pages.JoinSharedTrip exposing (viewAuth)

{-| The `/sharedtrips/join?token=<jwt>` redemption page.

Two surfaces:

  - **Guest** — the user is signed out. The token is held in
    `GuestState.pendingJoinToken` and the sign-in flow knows to navigate
    back to `/sharedtrips/join?token=...` once auth succeeds.
  - **Auth** — the user is signed in. We decode the JWT payload
    (display only — the server checks the signature), show a
    confirmation card ("Alice invited you to join Honeymoon"), and on
    Accept hit `Http.SharedTripApi.joinSharedTrip`.

The JWT is split on `.` and the middle segment is base64url-decoded;
we never verify it on the client. We only pull `inviterEmail`,
`inviteeEmail`, and `flockName` for display, defaulting to a generic
copy if any field is missing.

-}

import Html exposing (Html)
import Html.Attributes
import Html.Extra
import Http.SharedTripApi
import Json.Decode
import RemoteData
import Types exposing (AuthMsg_(..), AuthState, Msg(..))
import UI.Button
import UI.Card
import Verify.Contract
import Verify.Specs.JoinSharedTrip


{-| Render the join confirmation for a signed-in user.
-}
viewAuth : AuthState -> String -> { actions : List (Html Msg), body : Html Msg, hero : Html Msg }
viewAuth as_ token =
    let
        invite =
            decodeInvite token
    in
    { actions = []
    , body =
        Html.div
            (Verify.Contract.verifyAttrs "JoinSharedTrip"
                (Verify.Specs.JoinSharedTrip.surface
                    (Verify.Specs.JoinSharedTrip.honest as_.joinSharedTripRequest)
                )
            )
            [ viewAuthBody as_ token invite ]
    , hero = viewHero invite
    }


viewHero : Invite -> Html msg
viewHero invite =
    Html.div [ Html.Attributes.class "text-sm text-muted" ]
        [ Html.text
            (case invite.inviterEmail of
                Just name ->
                    name ++ " invited you to join a shared trip."

                Nothing ->
                    "You've been invited to join a shared trip."
            )
        ]


viewAuthBody : AuthState -> String -> Invite -> Html Msg
viewAuthBody as_ token invite =
    let
        intendedEmail =
            invite.inviteeEmail |> Maybe.withDefault as_.creds.email

        wrongRecipient =
            String.toLower intendedEmail /= String.toLower as_.creds.email

        ( acceptButton, declineButton, errorChip ) =
            case as_.joinSharedTripRequest of
                RemoteData.NotAsked ->
                    ( Html.Extra.viewIf (not wrongRecipient)
                        (UI.Button.primary
                            { label = "Accept"
                            , onClick = AuthMsg (JoinSharedTripAccepted token)
                            }
                        )
                    , UI.Button.ghost
                        { label = "Decline"
                        , onClick = AuthMsg JoinSharedTripDeclined
                        }
                    , Html.Extra.nothing
                    )

                RemoteData.Loading ->
                    ( UI.Button.primaryBusy { label = "Joining…" }
                    , Html.button
                        [ Html.Attributes.type_ "button"
                        , Html.Attributes.disabled True
                        , Html.Attributes.class "bg-transparent border border-tan/60 text-moss/60 font-mono uppercase tracking-widest text-xs px-4 py-2 rounded-lg cursor-not-allowed"
                        ]
                        [ Html.text "Decline" ]
                    , Html.Extra.nothing
                    )

                RemoteData.Failure err ->
                    ( Html.Extra.viewIf (not wrongRecipient)
                        (UI.Button.primary
                            { label = "Accept"
                            , onClick = AuthMsg (JoinSharedTripAccepted token)
                            }
                        )
                    , UI.Button.ghost
                        { label = "Decline"
                        , onClick = AuthMsg JoinSharedTripDeclined
                        }
                    , Html.p [ Html.Attributes.class "text-sm text-rust" ]
                        [ Html.text (Http.SharedTripApi.joinErrorMessage err) ]
                    )

                RemoteData.Success _ ->
                    -- Navigation fires in the same tick; render idle while in flight.
                    ( Html.Extra.viewIf (not wrongRecipient)
                        (UI.Button.primary
                            { label = "Accept"
                            , onClick = AuthMsg (JoinSharedTripAccepted token)
                            }
                        )
                    , UI.Button.ghost
                        { label = "Decline"
                        , onClick = AuthMsg JoinSharedTripDeclined
                        }
                    , Html.Extra.nothing
                    )
    in
    UI.Card.subCard
        [ Html.div [ Html.Attributes.class "flex flex-col gap-3" ]
            [ Html.p [ Html.Attributes.class "text-base text-ink" ]
                [ Html.text
                    (case ( invite.inviterEmail, invite.flockName ) of
                        ( Just inviter, Just flockName ) ->
                            inviter ++ " invited you to join \"" ++ flockName ++ "\"."

                        ( Just inviter, Nothing ) ->
                            inviter ++ " invited you to join a shared trip."

                        ( Nothing, Just flockName ) ->
                            "You've been invited to join \"" ++ flockName ++ "\"."

                        ( Nothing, Nothing ) ->
                            "You've been invited to join a shared trip."
                    )
                ]
            , Html.Extra.viewIf wrongRecipient
                (Html.p [ Html.Attributes.class "text-sm text-rust" ]
                    [ Html.text
                        ("This invite is for "
                            ++ intendedEmail
                            ++ ". Sign in with that email to accept it."
                        )
                    ]
                )
            , errorChip
            , Html.div [ Html.Attributes.class "flex gap-2 mt-2" ]
                [ acceptButton
                , declineButton
                ]
            ]
        ]



-- JWT


type alias Invite =
    { flockName : Maybe String
    , inviteeEmail : Maybe String
    , inviterEmail : Maybe String
    }


emptyInvite : Invite
emptyInvite =
    { flockName = Nothing
    , inviteeEmail = Nothing
    , inviterEmail = Nothing
    }


{-| Decode the JWT payload for display purposes.

We don't verify the signature — that's the server's job. If the token
is malformed we return an empty invite and the view renders generic
copy.

-}
decodeInvite : String -> Invite
decodeInvite token =
    case String.split "." token of
        [ _, payload, _ ] ->
            case base64UrlDecode payload of
                Just json ->
                    Json.Decode.decodeString inviteDecoder json
                        |> Result.withDefault emptyInvite

                Nothing ->
                    emptyInvite

        _ ->
            emptyInvite


inviteDecoder : Json.Decode.Decoder Invite
inviteDecoder =
    Json.Decode.map3 Invite
        (Json.Decode.maybe (Json.Decode.field "flockName" Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field "inviteeEmail" Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field "inviterEmail" Json.Decode.string))


{-| Minimal base64url decoder for the JWT payload. We're after the
display fields — never crypto. Returns `Nothing` for any malformed
input.
-}
base64UrlDecode : String -> Maybe String
base64UrlDecode input =
    let
        padded =
            input
                |> String.replace "-" "+"
                |> String.replace "_" "/"
                |> padBase64

        chars =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

        lookup c =
            case String.indexes (String.fromChar c) chars of
                idx :: _ ->
                    Just idx

                [] ->
                    Nothing

        decodeChunk chunk =
            case chunk of
                [ Just a, Just b, Just c, Just d ] ->
                    Just
                        (String.fromList
                            [ Char.fromCode (a * 4 + b // 16)
                            , Char.fromCode (modBy 16 b * 16 + c // 4)
                            , Char.fromCode (modBy 4 c * 64 + d)
                            ]
                        )

                _ ->
                    Nothing
    in
    padded
        |> String.replace "=" "A"
        |> String.toList
        |> List.map lookup
        |> chunkBy4
        |> List.map decodeChunk
        |> combineMaybes
        |> Maybe.map (String.concat >> stripTrailingNulls (String.length padded - String.length input))


padBase64 : String -> String
padBase64 s =
    case modBy 4 (String.length s) of
        0 ->
            s

        n ->
            s ++ String.repeat (4 - n) "="


chunkBy4 : List a -> List (List a)
chunkBy4 list =
    case list of
        a :: b :: c :: d :: rest ->
            [ a, b, c, d ] :: chunkBy4 rest

        [] ->
            []

        _ ->
            [ list ]


combineMaybes : List (Maybe a) -> Maybe (List a)
combineMaybes list =
    List.foldr
        (\maybe acc ->
            case ( maybe, acc ) of
                ( Just v, Just vs ) ->
                    Just (v :: vs)

                _ ->
                    Nothing
        )
        (Just [])
        list


stripTrailingNulls : Int -> String -> String
stripTrailingNulls padCount s =
    if padCount > 0 then
        String.dropRight padCount s

    else
        s
