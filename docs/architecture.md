# Ternpike — App Architecture

> Audience: Elm developer who is new to this codebase but not new to Elm.
> Focus: PouchDB wiring, data modeling with Dicts, and the full read/write lifecycle.

---

## Glossary

- **Expense** — a single saved expense document. Immutable after creation.
- **Amendment** — a partial edit. Carries only the fields that changed,
  plus a `targetId` pointing at the expense. Never overwrites the original.
- **Void** — a tombstone. Soft-deletes an expense (or trip) by ID. Sync-safe.
- **Effective entry** — what the UI actually shows: an expense with every
  amendment folded in, minus anything that's been voided. `EffectiveEntry`
  in `Data/Entry.elm` is the type; "effective" anywhere in this doc or in
  function names (`resolveForTrip`, `findEffective`) means "post-amendment,
  non-voided." This is event-sourcing-lite: raw expenses + amendments are
  the events, `EffectiveEntry` is the projection.

---

## Directory map

```
src/
├── Main.elm            # Port module — the app entry point, all update logic
├── Types.elm           # Model, AuthState, GuestState, Msg
├── Routing.elm         # URL ↔ Route parsing
├── Helpers.elm         # Utility functions
├── Data/
│   ├── Amendment.elm     # Amendment type, encoder, decoder
│   ├── Auth.elm          # Creds, AppConfig (session + runtime config)
│   ├── Category.elm      # 12 expense categories
│   ├── Entry.elm         # EffectiveEntry — expense after amendments applied
│   ├── Expense.elm       # Expense type, encoder, decoder
│   ├── ExpenseId.elm     # Newtype wrapper around String
│   ├── Guest.elm         # GuestReason, GuestSession (sign-in flow state)
│   ├── Ledger.elm        # LedgerMode (loading vs ready)
│   ├── Location.elm      # LocationSource, LocationState (geo/EXIF capture)
│   ├── Navigation.elm    # Route, Tab
│   ├── PaymentMethod.elm # Cash / Credit
│   ├── PendingEntry.elm  # In-progress Add-page form state
│   ├── Pouch.elm         # PouchOutbound / PouchInbound port protocol
│   ├── Scan.elm          # Receipt-scan queue items and OCR data
│   ├── Sync.elm          # SyncState (PouchDB sync health)
│   ├── Trip.elm          # Trip type, encoder, decoder
│   ├── TripId.elm        # Newtype wrapper around String
│   ├── Trips.elm         # Zipper-like collection + TripsState loading wrapper
│   └── Void.elm          # Soft-delete tombstone type
├── Pages/              # One file per page; only view + local Msg handlers
├── UI/                 # Dumb UI components (buttons, cards, layout)
└── Json/Decode/Pipeline.elm  # Decoder pipeline helpers
```

`Types.elm` is intentionally thin: it owns the top-level `Model`,
`AuthState`, `GuestState`, and the `Msg` union. Every cohesive group of
supporting types — navigation, location, scan queue, form state, auth
config, sync, guest flow, PouchDB port protocol — lives in its own
`Data/*` module so the type surface is searchable and each module can
carry its own doc comment explaining the design.

JavaScript lives alongside this:

```
src/
├── main.js    # Elm init, port handlers for storage and geolocation
└── pouch.js   # All PouchDB operations; subscribed to Elm ports
```

---

## Model split: GuestModel vs AuthModel

```elm
type Model
    = AuthModel AuthState
    | GuestModel GuestState
```

The Elm compiler enforces that auth-only pages cannot be reached while signed out.
A 401 from any HTTP call or CouchDB sync immediately transitions to `GuestModel`.

`AuthState` (in `Types.elm`) is where all the interesting data lives:

```elm
type alias AuthState =
    { amendments    : Dict String Amendment
    , creds         : Creds
    , expenses      : Dict String Expense
    , loadingExpenses : Set String
    , loadingTrips  : Set String
    , networkOffline : Bool
    , page          : Page
    , route         : Route
    , syncState     : SyncState
    , tripLoaded    : Set String
    , trips         : TripsState
    , voids         : Dict String Void
    -- ... form fields, UI state, etc.
    }
```

`networkOffline` is also tracked on `GuestState` so the disconnected-banner
UI works before sign-in. Both fields are kept in sync via the `networkStatus`
port (see below) which forwards `navigator.onLine` plus `online`/`offline`
window events. The value is inverted so the field reads naturally
(`if as_.networkOffline then ...`).

