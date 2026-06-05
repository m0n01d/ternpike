/***
User detail — ported from UserDetail.tsx, shaped as TEA, with the new
full-record view + `$EDITOR` record edit.

  model  = { detail, exStr, mode, tripsStr }
  msg    = Loaded | LoadFailed | SetMode | SetTripsStr | SetExStr
  update = pure

The server's `GET /admin/users/:email` now returns the full `UserRecord` under
`record` alongside `tier` / `personalDb` / `docCount` / `sizeBytes` /
`sharedTrips`. We render every record field (sorted, generic over the JSON
object so the view never drifts from the schema) plus the DB stats.

New action:
  [ e ] edit record — opens the raw `record` JSON in `$EDITOR`
    (`Editor.editJson`, blocking), then `PUT /admin/users/:email` with the
    edited body. A `409 trailblazer_permanent` is surfaced as a clear status.

Existing actions kept: [ t ] tier, [ s ] seed sample data, [ Enter ] browse
docs, [ Esc ] back.
*/

type sharedTrip = {
  id: string,
  name: string,
}

type detail = {
  docCount: option<int>,
  email: string,
  personalDb: string,
  record: JSON.t,
  sharedTrips: array<sharedTrip>,
  sizeBytes: option<int>,
  tier: string,
}

type mode =
  | SeedExpenses(int) // arg is the chosen trip count
  | SeedTrips
  | TierMode
  | View

type model = {
  detail: option<detail>,
  exStr: string,
  mode: mode,
  tripsStr: string,
}

type msg =
  | Loaded(detail)
  | LoadFailed
  | SetExStr(string)
  | SetMode(mode)
  | SetTripsStr(string)

let decodeSharedTrip = (json: JSON.t): sharedTrip => {
  id: Decode.stringField(json, "id")->Option.getOr(""),
  name: Decode.stringField(json, "name")->Option.getOr(""),
}

let decodeDetail = (json: JSON.t): detail => {
  docCount: Decode.intField(json, "docCount"),
  email: Decode.stringField(json, "email")->Option.getOr(""),
  personalDb: Decode.stringField(json, "personalDb")->Option.getOr(""),
  record: Decode.field(json, "record")->Option.getOr(JSON.Null),
  sharedTrips: Decode.arrayField(json, "sharedTrips")
  ->Option.getOr([])
  ->Array.map(decodeSharedTrip),
  sizeBytes: Decode.intField(json, "sizeBytes"),
  tier: Decode.stringField(json, "tier")->Option.getOr("tern"),
}

let update = (model: model, msg: msg): model =>
  switch msg {
  | Loaded(detail) => {...model, detail: Some(detail)}
  | LoadFailed => model
  | SetExStr(exStr) => {...model, exStr}
  | SetMode(mode) => {...model, mode}
  | SetTripsStr(tripsStr) => {...model, tripsStr}
  }

/** One-line display of a JSON scalar (or compact JSON for nested values). */
let scalarToString = (json: JSON.t): string =>
  switch json {
  | JSON.Null => "—"
  | JSON.String(s) => s === "" ? "—" : s
  | JSON.Number(n) => Float.toString(n)
  | JSON.Boolean(b) => b ? "true" : "false"
  | JSON.Object(_) | JSON.Array(_) => JSON.stringify(json)
  }

/** `record` field rows, sorted by key so the layout is stable. */
let recordRows = (record: JSON.t): array<(string, string)> =>
  switch record {
  | JSON.Object(d) =>
    Dict.toArray(d)
    ->Array.toSorted(((a, _), (b, _)) => String.compare(a, b))
    ->Array.map(((k, v)) => (k, scalarToString(v)))
  | _ => []
  }

let clampInt = (raw: string, lo: int, hi: int): int => {
  let n = switch Int.fromString(raw) {
  | Some(v) => v
  | None => lo
  }
  let n = n < lo ? lo : n
  n > hi ? hi : n
}

