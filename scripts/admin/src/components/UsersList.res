/***
Users screen — ported from UsersList.tsx, shaped as TEA.

  model  = { cursor, filter, mode, newEmail, users }
  msg    = Loaded | LoadFailed | SetFilter | … (pure transitions)
  update = pure

API calls (refresh / setTier / createUser / deleteUser) run in event handlers
and dispatch a *result* msg back, Elm Cmd→Msg style. List rows now carry
`subscriptionStatus` + `trailblazerNumber` (server `GET /admin/users`), surfaced
inline after the tier.

  [ ↑↓ ] move · [ Enter ] open · [ / ] filter · [ t ] tier
  [ n ] new · [ d ] delete · [ r ] refresh
*/

type user = {
  email: string,
  subscriptionStatus: option<string>,
  tier: string,
  trailblazerNumber: option<int>,
}

type mode =
  | DeleteMode(user)
  | Filter
  | List
  | NewEmail
  | NewTier(string)
  | TierMode(user)

type model = {
  cursor: int,
  filter: string,
  mode: mode,
  newEmail: string,
  users: option<array<user>>,
}

type msg =
  | CursorDown(int) // arg is the max selectable index (filtered length - 1)
  | CursorUp
  | Loaded(array<user>)
  | LoadFailed
  | SetFilter(string)
  | SetMode(mode)
  | SetNewEmail(string)

let decodeUser = (json: JSON.t): user => {
  email: Decode.stringField(json, "email")->Option.getOr(""),
  subscriptionStatus: Decode.stringField(json, "subscriptionStatus"),
  tier: Decode.stringField(json, "tier")->Option.getOr("tern"),
  trailblazerNumber: Decode.intField(json, "trailblazerNumber"),
}

let decodeUsers = (json: JSON.t): array<user> =>
  Decode.arrayField(json, "users")->Option.getOr([])->Array.map(decodeUser)

let update = (model: model, msg: msg): model =>
  switch msg {
  | CursorDown(max) => {...model, cursor: model.cursor + 1 > max ? max : model.cursor + 1}
  | CursorUp => {...model, cursor: model.cursor - 1 < 0 ? 0 : model.cursor - 1}
  | Loaded(users) => {...model, cursor: 0, users: Some(users)}
  | LoadFailed => {...model, users: Some([])}
  | SetFilter(filter) => {...model, filter}
  | SetMode(mode) => {...model, mode}
  | SetNewEmail(newEmail) => {...model, newEmail}
  }

/** Trailing label for a row's Trailblazer number + subscription status. */
let rowSuffix = (u: user): string => {
  let trail = switch u.trailblazerNumber {
  | Some(n) => ` #${Int.toString(n)}`
  | None => ""
  }
  let sub = switch u.subscriptionStatus {
  | Some(s) if s !== "" => ` (${s})`
  | _ => ""
  }
  trail ++ sub
}