Transient view state (`statsHover : Data.StatsHover.Hover`,
`statsGranularity : Maybe Data.StatsGranularity.Granularity`,
`showDayIntensity : Bool`, `showInstallPrompt : Bool`, `scanQueue`,
`confirmDeleteTrip`, etc.) also lives on `AuthState`, but it never
persists — these fields are reset on the relevant pointer-leave /
submit / sign-out event. `showInstallPrompt` is driven by the
`canInstall` port: `True` once the browser fires
`beforeinstallprompt` (stashed JS-side), back to `False` after the
user accepts/dismisses the prompt or after `appinstalled`. The
Settings tab renders an "Install app" button only when it's `True`.
`showDayIntensity` defaults to `True` and toggles the Ledger's
band-tinted day rail; it's an in-memory UI pref until the
`user:profile` PouchDB doc lands and absorbs it. The hover state for the
Stats charts records the elm-charts `CI.One` handle(s) the user is
currently touching so the page can render anchored `C.tooltip`
overlays; pointer leave clears them back to `StatsHover.empty`.
`statsGranularity` is `Nothing` on initial load — the chart picks
a default per trip via `StatsGranularity.fromSpan` — and becomes
`Just g` after the user touches the chip selector (Daily / Weekly /
Monthly). In-memory only; never syncs to PouchDB.

`openLedgerMenu : Maybe ExpenseId` tracks which ledger row currently has its
kebab popover open. The popover holds secondary row actions (Duplicate,
Move to trip…, Delete); a full-screen transparent
`<button aria-label="Close menu">` backdrop closes it. In-memory only;
reset by `OpenLedgerMenu` / `CloseLedgerMenu` and cleared whenever a row
action fires.

`movePicker : Maybe Expense` is `Just` while the move-to-trip modal is open;
the `Expense` payload is the source row's effective snapshot, used by
`UI.TripPicker.viewMove` to render the picker header and by `MoveEntry`
when the user picks a destination. In-memory only.

---

## Data modeling with Dicts

Core document types are cached in `AuthState` as Dicts:

| Field | Type | Key |
|---|---|---|
| `expenses` | `Dict String (Dict String Expense)` | outer: `TripId.toString`, inner: `ExpenseId.toString` |
| `amendments` | `Dict String Amendment` | amendment's own string `id` |
| `voids` | `Dict String Void` | void's own string `id` |

`expenses` is nested by trip so a single-trip lookup is one `Dict.get` on the outer
dict. Amendments and voids are flat — they carry a `targetId` field pointing at the
expense, and `Entry.resolve` builds its own per-call indexes.

To render a trip, callers scope expenses to that trip via `Dict.get tripId as_.expenses`
and pass the result with all amendments and voids to `Entry.resolve`. Inside `resolve`
(`src/Data/Entry.elm`), the lookups are efficient:

- **Amendments** are re-indexed into a `Dict String (List Amendment)` keyed by
  expense ID, then `Dict.get` is used — O(log n) per expense.
- **Voids** are collected into a `Set String` of voided IDs, then `Set.member`
  is used — O(log n) per expense.
- **Expenses** are already scoped to one trip by the caller — no linear scan needed.

### Document ID conventions

The `_id` field is how PouchDB identifies and orders documents. This app uses
structured string IDs to enable efficient range queries:

```
expense::2024-05-21T14:30:45Z::a1b2c3d4
amend::expense::2024-05-21T14:30:45Z::a1b2c3d4::t5s6f7g8
void::expense::2024-05-21T14:30:45Z::a1b2c3d4::del
trip::2024-05-21T14:30:45Z::a1b2c3d4
```

The `amend::` prefix plus the target expense ID lets `pouch.js` fetch all
amendments for one expense with a single PouchDB `allDocs` range query:

```js
db.allDocs({
    startkey: `amend::${expenseId}::`,
    endkey:   `amend::${expenseId}::￿`,
    include_docs: true,
})
```

`￿` is the highest Unicode character, so the range matches everything that
starts with `amend::<expenseId>::`.

---

## Storage tiers: PouchDB vs IndexedDB vs Server

Not everything goes in PouchDB. The app spreads persistent state across three
deliberately separate places:

