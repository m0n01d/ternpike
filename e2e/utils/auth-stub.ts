import type { BrowserContext } from '@playwright/test'

const IDB_NAME = 'alaska-tracker'
const IDB_STORE = 'kv'

export type AuthCreds = {
  dbName: string
  email: string
  password: string
  // Optional. When set, the Elm app reads it off the auth_creds blob and
  // initializes `AuthState.tier`. Matches the `Data.Tier.fromString` wire
  // values: 'tern' | 'osprey' | 'trailblazer'.
  tier?: string
}

/**
 * Writes `auth_creds` into IndexedDB so the Elm app boots into AuthModel
 * without a real login flow. Matches what `src/main.js` reads at startup
 * (`alaska-tracker` / `kv` / `auth_creds`).
 *
 * Navigates to `/seed.html` (which boots PouchDB but does not start the Elm
 * app or read `auth_creds`), writes IndexedDB synchronously, then closes
 * the page. Subsequent navigations to app routes pick up the value.
 */
export const stubAuthCreds = async (
  context: BrowserContext,
  creds: AuthCreds,
): Promise<void> => {
  // Intercept GET /me so the fetchMe call fired on AuthModel construction
  // (src/Main.elm) sees a coherent tier matching what we seeded into
  // IndexedDB, rather than the server's empty-TIERS_KV default of 'tern'
  // overwriting it mid-test.
  await context.route('**/me', async (route) => {
    if (route.request().method() !== 'GET') {
      return route.fallback()
    }
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        email: creds.email.toLowerCase(),
        stripeCustomerId: null,
        subscriptionId: null,
        subscriptionStatus: null,
        tier: (creds.tier || 'tern').toLowerCase(),
        trailblazerNumber: null,
      }),
    })
  })

  const payload = JSON.stringify(creds)
  const page = await context.newPage()
  // seed.html is a real file in `public/` and boots PouchDB but does not
  // call indexedDB.open('alaska-tracker', …) — safe to piggyback on for the
  // IDB write. Block its CDN fetch so it doesn't hang on offline networks.
  await page.route('**/pouchdb.min.js', (route) =>
    route.fulfill({ status: 200, contentType: 'application/javascript', body: '' }),
  )
  // Honor the vite port override used by `e2e/global-setup.ts`. The IDB
  // is per-origin so the seed page must live on the same host:port the
  // spec navigates to, otherwise the Elm app never sees `auth_creds`.
  const vitePort = process.env.E2E_VITE_PORT || '3000'
  await page.goto(`http://localhost:${vitePort}/seed.html`, {
    waitUntil: 'domcontentloaded',
  })
  await page.evaluate(
    async ([dbName, storeName, value]) => {
      await new Promise<void>((resolve, reject) => {
        const open = indexedDB.open(dbName, 1)
        open.onupgradeneeded = (event) => {
          const db = (event.target as IDBOpenDBRequest).result
          if (!db.objectStoreNames.contains(storeName)) {
            db.createObjectStore(storeName)
          }
        }
        open.onsuccess = () => {
          const db = open.result
          const tx = db.transaction(storeName, 'readwrite')
          tx.objectStore(storeName).put(value, 'auth_creds')
          tx.oncomplete = () => {
            db.close()
            resolve()
          }
          tx.onerror = () => reject(tx.error)
        }
        open.onerror = () => reject(open.error)
      })
    },
    [IDB_NAME, IDB_STORE, payload] as const,
  )
  await page.close()
}
