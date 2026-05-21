---
name: elm-program-test
description: Write integration-style tests for ternpike's Elm code using avh4/elm-program-test — drive a program with fillIn / clickButton / simulateIncomingPort and assert on the rendered DOM. Use when adding tests for a Page's view+update behavior, or when introducing an Effect-type refactor that needs SimulatedEffect.Http / SimulatedEffect.Ports coverage. Tests run via `npm test`.
---

# elm-program-test in ternpike

`avh4/elm-program-test@4.0.1` is wired into `elm.json` (test-deps). Tests live in `tests/` and run as part of `npm test` (alongside `elm-verify-examples` and the existing `elm-test` suites).

The agent path:

1. Read `tests/ProgramTestSetupTest.elm` — it's a working reference that exercises `createElement`, `fillIn`, `clickButton`, `expectViewHas`, `expectViewHasNot`. Copy its shape.
2. Add your new test file to `tests/` (flat layout, mirroring `RoutingTest.elm`).
3. `npm test` → expect "TEST RUN PASSED" with the test count bumped by the number of cases you added.

## When to reach for it

- **Page-level view+update behavior** that's annoying to express as a pure unit test — typing into a field changes a button's enabled state, clicking a category chip updates a hidden state that drives the next render.
- **Refactor safety net.** ProgramTest assertions hit the rendered DOM rather than internal data shapes, so they survive Model/Msg restructures.
- **Future: Effect-type refactor.** When (if) `Main.elm` is split into an `Effect` ADT + a `perform : Effect -> Cmd Msg` for production, `SimulatedEffect.Http` / `SimulatedEffect.Ports` lets tests assert on outgoing HTTP requests and port messages without running PouchDB. The docs are <https://elm-program-test.netlify.app/cmds> and `/ports`.

## What's currently testable

Ternpike's `Main.elm` is one big `Browser.application` with raw `Cmd`s and PouchDB ports inline. **Directly driving `Main.main` under ProgramTest is not set up** (it would need stubs for every port subscription and a `withSimulatedEffects` covering every Cmd). Instead:

- **Use ProgramTest against pure, self-contained programs.** The reference test (`ProgramTestSetupTest.elm`) defines its own tiny `init`/`update`/`view` inline and tests *that*. This is the right shape for any new test until pages are refactored.
- **Extract a `Page` first.** If you want to test, say, `Pages.Add`, the prerequisite is pulling its state out of `Main.Model` into a `Pages.Add.Model` + `Pages.Add.update : Msg -> Model -> ( Model, Effect )` quartet. Then ProgramTest can drive it. The current `Pages/*` modules expose only view functions — that has to change first.

If you find yourself wanting to stub PouchDB inside a test, **stop and discuss with the user** — that's an Effect-type refactor (issue-sized, not commit-sized).

## The reference test, abridged

```elm
import ProgramTest exposing (ProgramTest)
import Test.Html.Selector

start : ProgramTest Model Msg (Cmd Msg)
start =
    ProgramTest.createElement
        { init = init, update = update, view = view }
        |> ProgramTest.start ()

suite =
    describe "..."
        [ test "fillIn + clickButton" <| \() ->
            start
                |> ProgramTest.fillIn "amount" "Amount" "12.50"
                |> ProgramTest.clickButton "Save expense"
                |> ProgramTest.expectViewHas
                    [ Test.Html.Selector.tag "li"
                    , Test.Html.Selector.text "12.50"
                    ]
        ]
```

Full file: `tests/ProgramTestSetupTest.elm`.

## API quick reference

The bits you'll reach for first:

| API | Purpose |
|---|---|
| `ProgramTest.createElement { init, update, view }` | Wrap a `Browser.element`-shaped program |
| `ProgramTest.createDocument` / `createApplication` | For `Browser.document` / `Browser.application` |
| `ProgramTest.start flags` | Run `init` and produce the `ProgramTest` |
| `ProgramTest.fillIn "id" "Label text" "value"` | Types into an `<input id="id">` with a `<label for="id">Label text</label>` |
| `ProgramTest.clickButton "Save"` | Click the `<button>` whose visible text is "Save" |
| `ProgramTest.expectViewHas [ selectors ]` | Assert the current view matches a list of `Test.Html.Selector` selectors |
| `ProgramTest.expectViewHasNot [ selectors ]` | Inverse |
| `ProgramTest.ensureViewHas / ensureViewHasNot` | Same but returns `ProgramTest` so you can keep driving |

For HTTP/ports/tasks (only once the Effect refactor lands):

