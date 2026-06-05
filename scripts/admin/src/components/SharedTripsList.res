/***
Shared trips screen — lists shared trips with billing status.

Keys:
  ↑/↓  move cursor
  Enter  browse docs in the selected trip's DB
  r      refresh
*/

// LOCAL binding: String.padEnd is not in ReScript stdlib.
// padEnd(s, n) right-pads `s` with spaces to at least `n` chars.
@send external padEnd: (string, int) => string = "padEnd"

type sharedTrip = {
  id: string,
  name: string,
  dbName: string,
  billingOwner: string,
  billingStatus: string,
  memberCount: int,
}

type state =
  | Loading
  | Loaded(array<sharedTrip>)
  | Failed

type msg =
  | SetTrips(array<sharedTrip>)
  | FetchFailed
  | MoveCursor(int)

type model = {
  state: state,
  cursor: int,
}

let decodeTrip = (json: JSON.t): sharedTrip => {
  let name = Decode.stringField(json, "name")->Option.getOr("")
  let dbName = Decode.stringField(json, "dbName")->Option.getOr("")
  let id = Decode.stringField(json, "id")->Option.getOr(dbName)
  let billingOwner = Decode.stringField(json, "billingOwner")->Option.getOr("")
  let billingStatus = Decode.stringField(json, "billingStatus")->Option.getOr("")
  let members = Decode.arrayField(json, "members")->Option.getOr([])
  let memberCount = Array.length(members)
  {id, name, dbName, billingOwner, billingStatus, memberCount}
}

let update = (model: model, msg: msg): model =>
  switch msg {
  | SetTrips(trips) => {state: Loaded(trips), cursor: 0}
  | FetchFailed => {state: Failed, cursor: 0}
  | MoveCursor(n) =>
    switch model.state {
    | Loaded(trips) =>
      let len = Array.length(trips)
      let next = if n < 0 {0} else if n >= len {len - 1} else {n}
      {...model, cursor: next}
    | _ => model
    }
  }

let statusColor = (s: string): string =>
  switch s {
  | "active" => "green"
  | "grace" => "yellow"
  | "frozen" => "red"
  | _ => "gray"
  }

@react.component
let make = (
  ~onPick: string => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let (model, dispatch) = React.useReducer(update, {state: Loading, cursor: 0})

  let doFetch = React.useCallback0(async () => {
    setStatus("loading shared trips…")
    let result = await Req.get("/admin/sharedtrips")
    switch result {
    | Ok(json) =>
      let trips =
        Decode.arrayField(json, "sharedTrips")
        ->Option.getOr([])
        ->Array.map(decodeTrip)
      dispatch(SetTrips(trips))
      setError(None)
      setStatus(`${Int.toString(Array.length(trips))} shared trips`)
    | Error(e) =>
      dispatch(FetchFailed)
      setError(Some(e.message))
    }
  })

  React.useEffect0(() => {
    let _ = doFetch()
    None
  })

  Ink.useInput((input, key) => {
    switch model.state {
    | Loaded(trips) =>
      if key.upArrow {
        dispatch(MoveCursor(model.cursor - 1))
      } else if key.downArrow {
        dispatch(MoveCursor(model.cursor + 1))
      } else if key.return {
        switch Array.get(trips, model.cursor) {
        | Some(t) => onPick(t.dbName)
        | None => ()
        }
      } else if input === "r" {
        let _ = doFetch()
      }
    | _ =>
      if input === "r" {
        let _ = doFetch()
      }
    }
  })

  switch model.state {
  | Loading =>
    <Ink.Text>
      <Ink.Spinner type_="dots" />
      {React.string(" loading")}
    </Ink.Text>
  | Failed => <Ink.Text color="red"> {React.string("fetch failed — press r to retry")} </Ink.Text>
  | Loaded(trips) =>
    if Array.length(trips) === 0 {
      <Ink.Text color="gray"> {React.string("no shared trips")} </Ink.Text>
    } else {
      let visible = Array.slice(trips, ~start=0, ~end=30)
      <Ink.Box flexDirection=#column>
        <Ink.Text color="gray">
          {React.string(
            `${Int.toString(Array.length(trips))} shared trips   [ Enter ] browse · [ r ] refresh`,
          )}
        </Ink.Text>
        {visible
        ->Array.mapWithIndex((t, i) => {
          let cursor = if i === model.cursor {"› "} else {"  "}
          let nameLabel = Format.truncate(t.name === "" ? t.dbName : t.name, 28)->padEnd(28)
          let statusLabel = Format.truncate(t.billingStatus === "" ? "?" : t.billingStatus, 7)->padEnd(7)
          let ownerLabel = Format.truncate(t.billingOwner, 30)->padEnd(30)
          let mbrs = `${Int.toString(t.memberCount)} mbrs`
          <Ink.Text key={t.dbName}>
            {React.string(cursor ++ nameLabel ++ " ")}
            <Ink.Text color={statusColor(t.billingStatus)}>
              {React.string(statusLabel)}
            </Ink.Text>
            {React.string(" ")}
            <Ink.Text color="gray"> {React.string(ownerLabel)} </Ink.Text>
            {React.string(" ")}
            <Ink.Text color="gray"> {React.string(mbrs)} </Ink.Text>
          </Ink.Text>
        })
        ->React.array}
      </Ink.Box>
    }
  }
}
