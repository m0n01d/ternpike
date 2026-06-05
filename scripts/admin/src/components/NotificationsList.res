/***
Notifications screen — ported from NotificationsList.tsx (Phase B).

Push subscribers grouped by email, drill into per-device prefs, and a
test-push action. Shaped as TEA:

  model  = { email, menuCursor, mode }
  msg    = navigation + async-result messages
  update = pure (model, msg) => model

The list-fetch and the test-push call are effects: each is fired from a
`useEffect` keyed on the mode it belongs to, dispatching a result `msg` back
into the reducer. The scrollable subscriber list is a self-contained
sub-component (`UserList`) with its own sub-TEA, mirroring the original.
*/

// ----- data model (mirrors api.ts NotificationDevice / NotificationUser) -----

type prefs = {weeklyScanReminder: bool}

type device = {
  createdAt: string,
  endpoint: string,
  prefs: prefs,
}

type user = {
  devices: array<device>,
  email: string,
  tier: string,
}

let decodePrefs = (json: JSON.t): prefs => {
  weeklyScanReminder: Decode.boolField(json, "weeklyScanReminder")->Option.getOr(false),
}

let decodeDevice = (json: JSON.t): device => {
  createdAt: Decode.stringField(json, "createdAt")->Option.getOr(""),
  endpoint: Decode.stringField(json, "endpoint")->Option.getOr(""),
  prefs: Decode.field(json, "prefs")->Option.map(decodePrefs)->Option.getOr({
    weeklyScanReminder: false,
  }),
}

let decodeUser = (json: JSON.t): user => {
  devices: Decode.arrayField(json, "devices")
  ->Option.getOr([])
  ->Array.map(decodeDevice),
  email: Decode.stringField(json, "email")->Option.getOr(""),
  tier: Decode.stringField(json, "tier")->Option.getOr("tern"),
}

let decodeUsers = (json: JSON.t): array<user> =>
  Decode.arrayField(json, "users")->Option.getOr([])->Array.map(decodeUser)

// ----- shared colour helper (mirrors tierColor in the TSX) -----

let tierColor = (tier: string): string =>
  switch tier {
  | "osprey" => "green"
  | "trailblazer" => "yellow"
  | _ => "gray"
  }

// ----- top-level mode machine -----

type mode =
  | Menu
  | TestPushEmail
  | TestPushLoading(string) // email
  | TestPushResult({email: string, ok: bool, result: string})
  | ListLoading
  | List(array<user>)

let menuItems = [
  {Ink.SelectInput.label: "Test push (prompt for email)", value: "test-push"},
  {Ink.SelectInput.label: "List subscribers", value: "list"},
]

type model = {
  email: string,
  menuCursor: int,
  mode: mode,
}

type msg =
  | MenuUp
  | MenuDown
  | MenuSelect
  | SetEmail(string)
  | SubmitEmail(string)
  | TestPushDone({email: string, ok: bool, result: string})
  | ListLoaded(array<user>)
  | ListFailed
  | BackToMenu

let update = (model: model, msg: msg): model =>
  switch msg {
  | MenuUp => {...model, menuCursor: Math.Int.max(0, model.menuCursor - 1)}
  | MenuDown => {
      ...model,
      menuCursor: Math.Int.min(Array.length(menuItems) - 1, model.menuCursor + 1),
    }
  | MenuSelect =>
    switch Array.get(menuItems, model.menuCursor) {
    | Some(item) if item.value === "test-push" => {...model, email: "", mode: TestPushEmail}
    | Some(_) => {...model, mode: ListLoading}
    | None => model
    }
  | SetEmail(email) => {...model, email}
  | SubmitEmail(v) =>
    if String.includes(v, "@") {
      {...model, mode: TestPushLoading(v)}
    } else {
      {...model, mode: Menu}
    }
  | TestPushDone({email, ok, result}) => {
      ...model,
      mode: TestPushResult({email, ok, result}),
    }
  | ListLoaded(users) => {...model, mode: List(users)}
  | ListFailed => {...model, mode: Menu}
  | BackToMenu => {...model, mode: Menu}
  }