| API | Purpose |
|---|---|
| `ProgramTest.withSimulatedEffects effectToSim` | Tell ProgramTest how to interpret your `Effect` type |
| `ProgramTest.withSimulatedSubscriptions subToSim` | Same for subscriptions / incoming ports |
| `SimulatedEffect.Http.get` / `.post` | Build a simulated HTTP effect from the production-shaped record |
| `SimulatedEffect.Ports.send "portName" json` | Outgoing port |
| `SimulatedEffect.Ports.subscribe "portName" decoder Msg` | Incoming port subscription |
| `ProgramTest.simulateHttpOk "METHOD" "url" body` | Resolve a pending simulated request |
| `ProgramTest.expectHttpRequest "METHOD" "url" predicate` | Assert request shape |
| `ProgramTest.simulateIncomingPort "portName" json` | Push a value into an incoming port |
| `ProgramTest.ensureOutgoingPortValues "portName" decoder pred` | Assert outgoing port values |

Full docs: <https://elm-program-test.netlify.app/> — guidebooks for `/html`, `/cmds`, `/ports` plus the package API at <https://package.elm-lang.org/packages/avh4/elm-program-test/4.0.1>.

## Conventions for new ProgramTest files in this repo

- **Alphabetize record fields and type constructor lists** (project rule from `CLAUDE.md` § Elm style guide). The reference test follows this.
- **Fully qualify imports.** `import Test.Html.Selector` then `Test.Html.Selector.tag "li"` — not `exposing (..)`.
- **`elm-format src --yes` does not touch `tests/`.** Run `npx elm-format tests/<NewFile>.elm --yes` after writing, then `npx elm-format tests/<NewFile>.elm --validate` to confirm clean.
- **Don't add to `tests/elm-verify-examples.json`.** That file lists modules whose `-->` examples get harvested into generated tests; ProgramTest files don't have `-->` examples.
- **Name `tests/<Something>Test.elm`** — same as `RoutingTest.elm`. elm-test discovers any `module Foo exposing (suite)` (or any exposed `Test`) under `tests/`.

## Running

```bash
npm test                     # elm-verify-examples && npx elm-test — runs everything
npx elm-test tests/ProgramTestSetupTest.elm   # one file
npx elm-test --watch         # watch mode
```

First run after pulling a fresh tree installs `elm-test@0.19.1-revision17` via `npx` (the `npm warn exec` line is expected). It caches; subsequent runs are ~300 ms for the full suite.

## Adding the dependency on a fresh clone

It's already in `elm.json`'s `test-dependencies` block, but if you ever need to re-add or bump:

```bash
npx -y --package elm-json elm-json install --test avh4/elm-program-test@<version> --yes
```

`elm-json` resolves indirect deps automatically. The current pin is `4.0.1`, which brings in `avh4/elm-fifo`, `elm-community/list-extra`, `hecrj/html-parser`, `mgold/elm-nonempty-list`, `rtfeldman/elm-hex` as indirect test deps.

## Gotchas

- **`fillIn` needs both an `id` on the input and a matching `<label for="id">`.** No label → "No <label> for the given <input> was found." Wire both, even on a tiny test program.
- **`clickButton "text"` matches button label text exactly.** Whitespace inside the button counts. If the button renders `Save expense` with a leading space, the matcher won't find `"Save expense"`. Trim it in the view.
- **Buttons must be `<button>` elements**, not `<div>` with `onClick`. Ternpike already enforces this (CLAUDE.md § Elm style — "only `<button>` elements get click handlers"); ProgramTest enforces it back.
- **Don't import `Test.Html.Selector exposing (..)`.** `NoImportingEverything` rule fires under `npm run review`. Qualify it: `import Test.Html.Selector` then `Test.Html.Selector.tag "li"`.
- **`Browser.application` tests need a real `Nav.Key`.** `ProgramTest.createApplication` produces one for you, but you cannot construct one by hand — so any test that hits routing or commands a navigation must go through `createApplication`, not `createElement`.

## Troubleshooting

- **`Module not found: ProgramTest`**: `elm.json` test-deps got reverted. Re-run the `elm-json install --test` line above.
- **`Could not match the type ... ProgramTest model msg effect`**: the `effect` param of `createElement`/`Document`/`Application` defaults to `Cmd Msg`. If you switch to `withSimulatedEffects`, change the type signature on your `start` function to `ProgramTest Model Msg MyEffect` and pass the effect-to-simulated mapper.
- **`The button "X" was not found in the view`**: the visible button text doesn't match. Either fix the assertion or check for stray whitespace inside the `<button>`.
- **`HTTP request was not handled`**: you called `simulateHttpOk` for a URL the program never requested, or the program is using a real `Cmd` (not `withSimulatedEffects`). For the latter, the production code has to emit your `Effect` type, not a raw `Http.get`.
