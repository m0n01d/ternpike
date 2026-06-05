/***
Seed screen — port of SeedScreen.tsx. Quick-seeds users (menu of test emails +
custom email→tier via POST /admin/users) and "Seed dev-tier accounts" (runs
SeedDevTiers.seedDevTiers with a configurable base email).
*/

let quickUsers = [
  "alice@test.ternpike.com",
  "bob@test.ternpike.com",
  "carol@test.ternpike.com",
  "eve@test.ternpike.com",
]

// Menu items = quick users + "Custom…" + "Seed dev-tier accounts"
let menuLen = Array.length(quickUsers) + 2
let customIdx = Array.length(quickUsers)
let devSeedIdx = Array.length(quickUsers) + 1

type msg =
  | CursorUp
  | CursorDown
  | MenuSelect
  | EmailChange(string)
  | EmailSubmit(string)
  | TierSelected(Tier.t)
  | CreateDone(string, Tier.t) // email, tier
  | CreateFailed(string) // error message
  | DevSeedBaseChange(string)
  | DevSeedSubmit(string)
  | DevSeedOutcome(SeedDevTiers.outcome)
  | DevSeedDone
  | BackToMenu

type mode =
  | Menu
  | QuickTier(string) // email chosen, picking tier
  | CustomEmail
  | CustomTier(string) // email entered, picking tier
  | DevSeedPrompt(string) // editing base email
  | DevSeedRunning(int) // outcomes received so far

type model = {
  cursor: int,
  email: string,
  mode: mode,
}

let init: model = {
  cursor: 0,
  email: "",
  mode: Menu,
}

let update = (model: model, msg: msg): model =>
  switch msg {
  | CursorUp => {...model, cursor: max(0, model.cursor - 1)}
  | CursorDown => {...model, cursor: min(menuLen - 1, model.cursor + 1)}
  | MenuSelect =>
    if model.cursor < customIdx {
      switch quickUsers->Array.get(model.cursor) {
      | Some(email) => {...model, mode: QuickTier(email)}
      | None => model
      }
    } else if model.cursor === customIdx {
      {...model, email: "", mode: CustomEmail}
    } else {
      // devSeedIdx
      let base = Config.get("DEV_SEED_BASE")->Option.getOr("")
      {...model, email: base, mode: DevSeedPrompt(base)}
    }
  | EmailChange(v) => {...model, email: v}
  | EmailSubmit(v) =>
    if String.includes(v, "@") {
      {...model, mode: CustomTier(v)}
    } else {
      {...model, mode: Menu}
    }
  | TierSelected(_) => model // effects dispatched from handler; model unchanged until Done/Failed
  | CreateDone(_, _) => {...model, mode: Menu}
  | CreateFailed(_) => {...model, mode: Menu}
  | DevSeedBaseChange(v) => {...model, email: v, mode: DevSeedPrompt(v)}
  | DevSeedSubmit(_) => {...model, mode: DevSeedRunning(0)}
  | DevSeedOutcome(_) =>
    switch model.mode {
    | DevSeedRunning(n) => {...model, mode: DevSeedRunning(n + 1)}
    | _ => model
    }
  | DevSeedDone => {...model, mode: Menu}
  | BackToMenu => {...model, mode: Menu}
  }

