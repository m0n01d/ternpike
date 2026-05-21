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

export type SeedData = {
  expenses?: SeedExpense[]
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
    docs.push({
      _id: id,
      budget: trip.budget ?? 0,
      coverPhotoUrl: '',
      description: trip.description || '',
      endDate: trip.endDate,
      name: trip.name,
      startDate: trip.startDate,
      type: 'trip',
    })
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

  return docs
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
  await page.evaluate(async (allDocs) => {
    const PouchDB = (window as unknown as { PouchDB: new (n: string) => unknown }).PouchDB
    const db = new PouchDB('ternpike') as {
      bulkDocs: (docs: unknown[]) => Promise<unknown>
    }
    await db.bulkDocs(allDocs)
  }, docs as unknown as Record<string, unknown>[])
  await page.close()
  await context.unroute(sentinel)
}
