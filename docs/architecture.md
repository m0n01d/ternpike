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
├── Main.elm            # App entry point + top-level update/dispatch
├── Ports.elm           # The port module — all JS interop ports (Cmd/Sub)
├── Codec.elm           # Flags / Creds JSON codecs (credsDecoder, encodeCreds)
├── Types.elm           # Model, AuthState, GuestState, Msg
├── Routing.elm         # URL ↔ Route parsing
├── Helpers.elm         # Utility functions
├── Msg/
│   └── Scan.elm         # Scan-feature Msg (nested under AuthMsg_'s ScanMsg)
├── Page/
│   └── Scan.elm         # Scan/OCR feature update (per-feature TEA, #368)
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
├── main.js              # Elm init, port handlers for storage and geolocation
├── pouch.js             # All PouchDB operations; subscribed to Elm ports
└── elements/            # Custom elements registered for side effects
    ├── map-picker.js    # <map-picker> — full-screen Leaflet picker
    ├── waypoint-map.js  # <waypoint-map> — Leaflet map with clustered points
    ├── relative-time.js # <relative-time> — @github/relative-time-element re-export
    └── tp-amount.js     # <tp-amount> — Intl.NumberFormat-backed accessible currency
```

### Custom elements

Every custom element lives in its own file under `src/elements/` and is
registered for side effects from `src/main.js`. New element? add the file
under `src/elements/`, add a side-effect `import './elements/foo.js'` to
`main.js`, and write an Elm wrapper under `src/UI/` so the call sites can
stay tidy and the attribute names don't drift.

- **`<tp-amount value="12.34" currency="USD">`** — renders a currency
  amount via `Intl.NumberFormat`. Wrapped in Elm by `UI.MoneyView.amount` /
  `UI.MoneyView.wholeDollars`. The element carries `role="text"` and a
  spoken-form `aria-label` (e.g. `"twelve dollars and thirty-four cents"`,
  `"negative five dollars"`); the visible `$` glyph sits inside an
  `aria-hidden="true"` span. The full a11y contract is documented at the
  top of `src/elements/tp-amount.js`.
- **`<relative-time datetime="2024-05-21">`** — the
  `@github/relative-time-element` package, registered as a side-effect
  import. Wrapped in Elm by `UI.DateView`:
  - `short : DateField -> Html msg` — long absolute shape (`"May 21, 2024"`)
  - `monthDay : DateField -> Html msg` — short shape (`"May 21"`)
  - `dateOf : Time.Posix -> Html msg` — short shape derived from an
    instant; the browser converts UTC to the user's local zone via
    `Intl.DateTimeFormat`.
  - `timeOf : Time.Posix -> Html msg` — hour + minute only (`"5:42 PM"`);
    suppresses every date field explicitly (`weekday=""`, `day=""`,
    `month=""`, `year=""`) because missing attrs default ON and the
    library renders an unwanted weekday + date prefix.

  Always set `no-title=""` per the library's own a11y guidance.
- **`<map-picker>` / `<waypoint-map>`** — Leaflet-backed elements. No Elm
  wrapper today; called via `Html.node` directly because they show up in
  exactly one place each.

`Data.Money.format`, `Data.DateField.formatDisplay`, and
`Data.DateField.formatMonthDay` are intentionally still alive — they're
used by non-HTML consumers (Leaflet popup labels in
`Helpers.encodeWaypoints`, elm-charts tick labels in `Pages.Stats`). DOM
render sites must go through the web components / wrapper modules above.

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
    , milepost      : MilepostState
    , milepostStates : List Milepost.MarkerState
    , milepostToasts : List Milepost.Marker
    , network       : NetworkState
    , page          : Page
    , route         : Route
    , subscriptionStatus : Maybe SubscriptionStatus
    , syncState     : SyncState
    , tier          : Tier
    , trailblazerNumber : Maybe Int
    , tripLoaded    : Set String
    , trips         : TripsState
    , voids         : Dict String Void
    -- ... form fields, UI state, etc.
    }
```

`tier`, `subscriptionStatus`, and `trailblazerNumber` are server-authoritative
billing fields. They're seeded from the `/auth/verify-code` response (or the
cached `auth_creds` blob on cold boot) and refreshed via `GET /me` once per
session — see the startup sequence below. The `subscriptionStatus` value is
`Maybe` because non-subscribers (most Tern users, and Trailblazers, who have
no Stripe subscription) have no status to report; the server returns `null`
and the wire decoder maps that to `Nothing`. `trailblazerNumber` is `Just n`
(1..500) only for confirmed Trailblazer purchases. None of these three fields
go through PouchDB — a tier change made on Device A must not wait for sync to
propagate.

`milepost : MilepostState` (`Types.MilepostState = Loaded { earned, rev } |
NotLoaded`) holds the user's earned-achievement progress. The earned-marker map
is persisted in PouchDB at `milepost::progress` (`Data.MilepostProgress`); the
reconcile pass in `Main` re-evaluates `Data.Milepost.evaluate` on every settled
sync edge and unions newly-earned markers into the doc. `rev` carries the
PouchDB `_rev` so the next write doesn't 409; it is `Nothing` only transiently
before the first write confirms back on the change feed. Unlike the billing
fields above, this DOES live in PouchDB — earned achievements should sync across
the user's own devices. See "Startup sequence" and "Document ID conventions"
below.

`milepostStates : List Milepost.MarkerState` is the *evaluated* catalog (every
marker's `Earned`/`Locked` state, with locked-progress) that `reconcileMileposts`
stashes on every pass — not just the earned set in the persisted doc. Rendering
needs the full evaluated catalog, but there is no `now` on the model at view
time, so the reconcile (which already has `now`) writes the result here. "The
Milepost" collection screen (`Pages.Milepost`, `RouteMilepost` at
`/milepost`, reached via the header flag affordance — not the bottom nav, which
stays trip-scoped) renders straight off this field, grouped by `Milepost.Family`.
Navigating to `RouteMilepost` kicks a fresh `ReconcileMileposts Time.now` so the
screen reflects current locked/progress. Shared chip styling lives in
`UI.Milepost.markerChip`; family colour accents (`brown`/`amber` tokens added to
`theme.css`) are single-sourced there.

