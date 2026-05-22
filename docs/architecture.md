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
│   ├── UserId.elm        # Opaque user identifier (email-backed today)
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
| `OpenFlock` | `{ flockId, dbName }` | Open a flock-local PouchDB handle immediately (used by the New Trip flow after `POST /flocks` succeeds — avoids racing the personal-DB sync that would otherwise hydrate the handle via `reconcileFlocks`). Idempotent. |

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
    , createdAt : String
    , createdBy : UserId            -- which signed-in user wrote the patch
    , date      : Maybe String
    , id        : String           -- "amend::<expenseId>::<ts>"
    , longNote  : Maybe String
    , merchant  : Maybe String
    , note      : Maybe String
    , targetId  : ExpenseId        -- points at the original expense
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
    , createdBy : UserId    -- which signed-in user wrote the tombstone
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

`pouch.js` keeps a `Map<string, Handle>` of open PouchDBs — the personal
DB (`ternpike` ↔ `ternpike-<email>`) plus one entry per flock the user
belongs to (`ternpike-<flockDbName>` ↔ `<flockDbName>`). Each handle
runs its own `db.sync(remote, { live: true, retry: true })`; CouchDB's
`_security` doc gates membership per remote, so we don't reimplement
permission routing in JS.

```js
// pouch.js
const handles = new Map() // localName -> { local, remote, sync, changes, flockId? }
handles.get('ternpike')   // personal handle, flockId === null
```

Solo users (no flocks) keep exactly one handle — no regression on the
single-user path.

### Startup sequence

1. Open the personal local DB and start its sync.
2. On the first non-error `paused` event (PouchDB's "fully caught up"
   signal), `db.get('user:flocks')` from the personal DB. If 404, no
   flocks — done.
3. For each `{ flockId, dbName }` entry in `flocks[]`, open a local DB
   named `ternpike-<dbName>` and start syncing it to `<dbName>` using
   the same CouchDB credentials (one user, many DBs).
4. The personal handle watches its own `changes` stream for `user:flocks`
   updates; reconciliation opens new handles and closes departed ones
   without a reload. Server admin-writes `user:flocks` on
   create/join/leave, so the change stream is the trigger.

### Port message fan-out

- `GetAllTrips` queries every handle in parallel, merges by `_id`
  (globally unique — timestamp + nonce), and tags each trip with
  `flockId` (`null` for personal, the flock id otherwise). The field is
  derived from the source DB, **not** stored on disk.
- `GetTripExpenses` / `GetExpense` / `Save*` take a `target` field on the
  outbound message: `{ kind: "Personal" }` or
  `{ kind: "InFlock", flockId }`. Until the Elm side wires this up
  (#60), missing `target` defaults to the personal handle so the solo
  path keeps working.

### Live changes feed

Every handle has its own `db.changes({ live, since: 'now' })` listener.
Each emitted `DbChange` / `DbDeleted` includes a `sourceDbName` field
so Elm can attribute the doc later when needed; the existing decoder
ignores it for now.

### Sync state and auth

- `live: true` keeps the connection open permanently; `retry: true`
  reconnects on network drops.
- A 401/403 from **any** handle's sync is sent back as `auth_error`,
  which transitions Elm to `GuestModel SessionExpired` and kicks the
  user to the login screen. We don't try to keep some flocks alive
  while others are dead.
- `clearStorage` / `clearAllStorage` cancel every sync, close every
  remote, and `local.destroy()` every local DB — so a sign-out / 401
  wipes IndexedDB for all flock DBs, not just the personal one.

### Flocks in Elm

The Elm-side types for the multi-DB world live in three modules:

- `Data.FlockId` — opaque wrapper around a 12-character lowercase hex
  nonce. `fromString` validates the shape and returns `Maybe FlockId`.
- `Data.Flock` — the `Flock` record. Members are modeled as
  `billingOwner :: otherMembers` so "the owner is always a member" is
  a structural invariant; `members : Flock -> List UserId` derives the
  provably-non-empty flat list on demand. On the wire (`flock:meta`
  doc) the field is flat — the decoder picks the owner out and
  hard-rejects (`Json.Decode.fail`) any doc where `billingOwner` is
  not in `members`. The CouchDB document id is the literal marker
  string `flock:meta` (one such doc per per-flock DB), so the per-flock
  identifier rides on a separate `flockId` field that `Data.Flock.decoder`
  reads via `Data.FlockId.decoder`.
- `Data.Flocks` — `Dict String Flock` keyed by `FlockId.toString`,
  lives at `AuthState.flocks`. `ownedBy` / `joinedBy` filter by user.

`Trip.flockId : Maybe FlockId` is in-memory only: `Trip.encoder`
deliberately omits it and `Trip.decoder` only reads it if present.
`src/pouch.js` is the source of truth — it tags trip docs with the
handle's `flockId` at the port boundary on the way in from
`GetAllTrips` and from the live-changes feed. Storing it inside the
doc would let it diverge from the DB it actually lives in.

Startup hydration is JS-driven: after the personal DB's first
non-error `paused` event, `pouch.js` reads `user:flocks` from the
personal DB and (a) opens / closes flock handles via `reconcileFlocks`,
(b) emits `FlocksReconciled flockIds` so Elm can drop cached entries
for flocks the user has left, and (c) fetches each flock's
`flock:meta` doc and emits it as `FlockMeta`. The Elm decoder turns
that into a `Flock` and inserts into `AuthState.flocks`. Subsequent
live changes to `flock:meta` docs are routed up as `FlockMeta` events
too, so membership/billing transitions converge without a reload.

The `Data.Pouch` inbound protocol carries the new tags:

- `FlocksReconciled (List FlockId)` — replaces the known-flock set.
- `FlockMetaChanged Flock` — upserts one flock.

### Paid-feature gating: `Trip.effectiveTier`

Any predicate that asks "can the user do X on **this trip**?" must consult
`Trip.effectiveTier : Trip -> { a | flocks, tier } -> Tier` (defined in
`Data/Trip.elm`), **not** `as_.tier` directly. The rule:

- **Personal trip** (`trip.flockId == Nothing`) → `as_.tier`.
- **Trip in a flock with `billingStatus == Active`** → `Fly`. The flock's
  billing owner pays for the flock, and we don't carry the owner's exact
  tier locally — `Active` is sufficient evidence that they're at least
  `Fly`. (`Trailblazer` is a billing distinction, not a feature one.)
- **Flock in `Grace` or `Frozen`** → falls back to `as_.tier`. The
  lapsed-billing banner handles user messaging.
- **Trip references a flock we don't yet have data for** → falls back to
  `as_.tier`, never crashes.

Two convenience wrappers — `Trip.canUseProxiedOCR` and `Trip.canBatchScan`
— resolve `Tier.isPaid (effectiveTier trip as_)` so call sites stay terse.

The opposite rule still holds: predicates that ask "is the **logged-in
user** paid?" (Settings tier badge, "Create Flock" upgrade prompt, billing
screen) keep reading `as_.tier` directly. The headline UX — a Fledgling
invitee gets paid OCR inside a flock trip but stays Fledgling on personal
data — falls straight out of this split.

