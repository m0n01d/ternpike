/***
Databases screen, ported from DbsList.tsx. Lists CouchDB dbs from
`GET /admin/dbs`; `/` filter, `r` refresh, `↑`/`↓` move, `Enter` browse.
TEA: a `useReducer` model/msg with the refresh effect living in a handler that
dispatches the result message.
*/

type db = {
  docCount: option<int>,
  name: string,
  sizeBytes: option<int>,
}

let decodeDb = (json: JSON.t): option<db> =>
  switch Decode.stringField(json, "name") {
  | Some(name) =>
    Some({
      docCount: Decode.intField(json, "docCount"),
      name,
      sizeBytes: Decode.intField(json, "sizeBytes"),
    })
  | None => None
  }

type model = {
  cursor: int,
  dbs: option<array<db>>,
  filter: string,
  filterMode: bool,
}

type msg =
  | CursorDown
  | CursorUp
  | EnterFilter
  | ExitFilter
  | Loaded(array<db>)
  | LoadFailed
  | SetFilter(string)

let filteredOf = (m: model): array<db> =>
  switch m.dbs {
  | Some(dbs) =>
    let needle = String.toLowerCase(m.filter)
    dbs->Array.filter(d => String.includes(String.toLowerCase(d.name), needle))
  | None => []
  }

let update = (m: model, msg: msg): model =>
  switch msg {
  | CursorDown =>
    let max = Array.length(filteredOf(m)) - 1
    {...m, cursor: m.cursor + 1 > max ? max : m.cursor + 1}
  | CursorUp => {...m, cursor: m.cursor - 1 < 0 ? 0 : m.cursor - 1}
  | EnterFilter => {...m, filterMode: true}
  | ExitFilter => {...m, filterMode: false}
  | Loaded(dbs) => {...m, cursor: 0, dbs: Some(dbs)}
  | LoadFailed => {...m, dbs: Some([])}
  | SetFilter(filter) => {...m, cursor: 0, filter}
  }

let initial: model = {cursor: 0, dbs: None, filter: "", filterMode: false}

let padEnd = (s: string, n: int): string => String.padEnd(s, n, " ")
let padStart = (s: string, n: int): string => String.padStart(s, n, " ")

@react.component
let make = (
  ~onPick: string => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let (model, dispatch) = React.useReducer(update, initial)

  let refresh = () => {
    setStatus("loading dbs…")
    Req.get("/admin/dbs")
    ->Promise.then(result => {
      switch result {
      | Ok(json) =>
        let dbs =
          Decode.arrayField(json, "dbs")
          ->Option.getOr([])
          ->Array.filterMap(decodeDb)
        dispatch(Loaded(dbs))
        setError(None)
        setStatus(`${Int.toString(Array.length(dbs))} dbs`)
      | Error(e) =>
        setError(Some(e.message))
        dispatch(LoadFailed)
      }
      Promise.resolve()
    })
    ->Promise.ignore
  }

  React.useEffect0(() => {
    refresh()
    None
  })

  let filtered = filteredOf(model)

  Ink.useInput((input, key) =>
    if model.filterMode {
      ()
    } else if key.upArrow {
      dispatch(CursorUp)
    } else if key.downArrow {
      dispatch(CursorDown)
    } else if key.return {
      switch filtered->Array.get(model.cursor) {
      | Some(d) => onPick(d.name)
      | None => ()
      }
    } else if input === "/" {
      dispatch(EnterFilter)
    } else if input === "r" {
      refresh()
    }
  )

  if model.filterMode {
    <Ink.Box>
      <Ink.Text> {React.string("filter: ")} </Ink.Text>
      <Ink.TextInput
        value=model.filter
        onChange={v => dispatch(SetFilter(v))}
        onSubmit={_ => dispatch(ExitFilter)}
      />
    </Ink.Box>
  } else {
    switch model.dbs {
    | None =>
      <Ink.Text>
        <Ink.Spinner /> {React.string(" loading")}
      </Ink.Text>
    | Some(_) =>
      if Array.length(filtered) === 0 {
        <Ink.Text color="gray"> {React.string("no databases")} </Ink.Text>
      } else {
        let rows = filtered->Array.slice(~start=0, ~end=30)
        <Ink.Box flexDirection=#column>
          <Ink.Text color="gray">
            {React.string(
              `${Int.toString(Array.length(filtered))} dbs   [ Enter ] browse · [ / ] filter · [ r ] refresh`,
            )}
          </Ink.Text>
          <Ink.Box marginTop=1>
            <Ink.Text color="cyan" bold=true>
              {React.string(
                "  " ++ padEnd("name", 48) ++ padStart("docs", 8) ++ "  " ++ padStart("size", 10),
              )}
            </Ink.Text>
          </Ink.Box>
          {rows
          ->Array.mapWithIndex((d, i) => {
            let marker = i === model.cursor ? "› " : "  "
            let docs = padStart(d.docCount->Option.mapOr("—", n => Int.toString(n)), 8)
            let size = padStart(Format.formatBytes(d.sizeBytes), 10)
            <Ink.Text key=d.name>
              {React.string(marker ++ padEnd(Format.truncate(d.name, 48), 48) ++ docs ++ "  " ++ size)}
            </Ink.Text>
          })
          ->React.array}
          {Array.length(filtered) > 30
            ? <Ink.Text color="gray">
                {React.string(`… ${Int.toString(Array.length(filtered) - 30)} more`)}
              </Ink.Text>
            : React.null}
        </Ink.Box>
      }
    }
  }
}
