/***
Doc browser, ported from DocBrowser.tsx. Lists docs in a db
(`GET /admin/dbs/:db/docs?prefix&limit`), previews/edits one in `$EDITOR`
(`PUT …/docs/:id`), voids (`POST …/void`), or hard-deletes
(`DELETE …/docs/:id?rev=`). `/` prefix filter, `r` refresh, `Esc` back.
TEA: a `mode` union + reducer; the editor flow blocks the TTY via
`Editor.editJson`.
*/

type doc = {
  id: string,
  json: JSON.t,
  rev: option<string>,
}

let decodeDoc = (json: JSON.t): option<doc> =>
  switch Decode.stringField(json, "_id") {
  | Some(id) => Some({id, json, rev: Decode.stringField(json, "_rev")})
  | None => None
  }

// type · name · date — the one-line list summary.
let summary = (d: doc): string => {
  let str = key => Decode.stringField(d.json, key)
  let typ = str("type")->Option.getOr("")
  let date = switch str("date") {
  | Some(s) if s !== "" => s
  | _ => str("createdAt")->Option.getOr("")
  }
  let name = switch str("name") {
  | Some(s) if s !== "" => s
  | _ =>
    switch str("merchant") {
    | Some(s) if s !== "" => s
    | _ =>
      switch Decode.field(d.json, "amount") {
      | Some(JSON.Number(n)) => Float.toString(n)
      | Some(JSON.String(s)) => s
      | _ => ""
      }
    }
  }
  [typ, name, date]->Array.filter(s => s !== "")->Array.join(" · ")
}

type mode =
  | Delete(doc)
  | Filter
  | List
  | Preview(doc)
  | Void(doc)

type model = {
  cursor: int,
  docs: option<array<doc>>,
  filter: string,
  mode: mode,
}

type msg =
  | CursorDown
  | CursorUp
  | Loaded(array<doc>)
  | LoadFailed
  | SetFilter(string)
  | SetMode(mode)

let update = (m: model, msg: msg): model =>
  switch msg {
  | CursorDown =>
    let max = m.docs->Option.mapOr(0, d => Array.length(d)) - 1
    let max = max < 0 ? 0 : max
    {...m, cursor: m.cursor + 1 > max ? max : m.cursor + 1}
  | CursorUp => {...m, cursor: m.cursor - 1 < 0 ? 0 : m.cursor - 1}
  | Loaded(docs) => {...m, docs: Some(docs)}
  | LoadFailed => {...m, docs: Some([])}
  | SetFilter(filter) => {...m, filter}
  | SetMode(mode) => {...m, mode}
  }

let initial: model = {cursor: 0, docs: None, filter: "", mode: List}

let padEnd = (s: string, n: int): string => String.padEnd(s, n, " ")

module PreviewDoc = {
  @react.component
  let make = (~doc: doc, ~onBack: unit => unit, ~onEdit: unit => unit) => {
    Ink.useInput((input, key) =>
      if key.escape {
        onBack()
      } else if input === "e" {
        onEdit()
      }
    )
    let json = JSON.stringify(doc.json, ~space=2)
    let allLines = String.split(json, "\n")
    let lines = allLines->Array.slice(~start=0, ~end=40)
    <Ink.Box flexDirection=#column>
      <Ink.Text color="cyan"> {React.string(doc.id)} </Ink.Text>
      {lines
      ->Array.mapWithIndex((l, i) =>
        <Ink.Text key={Int.toString(i)} color="white"> {React.string(l)} </Ink.Text>
      )
      ->React.array}
      {Array.length(allLines) > 40
        ? <Ink.Text color="gray">
            {React.string("… (truncated; use e to open in $EDITOR)")}
          </Ink.Text>
        : React.null}
      <Ink.Box marginTop=1>
        <Ink.Text color="gray"> {React.string("[ e ] edit in $EDITOR · [ Esc ] back")} </Ink.Text>
      </Ink.Box>
    </Ink.Box>
  }
}