// ----- internal sub-component: the scrollable subscriber list -----

module UserList = {
  type listMode =
    | Users
    | Devices
    | Detail

  type model = {
    cursor: int,
    deviceCursor: int,
    mode: listMode,
    selected: option<user>,
  }

  type msg =
    | Up
    | Down
    | Back
    | Enter

  @react.component
  let make = (~users: array<user>, ~onBack: unit => unit) => {
    let (state, dispatch) = React.useReducer((state: model, msg: msg): model => {
      switch (state.mode, msg) {
      | (Users, Up) => {...state, cursor: Math.Int.max(0, state.cursor - 1)}
      | (Users, Down) => {
          ...state,
          cursor: Math.Int.min(Array.length(users) - 1, state.cursor + 1),
        }
      | (Users, Enter) => {
          ...state,
          selected: Array.get(users, state.cursor),
          deviceCursor: 0,
          mode: Devices,
        }
      | (Users, Back) => state // handled as a side-effect below
      | (Devices, Up) => {...state, deviceCursor: Math.Int.max(0, state.deviceCursor - 1)}
      | (Devices, Down) =>
        switch state.selected {
        | Some(u) => {
            ...state,
            deviceCursor: Math.Int.min(Array.length(u.devices) - 1, state.deviceCursor + 1),
          }
        | None => state
        }
      | (Devices, Back) => {...state, mode: Users}
      | (Devices, Enter) => {...state, mode: Detail}
      | (Detail, Back) | (Detail, Enter) => {...state, mode: Devices}
      | (Detail, Up) | (Detail, Down) => state
      }
    }, {cursor: 0, deviceCursor: 0, mode: Users, selected: None})

    Ink.useInput((_input, key) => {
      switch state.mode {
      | Users =>
        if key.upArrow {
          dispatch(Up)
        } else if key.downArrow {
          dispatch(Down)
        } else if key.escape {
          onBack()
        } else if key.return {
          dispatch(Enter)
        }
      | Devices =>
        if key.upArrow {
          dispatch(Up)
        } else if key.downArrow {
          dispatch(Down)
        } else if key.escape {
          dispatch(Back)
        } else if key.return {
          dispatch(Enter)
        }
      | Detail =>
        if key.escape || key.return {
          dispatch(Back)
        }
      }
    })

    switch (state.mode, state.selected) {
    | (Users, _) =>
      let count = Array.length(users)
      let plural = count === 1 ? "" : "s"
      <Ink.Box flexDirection=#column>
        <Ink.Text color="gray">
          {React.string(
            `${Int.toString(count)} subscriber${plural}   [ enter ] select · [ esc ] back`,
          )}
        </Ink.Text>
        {users
        ->Array.slice(~start=0, ~end=30)
        ->Array.mapWithIndex((u, i) => {
          let marker = i === state.cursor ? "› " : "  "
          let dPlural = Array.length(u.devices) === 1 ? "" : "s"
          let emailCol = Format.truncate(u.email, 36)->String.padEnd(36, " ")
          <Ink.Text key={u.email}>
            {React.string(marker ++ emailCol ++ " ")}
            <Ink.Text color="gray">
              {React.string(`${Int.toString(Array.length(u.devices))} dev${dPlural}`)}
            </Ink.Text>
            {React.string(" ")}
            <Ink.Text color={tierColor(u.tier)}> {React.string(u.tier)} </Ink.Text>
          </Ink.Text>
        })
        ->React.array}
      </Ink.Box>
    | (Devices, Some(u)) =>
      let dPlural = Array.length(u.devices) === 1 ? "" : "s"
      <Ink.Box flexDirection=#column>
        <Ink.Text>
          <Ink.Text color="cyan"> {React.string(u.email)} </Ink.Text>
          {React.string(" ")}
          <Ink.Text color={tierColor(u.tier)}> {React.string(`(${u.tier})`)} </Ink.Text>
          {React.string(` — ${Int.toString(Array.length(u.devices))} device${dPlural}`)}
        </Ink.Text>
        <Ink.Box marginTop=1 flexDirection=#column>
          {u.devices
          ->Array.mapWithIndex((d, i) => {
            let marker = i === state.deviceCursor ? "› " : "  "
            let suffix = String.slice(
              d.endpoint,
              ~start=String.length(d.endpoint) - 20,
              ~end=String.length(d.endpoint),
            )
            let (reminderColor, reminderText) = d.prefs.weeklyScanReminder
              ? ("green", "reminder:on")
              : ("red", "reminder:off")
            <Ink.Text key={d.endpoint}>
              {React.string(marker)}
              <Ink.Text color="gray"> {React.string(`…${suffix}`)} </Ink.Text>
              {React.string(" ")}
              <Ink.Text color={reminderColor}> {React.string(reminderText)} </Ink.Text>
            </Ink.Text>
          })
          ->React.array}
        </Ink.Box>
        <Ink.Box marginTop=1>
          <Ink.Text color="gray"> {React.string("[ enter ] detail · [ esc ] back")} </Ink.Text>
        </Ink.Box>
      </Ink.Box>
    | (Detail, Some(u)) =>
      switch Array.get(u.devices, state.deviceCursor) {
      | None => React.null
      | Some(d) =>
        let suffix = String.slice(
          d.endpoint,
          ~start=String.length(d.endpoint) - 20,
          ~end=String.length(d.endpoint),
        )
        let (prefColor, prefText) = d.prefs.weeklyScanReminder ? ("green", "on") : ("red", "off")
        <Ink.Box flexDirection=#column>
          <Ink.Text>
            <Ink.Text color="cyan"> {React.string(u.email)} </Ink.Text>
            {React.string(" — device detail")}
          </Ink.Text>
          <Ink.Box marginTop=1 flexDirection=#column>
            <Ink.Text>
              {React.string("endpoint: ")}
              <Ink.Text color="gray"> {React.string(`…${suffix}`)} </Ink.Text>
            </Ink.Text>
            <Ink.Text>
              {React.string("createdAt: ")}
              <Ink.Text color="gray"> {React.string(d.createdAt)} </Ink.Text>
            </Ink.Text>
            <Ink.Text>
              {React.string("weeklyScanReminder: ")}
              <Ink.Text color={prefColor}> {React.string(prefText)} </Ink.Text>
            </Ink.Text>
          </Ink.Box>
          <Ink.Box marginTop=1>
            <Ink.Text color="gray"> {React.string("[ esc / enter ] back")} </Ink.Text>
          </Ink.Box>
        </Ink.Box>
      }
    | (Devices, None) | (Detail, None) => React.null
    }
  }
}

