module Data.SharedTripUiTest exposing (suite)

{-| Hermetic coverage of the shared-trip modal error-message mapping — the
"Already a member." inline error the e2e `create-sharedtrip.spec.ts` guarded on a
duplicate invite (409), plus the other modal failure chips. Browser-free.
-}

import Data.SharedTripUi as SharedTripUi
import Expect
import Http
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Data.SharedTripUi.errorMessage"
        [ test "409 → already a member (duplicate invite)" <|
            \_ ->
                SharedTripUi.errorMessage (Http.BadStatus 409)
                    |> Expect.equal "Already a member."
        , test "403 → not allowed" <|
            \_ ->
                SharedTripUi.errorMessage (Http.BadStatus 403)
                    |> Expect.equal "Not allowed. Refresh and try again."
        , test "404 → shared trip not found" <|
            \_ ->
                SharedTripUi.errorMessage (Http.BadStatus 404)
                    |> Expect.equal "That shared trip wasn't found."
        , test "422 → request rejected" <|
            \_ ->
                SharedTripUi.errorMessage (Http.BadStatus 422)
                    |> Expect.equal "Request rejected. Check the details and try again."
        , test "BadBody passes the client-side validation string through verbatim" <|
            \_ ->
                SharedTripUi.errorMessage (Http.BadBody "Name is required.")
                    |> Expect.equal "Name is required."
        , test "network error → friendly retry" <|
            \_ ->
                SharedTripUi.errorMessage Http.NetworkError
                    |> Expect.equal "Network error. Try again."
        , test "timeout → friendly retry" <|
            \_ ->
                SharedTripUi.errorMessage Http.Timeout
                    |> Expect.equal "Took too long. Try again."
        , test "unmapped status → generic fallback" <|
            \_ ->
                SharedTripUi.errorMessage (Http.BadStatus 500)
                    |> Expect.equal "Something went wrong. Try again."
        ]
