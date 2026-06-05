/***
TEA hello-world rendered through Ink. This is the TEMPLATE for the whole admin
TUI rewrite: it mirrors Elm's Model / Msg / update split on top of
`React.useReducer`.

  model   ↔ Elm Model        (immutable state record)
  msg     ↔ Elm Msg          (variant of every event the UI can dispatch)
  update  ↔ Elm update       (pure (model, msg) => model — NO side effects here)
  view    ↔ Elm view         (model => Html — here it's the React component)

Side effects in the real app: `update` would, for an effectful Msg, kick off
the work in a `React.useEffect` keyed on model state (or via a small command
queue in the model) and dispatch a *result* Msg back into the reducer — exactly
like an Elm `Cmd`. hello-world has no effects, so `update` is purely synchronous.
*/

// --- Model -----------------------------------------------------------------

type model = {count: int}

let init: model = {count: 0}

// --- Msg -------------------------------------------------------------------

type msg =
  | Increment
  | Quit

// --- update (pure) ---------------------------------------------------------

let update = (model: model, msg: msg): model =>
  switch msg {
  | Increment => {count: model.count + 1}
  | Quit => model // quitting is an effect, handled at the view boundary
  }

// --- view ------------------------------------------------------------------

@react.component
let make = () => {
  let (model, dispatch) = React.useReducer(update, init)
  let app = Ink.useApp()

  Ink.useInput((input, key) => {
    if input === " " {
      dispatch(Increment)
    } else if input === "q" || key.escape {
      // Quit is the one effect: dispatch the Msg for symmetry/logging, then
      // perform the unmount. In Elm this would be a Cmd returned from update.
      dispatch(Quit)
      app.exit()
    }
  })

  <Ink.Box flexDirection=#column padding=1>
    <Ink.Text color="green" bold=true>
      {React.string("Ternpike Admin — ReScript + Ink + TEA")}
    </Ink.Text>
    <Ink.Box>
      <Ink.Text> {React.string("count: ")} </Ink.Text>
      <Ink.Text color="cyan" bold=true> {React.int(model.count)} </Ink.Text>
    </Ink.Box>
    <Ink.Text dimColor=true>
      {React.string("press <space> to increment · q or <esc> to quit")}
    </Ink.Text>
  </Ink.Box>
}
