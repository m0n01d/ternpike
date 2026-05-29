module Http.SharedTripApiTest exposing (suite)

{-| Hermetic coverage of the join-error status→message mapping. This is the
regression-prone bit the e2e `join-sharedtrip.spec.ts` sad-paths guarded
(expired / already-member / wrong-recipient copy); covering it here takes it off
the browser harness.
-}

import Expect
import Http
import Http.SharedTripApi as SharedTripApi
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Http.SharedTripApi.joinErrorMessage"
        [ test "410 → expired" <|
            \_ ->
                SharedTripApi.joinErrorMessage (Http.BadStatus 410)
                    |> Expect.equal "This invite has expired. Ask the inviter for a fresh link."
        , test "409 → already a member" <|
            \_ ->
                SharedTripApi.joinErrorMessage (Http.BadStatus 409)
                    |> Expect.equal "You're already a member of that shared trip."
        , test "403 → for someone else" <|
            \_ ->
                SharedTripApi.joinErrorMessage (Http.BadStatus 403)
                    |> Expect.equal "This invite is for someone else."
        , test "404 → expired or used" <|
            \_ ->
                SharedTripApi.joinErrorMessage (Http.BadStatus 404)
                    |> Expect.equal "Invite expired or already used."
        , test "401 → no longer valid" <|
            \_ ->
                SharedTripApi.joinErrorMessage (Http.BadStatus 401)
                    |> Expect.equal "This invite is no longer valid. Ask the inviter for a fresh link."
        , test "network error → generic fallback" <|
            \_ ->
                SharedTripApi.joinErrorMessage Http.NetworkError
                    |> Expect.equal "Couldn't join — something went wrong. Try again."
        , test "unmapped status → generic fallback" <|
            \_ ->
                SharedTripApi.joinErrorMessage (Http.BadStatus 500)
                    |> Expect.equal "Couldn't join — something went wrong. Try again."
        ]
