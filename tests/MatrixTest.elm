module MatrixTest exposing (suite)

{-| The pure verification tier: run every unit × fixture in the registry and
assert the verdicts. This is the hermetic, backend-free signal that replaces
most of what the flaky full-stack Playwright e2e gave us.

Two properties hold for every registered unit:

  - **Non-probe fixtures pass.** A real fixture observed at its surface must
    satisfy every invariant.
  - **Probe fixtures fail.** Each unit ships at least one adversarial probe
    whose injected regression must trip an invariant — proof the harness
    catches lies, not just confirms truths.

Inputs are key-free projections, so no `Browser.Navigation.Key` (and therefore
no `Main`) is needed here.

-}

import Expect
import Test exposing (Test, describe, test)
import Verify.Core as Core
import Verify.Registry as Registry


suite : Test
suite =
    describe "Verify matrix"
        [ describe "every registered result has an honest verdict"
            (List.map resultTest Registry.runAll)
        , test "the registry is non-empty" <|
            \_ ->
                List.length Registry.runAll
                    |> Expect.greaterThan 0
        , test "at least one probe fixture is present" <|
            \_ ->
                Registry.runAll
                    |> List.filter isProbeFixture
                    |> List.length
                    |> Expect.greaterThan 0
        ]


{-| A non-probe fixture must `Pass`; a probe fixture must `Fail`. We identify
probes by the `probe` naming convention used in the spec fixtures.
-}
resultTest : Core.RunResult -> Test
resultTest result =
    test (result.unit ++ " / " ++ result.fixture) <|
        \_ ->
            if isProbeFixture result then
                case result.verdict of
                    Core.Fail _ ->
                        Expect.pass

                    Core.Pass ->
                        Expect.fail
                            ("probe fixture " ++ result.fixture ++ " unexpectedly PASSED — the harness is not catching the injected regression")

            else
                case result.verdict of
                    Core.Pass ->
                        Expect.pass

                    Core.Fail detail ->
                        Expect.fail (result.unit ++ " / " ++ result.fixture ++ " FAILED: " ++ detail)


isProbeFixture : Core.RunResult -> Bool
isProbeFixture result =
    String.startsWith "probe" result.fixture
