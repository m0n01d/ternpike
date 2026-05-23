import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import type { BrowserContext } from '@playwright/test'

const POUCHDB_PATH = resolve(__dirname, '../../node_modules/pouchdb/dist/pouchdb.min.js')

let pouchdbBodyCache: string | null = null

const pouchdbBody = (): string => {
  if (pouchdbBodyCache === null) {
    pouchdbBodyCache = readFileSync(POUCHDB_PATH, 'utf8')
  }
  return pouchdbBodyCache
}

export type SeedTrip = {
  budget?: number
  description?: string
  endDate: string
  flockId?: string
  name: string
  startDate: string
}

export type SeedExpense = {
  amount: number
  category: string
  date: string
  merchant?: string
  note?: string
}

/**
 * Flock seed shape — writes a `flock:meta` doc and registers it in
 * `user:flocks`. Both docs go into the user's personal PouchDB so the
 * change feed routes the meta up as a `FlockMeta` event and the Settings
 * Flocks card renders without requiring a real remote sync.
 *
 * `id` must be 12 lowercase hex chars (matches `Data.FlockId.fromString`).
 * `members` is the email of every member; `owner` must be one of them.
 */
export type SeedFlock = {
  billingStatus?: 'active' | 'frozen' | 'grace'
  dbName?: string
  id: string
  members: string[]
  name: string
  owner: string
}

export type SeedData = {
  expenses?: SeedExpense[]
  flocks?: SeedFlock[]
  trips?: SeedTrip[]
}

/**
 * Routes the cdn.jsdelivr.net PouchDB request to the local copy so seed pages
 * work in sandboxed environments. Idempotent per context.
 */
export const interceptPouchdbCdn = async (
  context: BrowserContext,
): Promise<void> => {
  await context.route('**/pouchdb.min.js', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/javascript',
      body: pouchdbBody(),
    }),
  )
}

const makeId = (prefix: string, date: string, seq: number): string => {
  const iso = new Date(date).toISOString()
  const rand = (Date.now() + seq).toString(36).slice(-8).padStart(8, '0')
  return `${prefix}::${iso}::${rand}`
}

const buildDocs = (data: SeedData): Record<string, unknown>[] => {
  const docs: Record<string, unknown>[] = []
  let seq = 0
  const tripIds: string[] = []

  for (const trip of data.trips || []) {
    const id = makeId('trip', trip.startDate, seq++)
    tripIds.push(id)
    const tripDoc: Record<string, unknown> = {
      _id: id,
      budget: trip.budget ?? 0,
      coverPhotoUrl: '',
      description: trip.description || '',
      endDate: trip.endDate,
      name: trip.name,
      startDate: trip.startDate,
      type: 'trip',
    }
    // flockId is stamped by the per-flock PouchDB handle at the port boundary
    // in production (`src/pouch.js`), so it isn't part of the stored doc
    // shape. The Elm decoder still reads it optionally, so seeding it
    // directly into the personal PouchDB is the simplest way to make a
    // single-DB test exercise a flock-tagged trip without standing up a
    // real per-flock handle.
    if (trip.flockId) {
      tripDoc.flockId = trip.flockId
    }
    docs.push(tripDoc)
  }

  // Expenses attach to the first trip if any; otherwise they have no tripId.
  const tripId = tripIds[0] || ''
  for (const exp of data.expenses || []) {
    docs.push({
      _id: makeId('expense', exp.date, seq++),
      amount: exp.amount,
      category: exp.category,
      createdAt: new Date(exp.date).toISOString(),
      date: exp.date,
      lat: null,
      lon: null,
      longNote: '',
      merchant: exp.merchant || '',
      note: exp.note || '',
      tripId,
      type: 'expense',
    })
  }

  // Note on flocks: `data.flocks` is intentionally NOT written here.
  // `pouch.js` only routes `flock:meta` docs to Elm via the live changes
  // feed (`since: 'now'`), and reads `user:flocks` only after the first
  // remote sync settles. Pre-loading them into IndexedDB before the app
  // boots makes them invisible to the app. Use `pushFlocksLive` from a
  // spec after the page is loaded if you need the flock card to render.
  return docs
}

/**
 * Writes flock-related documents into the live app page's PouchDB after
 * the Elm app has booted. Use this for any seed that must be observed by
 * `pouch.js`'s `since: 'now'` changes feed — most notably `flock:meta`
 * and `user:flocks`, which `pouch.js` only routes to Elm when they
 * arrive via the live changes feed (there's no startup fetch for them
 * yet).
 *
 * NOTE — harness gap (#76): in practice, only the `user:flocks` write
 * reliably propagates from this injected PouchDB instance to the app's
 * bundled instance. The `flock:meta` write lands in IndexedDB but the
 * app's change feed on the per-flock handle doesn't observe it across
 * separate PouchDB library copies. As a result the Flocks card doesn't
 * render today even with this helper — closing the gap likely needs
 * either (a) a port-level test seam in `src/main.js` (e.g. expose
 * `window.__pouchInject__` that calls `app.ports.pouchIn.send` with a
 * synthetic `FlockMeta` event), or (b) a real CouchDB-backed sync
 * round-trip in the harness. Leave this helper in place for when
 * either path lands.
 *
 * The page must already have the app loaded (i.e. `goto('/settings')`
 * or similar before calling).
 */