| Tier | Examples | Why this tier |
|---|---|---|
| **Server** (Worker KV) | Subscription tier, `stripeCustomerId`, identity | Source of truth. Re-checked on every gated request — never trusted from the client. |
| **IndexedDB** (outside PouchDB) | JWT (`auth_creds`), BYO API keys (`ai_config`) | Device-local. Must not sync — keys would land on CouchDB. |
| **PouchDB** | Expenses, trips, amendments, voids, `user:profile` | Things that should sync across the user's devices, that aren't secret and aren't server-authoritative. |

The trap to avoid: don't put `tier` or `stripeCustomerId` in PouchDB even as a
cache. If a user upgrades on Device A, PouchDB sync won't propagate that until
the next push — and the source of truth is Stripe → Worker KV anyway. The
client refresh path is the `/me` endpoint, called on startup and after
returning from Stripe Checkout.

### The user profile doc

There's exactly one profile doc per user (per-user remote DB scopes it, so no
namespace is needed in the `_id`):

```json
{
  "_id": "user:profile",
  "_rev": "...",
  "createdAt": "2026-05-21T...",
  "defaultCurrency": "USD",
  "favoriteCategories": ["fuel", "lodging"],
  "preferredScanSource": "hosted",
  "type": "userProfile",
  "ui": {
    "denseTables": false,
    "theme": "system"
  },
  "updatedAt": "2026-05-21T..."
}
```

- Fixed `_id = "user:profile"` (not a ULID) — there's only ever one, and a
  known ID makes startup fetch trivial: `db.get("user:profile")`. On 404,
  create with defaults.
- `type: "userProfile"` follows the same convention other docs use for view
  filters.
- `preferredScanSource` is a *preference*, not a *capability*. Capability
  (is the user actually Paid?) comes from the server. Free users may still
  have `"hosted"` saved — it just won't render the hosted option until they
  upgrade.

### What does NOT go in `user:profile`

- `tier`, `subscriptionStatus`, `stripeCustomerId` — server-authoritative
  (see above).
- API keys — IndexedDB only, never PouchDB.
- `email`, `googleSub` — already in `AuthState` from the auth flow, no need
  to duplicate.

---

## PouchDB: what it is and how it plugs in