@react.component
let make = (
  ~email: string,
  ~onBack: unit => unit,
  ~onBrowse: string => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let (model, dispatch) = React.useReducer(update, {
    detail: None,
    exStr: "10",
    mode: View,
    tripsStr: "1",
  })

  let refresh = () => {
    setStatus(`loading ${email}…`)
    Req.get("/admin/users/" ++ email)
    ->Promise.thenResolve(result =>
      switch result {
      | Ok(json) =>
        dispatch(Loaded(decodeDetail(json)))
        setError(None)
        setStatus(email)
      | Error(e) =>
        dispatch(LoadFailed)
        setError(Some(e.message))
      }
    )
    ->Promise.ignore
  }

  React.useEffect1(() => {
    refresh()
    None
  }, [email])

  let setTier = (tier: Tier.t) => {
    let label = Tier.label(tier)
    setStatus(`setting tier ${label}…`)
    Req.put(
      "/admin/users/" ++ email ++ "/tier",
      JSON.Object(Dict.fromArray([("tier", JSON.String(label))])),
    )
    ->Promise.thenResolve(result => {
      switch result {
      | Ok(_) => setStatus(`${email} → ${label}`)
      | Error(e) if e.status === 409 =>
        setError(Some("Trailblazer is permanent — cannot change tier"))
      | Error(e) => setError(Some(e.message))
      }
      dispatch(SetMode(View))
      refresh()
    })
    ->Promise.ignore
  }

  let seedExpenses = (tripCount: int, raw: string) => {
    let perTrip = clampInt(raw, 1, 200)
    setStatus(`seeding ${Int.toString(tripCount)} × ${Int.toString(perTrip)}…`)
    Req.post(
      "/admin/seed/expenses",
      JSON.Object(
        Dict.fromArray([
          ("email", JSON.String(email)),
          ("expensesPerTrip", JSON.Number(Int.toFloat(perTrip))),
          ("tripCount", JSON.Number(Int.toFloat(tripCount))),
        ]),
      ),
    )
    ->Promise.thenResolve(result => {
      switch result {
      | Ok(json) =>
        let written = Decode.intField(json, "written")->Option.getOr(0)
        setStatus(`seeded ${Int.toString(written)} docs into ${email}`)
      | Error(e) => setError(Some(e.message))
      }
      dispatch(SetMode(View))
      refresh()
    })
    ->Promise.ignore
  }

  // Edit the raw record in $EDITOR (blocking, takes over the TTY), then PUT it.
  let editRecord = (record: JSON.t) => {
    let initial = switch record {
    | JSON.Null => JSON.Object(Dict.fromArray([("email", JSON.String(email))]))
    | other => other
    }
    switch Editor.editJson(initial, "user") {
    | Ok(edited) =>
      setStatus(`saving ${email}…`)
      Req.put("/admin/users/" ++ email, edited)
      ->Promise.thenResolve(result => {
        switch result {
        | Ok(_) => setStatus(`updated ${email}`)
        | Error(e) if e.status === 409 =>
          setError(Some("Trailblazer is permanent — record not changed"))
        | Error(e) => setError(Some(e.message))
        }
        refresh()
      })
      ->Promise.ignore
    | Error(reason) => setError(Some(reason))
    }
  }

  Ink.useInput((input, key) =>
    switch model.mode {
    | View =>
      if key.escape {
        onBack()
      } else if key.return {
        switch model.detail {
        | Some(d) => onBrowse(d.personalDb)
        | None => ()
        }
      } else if input === "t" {
        dispatch(SetMode(TierMode))
      } else if input === "e" {
        switch model.detail {
        | Some(d) => editRecord(d.record)
        | None => ()
        }
      } else if input === "s" {
        dispatch(SetMode(SeedTrips))
      } else if input === "r" {
        refresh()
      }
    | SeedExpenses(_) | SeedTrips | TierMode => ()
    }
  )

  switch (model.mode, model.detail) {
  | (TierMode, Some(d)) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text>
        {React.string("Set tier for ")}
        <Ink.Text color="cyan"> {React.string(d.email)} </Ink.Text>
      </Ink.Text>
      <TierSelect current={TierSelect.parse(d.tier)} onSelect={tier => setTier(tier)} />
    </Ink.Box>
  | (SeedTrips, _) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text> {React.string("How many trips? (1-10)")} </Ink.Text>
      <Ink.TextInput
        value={model.tripsStr}
        onChange={v => dispatch(SetTripsStr(v))}
        onSubmit={v => {
          let n = clampInt(v, 1, 10)
          dispatch(SetTripsStr(Int.toString(n)))
          dispatch(SetMode(SeedExpenses(n)))
        }}
      />
    </Ink.Box>
  | (SeedExpenses(tripCount), _) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text> {React.string("How many expenses per trip? (1-200)")} </Ink.Text>
      <Ink.TextInput
        value={model.exStr}
        onChange={v => dispatch(SetExStr(v))}
        onSubmit={v => seedExpenses(tripCount, v)}
      />
    </Ink.Box>
  | (View, None) | (TierMode, None) =>
    <Ink.Text>
      <Ink.Spinner />
      {React.string(" loading")}
    </Ink.Text>
  | (View, Some(d)) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text>
        <Ink.Text bold=true> {React.string(d.email)} </Ink.Text>
        {React.string(" ")}
        {React.string(Format.tierBadge(d.tier))}
      </Ink.Text>
      <Ink.Text color="gray">
        {React.string("personalDb: ")}
        <Ink.Text color="white"> {React.string(d.personalDb)} </Ink.Text>
      </Ink.Text>
      <Ink.Text color="gray">
        {React.string("docs: ")}
        <Ink.Text color="white">
          {React.string(d.docCount->Option.mapOr("—", n => Int.toString(n)))}
        </Ink.Text>
        {React.string("   size: ")}
        <Ink.Text color="white"> {React.string(Format.formatBytes(d.sizeBytes))} </Ink.Text>
      </Ink.Text>
      <Ink.Text color="gray">
        {React.string("ownedSharedTrips: ")}
        <Ink.Text color="white"> {React.string(Int.toString(Array.length(d.sharedTrips)))} </Ink.Text>
      </Ink.Text>
      {d.sharedTrips
      ->Array.map(st =>
        <Ink.Text key={st.id} color="gray">
          {React.string(`   - ${st.name} (${st.id})`)}
        </Ink.Text>
      )
      ->React.array}
      <Ink.Box marginTop=1 flexDirection=#column>
        <Ink.Text color="gray"> {React.string("record:")} </Ink.Text>
        {switch recordRows(d.record) {
        | [] => <Ink.Text color="gray"> {React.string("   (no record — legacy user)")} </Ink.Text>
        | rows =>
          rows
          ->Array.map(((k, v)) =>
            <Ink.Text key={k} color="gray">
              {React.string(`   ${k}: `)}
              <Ink.Text color="white"> {React.string(v)} </Ink.Text>
            </Ink.Text>
          )
          ->React.array
        }}
      </Ink.Box>
      <Ink.Box marginTop=1>
        <Ink.Text color="gray">
          {React.string(
            "[ Enter ] browse docs · [ t ] tier · [ e ] edit record · [ s ] seed sample data · [ Esc ] back",
          )}
        </Ink.Text>
      </Ink.Box>
    </Ink.Box>
  }
}
