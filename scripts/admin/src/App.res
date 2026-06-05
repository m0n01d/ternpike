/***
Root router for the admin TUI, ported from App.tsx and shaped as TEA:

  model  = { view, status, error }
  msg    = SetView | SetStatus | SetError
  update = pure (model, msg) => model

Children stay callback-driven (`setStatus`/`setError`/`onPick`/…) — App wires
those callbacks to `dispatch`, so each screen owns its own sub-TEA while the
router owns navigation + the shared status/error line.
*/

type section =
  | Users
  | Dbs
  | SharedTrips
  | Seed
  | Notifications
  | Qr

type view =
  | ViewUsers
  | ViewUserDetail(string)
  | ViewDbs
  | ViewDocBrowser(string, section) // db, origin section (for back nav)
  | ViewSharedTrips
  | ViewSeed
  | ViewNotifications
  | ViewQr

type model = {
  view: view,
  status: string,
  error: option<string>,
}

type msg =
  | SetView(view)
  | SetStatus(string)
  | SetError(option<string>)

let update = (model: model, msg: msg): model =>
  switch msg {
  | SetView(view) => {...model, view}
  | SetStatus(status) => {...model, status}
  | SetError(error) => {...model, error}
  }

let sectionOf = (view: view): section =>
  switch view {
  | ViewUsers | ViewUserDetail(_) => Users
  | ViewDbs => Dbs
  | ViewDocBrowser(_, from) => from
  | ViewSharedTrips => SharedTrips
  | ViewSeed => Seed
  | ViewNotifications => Notifications
  | ViewQr => Qr
  }

let sectionKey = (s: section): string =>
  switch s {
  | Users => "users"
  | Dbs => "dbs"
  | SharedTrips => "sharedtrips"
  | Seed => "seed"
  | Notifications => "notifications"
  | Qr => "qr"
  }

let viewForSection = (s: section): view =>
  switch s {
  | Users => ViewUsers
  | Dbs => ViewDbs
  | SharedTrips => ViewSharedTrips
  | Seed => ViewSeed
  | Notifications => ViewNotifications
  | Qr => ViewQr
  }

let baseHints = "↑↓ navigate · enter select · esc back · q quit"
let tabOrder = [Users, Dbs, SharedTrips, Seed, Notifications, Qr]

@react.component
let make = () => {
  let app = Ink.useApp()
  let (model, dispatch) = React.useReducer(update, {
    view: ViewUsers,
    status: "ready",
    error: None,
  })
  let setView = v => dispatch(SetView(v))
  let setStatus = s => dispatch(SetStatus(s))
  let setError = e => dispatch(SetError(e))

  Ink.useInput((input, key) =>
    if input === "q" || (key.ctrl && input === "c") {
      app.exit()
    } else if key.tab {
      let cur = sectionOf(model.view)
      let idx = tabOrder->Array.indexOf(cur)
      let next =
        tabOrder
        ->Array.get(mod(idx + 1, Array.length(tabOrder)))
        ->Option.getOr(Users)
      setView(viewForSection(next))
    }
  )

  let (content, hints) = switch model.view {
  | ViewUsers => (
      <UsersList onPick={email => setView(ViewUserDetail(email))} setStatus setError />,
      `${baseHints} · t tier · n new · d delete · / filter · r refresh · tab switch`,
    )
  | ViewUserDetail(email) => (
      <UserDetail
        email
        onBack={() => setView(ViewUsers)}
        onBrowse={db => setView(ViewDocBrowser(db, Users))}
        setStatus
        setError
      />,
      `${baseHints} · t tier · e edit record · s seed data`,
    )
  | ViewDbs => (
      <DbsList onPick={db => setView(ViewDocBrowser(db, Dbs))} setStatus setError />,
      `${baseHints} · / filter · r refresh · tab switch`,
    )
  | ViewDocBrowser(db, from) => (
      <DocBrowser
        db
        onBack={() =>
          setView(
            switch from {
            | Dbs => ViewDbs
            | SharedTrips => ViewSharedTrips
            | Users | Seed | Notifications | Qr => ViewUsers
            },
          )}
        setStatus
        setError
      />,
      `${baseHints} · e edit · v void · d hard-delete · / filter · r refresh`,
    )
  | ViewSharedTrips => (
      <SharedTripsList
        onPick={db => setView(ViewDocBrowser(db, SharedTrips))}
        setStatus
        setError
      />,
      `${baseHints} · r refresh · tab switch`,
    )
  | ViewSeed => (
      <SeedScreen setStatus setError />,
      `${baseHints} · enter create · tab switch`,
    )
  | ViewNotifications => (
      <NotificationsList setStatus setError />,
      `${baseHints} · tab switch`,
    )
  | ViewQr => (
      <QrList setStatus setError />,
      `${baseHints} · p print · shift-P print all · n new · t template · r refresh · tab switch`,
    )
  }

  <Layout section={sectionKey(sectionOf(model.view))} hints status={model.status} error={model.error}>
    content
  </Layout>
}