PouchDB is a client-side database that stores documents in IndexedDB (the
browser's built-in key-value store). It has a built-in sync protocol compatible
with CouchDB. The app keeps a local PouchDB instance (`'ternpike'`) that syncs
bidirectionally with `https://couch.ternpike.com/<dbName>`.

Because PouchDB is JavaScript-only, Elm talks to it through **ports**.

### Port overview

```elm
-- Elm → JS
port pouchOut             : Json.Encode.Value -> Cmd msg   -- send a command to PouchDB
port startSync            : Json.Encode.Value -> Cmd msg   -- start live CouchDB sync
port stopSync             : () -> Cmd msg
port triggerInstallPrompt : () -> Cmd msg                  -- replay stashed beforeinstallprompt

-- JS → Elm
port pouchIn       : (Json.Decode.Value -> msg) -> Sub msg  -- receive a result
port networkStatus : (Bool -> msg) -> Sub msg               -- True = online, False = offline
port canInstall    : (Bool -> msg) -> Sub msg               -- True = home-screen install available
```

`networkStatus` is wired in `src/main.js`: it sends `navigator.onLine` once
immediately after Elm init (so the model has the truth from frame zero) and
then forwards `online`/`offline` window events. The `NetworkStatusChanged`
message updates `networkOffline` on whichever model branch is active.

`canInstall` / `triggerInstallPrompt` wire up the PWA home-screen install
flow. JS listens for `beforeinstallprompt`, calls `preventDefault`, stashes
the deferred event, and sends `canInstall True`. When the user taps the
"Install app" button in Settings, Elm calls `triggerInstallPrompt`, JS
replays the stashed event, awaits `userChoice`, and sends `canInstall
False`. Same on `appinstalled`. Browsers that never fire
`beforeinstallprompt` (e.g. Safari) leave `showInstallPrompt` at `False`,
so users there see no button — matching the address-bar install icon's
behaviour.

All PouchDB commands go through one `pouchOut` port. The payload is a JSON
object with a `tag` field that `pouch.js` switches on. All PouchDB responses
come back through one `pouchIn` port, also tagged.

---

## The message protocol (pouchOut / pouchIn)

### Commands Elm sends (pouchOut)

| Tag | Payload | What it does |
|---|---|---|
| `GetAllTrips` | — | Fetches all `type: "trip"` docs |
| `GetTripExpenses` | `{ tripId }` | Fetches all expenses, amendments, voids for a trip |
| `GetExpense` | `{ id }` | Fetches one expense + its amendments + its void |
| `SaveTrip` | trip JSON | Upsert trip doc |
| `SaveExpense` | expense JSON | Upsert expense doc |
| `SaveAmend` | amendment JSON | Upsert amendment doc |
| `SaveVoid` | void JSON | Upsert void doc (soft delete) |

Example:
```json
{ "tag": "GetTripExpenses", "tripId": "trip::2024-05-21T14:30:45Z::a1b2c3d4" }
```

### Responses JS sends back (pouchIn)

| Tag | Payload |
|---|---|
| `TripsFetched` | `{ trips: Dict<id, tripDoc> }` |
| `TripExpensesLoaded` | `{ tripId, expenses: Dict, amendments: Dict, voids: Dict }` |
| `ExpenseFetched` | `{ expense, amendments: Dict, void: Maybe voidDoc }` |
| `DbChange` | a single changed document |
| `DbDeleted` | `{ id }` of deleted doc |
| `SyncStateMsg` | `"syncing" \| "synced" \| "error" \| "auth_error"` |

---

## Startup sequence

```
Browser loads
  └─ main.js reads IndexedDB
       ├─ auth_creds  (email, password, dbName)
       └─ anthropic_key
  └─ Elm.Main.init receives flags
       ├─ If no creds → GuestModel FreshGuest
       └─ If creds found → AuthModel (initial AuthState, no data fetched yet)
            └─ startSync port called immediately
                 └─ pouch.js begins db.sync(remote, { live, retry })
                      └─ On first "synced" event → Elm receives SyncStateMsg Synced
                           └─ update sends GetAllTrips via pouchOut
                                └─ pouch.js queries allDocs for type:"trip"
                                     └─ pouchIn receives TripsFetched
                                          └─ update populates as_.trips
```

Data is **not** fetched on login — it waits for the first sync to settle.
This prevents a race where Elm reads stale local data before the sync pulls
down remote changes.

---

## Route-driven lazy loading

Expense data is fetched per-trip, on demand, when the user navigates there.

In `Main.elm`, `fetchesForRoute` checks whether a trip's data is already in
memory before issuing a fetch:

```elm
fetchesForRoute : AuthState -> Route -> List (Cmd Msg)
fetchesForRoute as_ route =
    case route of
        LedgerRoute tripId ->
            if Set.member (TripId.toString tripId) as_.tripLoaded then
                []
            else
                [ pouchOut (encodePouchCmd (GetTripExpenses tripId)) ]
        ...
```

`tripLoaded` is a `Set String` of trip IDs whose data is already in cache.
`loadingTrips` and `loadingExpenses` are `Set String` tracking in-flight
requests, preventing duplicate fetches during navigation.

---

## Live changes feed

`pouch.js` subscribes to the local database with:

```js
db.changes({ since: 'now', live: true, include_docs: true })
  .on('change', change => {
      app.ports.pouchIn.send({ tag: 'DbChange', doc: change.doc })
  })
```

Any write — local or synced from CouchDB — fires `DbChange` through `pouchIn`.
The `update` function in `Main.elm` routes incoming docs by their `type` field:

```elm
"expense" -> ExpenseChanged (Expense.decoder value)
"amend"   -> AmendChanged   (Amendment.decoder value)
"trip"    -> TripChanged     (Trip.decoder value)
"void"    -> VoidChanged     (Void.decoder value)
```

Each branch inserts or replaces the doc in the appropriate Dict:

```elm
ExpenseChanged (Ok expense) ->
    ( AuthModel { as_ | expenses = Dict.insert (ExpenseId.toString expense.id) expense as_.expenses }
    , Cmd.none
    )
```

This is how synced remote changes appear in the UI without a page reload.

---

## Saving a new expense

1. User submits form on the Add page.
2. `update` generates a timestamp and random nonce → assembles `ExpenseId`.
3. `Expense.encode expense` produces the JSON document with `_id` set.
4. `pouchOut (SaveExpense encodedExpense)` is sent.
5. `pouch.js` calls `db.put(doc)` (upsert — checks for `_rev` on existing docs).
6. The live changes feed fires, `pouchIn` receives `DbChange`, and the expense
   lands in `as_.expenses` via the normal `ExpenseChanged` branch.

No separate "confirm success" message is needed — the live feed is the confirmation.

### Duplicating an expense

Duplicate is the simplest possible "save a new expense" path: the kebab menu on
a ledger row dispatches `DuplicateEntry expense` carrying the row's effective
snapshot (`Helpers.effectiveEntryToExpense`). `update` performs
`Task.perform Time.now`, and `GotDuplicateTime` calls
`Expense.snapshotWith { id, createdAt, tripId }` to mint a new expense doc that
copies every user-visible field (date, amount, category, merchant, note,
longNote, paymentMethod, lat, lon) onto a fresh `ExpenseId` and `createdAt`,
with the *same* `tripId`. The duplicate is then sent through `SaveExpense` and
optimistically inserted into the destination trip's inner dict — the same path
as a brand-new expense.

A duplicate is **not** an amendment: it's an independent document with its own
identity and its own amendment chain going forward.

---

## Editing an expense: the amendment pattern

Expenses are never mutated. Instead, an **amendment** document is created:

```elm
type alias Amendment =
    { amount    : Maybe Float      -- only the fields the user changed
    , category  : Maybe Category
    , date      : Maybe String
    , id        : String           -- "amend::<expenseId>::<ts>"
    , longNote  : Maybe String
    , merchant  : Maybe String
    , note      : Maybe String
    , targetId  : ExpenseId        -- points at the original expense
    , createdAt : String
    }
```

`Maybe` fields mean "this field was changed". `Nothing` means "keep the original
value". To get the effective values, `Entry.resolve` (`src/Data/Entry.elm:38`)
first re-indexes all amendments into a `Dict String (List Amendment)` keyed by
`ExpenseId.toString a.targetId`, then does a single `Dict.get` per expense and
folds the matching amendments in chronological order:

```elm
-- actual shape (Entry.elm:45-63)
amendsByTarget : Dict String (List Amendment)  -- built once per resolve call

applyAmends expense =
    case Dict.get (ExpenseId.toString expense.id) amendsByTarget of
        Nothing    -> toEffectiveEntry False expense
        Just amends ->
            amends
                |> List.sortBy .createdAt
                |> List.foldl applyAmendment (toEffectiveEntry True expense)
```

`EffectiveEntry` is what the UI actually renders. `isAmended : Bool` lets the
view show an "edited" badge.

This pattern means:
- Full edit history is preserved in the database.
- Sync conflicts are far less likely (amendments rarely clash).
- You can reconstruct what an expense looked like at any point in time.

One thing amendments **cannot** do: change `tripId`. The outer dict in
`as_.expenses` is keyed by `TripId.toString` and `Entry.resolve` filters by
`expense.tripId == activeTripId` on the *base* expense before folding
amendments. To move an expense to another trip, see the next section.

---

## Moving an expense between trips

Moving is "void the original + write a new expense in the destination trip"
because amendments can't change `tripId` (see above) and the outer
`as_.expenses` dict is keyed by trip. Triggered from the ledger row kebab
("Move to trip…") which opens `UI.TripPicker.viewMove`. Tapping a destination
fires `MoveEntry expense newTripId`, which `Task.perform Time.now`s into
`GotMoveTime` and runs the compound write:

1. Snapshot the source row's effective state via `Helpers.effectiveEntryToExpense`.
2. Mint a fresh `ExpenseId` and `createdAt`; override `tripId` to the destination.
3. `Cmd.batch` two `sendPouch` calls — `SaveVoid` on the old ID and
   `SaveExpense` for the new doc — plus `Nav.pushUrl` to the destination
   trip's ledger so the moved row is immediately visible.
4. Optimistically insert the void into `as_.voids` and the new expense into
   the destination's inner dict so the UI updates before the live-changes
   feed confirms.

Trade-offs:

- The expense gets a new `id`. Any deep link to the old id (`RouteEditEntry`)
  will `findEffective` to `Nothing` because the original is voided.
- The pre-move amendment chain is *orphaned*: it still exists in PouchDB, but
  the base expense it targets is voided, so `Entry.resolve` never folds it.
  No "edited" badge survives a move.
- On other devices, the void may replicate slightly before the new expense →
  a brief disappearance, then reappearance under the new trip. Acceptable.

The picker is only offered when the user has more than one trip; the
"Move to trip…" menu item is hidden otherwise.

---

## Deleting an expense: soft deletes with Void

Deleting also avoids mutation. A **void** document is created:

```elm
type alias Void =
    { createdAt : String
    , id        : String    -- "void::<targetId>::del"
    , targetId  : String    -- the expense or trip being deleted
    }
```

On delete:
1. `SaveVoid` is sent through `pouchOut`.
2. The void is also inserted into `as_.voids` **immediately** (optimistic update)
   so the UI hides the entry before the database confirms.
3. `Entry.resolve` filters out any expense whose ID appears in `as_.voids`.

Soft deletes sync correctly: the void document propagates to all devices, so the
entry disappears everywhere without needing CouchDB's built-in deletion (which
can cause sync headaches).