@react.component
let make = (~setStatus: string => unit, ~setError: option<string> => unit) => {
  let (model, dispatch) = React.useReducer(update, init)

  // Keyboard handler — active only in Menu mode
  Ink.useInput((_input, key) => {
    switch model.mode {
    | Menu =>
      if key.upArrow {
        dispatch(CursorUp)
      } else if key.downArrow {
        dispatch(CursorDown)
      } else if key.return {
        dispatch(MenuSelect)
      } else if key.escape {
        ()
      }
    | _ => ()
    }
  })

  // Effect: create a single user (for quick-tier and custom-tier flows)
  let create = (email: string, tier: Tier.t) => {
    setStatus(`creating ${email}…`)
    let _ = async () => {
      let result = await AdminApi.createUser(email, tier)
      switch result {
      | AdminApi.Created =>
        setStatus(`created ${email} (${Tier.label(tier)})`)
        dispatch(CreateDone(email, tier))
      | AdminApi.TrailblazerSkip =>
        setStatus(`${email} is already a Trailblazer — skipped`)
        dispatch(CreateDone(email, tier))
      | AdminApi.Failed(msg) =>
        setError(Some(msg))
        dispatch(CreateFailed(msg))
      }
    }
  }

  // Effect: run the dev-tier seeder
  let runDevSeed = (base: string) => {
    dispatch(DevSeedSubmit(base))
    setStatus(`seeding dev tiers for ${base}…`)
    let _ = async () => {
      let outcomes = await SeedDevTiers.seedDevTiers(base)
      outcomes->Array.forEach(o => {
        let resultLabel = switch o.result {
        | AdminApi.Created => "created"
        | AdminApi.TrailblazerSkip => "trailblazer (skipped)"
        | AdminApi.Failed(e) => `failed: ${e}`
        }
        setStatus(`${o.email} (${Tier.label(o.tier)}): ${resultLabel}`)
        dispatch(DevSeedOutcome(o))
      })
      setStatus(`dev-tier seed complete for ${base}`)
      dispatch(DevSeedDone)
    }
  }

  switch model.mode {
  | QuickTier(email) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text>
        {React.string("Create ")}
        <Ink.Text color="cyan"> {React.string(email)} </Ink.Text>
        {React.string(" at tier:")}
      </Ink.Text>
      <TierSelect onSelect={tier => create(email, tier)} />
    </Ink.Box>

  | CustomEmail =>
    <Ink.Box flexDirection=#column>
      <Ink.Text> {React.string("Email:")} </Ink.Text>
      <Ink.TextInput
        value={model.email}
        onChange={v => dispatch(EmailChange(v))}
        onSubmit={v => dispatch(EmailSubmit(v))}
      />
    </Ink.Box>

  | CustomTier(email) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text>
        {React.string("Tier for ")}
        <Ink.Text color="cyan"> {React.string(email)} </Ink.Text>
        {React.string(":")}
      </Ink.Text>
      <TierSelect onSelect={tier => create(email, tier)} />
    </Ink.Box>

  | DevSeedPrompt(_) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text> {React.string("Base email (e.g. you@gmail.com):")} </Ink.Text>
      <Ink.TextInput
        value={model.email}
        onChange={v => dispatch(DevSeedBaseChange(v))}
        onSubmit={v =>
          if String.includes(v, "@") {
            runDevSeed(v)
          } else {
            dispatch(BackToMenu)
          }}
      />
    </Ink.Box>

  | DevSeedRunning(n) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text color="cyan"> {React.string(`Seeding dev tiers… (${Int.toString(n)} done)`)} </Ink.Text>
    </Ink.Box>

  | Menu =>
    <Ink.Box flexDirection=#column>
      <Ink.Text color="gray"> {React.string("Quick-seed a user. Pick one or \"Custom…\".")} </Ink.Text>
      <Ink.Box marginTop=1 flexDirection=#column>
        {quickUsers
        ->Array.mapWithIndex((email, i) =>
          <Ink.Text key={email}>
            {React.string(model.cursor === i ? "› " : "  ")}
            {React.string(email)}
          </Ink.Text>
        )
        ->React.array}
        <Ink.Text>
          {React.string(model.cursor === customIdx ? "› " : "  ")}
          <Ink.Text color="cyan"> {React.string("Custom…")} </Ink.Text>
        </Ink.Text>
        <Ink.Text>
          {React.string(model.cursor === devSeedIdx ? "› " : "  ")}
          <Ink.Text color="yellow"> {React.string("Seed dev-tier accounts")} </Ink.Text>
        </Ink.Text>
      </Ink.Box>
    </Ink.Box>
  }
}