export const pushFlocksLive = async (
  page: import('@playwright/test').Page,
  flocks: SeedFlock[],
): Promise<void> => {
  if (flocks.length === 0) return
  // Order matters. We write `user:flocks` first — that triggers
  // `reconcileFlocks` in `pouch.js`, which opens a per-flock PouchDB
  // handle (`ternpike-${dbName}`). The flock card needs that handle's
  // `flockId` to be known by the time the `flock:meta` doc arrives,
  // otherwise `FlocksReconciled` will filter the meta out of
  // `as_.flocks` on arrival. We then write `flock:meta` into the
  // per-flock DB so the change feed there routes it up.
  const userFlocksDoc = {
    _id: 'user:flocks',
    flocks: flocks.map((f) => ({
      dbName: f.dbName || `ternpike-flock-${f.id}`,
      flockId: f.id,
    })),
    type: 'user:flocks',
  }
  const flockMetaDocs = flocks.map((flock) => ({
    dbName: flock.dbName || `ternpike-flock-${flock.id}`,
    doc: {
      _id: flock.id,
      billingLapsedAt: null,
      billingOwner: flock.owner,
      billingStatus: flock.billingStatus || 'active',
      createdAt: new Date('2026-01-01').toISOString(),
      createdBy: flock.owner,
      members: flock.members,
      name: flock.name,
      type: 'flock:meta',
    },
  }))
  // The Elm app's bundled PouchDB is not exposed on `window`, so we
  // inject the same local PouchDB bundle that `seedPouchDB` uses and
  // open the `ternpike` database from script. PouchDB cooperates with
  // the live instance the app holds open — both write to the same
  // IndexedDB, and the app's change feed observes our writes.
  await page.addScriptTag({ content: pouchdbBody() })
  await page.waitForFunction(
    () => typeof (window as unknown as { PouchDB?: unknown }).PouchDB !== 'undefined',
    { timeout: 5_000 },
  )
  await page.evaluate(
    async ([userFlocks, metas]) => {
      const PouchDB = (window as unknown as { PouchDB: new (n: string) => unknown }).PouchDB
      type DbHandle = {
        bulkDocs: (docs: unknown[]) => Promise<unknown>
        put: (doc: unknown) => Promise<unknown>
      }
      const personal = new PouchDB('ternpike') as DbHandle
      await personal.put(userFlocks)
      // Give `reconcileFlocks` in `src/pouch.js` time to open each
      // per-flock handle before we write into it. Without this wait
      // the per-flock PouchDB the app holds and the one we open
      // below can race and our write lands before the app's change
      // feed is attached.
      await new Promise((r) => setTimeout(r, 250))
      for (const { dbName, doc } of metas as { dbName: string; doc: unknown }[]) {
        const flockDb = new PouchDB(`ternpike-${dbName}`) as DbHandle
        await flockDb.put(doc)
      }
    },
    [userFlocksDoc, flockMetaDocs] as const,
  )
}

/**
 * Seeds the user's PouchDB (database name `ternpike`) with the given trips
 * and expenses. Runs in-browser using the local PouchDB bundle.
 *
 * This is intentionally smaller than `public/seed.html` — that page is
 * tuned for screenshot demos with 200+ documents. E2E specs should add only
 * what the test actually exercises.
 */
export const seedPouchDB = async (
  context: BrowserContext,
  data: SeedData,
): Promise<void> => {
  await interceptPouchdbCdn(context)
  // Same vite-port override as `auth-stub.ts` — the seed sentinel must
  // live on the origin the spec navigates to so IndexedDB is shared.
  const vitePort = process.env.E2E_VITE_PORT || '3000'
  const sentinel = `http://localhost:${vitePort}/__e2e_seed__`
  await context.route(sentinel, (route) =>
    route.fulfill({
      status: 200,
      contentType: 'text/html',
      body: '<!doctype html><html><body><script src="https://cdn.jsdelivr.net/npm/pouchdb@9.0.0/dist/pouchdb.min.js"></script></body></html>',
    }),
  )
  const page = await context.newPage()
  await page.goto(sentinel, { waitUntil: 'domcontentloaded' })
  // Wait for PouchDB global.
  await page.waitForFunction(
    () => typeof (window as unknown as { PouchDB?: unknown }).PouchDB !== 'undefined',
    { timeout: 10_000 },
  )
  const docs = buildDocs(data)
  const written = await page.evaluate(async (allDocs) => {
    const PouchDB = (window as unknown as { PouchDB: new (n: string) => unknown }).PouchDB
    const db = new PouchDB('ternpike') as {
      allDocs: (opts: unknown) => Promise<{ total_rows: number }>
      bulkDocs: (docs: unknown[]) => Promise<unknown>
      close: () => Promise<void>
    }
    await db.bulkDocs(allDocs)
    // Re-read to ensure the IDB transaction has committed before the seed
    // page closes. Without this verify-step on CI we sometimes saw a race
    // where the app's freshly-opened PouchDB instance read an empty store
    // back, despite bulkDocs having "resolved".
    const verify = await db.allDocs({ include_docs: false })
    await db.close()
    return verify.total_rows
  }, docs as unknown as Record<string, unknown>[])
  if (written < docs.length) {
    throw new Error(
      `seedPouchDB verify: expected ${docs.length} docs in PouchDB, saw ${written}`,
    )
  }
  await page.close()
  await context.unroute(sentinel)
}