---

## Trips collection: the Zipper

`as_.trips` is not a plain `Dict` — it uses a zipper-like type defined in
`Data/Trips.elm` to track which trip is currently selected:

```elm
-- conceptually
type Trips
    = Trips Trip (List Trip)   -- head + rest, head is selected
```

The head is always the active/selected trip. This lets the UI safely use
`Trips.selectedTrip` without a `Maybe` unwrap in most rendering paths.

The `AuthState.trips` field is wrapped in `TripsState` (also in
`Data/Trips.elm`) to track loading:

```elm
type TripsState
    = NoTripsYet
    | TripsFailed String
    | TripsLoaded Trips
    | TripsLoading (Dict String Trip) (Maybe TripId)
```

`TripsLoading` carries any trip documents that arrived via the
live-changes feed before the bulk `GetAllTrips` response, plus the
route's intended selection hint, so we can pick the right trip the
moment loading completes.

---

## CouchDB sync

```js
// pouch.js
const remote = new PouchDB(
    `https://couch.ternpike.com/${creds.dbName}`,
    { auth: { username: creds.email, password: creds.password } }
)
db.sync(remote, { live: true, retry: true })
  .on('active',   () => send({ tag: 'SyncStateMsg', state: 'syncing' }))
  .on('paused',   () => send({ tag: 'SyncStateMsg', state: 'synced'  }))
  .on('error',    e  => send({ tag: 'SyncStateMsg', state: e.status === 401 ? 'auth_error' : 'error' }))