Server endpoints back paid features still re-check the actual tier
(caller's or flock-owner's depending on the call). Client-side gating is
UX, not security.

### Flocks settings UI

`src/Pages/Settings/Flocks.elm` is the **manage** surface — invite,
leave, transfer ownership for flocks the user already belongs to.
Modals and inline errors sit on `AuthState.flockUi : Data.FlockUi.FlockUiState`
and the HTTP wrappers for `inviteToFlock`, `joinFlock`, `leaveFlock`,
`transferOwnership` live in `src/Http/FlockApi.elm`.

**Creation does not happen here.** The unified "+ New shared trip"
flow on the Trips page is the only entry point for creating a new
flock (see the Trip + Ledger UI section below). If the user has zero
flocks, this section renders an empty-state card pointing back at
`/trips` rather than offering its own Create button.

Invite links land on a new `RouteJoinFlock String` route at
`/flocks/join?token=<jwt>` (path-segment-safe — the token has no `:`
collisions). Signed-out users get the token parked on
`GuestState.pendingJoinToken` and the verify-code success path
redirects to `/flocks/join?token=…` instead of `/trips`, so the
invite is consumed immediately after auth. The signed-in view
(`src/Pages/JoinFlock.elm`) decodes the JWT payload locally for
display only — the server checks the signature — and surfaces a
friendly "this invite is for someone else" error when the token's
`inviteeEmail` doesn't match `creds.email`.

### Trip + Ledger UI in flock-shared trips