@react.component
let make = (
  ~onPick: string => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let (model, dispatch) = React.useReducer(update, {
    cursor: 0,
    filter: "",
    mode: List,
    newEmail: "",
    users: None,
  })

  let refresh = () => {
    setStatus("loading users…")
    Req.get("/admin/users")
    ->Promise.thenResolve(result =>
      switch result {
      | Ok(json) =>
        let users = decodeUsers(json)
        dispatch(Loaded(users))
        setError(None)
        setStatus(`${Int.toString(Array.length(users))} users`)
      | Error(e) =>
        dispatch(LoadFailed)
        setError(Some(e.message))
      }
    )
    ->Promise.ignore
  }

  React.useEffect0(() => {
    refresh()
    None
  })

  let users = model.users->Option.getOr([])
  let needle = String.toLowerCase(model.filter)
  let filtered = users->Array.filter(u => String.includes(String.toLowerCase(u.email), needle))
  let selected = filtered->Array.get(model.cursor)

  let setTier = (u: user, tier: Tier.t) => {
    let label = Tier.label(tier)
    setStatus(`setting tier ${label}…`)
    Req.put(
      "/admin/users/" ++ u.email ++ "/tier",
      JSON.Object(Dict.fromArray([("tier", JSON.String(label))])),
    )
    ->Promise.thenResolve(result => {
      switch result {
      | Ok(_) => setStatus(`${u.email} → ${label}`)
      | Error(e) if e.status === 409 =>
        setError(Some("Trailblazer is permanent — cannot change tier"))
      | Error(e) => setError(Some(e.message))
      }
      dispatch(SetMode(List))
      refresh()
    })
    ->Promise.ignore
  }

  let createUser = (email: string, tier: Tier.t) => {
    let label = Tier.label(tier)
    setStatus(`creating ${email}…`)
    Req.post(
      "/admin/users",
      JSON.Object(Dict.fromArray([("email", JSON.String(email)), ("tier", JSON.String(label))])),
    )
    ->Promise.thenResolve(result => {
      switch result {
      | Ok(_) => setStatus(`created ${email} (${label})`)
      | Error(e) if e.status === 409 => setError(Some("Trailblazer is permanent"))
      | Error(e) => setError(Some(e.message))
      }
      dispatch(SetMode(List))
      refresh()
    })
    ->Promise.ignore
  }

  let deleteUser = (u: user) => {
    setStatus(`deleting ${u.email}…`)
    Req.delete("/admin/users/" ++ u.email)
    ->Promise.thenResolve(result => {
      switch result {
      | Ok(_) => setStatus(`deleted ${u.email}`)
      | Error(e) => setError(Some(e.message))
      }
      dispatch(SetMode(List))
      refresh()
    })
    ->Promise.ignore
  }

  Ink.useInput((input, key) =>
    switch model.mode {
    | List =>
      if key.upArrow {
        dispatch(CursorUp)
      } else if key.downArrow {
        dispatch(CursorDown(Array.length(filtered) - 1))
      } else if key.return {
        switch selected {
        | Some(u) => onPick(u.email)
        | None => ()
        }
      } else if input === "/" {
        dispatch(SetMode(Filter))
      } else if input === "t" {
        switch selected {
        | Some(u) => dispatch(SetMode(TierMode(u)))
        | None => ()
        }
      } else if input === "d" {
        switch selected {
        | Some(u) => dispatch(SetMode(DeleteMode(u)))
        | None => ()
        }
      } else if input === "n" {
        dispatch(SetNewEmail(""))
        dispatch(SetMode(NewEmail))
      } else if input === "r" {
        refresh()
      }
    | DeleteMode(_) | Filter | NewEmail | NewTier(_) | TierMode(_) => ()
    }
  )

  switch model.mode {
  | Filter =>
    <Ink.Box>
      <Ink.Text> {React.string("filter: ")} </Ink.Text>
      <Ink.TextInput
        value={model.filter}
        onChange={v => dispatch(SetFilter(v))}
        onSubmit={_ => dispatch(SetMode(List))}
      />
    </Ink.Box>
  | TierMode(u) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text>
        {React.string("Set tier for ")}
        <Ink.Text color="cyan"> {React.string(u.email)} </Ink.Text>
      </Ink.Text>
      <TierSelect current={TierSelect.parse(u.tier)} onSelect={tier => setTier(u, tier)} />
    </Ink.Box>
  | NewEmail =>
    <Ink.Box flexDirection=#column>
      <Ink.Text> {React.string("New user email:")} </Ink.Text>
      <Ink.TextInput
        value={model.newEmail}
        onChange={v => dispatch(SetNewEmail(v))}
        onSubmit={v =>
          if String.includes(v, "@") {
            dispatch(SetMode(NewTier(v)))
          } else {
            dispatch(SetMode(List))
          }}
      />
    </Ink.Box>
  | NewTier(email) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text>
        {React.string("Initial tier for ")}
        <Ink.Text color="cyan"> {React.string(email)} </Ink.Text>
        {React.string(":")}
      </Ink.Text>
      <TierSelect onSelect={tier => createUser(email, tier)} />
    </Ink.Box>
  | DeleteMode(u) =>
    <Confirm
      prompt={`Delete ${u.email}? This drops their CouchDB user, personal DB, and tier key.`}
      expectedAnswer={u.email}
      onCancel={() => dispatch(SetMode(List))}
      onConfirm={() => deleteUser(u)}
    />
  | List =>
    switch model.users {
    | None =>
      <Ink.Text>
        <Ink.Spinner />
        {React.string(" loading")}
      </Ink.Text>
    | Some(_) =>
      if Array.length(filtered) === 0 {
        <Ink.Text color="gray"> {React.string("no users")} </Ink.Text>
      } else {
        <Ink.Box flexDirection=#column>
          {model.filter === ""
            ? React.null
            : <Ink.Text color="gray">
                {React.string("filter: ")}
                <Ink.Text color="white"> {React.string(model.filter)} </Ink.Text>
                {React.string("  (press / to edit)")}
              </Ink.Text>}
          {filtered
          ->Array.slice(~start=0, ~end=30)
          ->Array.mapWithIndex((u, i) =>
            <Ink.Text key={u.email}>
              {React.string(i === model.cursor ? "› " : "  ")}
              {React.string(Format.truncate(u.email, 48))}
              {React.string("  ")}
              {React.string(Format.tierColor(u.tier))}
              <Ink.Text color="gray"> {React.string(rowSuffix(u))} </Ink.Text>
            </Ink.Text>
          )
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