// ----- top-level component -----

@react.component
let make = (~setStatus: string => unit, ~setError: option<string> => unit) => {
  let (state, dispatch) = React.useReducer(update, {email: "", menuCursor: 0, mode: Menu})

  // Fetch the subscriber list when entering ListLoading mode.
  React.useEffect1(() => {
    switch state.mode {
    | ListLoading =>
      let cancelled = ref(false)
      Req.get("/admin/notifications/list")
      ->Promise.thenResolve(result =>
        if !cancelled.contents {
          switch result {
          | Ok(json) =>
            let users = decodeUsers(json)
            let count = Array.length(users)
            let plural = count === 1 ? "" : "s"
            setStatus(`${Int.toString(count)} subscriber${plural}`)
            setError(None)
            dispatch(ListLoaded(users))
          | Error(e) =>
            setError(Some(e.message))
            dispatch(ListFailed)
          }
        }
      )
      ->Promise.ignore
      Some(() => cancelled := true)
    | Menu | TestPushEmail | TestPushLoading(_) | TestPushResult(_) | List(_) => None
    }
  }, [state.mode])

  // Fire the test-push call when entering TestPushLoading mode.
  React.useEffect1(() => {
    switch state.mode {
    | TestPushLoading(target) =>
      let cancelled = ref(false)
      let body = JSON.Object(Dict.fromArray([("email", JSON.String(target))]))
      Req.post("/admin/test-push", body)
      ->Promise.thenResolve(result =>
        if !cancelled.contents {
          switch result {
          | Ok(json) =>
            let ok = Decode.boolField(json, "ok")->Option.getOr(false)
            let resultText = if ok {
              let sent = Decode.intField(json, "sent")->Option.getOr(0)
              let plural = sent === 1 ? "" : "s"
              `sent to ${Int.toString(sent)} device${plural}`
            } else {
              let reason = Decode.stringField(json, "reason")->Option.getOr("unknown")
              `failed: ${reason}`
            }
            setStatus(ok ? `test push sent — ${resultText}` : "test push failed")
            dispatch(TestPushDone({email: target, ok, result: resultText}))
          | Error(e) =>
            setError(Some(e.message))
            dispatch(TestPushDone({email: target, ok: false, result: e.message}))
          }
        }
      )
      ->Promise.ignore
      Some(() => cancelled := true)
    | Menu | TestPushEmail | ListLoading | TestPushResult(_) | List(_) => None
    }
  }, [state.mode])

  Ink.useInput((_input, key) => {
    switch state.mode {
    | Menu =>
      if key.upArrow {
        dispatch(MenuUp)
      } else if key.downArrow {
        dispatch(MenuDown)
      } else if key.return {
        dispatch(MenuSelect)
      }
    | TestPushResult(_) =>
      if key.escape || key.return {
        dispatch(BackToMenu)
        setError(None)
      }
    | List(_) =>
      if key.escape {
        dispatch(BackToMenu)
      }
    | TestPushEmail | TestPushLoading(_) | ListLoading => ()
    }
  })

  switch state.mode {
  | Menu =>
    <Ink.Box flexDirection=#column>
      <Ink.Text color="gray"> {React.string("Notifications — choose an action:")} </Ink.Text>
      <Ink.Box marginTop=1 flexDirection=#column>
        {menuItems
        ->Array.mapWithIndex((item, i) => {
          let marker = i === state.menuCursor ? "› " : "  "
          <Ink.Text key={item.value}> {React.string(marker ++ item.label)} </Ink.Text>
        })
        ->React.array}
      </Ink.Box>
    </Ink.Box>

  | TestPushEmail =>
    <Ink.Box flexDirection=#column>
      <Ink.Text> {React.string("Email to test push:")} </Ink.Text>
      <Ink.TextInput
        value={state.email}
        onChange={v => dispatch(SetEmail(v))}
        onSubmit={v => dispatch(SubmitEmail(v))}
      />
      <Ink.Text color="gray"> {React.string("[ esc ] cancel")} </Ink.Text>
    </Ink.Box>

  | TestPushLoading(email) =>
    <Ink.Text>
      <Ink.Spinner /> {React.string(` Sending test push to ${email}…`)}
    </Ink.Text>

  | TestPushResult({email, ok, result}) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text>
        {React.string("Test push to ")}
        <Ink.Text color="cyan"> {React.string(email)} </Ink.Text>
        {React.string(": ")}
        <Ink.Text color={ok ? "green" : "red"}> {React.string(result)} </Ink.Text>
      </Ink.Text>
      <Ink.Text color="gray"> {React.string("[ enter / esc ] back")} </Ink.Text>
    </Ink.Box>

  | ListLoading =>
    <Ink.Text>
      <Ink.Spinner /> {React.string(" loading subscribers…")}
    </Ink.Text>

  | List(users) =>
    if Array.length(users) === 0 {
      <Ink.Box flexDirection=#column>
        <Ink.Text color="gray"> {React.string("no push subscribers")} </Ink.Text>
        <Ink.Text color="gray"> {React.string("[ esc ] back")} </Ink.Text>
      </Ink.Box>
    } else {
      <UserList users onBack={() => dispatch(BackToMenu)} />
    }
  }
}