`milepostToasts : List Milepost.Marker` is the earn-toast queue (#410). When the
`Loaded` branch of `reconcileMileposts` finds newly-earned markers, it maps their
ids back through `Milepost.catalog` and appends the `Marker`s here; the
`NotLoaded` first-load seed never enqueues (no celebrating the pre-existing
backlog). `UI.MilepostToast.view` renders the head of the queue
(`UI.MilepostToast.next` — the pure decision shared with the
`Verify.Specs.MilepostToast` surface) as a bottom-anchored forest plaque sliding
up over the dimmed view, reusing `UI.Milepost`'s family accent + glyph for the
parchment badge. `DismissMilepostToast` drops the head and re-arms a
`Process.sleep` auto-advance (mirroring `ToastExpired`/`toastFor`) so a batch of
earns plays through one at a time; the timer is armed once on enqueue and chained
by each dismiss so sleeps never stack.

`network : NetworkState` (`Data.Sync`) is also tracked on `GuestState` so the
disconnected-banner UI works before sign-in. It's a tri-state — `Unknown`
until the first `networkStatus` report, then `Online` / `Offline` from
`navigator.onLine` plus `online`/`offline` window events. Reads go through
`Data.Sync.isOffline`, which treats `Unknown` as offline-safe (the boot
window defers OCR rather than firing a doomed call — see the Scan capture
path). The `networkStatus` port forwards a `Bool`; `Main.networkStateFromOnline`
maps it into the tri-state.

`demoMode : Bool` is also on both states. Set to `True` by the
`demoMode` flag when the app boots at `/demo` (see `src/main.js` and
`src/demo.js`) — turns on the top "DEMO MODE" banner and is the only
piece of UI that branches on it. The flag flows `flags → init → gs →
toAuthState` and back via `toGuestState` so it survives any
hypothetical session-expired roundtrip without re-detection.

`GuestState` (in `Types.elm`) holds the signed-out flow:

```elm
type alias GuestState =
    { authError        : Maybe String
    , basePath         : String
    , codeInput        : String
    , demoMode         : Bool
    , emailInput       : String
    , key              : Nav.Key
    , network          : NetworkState
    , pendingJoinToken : Maybe String
    , pendingRef       : Maybe String
    , resendStatus     : RemoteData Http.Error ()
    , route            : Route
    , session          : GuestSession
    , showSettings     : Bool
    , today            : DateField
    , version          : String
    }
```

`route : Route` is the guest tree's current route, kept in sync by the
`UrlChanged` handler (`updateShared` in `Main.elm`) exactly as
`AuthState.route` is. It's seeded from the boot URL in `init`, carried
across the auth boundary by `toGuestState`/`toAuthState`, and lets the
guest view (`Pages.Guest.viewGuest`) dispatch on the URL. Today every
route falls through to the login form via `viewLogin`; the Nest invite
funnel (`docs/nest-invite-funnel.md`) adds dedicated unauthenticated
pages that branch off this field. Storing the route here (rather than
re-parsing the URL in the view) keeps the guest tree consistent with
the auth tree, which has always carried its own `route`.

Transient view state (`statsHover : Data.StatsHover.Hover`,
`statsGranularity : Maybe Data.StatsGranularity.Granularity`,
`showDayIntensity : Bool`, `showInstallPrompt : Bool`,
`postJoinPrompt : Bool`, `scanQueue`, `confirmDeleteTrip`, etc.) also
lives on `AuthState`, but it never persists — these fields are reset on
the relevant pointer-leave / submit / sign-out event. `postJoinPrompt`
is the one-time post-join retention card (#338): set `True` in the
`JoinSharedTripResult` Ok arm after a successful funnel conversion,
cleared by `DismissPostJoinPrompt` (and by `EnableCrewPush` once the user
opts in). The Settings member-landing renders the Add-to-Home-Screen /
crew-push card while it's `True`, reusing the existing `showInstallPrompt`
/ `TriggerInstallPrompt` / `subscribePush` plumbing rather than a new
port. `showInstallPrompt` is driven by the
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

`duplicateWarning : Maybe Expense` is `Just` when the Add-page submit handler
found a likely duplicate in the same trip's expense cache (same merchant
case-insensitively, amount within $1, same date). The UI renders an inline
warning above the submit button and changes the button label to "Add anyway".
The second `SubmitEntry` with a non-`Nothing` `duplicateWarning` bypasses the
check and submits. Cleared on any field edit (amount, merchant, date) or
after the expense is saved. In-memory only.

`lastSyncedAt : Maybe Time.Posix` is the instant the last successful sync
landed. Captured via `Task.perform GotSyncTime Time.now` whenever
`SyncStateMsg` transitions into `Synced`. The Settings page renders it via
`UI.DateView.dateOf` + `UI.DateView.timeOf`, both of which emit
`<relative-time>` web components — the browser converts to the user's local
zone via `Intl.DateTimeFormat`, so no `Time.Zone` is tracked on the model.
In-memory only; never syncs to PouchDB.

### Nested update dispatch (per-feature `Page.Foo.update`)

`Main.update` pattern-matches `(Msg, Model)` and delegates to `updateAuth`
/ `updateGuest` / `updateShared`. `updateAuth` is a large `case msg of` over
`AuthMsg_`. As features grow, individual features are being carved out of
that monolithic `case` into their own `Page.Foo` modules — the first being
the Scan/OCR feature (#368).

The mechanics that avoid an import cycle (Elm forbids them):

- Feature messages live in a dedicated `Msg.Foo` module (e.g. `Msg.Scan`)
  that **does not import `Types`**. `Types.AuthMsg_` gains one variant,
  `ScanMsg Msg.Scan.Msg`, and imports `Msg.Scan`.
- `Page.Foo` (e.g. `Page.Scan`) imports `Msg.Foo` (for the message
  constructors it pattern-matches) and exposes
  `update : Msg.Foo.Msg -> Page.Foo.Model -> ( Page.Foo.Model, Effect )`.
- `updateAuth` collapses every feature arm to one router arm that projects
  the slice out of `AuthState`, runs `update`, merges the slice back, and
  lifts the returned `Effect` to a `Cmd`:

  ```elm
  ScanMsg m ->
      let
          ( scanModel, effect ) =
              Page.Scan.update m (scanModelFromAuth as_)
      in
      ( AuthModel (mergeScanModel scanModel as_), Effect.perform as_.key effect )
  ```

#### The `Effect` seam + narrow `Model` slice (#369)

`Page.Scan.update` was re-typed in #369 from `… -> AuthState -> ( AuthState, Cmd Types.Msg )`
to `… -> Page.Scan.Model -> ( Page.Scan.Model, Effect )`. Two changes, one purpose
— making the Scan slice **hermetically testable under `avh4/elm-program-test`**
(the first PR-gated feature; see "Verification" / `CLAUDE.md`):

- **Narrow `Model` slice.** `AuthState` embeds `key : Nav.Key`, and a `Nav.Key`
  cannot be hand-constructed — so a test can't build a seed `AuthState`.
  `Page.Scan.Model` is the subset of `AuthState` fields the Scan flows actually
  touch (`activeScanItemId`, `basePath`, `config`, `creds`, `currentUser`,
  `duplicateWarning`, `error`, `form`, `network`, `ocrInFlight`, `route`,
  `scanQueue`, `scanSeq`, `scanTombstones`, `sharedTrips`, `storageAvailable`,
  `tier`, `today`, `trips`) — no `Nav.Key`, so it's fully constructible in a
  test. `Main.scanModelFromAuth` / `mergeScanModel` project and merge. The
  `currentUser` / `sharedTrips` / `tier` trio is carried because
  `geocodeDispatch` needs them to satisfy `Data.Trip.TierContext`.
- **`Effect` seam (`src/Effect.elm`).** `update` returns a description of its
  side effects (`Effect` ADT) instead of an opaque `Cmd`. `Effect.perform :
  Nav.Key -> Effect -> Cmd Types.Msg` is the production interpreter (the router
  hands it `as_.key`); the test-side `simulate : Effect -> SimulatedEffect
  Types.Msg` (in `tests/PageScanEffectTest.elm`) mirrors it effect-for-effect.
  `Effect` carries no `Nav.Key` — the key is supplied at `perform` time — which
  keeps the slice and the seed state key-free. `simulate` lives in the test tree
  because `avh4/elm-program-test` is a test-only dependency; importing its
  `SimulatedEffect.*` modules from `src/` would pull the harness into the
  production build.

  Variants (one per construction site in `Page.Scan.update`, as
  `NoUnused.CustomTypeConstructors` requires): `Batch (List Effect)`,
  `DeleteScanItem String` (remove one durable row — multi-receipt split source
  + `ClearDoneItems`, #374), `ExtractExifGps`, `FetchFileUrl File`,
  `Geocode Creds itemId address`,
  `MakeOcrCall { backendUrl, body, itemId, path }`,
  `MintIdsThen String (List OcrData)` (run `Time.now` so a multi-receipt split
  can mint durable child ids from real capture millis → `GotMintedScanIds`,
  #374), `Navigate String` (the `BackToQueue` `Nav.pushUrl`), `NoEffect`,
  `PrepareOcrImage`, `SaveScanItem Json.Encode.Value` (offline-capture persist
  #372 + the reconnect status-flip persist #373 + every queue-mutating handler
  #374), `StampCapture (List File)` (the `FilesSelected` → `Time.now`
  capture-millis stamp #372).

`Effect.perform` reconstructs exactly the Cmds #368 moved, so behavior is
identical — `npm test` stays green and the wire traffic is unchanged. The win:
Scan changes touch only `Page/Scan.elm` + `Msg/Scan.elm` + `Effect.elm`, never
`AuthMsg_`, and `tests/PageScanEffectTest.elm` drives the real `update` through
`simulate` to pin state transitions.

The top-level `( AuthMsg _, GuestModel gs ) -> ( GuestModel gs, Cmd.none )`
arm intentionally drops an `AuthMsg` that arrives after the session was torn
down (sign-out / 401) — there's no `AuthState` to run `updateAuth` against.
In-flight scan results are recovered on the next login from the IndexedDB
row, not from this dropped message.

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

Two singleton docs in the personal DB use fixed (non-ULID) `_id`s because there
is only ever one of each: `user:profile` (see "Local-first storage" below) and
`milepost::progress` (`type = "milepostProgress"`, `Data.MilepostProgress`) —
the earned-achievement map `{ earned : Dict MarkerId earnedAtIso }`. The
client writes `milepost::progress` (it's not server-authoritative); the
`Data.Pouch.SaveMilepostProgress` outbound command upserts it on the personal
handle, and the change feed routes it back as a `MilepostProgressChanged`
`DocChange` (keeping `_rev` on the payload so Elm can thread it through the next
write).

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
| **IndexedDB** (outside PouchDB) | JWT (`auth_creds`), BYO API keys (`ai_config`), the durable offline scan queue (`scanQueue` store) | Device-local. Must not sync — keys would land on CouchDB; in-flight scan captures are device-specific. |
| **PouchDB** | Expenses, trips, amendments, voids, `user:profile` | Things that should sync across the user's devices, that aren't secret and aren't server-authoritative. |

The trap to avoid: don't put `tier` or `stripeCustomerId` in PouchDB even as a
cache. If a user upgrades on Device A, PouchDB sync won't propagate that until
the next push — and the source of truth is Stripe → Worker KV anyway. The
client refresh path is the `/me` endpoint, called on startup and after
returning from Stripe Checkout.

> Admin / dev: the `ternpike-admin` TUI (`npm run admin`) talks to a
> protected `/admin/*` surface on the auth Worker for browsing users,
> CouchDB databases and shared trips, mutating tiers, and editing docs
> inline in `$EDITOR`. See `scripts/admin/README.md`.

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

### The durable offline scan queue (`scanQueue` IndexedDB store)

The same IndexedDB database that holds `auth_creds` (`alaska-tracker`, opened
in `src/main.js`) has a second object store, `scanQueue` (added at db version
2, #371), keyed by scan id (`scan::<millis>::<seq>`). It durably holds the
offline receipt-scan queue — captured images plus the user's typed draft — so
nothing is lost across a reload or a days-later reconnect. Each value is a
`Data.Scan.scanItemEncoder` JSON blob; Elm reads them back through
`scanItemDecoder` + `reconcileHydratedQueue`. The queue is device-local (an
in-flight capture belongs to the device that took the photo) and never synced.

**The version-2 migration is safety-critical** — a botched `onupgradeneeded`
bricks `auth_creds` and logs everyone out. `openDB` therefore:

- Guards each store by `oldVersion`: `if (oldVersion < 1)` creates `kv`,
  `if (oldVersion < 2)` creates `scanQueue`. The pre-#371 code created `kv`
  unconditionally, which throws `ConstraintError` the instant the upgrade
  re-runs against an existing DB.
- Rejects on `req.onblocked` (another tab still holds v1 open) so the boot
  `idbGet` doesn't hang forever — the boot reads are wrapped in try/catch and
  degrade to "no creds" (login screen) instead of a blank hung screen.
- Sets `db.onversionchange = () => db.close()` on the open connection so a
  *future* tab's upgrade isn't blocked by this one.

**Lifecycle rules:**

- `clearStorage` (token-expiry logout) drops `auth_creds` but LEAVES the
  scan queue intact — an unsent receipt must survive a 401.
- `clearAllStorage` (Settings → Reset, via `ResetSettingsClicked`) explicitly
  `clear()`s the `scanQueue` store too (self-guarded for a DB still at v1).
- A failed `saveScanItem` `put` (e.g. `QuotaExceededError`, which the generic
  `idbSet` silently swallows) is surfaced through the `scanItemSaved` ack so
  Elm flips `persistError` on the item.
- A boot probe (trivial `getAll` of `scanQueue`) plus a best-effort
  `navigator.storage.persist()` report device storage availability via
  `storageStatus` → `AuthState.storageAvailable` (Private Browsing / Lockdown
  Mode read as unavailable).

**Honest persistence contract (iOS/WebKit — #377):**

`navigator.storage.persist()` resolves `true` only when the UA grants
*persistent* storage via the installed-app heuristic. On iOS/iPadOS this means
the user must have added Ternpike to their Home Screen — a plain Safari tab will
almost always return `false`.

| Context | Storage eviction | `persist()` result |
|---|---|---|
| **Installed PWA (standalone, iOS 17+)** | Persistent — survives indefinitely | `true` (granted by installed-app heuristic) |
| **Safari tab (in-browser)** | WebKit's ~7-day eviction window when the site hasn't been visited | `false` (not granted) |
| **Chrome/Android (installed PWA)** | Persistent | `true` |
| **Private Browsing / Lockdown Mode** | None — IndexedDB is unavailable | `false` (probe fails) |

Note: Safari and the installed PWA on the same device use **separate storage
partitions** — a queue item saved in a Safari tab is NOT visible in the installed
app and vice versa. This is a WebKit partition boundary, not a Ternpike choice.

The `storageStatus` port payload (`{ available, installed, isIos, persisted }`)
maps to three `AuthState` fields:

- `storageAvailable : Bool` — `False` in Private Browsing / Lockdown Mode.
- `storagePersisted : Bool` — `False` when `persist()` was denied; warns the
  user that receipts may be evicted after ~7 days of inactivity.
- `pwaInstalled : Bool` — `True` when running in standalone (installed-PWA) mode.
- `isIosDevice : Bool` — `True` on iOS/iPadOS; gates the static
  Add-to-Home-Screen nudge (iOS never fires `beforeinstallprompt`).

When `storagePersisted == False` and deferred items exist, the confidence badge
(`viewDeferredBadge` in `Pages.Scan`) switches to a warning tone and appends
"may not survive a week offline unless installed." When additionally
`isIosDevice == True && not pwaInstalled`, it shows the Add-to-Home-Screen
instructional line.

### Server-side user record (`UserRecord` in `server/users.js`)

Lives in `TIERS_KV` under `user:<lowercased-email>`. Alphabetized fields:

| Field | Type | Notes |
|---|---|---|
| `createdAt` | ISO string | Preserved across upserts. |
| `email` | string (lowercased) | Primary key. |
| `referredBy` | string \| null | Lowercased email of the referrer, set on first signup when `?ref=qr-user-XXXX` was carried through. Write-once — `upsertUser` preserves the existing value on every subsequent write. Phase 1 is data-only; bonus issuance is a follow-on track. |
| `stripeCustomerId` | string \| null | Set by `/billing/checkout`. |
| `subscriptionId` | string \| null | Set by Stripe webhook. |
| `subscriptionStatus` | enum \| null | `active`/`canceled`/`past_due`/`trialing`. |
| `tier` | enum | `tern`/`osprey`/`trailblazer`. |
| `trailblazerNumber` | int \| null | 1..500, set when `/trailblazer/confirm` succeeds. |
| `trailblazerPurchasedAt` | ISO string \| null | Companion to `trailblazerNumber`. |
| `updatedAt` | ISO string | Stamped on every write. |

### Slug → email reverse index

`upsertUser` also writes a paired `slug:<slug>` entry pointing at the user's lowercased email, where `slug = 'user-' + shortHash(email)`. `shortHash` is FNV-1a 32-bit hex sliced to 4 chars, implemented byte-for-byte in both `src/Data/UserId.elm` and `server/users.js` (the values are pinned by tests on both sides; drift breaks attribution silently).

The index is the lookup for `/auth/verify-code` to resolve a `ref=qr-user-XXXX` to the referrer's email. Writes are idempotent (the mapping is deterministic from the email), so existing users predating the index get backfilled the next time any code path touches their record (billing webhook, `/me` refresh, `/auth/verify-code`).

### Referral attribution flow

The QR/share URL is `https://api.ternpike.com/qr/user-XXXX?via=share`. The `/qr/:slug` redirect (`server/qr.js`) appends `&via=share` to the marketing redirect when set; `bumpCounter` rolls up a `byVia: { qr, share }` count so analytics can split QR scans from social-share clicks.

The marketing page (`marketing/src/main.js`) captures `?ref=qr-user-XXXX` on landing into a `.ternpike.com` root-domain cookie (`tp_ref`, 30-day max-age). When the recipient lands on `app.ternpike.com`, `src/main.js` promotes the cookie value into IDB under `pending_ref` (so it survives cookie expiry and Safari ITP), passes it to Elm via flags as `pendingRef`, threaded through `GuestState.pendingRef`, and included in the body of the POST to `/auth/verify-code` as `ref`. The server's `resolveReferrer` calls `getEmailBySlug` to look up the referrer's email and stamps `referredBy` on the new `UserRecord` — guarded against self-referral and unknown slugs.

---

## PouchDB: what it is and how it plugs in

PouchDB is a client-side database that stores documents in IndexedDB (the
browser's built-in key-value store). It has a built-in sync protocol compatible
with CouchDB. The app keeps a local PouchDB instance (`'ternpike'`) that syncs
bidirectionally with `https://couch.ternpike.com/<dbName>`.

Because PouchDB is JavaScript-only, Elm talks to it through **ports**.

### Port overview

All `port` declarations live in `src/Ports.elm` (the app's single `port
module`, extracted from `Main` in #368) so feature modules like `Page.Scan`
can call the ports they need without importing `Main`. Ports merge into one
app namespace on the JS side, so `app.ports.<name>` is unaffected by the
move.

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
message maps the `Bool` through `networkStateFromOnline` and updates
`network : NetworkState` on whichever model branch is active. Before that
first report lands, `network` is `Unknown` (offline-safe).

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
| `SaveMilepostProgress` | `milepost::progress` JSON | Upsert the earned-achievement singleton on the personal handle (no `target` — it's always personal-DB). `upsertDoc` resolves the current `_rev` itself. |
| `OpenSharedTrip` | `{ flockId, dbName }` | Open a shared-trip-local PouchDB handle immediately (used by the New Trip flow after `POST /sharedtrips` succeeds — avoids racing the personal-DB sync that would otherwise hydrate the handle via `reconcileFlocks`). Idempotent. |

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

### Durable scan-queue ports (#371)

Separate from the `pouchOut`/`pouchIn` pair, the offline scan queue has its own
ports (declared in `src/Ports.elm`, handled in `src/main.js`):

| Direction | Port | Payload | What it does |
|---|---|---|---|
| Elm → JS | `loadScanQueue` | — | `getAll` the `scanQueue` store; reply via `scanQueueLoaded`. Fired from `init`'s authed branch + the `VerifyCodeResult`/`MagicVerifyResult` re-login arms. |
| JS → Elm | `scanQueueLoaded` | array of `scanItemEncoder` docs | Decoded item-by-item (bad docs quarantined) → `reconcileHydratedQueue` → `Data.Scan.mergeHydratedQueue` (`Dict.union inMemory (hydrated minus tombstones)`) into the live queue. |
| Elm → JS | `saveScanItem` | one `scanItemEncoder` doc | `put` it; ack via `scanItemSaved`. Surfaces `QuotaExceededError` (unlike `idbSet`). |
| JS → Elm | `scanItemSaved` | `{ id, ok, error }` | `ok:false` flips `persistError` on the item. |
| Elm → JS | `deleteScanItem` | the durable `scan::…` id (String) | `delete` one row; fire-and-forget, idempotent (absent-key delete is a no-op). Callers: the `ExpenseChanged` submit-clear echo, the multi-receipt split source, and `ClearDoneItems` (#374). |
| JS → Elm | `storageStatus` | `{ available, installed, isIos, persisted }` | Boot probe + best-effort `navigator.storage.persist()`. `available` → `AuthState.storageAvailable`; `persisted` → `storagePersisted`; `installed` → `pwaInstalled`; `isIos` → `isIosDevice`. See "Honest persistence contract" above. |

**Delete semantics (#374).** Every delete is really "absence," and a re-delivered
change-feed echo or a late `getAll` could otherwise resurrect a deleted receipt.
The `ExpenseChanged` change-feed echo OWNS all submit-clears, idempotently: at
`GotSubmitTime`'s `FreshForm` branch the just-submitted scan item is tagged with
the deterministic `expectedExpenseId` (`expense::<iso>::<8-of-millis>` — only
computable from the `posix` that exists there); when an expense arrives over the
change feed (the local save's echo, or a later sync pull) whose `_id` matches,
`Main.clearSubmittedScanItem` (`Data.Scan.idsWithExpectedExpense`) removes the
item from the queue, deletes its durable row, and tombstones its id. The
`EditForm` path emits `SaveAmend` (no `ExpenseChanged`) and is out of scope for
echo-delete. `scanTombstones : Set String` on `AuthState` holds ids deleted
since the last `loadScanQueue`; `mergeHydratedQueue` subtracts them so a
hydration-window race can't resurrect a just-removed card. Tombstones are
in-memory only (never persisted) — a fresh boot starts empty because the durable
store no longer holds the deleted docs.

---

## Startup sequence

```
Browser loads
  └─ main.js reads IndexedDB
       ├─ auth_creds  (email, password, dbName, tier, subscriptionStatus, trailblazerNumber)
       └─ anthropic_key
  └─ Elm.Main.init receives flags
       ├─ If no creds → GuestModel FreshGuest
       └─ If creds found → AuthModel (initial AuthState, no data fetched yet)
            ├─ fetchMe (GET /me) fires immediately
            │    └─ refreshes tier + subscriptionStatus + trailblazerNumber
            │       from the server, re-persists Creds to IndexedDB
            ├─ loadScanQueue port fires immediately (#371)
            │    └─ JS getAll's the scanQueue store → scanQueueLoaded →
            │       decode + reconcileHydratedQueue + mergeHydratedQueue
            │       (tombstone-aware union) → as_.scanQueue.
            │       Device-local, no PouchDB race, so it's safe on the
            │       critical path. Also re-fired from the in-SPA re-login
            │       arms (VerifyCodeResult / MagicVerifyResult), since
            │       toAuthState clears scanQueue and init never re-runs.
            └─ startSync port called immediately
                 └─ pouch.js begins db.sync(remote, { live, retry })
                      └─ On first settled sync edge → Elm receives SyncStateMsg
                           └─ update sends GetAllTrips via pouchOut
                                └─ pouch.js queries allDocs for type:"trip"
                                     └─ pouchIn receives TripsFetched
                                          └─ handleTripsFetched populates as_.trips,
                                             then loadAllTripExpenses fires
                                             GetTripExpenses for EVERY trip not yet
                                             cached (Decision 2 of #408 — milepost
                                             evaluation needs all trips' expenses,
                                             not just the visited one)
                                               └─ once loadingTrips drains to empty,
                                                  ReconcileMileposts fires:
                                                  evaluate the catalog, union any
                                                  newly-earned markers into
                                                  milepost::progress (silent seed on
                                                  first load, write-on-change after)
```

Data is **not** fetched on login — it waits for the first sync to settle.
This prevents a race where Elm reads stale local data before the sync pulls
down remote changes.

**Milepost evaluation needs a full expense load (#408).** Route-driven lazy
loading (below) only fetches the trip the user is looking at, but the
count/dollar/streak achievement markers need every trip's resolved expenses. So
after the initial `GetAllTrips` settles, `loadAllTripExpenses` issues a one-time
`GetTripExpenses` for every trip not already in `tripLoaded`/`loadingTrips`. It
is fully idempotent and never duplicates the lazy per-route fetch. When that
wave drains (`loadingTrips` empty), `ReconcileMileposts now` runs
`Data.Milepost.evaluate (Main.milepostInputs as_ now)` — the projection walks
all trips, resolves each through `Data.Entry.resolve` (amendments folded, voids
removed), and flattens to `Data.Milepost.ExpenseFacts` (`zone = Time.utc` in
v1). On a first load (`milepost == NotLoaded`) it seeds `milepost::progress`
from the current backlog silently (no toast); on later passes it writes the
union of `earnedNow \ persisted` only when that set is non-empty (markers never
un-earn, and the write is skipped when nothing changed so the oscillating
`Synced` edge doesn't churn the doc). This is local-first — it is NOT gated on
remote sync success.

The `/me` refresh is the one exception that fires immediately on `AuthModel`
construction: it's HTTP, not PouchDB, so there's no race with replication; the
response refreshes `tier`, `subscriptionStatus`, and `trailblazerNumber` on
both `AuthState` and the persisted `Creds` blob. Errors are swallowed —
`/me` is a refresh path, not a hard requirement; the cached `Creds` is
already good enough to render until the next call retries (next cold boot,
or the Settings billing UI's `?checkout=success` return).

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
"expense"         -> ExpenseChanged          (Expense.decoder value)
"amend"           -> AmendChanged            (Amendment.decoder value)
"milepostProgress"-> MilepostProgressChanged { progress, rev }
"trip"            -> TripChanged             (Trip.decoder value)
"void"            -> VoidChanged             (Void.decoder value)
```

The `milepost::progress` singleton is special-cased in `pouch.js`'s
`wireChanges`: it's routed as a `DbChange` like the rest, but its payload keeps
`_rev` (every other doc has `_rev` stripped) so the `MilepostProgressChanged`
handler can capture the revision into `MilepostState` for the next write.

Each branch inserts or replaces the doc in the appropriate Dict:

```elm
ExpenseChanged (Ok expense) ->
    ( AuthModel { as_ | expenses = Dict.insert (ExpenseId.toString expense.id) expense as_.expenses }
    , Cmd.none
    )
```

This is how synced remote changes appear in the UI without a page reload.

---

## Receipt scanning + OCR

The BYO/hosted credential decision is modelled by `Data.OcrPath` (#219):

- `Data.AnthropicKey` — opaque newtype wrapping the user's BYO key string.
  `AppConfig.anthropicKey : Maybe AnthropicKey` (replaces the former `String`
  sentinel; `Nothing` means "no key configured").
- `Data.OcrPath.OcrPath` — sum type with three constructors: `ByoPath AnthropicKey`
  (BYO key present), `HostedPath` (paid tier, no BYO key), `Unscannable` (Tern,
  no BYO key). `OcrPath.resolve` is the single decision point; consumers
  pattern-match on it.

The Scan/OCR feature's update logic lives in its own module,
`Page.Scan` (carved out of `Main.updateAuth` in #368 — see "Nested update
dispatch" below). The Scan messages live in `Msg.Scan` and nest under
`AuthMsg_`'s single `ScanMsg Msg.Scan.Msg` variant; `Main.updateAuth`
routes them with one arm that projects the narrow `Page.Scan.Model` slice
out of `AuthState`, runs `Page.Scan.update`, merges the slice back, and
lifts the returned `Effect` via `Effect.perform as_.key` (the `Effect`
seam — see "Nested update dispatch" below). The helpers named below all
live in `Page.Scan`.

Receipts go through Anthropic's vision model: `Page.Scan.update` emits an
`Effect.MakeOcrCall { backendUrl, body, itemId, path }` whose `body` is built by
`Page.Scan.ocrRequestBody`, and `Effect.perform` picks the transport from the
`OcrPath` — direct Anthropic `Http.request` for `ByoPath`, the `scanProxyOut`
port for `HostedPath`, nothing for `Unscannable`. The
system prompt (`Page.Scan.ocrSystemPrompt`) asks Claude to extract one JSON
object per receipt in the image, with these fields (every one optional —
Claude returns `null` for whatever it couldn't read):

- `address` — street address printed on the receipt (added in #150).
- `amount`, `category`, `date`, `longNote`, `merchant`, `note`,
  `paymentMethod`.

The raw OCR result lands on `ScanItem.ocrData : Maybe OcrData`
(`src/Data/Scan.elm`). On batch images, `Page.Scan`'s `GotOcrResult` handler splits one
source item into multiple `ScanReady` items, one per OCR result. The
Scan queue UI (`src/Pages/Scan.elm`) surfaces all of this — amount,
category pill, merchant, the extracted date with provenance ("📅 May
21" vs. "📅 Today · no date on receipt"), and the address — so a week's
worth of batch-scanned receipts are visibly distributed across the
right days before you tap Review on each one.

#### Durable scan queue (#370 foundation)

The `ScanItem` type/codec layer is built to survive a reload so an
offline capture isn't lost. The data-model pieces (the offline *behavior*
that builds on them — IndexedDB store + hydration #371, offline capture
#372, reconnect orchestration #373 — is documented under "Reconnect
orchestration" below and the `scanQueue` IndexedDB store section):

- **`ScanStatus` adds `ScanDeferred`** (alphabetized:
  `ScanDeferred | ScanProcessing | ScanQueued | ScanReady | ScanSubmitted`)
  — a receipt captured offline (or before the network state is known)
  whose image is persisted but for which no OCR has run.
- **`ScanItem` gains** (alphabetized) `draft : Maybe DraftFields`,
  `expectedExpenseId : Maybe String`, `lastError : Maybe String`,
  `persistError : Bool`, `retryCount : Int`, `schemaVersion : Int`.
  `DraftFields` is a **`Maybe`-typed** record (not a `PendingEntry`
  clone) — `Nothing` means "user hasn't set this field," so a persisted
  draft never clobbers OCR output with a defaulted `Fuel`/today (the #93
  sentinel lesson).
- **Durable id `scan::<millis>::<seq>`** (`Data.ScanItemId`), where
  `<seq>` is a monotonic per-session counter on `AuthState.scanSeq`
  (collision-free across same-millisecond captures, unlike a per-batch
  index). Mint via `Scan.mintId millis seq`; multi-receipt split
  children use `Scan.childId parentId i` (`scan::<parentId>::<i>`). The
  id is persisted to the offline store but, like before, never reaches
  PouchDB.
- **`Scan.scanItemEncoder` / `scanItemDecoder`** (de)serialize a
  `ScanItem` losslessly for the durable store, reusing the field codecs
  (`Money`, `DateField`, `Category.label`, `PaymentMethod.toString`,
  the new `GeoPoint.encoder`). The decoder is tolerant: a missing
  `status` defaults to `ScanDeferred`, missing `draft` to `Nothing`,
  missing `schemaVersion` to `currentSchemaVersion` — and the queue is
  decoded item-by-item so one bad doc can't fail the whole load.
- **`Scan.reconcileHydratedQueue`** normalizes the queue at boot: reset
  reload-orphaned in-flight statuses (`ScanProcessing`/`ScanQueued`) to
  `ScanDeferred`, **preserve `ScanReady` and `ScanSubmitted`**. It does
  NOT decide delete-vs-keep for submitted items — at boot
  `AuthState.expenses` is empty, so the PouchDB change echo owns that.

When OCR fails (HTTP error from Anthropic, refusal, unparseable JSON,
or no receipts detected), the failure reason is captured on
`ScanItem.ocrError : Maybe String` and rendered on the Scan card below
the "OCR failed — fill manually" header. `Effect.perform`'s `MakeOcrCall`
interpreter uses `Http.expectStringResponse` (not `expectString`), with an
internal response parser in `Effect`, so non-2xx bodies are preserved — that's where Anthropic's `error.message` lives, and
surfacing it lets the user tell a rate-limit from a corrupt-image from
a paymentMethod the decoder didn't recognize.

Every picked image goes through the `prepareOcrImage` /
`ocrImagePrepared` port pair (`src/main.js`) before reaching the OCR
call. Anthropic caps base64 image payloads at 5 MiB and phone JPEGs
routinely run 6–8 MB, so without this every real-world receipt photo
would 400. The JS handler draws to a canvas at max 1568px on the long
edge (Claude's recommended size), iterates JPEG quality from 0.85
down, then shrinks dimensions if needed, until the encoded byte count
fits `ocrMaxBase64Bytes` (4 MiB — comfortably under the 5 MiB cap).
The resized data URL replaces `ScanItem.imageUrl` and feeds the OCR
call; EXIF GPS extraction runs on the *original* data URL in parallel
(exifr needs the unmodified bytes).

#### Reconnect orchestration (#373)

Offline-deferred captures (`ScanStatus.ScanDeferred`, parked by the
offline-capture path in `Page.Scan` `GotFileUrl` / `Data.Scan.captureRoute`)
get OCR'd when connectivity returns — driven off the **proven `Synced`
sync edge, not `navigator.onLine`**:

- **Trigger.** `Main.updateAuth`'s `SyncStateMsg` handler computes
  `syncedEdge = state == Synced && as_.syncState /= Synced` — a genuine
  transition INTO `Synced`, which proves a real CouchDB round-trip and
  lets the `AuthExpired` logout win the race. On that edge it dispatches
  `Msg.Scan.RetryDeferredScans` through the normal `ScanMsg` path (via a
  `Task.succeed ()` self-message). `Synced` oscillates
  (Synced → Syncing → Synced each replication cycle) so this fires
  repeatedly; the handler is **idempotent** (see the gate below).
- **Concurrency gate.** `AuthState.ocrInFlight : Set String` (projected
  into the `Page.Scan.Model` slice, **in-memory only — never persisted,
  never in the codec**) is the set of ids whose OCR is in flight.
  `Page.Scan.dispatchOnReconnect` picks candidates via the pure
  `Data.Scan.reconnectCandidates tierCap inFlightCount excluded queue`:
  `slots = max 0 (tierCap − inFlightCount)`, candidates are **`ScanDeferred`
  only** (never processing/ready/submitted), excluding ids in
  `ocrInFlight`-equivalent `excluded`, excluding `persistError` items, take
  `slots`. `tierCap` is **1 for free `Tern`, 3 for paid** (resolved from the
  active trip's effective tier, falling back to the user's tier — same
  pattern as `geocodeDispatch`). For each chosen item: flip
  `ScanDeferred → ScanProcessing`, add the id to `ocrInFlight`, persist via
  `Effect.SaveScanItem`, and fire the OCR pipeline (`Effect.PrepareOcrImage`
  → `MakeOcrCall`). With `ocrInFlight` already at the cap, `slots == 0` →
  no candidates → no effects, which is what makes the oscillating edge safe.
- **Dispatch-next.** Both terminal OCR handlers (`GotOcrResult` BYO and
  `ScanProxyResult` hosted) funnel through `Page.Scan.finishOcr`: remove the
  id from `ocrInFlight`, write the result, then re-run the gate to fill the
  freed slot from the remaining `ScanDeferred` backlog. The just-handled id
  is `excluded` from that same-tick refill so a flap-requeued item waits for
  the next `Synced` edge instead of busy-retrying.
- **Transient vs terminal failure.** `Data.Scan.OcrFailureKind`
  (`Transient | Retryable | Permanent`) decides whether to spend the retry
  budget (`Data.Scan.maxOcrRetries == 3`). `Data.Scan.hostedFailureKind`
  (raw status: `0` = connection died = `Transient`; `429`/`500`/`502`/`503` =
  `Retryable`; else `Permanent`) and `Data.Scan.byoFailureKind` (recovers the
  class from the sentinel substrings `Effect.ocrResponseToResult` already
  collapsed the BYO `Http.Error` into) classify each path. **Only a
  `Retryable` real server response bumps `retryCount`;** a `Transient` flap
  (`NetworkError_` / `Timeout_` / status 0) returns the item to
  `ScanDeferred` WITHOUT incrementing (a flap must not burn the budget,
  recorded on `lastError`). At `maxOcrRetries` a `Retryable` goes terminal
  (`ScanReady` + `ocrError`); a `Permanent` failure goes terminal immediately.
- **Unscannable-on-reconnect keeps the draft.** If on reconnect the item
  re-resolves to `OcrPath.Unscannable` (tier lapsed / BYO key removed since
  capture), `dispatchOne` does NOT spend a slot: it flips the item to
  `ScanReady` and folds `item.draft` into `item.ocrData`
  (`draftIntoOcrData` — merge-with-`Nothing`-OCR is identity; only fields the
  user actually set override) so the review form still shows the
  offline-typed fields. The receipt is never stranded.

### Location precedence

`Data.Location.LocationSource` has four constructors, in preference
order:

1. `ExifGps` — coordinates pulled from the receipt photo's EXIF GPS
   tag. Most accurate (the photo was taken at the receipt's location).
2. `Geocoded` — paid-tier `POST /geocode` resolved the OCR'd address
   to lat/lon via the Google Maps Geocoding API. Wins over browser geo
   / manual when EXIF is absent; EXIF always trumps it. See "Geocoding"
   below.
3. `BrowserGeo` — `navigator.geolocation` fired when the user landed
   on the Add tab. Fallback when EXIF and Geocoded both miss.
4. `ManualPin` — the user tapped the map picker.

The `GotGeocodeResult` handler in `Main.elm` enforces the EXIF-wins
rule: it only promotes an item to `LocationGot _ Geocoded` if the
current `locationState` is not already `LocationGot _ ExifGps`.

### Geocoding

The `POST /geocode` Worker endpoint (`server/geocode.js`, #152, #169)
is a paid-tier address → lat/lon proxy. We use Google Maps Geocoding
API rather than letting browsers hit Google directly so the API key
never reaches the client and we get one consistent cache + rate-limit
story across users.

| Concern | Where it lives |
|---|---|
| Auth | HTTP Basic with HMAC-derived password (same scheme as `/sharedtrips`). Lives in `server/auth.js`. |
| Tier gate | `getTier(env, email)` → `isPaidTier(tier)` → 403 `paid_tier_required` for Tern. |
| Per-user rate limit | `GEOCODE_RL_KV`, key `rl:<email>`, JSON token bucket `{count, windowStart}`. 100 calls per rolling 60s window — sized for typical batch-scanned road-trip volume (30–50 receipts) plus runaway-loop defense. Over the cap → 429 `rate_limited`. |
| Response cache | `GEOCODE_CACHE_KV`, key `addr:<sha256(normalized address)>`. 30d for hits, 1d for no-match. Shared across users (address resolves to the same point regardless of who asks). |
| Upstream | `${GOOGLE_GEOCODING_BASE_URL or default}/maps/api/geocode/json?address=…&key=$GOOGLE_GEOCODING_API_KEY`. Key set via `wrangler secret put` (see issue #171 for provisioning). |
| Response | `{ ok: true, lat, lon, source: 'google' }` on hit; `{ ok: true, lat: null, lon: null }` on `ZERO_RESULTS`; `502 { ok: false, error: 'upstream' }` on any other Google status (`OVER_QUERY_LIMIT`, `REQUEST_DENIED`, `INVALID_REQUEST`, `UNKNOWN_ERROR`) or HTTP error. Google returns `lng`; we translate to `lon` at the boundary. |
| Cost model | Free tier 10k requests/month, then ~$5 per 1k. With the cache, distinct addresses (not receipts) drive the bill. See issue #172 for the paid-user-vs-cost curve and the switch-to-self-hosted-Nominatim / LocationIQ thresholds. |

The client side is `src/Http/GeocodeApi.elm`. `Main.GotOcrResult` fires
one `geocode` Cmd per touched scan item that has a non-empty extracted
address on a paid-tier trip; `GotGeocodeResult` applies the result with
the precedence rule above.

Free-tier (Tern) users get the address as plain text on the expense and
can pin manually via the Add page map picker — the geocode Cmd is never
fired for them.

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
longNote, paymentMethod, geoPoint) onto a fresh `ExpenseId` and `createdAt`,
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
    { address   : Maybe String     -- merchant address (#150)
    , amount    : Maybe Float      -- only the fields the user changed
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
DB (`ternpike` ↔ `ternpike-<email>`) plus one entry per shared trip the user
belongs to (`ternpike-<dbName>` ↔ `<dbName>`). Each handle
runs its own `db.sync(remote, { live: true, retry: true })`; CouchDB's
`_security` doc gates membership per remote, so we don't reimplement
permission routing in JS.

```js
// pouch.js
const handles = new Map() // localName -> { local, remote, sync, changes, flockId? }
handles.get('ternpike')   // personal handle, flockId === null
```

Solo users (no shared trips) keep exactly one handle — no regression on the
single-user path.

### Startup sequence

1. Open the personal local DB and start its sync.
2. On the first non-error `paused` event (PouchDB's "fully caught up"
   signal), `db.get('user:sharedtrips')` from the personal DB. If 404, no
   shared trips — done.
3. For each `{ flockId, dbName }` entry in the `flocks[]` array of the `user:sharedtrips` doc, open a local DB
   named `ternpike-<dbName>` and start syncing it to `<dbName>` using
   the same CouchDB credentials (one user, many DBs).
4. The personal handle watches its own `changes` stream for `user:sharedtrips`
   updates; reconciliation opens new handles and closes departed ones
   without a reload. Server admin-writes `user:sharedtrips` on
   create/join/leave, so the change stream is the trigger.

### Port message fan-out

- `GetAllTrips` queries every handle in parallel, merges by `_id`
  (globally unique — timestamp + nonce), and tags each trip with
  `flockId` (`null` for personal, the shared-trip id otherwise). The field is
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
  user to the login screen. We don't try to keep some shared trips alive
  while others are dead.
- `clearStorage` / `clearAllStorage` cancel every sync, close every
  remote, and `local.destroy()` every local DB — so a sign-out / 401
  wipes IndexedDB for all shared-trip DBs, not just the personal one.

### Shared trips in Elm

The Elm-side types for the multi-DB world live in four modules:

- `Data.SharedTripId` — opaque wrapper around a 12-character lowercase hex
  nonce. `fromString` validates the shape and returns `Maybe SharedTripId`.
- `Data.SharedTrip` — the `SharedTrip` record. Members are modeled as
  `billingOwner :: otherMembers` so "the owner is always a member" is
  a structural invariant; `members : SharedTrip -> List UserId` derives the
  provably-non-empty flat list on demand. On the wire (`sharedtrip:meta`
  doc) the field is flat — the decoder picks the owner out and
  hard-rejects (`Json.Decode.fail`) any doc where `billingOwner` is
  not in `members`. The CouchDB document id is the literal marker
  string `sharedtrip:meta` (one such doc per per-shared-trip DB), so the
  per-shared-trip identifier rides on a separate `flockId` field that
  `Data.SharedTrip.decoder` reads via `Data.SharedTripId.decoder`.
- `Data.SharedTrips` — `Dict String SharedTrip` keyed by `SharedTripId.toString`,
  lives at `AuthState.sharedTrips`. `ownedBy` / `joinedBy` filter by user.
- `Data.SharedTripUi` — UI state for the shared-trip settings modals
  (`SharedTripUiState`), lives at `AuthState.sharedTripUi`. Each
  `SharedTripModal` variant carries its own
  `request : RemoteData Http.Error <Response>` so the create / invite /
  leave / transfer HTTP calls have independent busy + error state — no
  shared `inFlight : Bool` at the parent level.

`Trip.flockId : Maybe SharedTripId` is in-memory only: `Trip.encoder`
deliberately omits it and `Trip.decoder` only reads it if present.
`src/pouch.js` is the source of truth — it tags trip docs with the
handle's `flockId` at the port boundary on the way in from
`GetAllTrips` and from the live-changes feed. Storing it inside the
doc would let it diverge from the DB it actually lives in.

Startup hydration is JS-driven: after the personal DB's first
non-error `paused` event, `pouch.js` reads `user:sharedtrips` from the
personal DB and (a) opens / closes shared-trip handles via `reconcileFlocks`,
(b) emits `SharedTripsReconciled flockIds` so Elm can drop cached entries
for shared trips the user has left, and (c) fetches each shared trip's
`sharedtrip:meta` doc and emits it as `SharedTripMeta`. The Elm decoder turns
that into a `SharedTrip` and inserts into `AuthState.sharedTrips`. Subsequent
live changes to `sharedtrip:meta` docs are routed up as `SharedTripMeta` events
too, so membership/billing transitions converge without a reload.

The `Data.Pouch` inbound protocol carries the new tags:

- `SharedTripsReconciled (List SharedTripId)` — replaces the known-shared-trip set.
- `SharedTripMetaChanged SharedTrip` — upserts one shared trip.

### Paid-feature gating: `Trip.effectiveTier`

Any predicate that asks "can the user do X on **this trip**?" must consult
`Trip.effectiveTier : Trip -> { a | sharedTrips, tier } -> Tier` (defined in
`Data/Trip.elm`), **not** `as_.tier` directly. The rule:

- **Personal trip** (`trip.flockId == Nothing`) → `as_.tier`.
- **Trip in a shared trip with `billingStatus == Active`** → `Osprey`. The shared trip's
  billing owner pays for the shared trip, and we don't carry the owner's exact
  tier locally — `Active` is sufficient evidence that they're at least
  `Osprey`. (`Trailblazer` is a billing distinction, not a feature one.)
- **Shared trip in `Grace` or `Frozen`** → falls back to `as_.tier`. The
  lapsed-billing banner handles user messaging.
- **Trip references a shared trip we don't yet have data for** → falls back to
  `as_.tier`, never crashes.

Two convenience wrappers — `Trip.canUseProxiedOCR` and `Trip.canBatchScan`
— resolve `Tier.isPaid (effectiveTier trip as_)` so call sites stay terse.

The opposite rule still holds: predicates that ask "is the **logged-in
user** paid?" (Settings tier badge, "Create shared trip" upgrade prompt, billing
screen) keep reading `as_.tier` directly. The headline UX — a Tern
invitee gets paid OCR inside a shared trip but stays Tern on personal
data — falls straight out of this split.

Server endpoints back paid features still re-check the actual tier
(caller's or shared-trip-owner's depending on the call). Client-side gating is
UX, not security.

### Shared trips settings UI

`src/Pages/Settings/SharedTrips.elm` is the **manage** surface — invite,
leave, transfer ownership for shared trips the user already belongs to.
Modals and inline errors sit on `AuthState.sharedTripUi : Data.SharedTripUi.SharedTripUiState`
and the HTTP wrappers for `inviteToSharedTrip`, `joinSharedTrip`, `leaveSharedTrip`,
`transferOwnership` live in `src/Http/SharedTripApi.elm`.

**Creation does not happen here.** The unified "+ New shared trip"
flow on the Trips page is the only entry point for creating a new
shared trip (see the Trip + Ledger UI section below). If the user has zero
shared trips, this section renders an empty-state card pointing back at
`/trips` rather than offering its own Create button.

Invite links land on a new `RouteJoinSharedTrip String` route at
`/sharedtrips/join?token=<jwt>` (path-segment-safe — the token has no `:`
collisions). Signed-out users get the token parked on
`GuestState.pendingJoinToken` and the verify-code success path
redirects to `/sharedtrips/join?token=…` instead of `/trips`, so the
invite is consumed immediately after auth. The signed-in view
(`src/Pages/JoinSharedTrip.elm`) decodes the JWT payload locally for
display only — the server checks the signature — and surfaces a
friendly "this invite is for someone else" error when the token's
`inviteeEmail` doesn't match `creds.email`.

### Trip + Ledger UI in shared trips

The day-to-day shared-trip chrome lives in five places (#63):

- **Trip card / hero** — `src/Pages/Trips.elm` overlays a
  `UI.SharedTripBadge` and an overlapping `UI.Avatar.viewStack` on the
  meta row, only for trips with a `flockId`. Personal trips render
  unchanged.
- **Ledger row** — `src/Pages/Ledger.elm` resolves the active trip's
  shared-trip membership into `Dict String SharedTripMember` and threads it to
  `viewEntryRow`, which renders an initials avatar + first name
  (Variant A) on the existing `mt-1.5 flex items-center gap-2` band.
  Personal trips pass `Dict.empty` so the chip never renders.
- **Add / Scan context strip** — `src/Pages/Add.elm` and
  `src/Pages/Scan.elm` render a persistent "ADDING TO / Trip Name"
  strip at the top of the form when the active trip belongs to a
  shared trip, plus a `visible to <first names>` caption under the amount
  input. The caption collapses to `+ N more` when the shared trip has
  more than three members.
- **Trip Picker drawer** — `src/UI/TripPicker.elm` decorates each
  candidate row with the shared-trip badge and avatar stack.
- **New Trip dialog** — `src/Pages/Trips.elm` `viewTargetPicker` asks
  "WHO'S ON THIS TRIP?" with one tile per option:
  - **Just me** (default) — personal trip, written to the user's
    solo PouchDB.
  - **One tile per owned shared trip** (`SharedTrips.ownedBy currentUser`) —
    writes the trip into that existing shared trip's local DB.
  - **+ New shared trip** — the unified shared-trip-creation entry point.
    Expands inline to an emails chip-input + an `Advanced — Group
    Name` reveal (defaults to the trip name; the override matters
    when the user wants a reusable group across multiple trips).
    Tern users see this tile but selecting it surfaces a
    contextual upgrade prompt; the form's Create button stays
    disabled until they pick a different tile or upgrade. This
    replaces the old standalone Settings → "Create Shared Trip" button.

  The picker writes to `TripForm.target : Data.Trip.CreateTarget`
  (`ToPersonal | ToExistingSharedTrip SharedTripId | ToNewSharedTrip NewSharedTripDraft`).
  `CreateTarget` is form-only — by the time the trip actually gets
  written to PouchDB, the orchestration in `Main.elm`'s submit
  handler has resolved any `ToNewSharedTrip` to `ToExistingSharedTrip <newId>`
  by sequencing `Http.SharedTripApi.createSharedTrip` → `Cmd.batch` of
  `OpenSharedTrip` port message + `Time.now` + fan-out
  `Http.SharedTripApi.inviteToSharedTrip` calls.

  Invite failures are non-blocking — the user can re-invite from
  Settings if a specific email bounced (server returns 409 for
  duplicates, the standard signal). Shared-trip-creation failures abort
  the whole submit and surface in the form's existing error block.

`UI.Avatar` hashes `UserId.toString` into a five-slot palette
(`bg-rust`, `bg-forest-mid`, `bg-moss`, `bg-rust-deep`, `bg-tan`) so
Alice keeps the same circle colour on every member's device. The
hash is pinned by `tests/UIAvatarTests.elm` so casual refactors of
the hashing function fail loudly.

### Tier resolution in shared trips

Paid features in a shared trip are gated by the **billing owner's** tier,
not the writer's, via `Data.Trip.effectiveTier`. The wrappers
`canUseProxiedOCR` / `canBatchScan` are convenience predicates over
the same answer — a free Tern member of an Osprey-owned shared trip gets
hosted OCR inside that shared trip's trips because that's the whole point
of pooling under one billing relationship. The tier-aware footnote
in `src/Pages/Scan.elm` is the first call site; the proxied-OCR
network path itself is still wired through #14.

`Data.Trip.TripTarget` is the routing tag carried on every outbound
`Save*` / `Get*` port message: `Personal` writes to the user's solo
PouchDB handle, `InFlock fid` writes to the matching shared-trip handle.
`Main.targetForTripId` resolves the tag by looking up the trip in
the loaded zipper; missing trips fall back to `Personal` so legacy
call sites stay safe. The encoder produces
`{ "kind": "Personal" }` or `{ "kind": "InFlock", "flockId": "..." }`,
matching the `targetHandle` reader in `src/pouch.js`.

### Billing-status UX contract

Every shared trip carries `billingStatus : BillingStatus` from
`sharedtrip:meta` (one of `Active`, `Grace`, `Frozen`) plus an optional
`billingLapsedAt : Maybe String` ISO timestamp. The server enforces
the same gate at the CouchDB `validate_doc_update` layer via `_design/sharedtrip_validator`
(#57); the client gates the UI so users don't submit and then see a 403.

  - `Active` — shared trip is writable. No banner, no disable.
  - `Grace` — billing has lapsed but writes are still allowed for the
    14-day grace window (mirrored by `UI.BillingBanner.graceWindowDays`).
    The full-bleed `UI.BillingBanner` shows on every shared-trip-scoped trip
    page (Ledger / Stats / Add / Scan) with status-specific copy and a
    days-remaining countdown derived from
    `(billingLapsedAt + 14 days) - today`. **Writes are pre-disabled**
    even during the grace window — the UX rule is "you can see what's
    coming but not pile on more entries while billing is sorted out."
  - `Frozen` — read-only indefinitely. Same banner, no countdown.

`Data.SharedTrip.isReadOnly : SharedTrip -> Bool` is the single source of truth
for the predicate (`True` for `Grace`/`Frozen`, `False` for `Active`).
Every disable site consults it: the Add submit button, the Ledger row
menu items (Duplicate / Move / Delete), and the Scan-tab dropzone. Do
not inline the predicate at call sites — go through `isReadOnly` so
the rule stays in one place.

The banner is inserted once in `Main.viewAuth` between the error
banner and the page content, so all four shared-trip-scoped tabs render it
identically without each page reproducing the chrome.

The role-aware copy matrix (owner / paid member / Tern member ×
Grace / Frozen) lives in `UI.BillingBanner.graceCopy` and `frozenCopy`
— the matrix is in the #64 issue body and transcribed verbatim into
those two functions. The "Transfer billing to me" CTA fires
`TakeOverBilling SharedTripId`, which calls
`Http.SharedTripApi.transferOwnership` with the calling user's email; the
button is hidden (not disabled) for Tern members since the
server would 403 their request anyway. The "Renew" CTA is a deep
link to `/settings#billing` — a placeholder until the dedicated
billing screen lands.

Settings/SharedTrips renders the smaller `UI.BillingBanner.viewInline`
chrome inside each shared-trip card so the status is also visible without
opening the shared trip's trip.

---

## Billing

The user-facing entry point to upgrade / manage subscription is the
**Plan** section at the top of `/settings`. It's rendered by
`Pages.Settings.viewPlanSection` (a small `PlanProps` projection of
`AuthState`) and switches on `AuthState.tier`:

  - **Tern** — three upgrade CTAs: "Osprey — $2.99 / mo",
    "Osprey yearly — $24 / yr (save $12)", and a Trailblazer button
    with a live "N of 500 left" countdown driven by
    `AuthState.trailblazerStatus` (a `RemoteData Http.Error TrailblazerStatus`). Buttons fire
    `BillingCheckoutClicked plan` where `plan` is the wire-form name
    (`"osprey_monthly" | "osprey_yearly" | "trailblazer"`).
  - **Osprey** — only "Manage billing", which fires
    `BillingPortalClicked`. If `subscriptionStatus` is anything other
    than `Active`, a chip surfaces it (e.g. "Past due" for `PastDue`).
  - **Trailblazer** — badge with `trailblazerNumber` ("Trailblazer
    #17 (of 500)"), lifetime-access copy, and a "View receipts /
    update card" portal button.

### Server wiring

All Stripe state is server-authoritative. The three endpoints (in
`server/billing.js`):

  - `POST /billing/checkout { plan }` — creates a Stripe Checkout
    session and returns `{ url }` for the client to
    `Browser.Navigation.load`. Trailblazer additionally reserves a
    slot in the `TRAILBLAZER_SLOTS` Durable Object (#16) before
    creating the Checkout, so the 500-cap is atomic against concurrent
    purchases. Two non-200 outcomes are special-cased on the client:
    `409 {ok: false, remaining: 0}` → `CheckoutSoldOut`,
    `403 {reason: "already_trailblazer"}` → `CheckoutAlreadyTrailblazer`.
    Existing Osprey re-requesting Osprey gets bounced to the Portal so
    Stripe handles the plan-swap rather than a duplicate subscription.
  - `POST /billing/portal` — opens the Stripe Customer Portal.
    Returns `{ url }`; same `load` redirect pattern.
  - `GET /billing/trailblazer-status` — public, cached 30s. Used by
    the Tern upgrade button's "N of 500 left" countdown. Fetched
    lazily on navigation to `/settings` in `fetchesForRoute` and
    cached on `AuthState.trailblazerStatus` so tab-flicking doesn't
    re-fetch.

### Wire-format-fidelity rules

  - **Stripe redirects use `Browser.Navigation.load url`, not
    `pushUrl`** — `load` is a full-page navigation so the Stripe-hosted
    Checkout page takes over the tab cleanly.
  - **Tier names** in code are `Tern` / `Osprey` / `Trailblazer`. Wire
    form is the lowercase `"tern" / "osprey" / "trailblazer"`. Plan
    names for `/billing/checkout` are `osprey_monthly`,
    `osprey_yearly`, `trailblazer`.
  - **Trailblazer is permanent.** Webhook + server code never downgrade
    a Trailblazer. If you find yourself writing `Trailblazer → Tern`
    flow, that's a bug.
  - **No Stripe SDK in the Worker.** `workerd` doesn't populate
    `process.env`, so the Stripe Node SDK can't read its `baseUrl` at
    module load time (same trap as the Resend SDK; see "Resend +
    workerd" in CLAUDE.md). Outbound calls go through raw `fetch` to
    `STRIPE_BASE_URL || 'https://api.stripe.com'`. Bodies are
    `application/x-www-form-urlencoded` per Stripe's REST conventions.
  - **Ternpike's Stripe secret never ships to the browser.** The
    client only sees Stripe-hosted URLs returned from the Worker; the
    actual key lives in a Worker secret.

### `?checkout=success` return

After Stripe redirects back to `/settings?checkout=success`, both
`init` (cold boot) and the `UrlChanged` handler:

  1. Show a "Welcome aboard! Your plan is active." toast.
  2. Fire `fetchMe` to refresh `AuthState.tier` /
     `subscriptionStatus` / `trailblazerNumber` from the server (the
     webhook has already mutated `TIERS_KV` by this point).
  3. `Nav.replaceUrl` to strip the query so a page refresh doesn't
     re-toast.

The `?checkout=canceled` variant just strips the query — no toast (the
user deliberately cancelled).

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

## Verification: the Verify layer

The `src/Verify/` modules port the [`verifiable-elm`](https://github.com/m0n01d/verifiable-elm)
"Surface" pattern: app behavior is verified by *observing it at the surface*,
hermetically and without the full-stack Playwright e2e harness (docker CouchDB +
wrangler + Resend), which is the historical source of CI flake.

**The Surface.** A `Verify.Contract.Surface` is `List ( String, String )` — one
typed value that drives *both* the rendered DOM (via `data-verify-*` attributes,
emitted by `Contract.verifyAttrs`) and the verification checks. No second schema
to drift.

**Units, fixtures, invariants** (`Verify.Spec`). A *unit* declares a
`surface : input -> Surface`, a list of *fixtures* (each a key-free `input` —
never the full `Model`, because `Browser.Navigation.Key` can't be constructed in
`elm-test`), and a list of *invariants* (`input -> Surface -> Maybe String`;
`Nothing` = holds). Every unit ships one `probe = True` fixture whose injected
regression must trip an invariant — proof the harness catches lies. The pilot
unit is `Verify.Specs.TierGating` (the "Share a trip" create-row gate).

**Two tiers, one verdict path** (`Verify.Runner` → `Verify.Core.Verdict`):

- **Pure tier** — `tests/MatrixTest.elm` runs every unit × fixture from
  `Verify.Registry.runAll` under `elm-test`. Hermetic, no backend, no `Main`.
  Non-probe fixtures must `Pass`; probes must `Fail`. This runs in CI via
  `.github/workflows/verify.yml` (the `npm test` job — the first elm-test CI
  gate in the repo).
- **DOM tier** — `/verify/:unit/:fixture` routes (`Data.Navigation.RouteVerify`,
  parsed in `Routing.elm`). `Main.init` short-circuits on these: it seeds a
  fixture `AuthState` via `toAuthState` (no `fetchMe`, no sync, no PouchDB), sets
  the stored route to `RouteSettings` so the real page renders with its
  `data-verify-*` attrs, and pushes the matrix to JS through the `verifyResults`
  port. `src/main.js` skips `attachPouch` for `/verify` paths and exposes
  `window.__verify` (`manifest()` / `runAll()` / `current()`). The Playwright
  spec `e2e/specs/verify.spec.ts` (config `e2e/verify.config.ts`, served by the
  dependency-free `e2e/verify-server.mjs`) reads the attrs + verdict. Run with
  `npm run verify:dom`.

**Adding a unit:** create `src/Verify/Specs/<Name>.elm` exposing `surface`,
`results` (`= Runner.runUnit spec`), and an `honest` projection; append its
`results` to `Verify.Registry.runAll`; attach `Contract.verifyAttrs "<Name>"` to
the real view; map its fixtures to seed state in `Main.seedVerifyAuthState`.

> Scope: this verifies **client-side** behavior off pure state projections. It
> does not replace genuine integration specs (real CouchDB sync, Resend email,
> two-user concurrency) — those stay on Playwright by design. Folding `Msg`s
> through the real `Main.update` for interactive units is a deferred follow-up
> (it needs to resolve the `Nav.Key` constraint, e.g. via elm-program-test's
> `createApplication`).

## Quick reference: where to find things

| I want to... | Look here |
|---|---|
| Add a field to Expense | `src/Data/Expense.elm` — update type, `encode`, `decoder`. Also `Amendment`, `OcrData`, `PendingEntry`/`ParsedEntry`, `EffectiveEntry`, `Helpers.effectiveEntryToExpense`, and the inline records in `Main.defaultPendingEntry`/`expenseToPending`/`ReviewScanItem`/`GotSubmitTime` |
| Add a new page | `src/Pages/`, wire into `Routing.elm` and `Main.elm` `view`/`update` |
| Change how PouchDB is queried | `src/pouch.js` |
| Add a new port | `src/Main.elm` (port declaration) + `src/main.js` (JS handler) |
| Change sync settings | `src/pouch.js` `startSync` handler |
| Understand what `EffectiveEntry` looks like | `src/Data/Entry.elm` |
| See how amendments are applied | `src/Data/Entry.elm` `resolve` function |
| Add an extracted field to the OCR prompt | `src/Main.elm` `ocrSystemPrompt`, `src/Data/Scan.elm` `OcrData` + `ocrDataDecoder` |
| Add a new Worker endpoint | `server/<name>.js` exporting `register<Name>Routes(app)`; wire from `server/index.js`. Reuse `server/auth.js` for authenticateCaller / getTier / isPaidTier |
| Change the Ledger map | `src/Helpers.elm` `encodeWaypoints` for the JSON wire shape; `src/main.js` `WaypointMap` for the Leaflet rendering |
| Add a hermetic verification unit | `src/Verify/Specs/<Name>.elm` + append to `Verify.Registry.runAll`; attach `Verify.Contract.verifyAttrs` to the view; seed in `Main.seedVerifyAuthState`. See the "Verification" section above |