The day-to-day flock chrome lives in five places (#63):

- **Trip card / hero** — `src/Pages/Trips.elm` overlays a
  `UI.FlockBadge` and an overlapping `UI.Avatar.viewStack` on the
  meta row, only for trips with a `flockId`. Personal trips render
  unchanged.
- **Ledger row** — `src/Pages/Ledger.elm` resolves the active trip's
  flock membership into `Dict String FlockMember` and threads it to
  `viewEntryRow`, which renders an initials avatar + first name
  (Variant A) on the existing `mt-1.5 flex items-center gap-2` band.
  Personal trips pass `Dict.empty` so the chip never renders.
- **Add / Scan context strip** — `src/Pages/Add.elm` and
  `src/Pages/Scan.elm` render a persistent "ADDING TO / Trip Name"
  strip at the top of the form when the active trip belongs to a
  flock, plus a `visible to <first names>` caption under the amount
  input. The caption collapses to `+ N more` when the flock has
  more than three members.
- **Trip Picker drawer** — `src/UI/TripPicker.elm` decorates each
  candidate row with the flock badge and avatar stack.
- **New Trip dialog** — `src/Pages/Trips.elm` `viewTargetPicker` asks
  "WHO'S ON THIS TRIP?" with one tile per option:
  - **Just me** (default) — personal trip, written to the user's
    solo PouchDB.
  - **One tile per owned flock** (`Flocks.ownedBy currentUser`) —
    writes the trip into that existing flock's local DB.
  - **+ New shared trip** — the unified flock-creation entry point.
    Expands inline to an emails chip-input + an `Advanced — Group
    Name` reveal (defaults to the trip name; the override matters
    when the user wants a reusable group across multiple trips).
    Fledgling users see this tile but selecting it surfaces a
    contextual upgrade prompt; the form's Create button stays
    disabled until they pick a different tile or upgrade. This
    replaces the old standalone Settings → "Create Flock" button.

  The picker writes to `TripForm.target : Data.Trip.CreateTarget`
  (`ToPersonal | ToExistingFlock FlockId | ToNewFlock NewFlockDraft`).
  `CreateTarget` is form-only — by the time the trip actually gets
  written to PouchDB, the orchestration in `Main.elm`'s submit
  handler has resolved any `ToNewFlock` to `ToExistingFlock <newId>`
  by sequencing `Http.FlockApi.createFlock` → `Cmd.batch` of
  `OpenFlock` port message + `Time.now` + fan-out
  `Http.FlockApi.inviteToFlock` calls.

  Invite failures are non-blocking — the user can re-invite from
  Settings if a specific email bounced (server returns 409 for
  duplicates, the standard signal). Flock-creation failures abort
  the whole submit and surface in the form's existing error block.

`UI.Avatar` hashes `UserId.toString` into a five-slot palette
(`bg-rust`, `bg-forest-mid`, `bg-moss`, `bg-rust-deep`, `bg-tan`) so
Alice keeps the same circle colour on every member's device. The
hash is pinned by `tests/UIAvatarTests.elm` so casual refactors of
the hashing function fail loudly.

### Tier resolution in shared trips

Paid features in a flock are gated by the **billing owner's** tier,
not the writer's, via `Data.Trip.effectiveTier`. The wrappers
`canUseProxiedOCR` / `canBatchScan` are convenience predicates over
the same answer — a free Fledgling member of a Fly-owned flock gets
hosted OCR inside that flock's trips because that's the whole point
of pooling under one billing relationship. The tier-aware footnote
in `src/Pages/Scan.elm` is the first call site; the proxied-OCR
network path itself is still wired through #14.

`Data.Trip.TripTarget` is the routing tag carried on every outbound
`Save*` / `Get*` port message: `Personal` writes to the user's solo
PouchDB handle, `InFlock fid` writes to the matching flock handle.
`Main.targetForTripId` resolves the tag by looking up the trip in
the loaded zipper; missing trips fall back to `Personal` so legacy
call sites stay safe. The encoder produces
`{ "kind": "Personal" }` or `{ "kind": "InFlock", "flockId": "..." }`,
matching the `targetHandle` reader in `src/pouch.js`.

### Billing-status UX contract

Every flock carries `billingStatus : BillingStatus` from
`flock:meta` (one of `Active`, `Grace`, `Frozen`) plus an optional
`billingLapsedAt : Maybe String` ISO timestamp. The server enforces
the same gate at the CouchDB `validate_doc_update` layer (#57); the
client gates the UI so users don't submit and then see a 403.

  - `Active` — flock is writable. No banner, no disable.
  - `Grace` — billing has lapsed but writes are still allowed for the
    14-day grace window (mirrored by `UI.BillingBanner.graceWindowDays`).
    The full-bleed `UI.BillingBanner` shows on every flock-scoped trip
    page (Ledger / Stats / Add / Scan) with status-specific copy and a
    days-remaining countdown derived from
    `(billingLapsedAt + 14 days) - today`. **Writes are pre-disabled**
    even during the grace window — the UX rule is "you can see what's
    coming but not pile on more entries while billing is sorted out."
  - `Frozen` — read-only indefinitely. Same banner, no countdown.

`Data.Flock.isReadOnly : Flock -> Bool` is the single source of truth
for the predicate (`True` for `Grace`/`Frozen`, `False` for `Active`).
Every disable site consults it: the Add submit button, the Ledger row
menu items (Duplicate / Move / Delete), and the Scan-tab dropzone. Do
not inline the predicate at call sites — go through `isReadOnly` so
the rule stays in one place.

The banner is inserted once in `Main.viewAuth` between the error
banner and the page content, so all four flock-scoped tabs render it
identically without each page reproducing the chrome.

The role-aware copy matrix (owner / paid member / Fledgling member ×
Grace / Frozen) lives in `UI.BillingBanner.graceCopy` and `frozenCopy`
— the matrix is in the #64 issue body and transcribed verbatim into
those two functions. The "Transfer billing to me" CTA fires
`TakeOverBilling FlockId`, which calls
`Http.FlockApi.transferOwnership` with the calling user's email; the
button is hidden (not disabled) for Fledgling members since the
server would 403 their request anyway. The "Renew" CTA is a deep
link to `/settings#billing` — a placeholder until the dedicated
billing screen lands.

Settings/Flocks renders the smaller `UI.BillingBanner.viewInline`
chrome inside each flock card so the status is also visible without
opening the flock's trip.

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