@react.component
let make = (
  ~db: string,
  ~onBack: unit => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let (model, dispatch) = React.useReducer(update, initial)
  let encodedDb = encodeURIComponent(db)

  let refresh = () => {
    setStatus(`loading ${db}…`)
    let prefix = model.filter === "" ? "" : `&prefix=${encodeURIComponent(model.filter)}`
    Req.get(`/admin/dbs/${encodedDb}/docs?limit=200${prefix}`)
    ->Promise.then(result => {
      switch result {
      | Ok(json) =>
        let docs =
          Decode.arrayField(json, "docs")->Option.getOr([])->Array.filterMap(decodeDoc)
        dispatch(Loaded(docs))
        setError(None)
        let total = switch Decode.intField(json, "total") {
        | Some(t) => ` of ${Int.toString(t)}`
        | None => ""
        }
        setStatus(`${db}: ${Int.toString(Array.length(docs))} docs${total}`)
      | Error(e) =>
        setError(Some(e.message))
        dispatch(LoadFailed)
      }
      Promise.resolve()
    })
    ->Promise.ignore
  }

  // refetch on db change or filter change
  React.useEffect2(() => {
    refresh()
    None
  }, (db, model.filter))

  // Editor flow blocks the TTY; runs synchronously then PUTs.
  let editFlow = (doc: doc) => {
    setStatus(`editing ${doc.id}…`)
    switch Editor.editJson(doc.json, "doc") {
    | Error(e) => setError(Some(e))
    | Ok(edited) =>
      let editedId = Decode.stringField(edited, "_id")
      let editedRev = Decode.stringField(edited, "_rev")
      if editedId !== Some(doc.id) {
        setError(Some("_id changed in editor — refusing to write"))
      } else if editedRev !== doc.rev {
        setError(Some("_rev changed in editor — refusing to write"))
      } else {
        Req.put(`/admin/dbs/${encodedDb}/docs/${encodeURIComponent(doc.id)}`, edited)
        ->Promise.then(result => {
          switch result {
          | Ok(json) =>
            let rev = Decode.stringField(json, "rev")->Option.getOr("?")
            setStatus(`saved ${doc.id} → rev ${rev}`)
            setError(None)
            refresh()
          | Error(e) => setError(Some(e.message))
          }
          Promise.resolve()
        })
        ->Promise.ignore
      }
    }
  }

  Ink.useInput((input, key) =>
    switch model.mode {
    | List =>
      if key.escape {
        onBack()
      } else if key.upArrow {
        dispatch(CursorUp)
      } else if key.downArrow {
        dispatch(CursorDown)
      } else {
        let current = model.docs->Option.flatMap(d => d->Array.get(model.cursor))
        if key.return || input === "p" {
          switch current {
          | Some(d) => dispatch(SetMode(Preview(d)))
          | None => ()
          }
        } else if input === "/" {
          dispatch(SetMode(Filter))
        } else if input === "r" {
          refresh()
        } else if input === "e" {
          switch current {
          | Some(d) => editFlow(d)
          | None => ()
          }
        } else if input === "v" {
          switch current {
          | Some(d) => dispatch(SetMode(Void(d)))
          | None => ()
          }
        } else if input === "d" {
          switch current {
          | Some(d) => dispatch(SetMode(Delete(d)))
          | None => ()
          }
        }
      }
    | _ => ()
    }
  )

  switch model.mode {
  | Filter =>
    <Ink.Box>
      <Ink.Text> {React.string("id prefix: ")} </Ink.Text>
      <Ink.TextInput
        value=model.filter
        onChange={v => dispatch(SetFilter(v))}
        onSubmit={_ => dispatch(SetMode(List))}
      />
    </Ink.Box>
  | Preview(doc) =>
    <PreviewDoc
      doc
      onBack={() => dispatch(SetMode(List))}
      onEdit={() => {
        editFlow(doc)
        dispatch(SetMode(List))
      }}
    />
  | Void(doc) =>
    <Confirm
      prompt={`Void ${doc.id}? Writes a soft-delete tombstone (void::…::del).`}
      onCancel={() => dispatch(SetMode(List))}
      onConfirm={() => {
        Req.post(`/admin/dbs/${encodedDb}/void`, JSON.Object(Dict.fromArray([("docId", JSON.String(doc.id))])))
        ->Promise.then(result => {
          switch result {
          | Ok(json) =>
            let voidId = Decode.stringField(json, "voidId")->Option.getOr("?")
            setStatus(`voided → ${voidId}`)
            setError(None)
          | Error(e) => setError(Some(e.message))
          }
          dispatch(SetMode(List))
          refresh()
          Promise.resolve()
        })
        ->Promise.ignore
      }}
    />
  | Delete(doc) =>
    <Confirm
      prompt={`HARD delete ${doc.id}? Skips the tombstone — sync may resurrect via conflict.`}
      expectedAnswer="delete"
      onCancel={() => dispatch(SetMode(List))}
      onConfirm={() => {
        let rev = doc.rev->Option.getOr("")
        Req.delete(
          `/admin/dbs/${encodedDb}/docs/${encodeURIComponent(doc.id)}?rev=${encodeURIComponent(rev)}`,
        )
        ->Promise.then(result => {
          switch result {
          | Ok(_) =>
            setStatus(`deleted ${doc.id}`)
            setError(None)
          | Error(e) => setError(Some(e.message))
          }
          dispatch(SetMode(List))
          refresh()
          Promise.resolve()
        })
        ->Promise.ignore
      }}
    />
  | List =>
    switch model.docs {
    | None =>
      <Ink.Text>
        <Ink.Spinner /> {React.string(" loading")}
      </Ink.Text>
    | Some(docs) =>
      if Array.length(docs) === 0 {
        <Ink.Box flexDirection=#column>
          <Ink.Text color="gray"> {React.string(`no docs (prefix: "${model.filter}")`)} </Ink.Text>
          <Ink.Text color="gray"> {React.string("[ / ] filter · [ Esc ] back")} </Ink.Text>
        </Ink.Box>
      } else {
        let rows = docs->Array.slice(~start=0, ~end=30)
        let header = model.filter === "" ? db : `${db}   prefix: ${model.filter}`
        <Ink.Box flexDirection=#column>
          <Ink.Text color="gray"> {React.string(header)} </Ink.Text>
          {rows
          ->Array.mapWithIndex((d, i) => {
            let marker = i === model.cursor ? "› " : "  "
            <Ink.Text key=d.id>
              {React.string(marker ++ padEnd(Format.truncate(d.id, 50), 50) ++ " " ++ summary(d))}
            </Ink.Text>
          })
          ->React.array}
          {Array.length(docs) > 30
            ? <Ink.Text color="gray">
                {React.string(`… ${Int.toString(Array.length(docs) - 30)} more (use filter)`)}
              </Ink.Text>
            : React.null}
        </Ink.Box>
      }
    }
  }
}