```

- `live: true` keeps the connection open permanently.
- `retry: true` reconnects automatically on network drops.
- A 401 from CouchDB is sent back as `auth_error`, which transitions Elm to
  `GuestModel SessionExpired` — the user is kicked to the login screen.
- Each remote change that sync pulls down fires the local changes feed, so the
  same `DbChange → pouchIn → update` path handles both local writes and
  remote sync.

---

## Encoders and decoders

Every `Data/*.elm` module exports an `encode` function and a `decoder`:

```elm
-- Data/Expense.elm
encode : Expense -> Json.Encode.Value
decoder : Json.Decode.Decoder Expense
```

The `encode` functions set the PouchDB `_id` field from the typed ID, and
add a `"type"` discriminator field (`"expense"`, `"amend"`, `"trip"`, `"void"`)
so `pouch.js` and the live-changes dispatcher can route docs correctly.

`_rev` (PouchDB's revision field, used for optimistic concurrency) is handled
entirely in `pouch.js` — it fetches the current `_rev` before upserting, so Elm
types never need to carry it.

---

## Quick reference: where to find things

| I want to... | Look here |
|---|---|
| Add a field to Expense | `src/Data/Expense.elm` — update type, `encode`, `decoder` |
| Add a new page | `src/Pages/`, wire into `Routing.elm` and `Main.elm` `view`/`update` |
| Change how PouchDB is queried | `src/pouch.js` |
| Add a new port | `src/Main.elm` (port declaration) + `src/main.js` (JS handler) |
| Change sync settings | `src/pouch.js` `startSync` handler |
| Understand what `EffectiveEntry` looks like | `src/Data/Entry.elm` |
| See how amendments are applied | `src/Data/Entry.elm` `resolve` function |
