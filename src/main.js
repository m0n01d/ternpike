import { Elm } from './Main.elm'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import 'leaflet.markercluster'
import 'leaflet.markercluster/dist/MarkerCluster.css'
import 'leaflet.markercluster/dist/MarkerCluster.Default.css'
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'

delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconUrl: markerIcon,
  iconRetinaUrl: markerIcon2x,
  shadowUrl: markerShadow,
})
import * as exifr from 'exifr'
import { attachPouch } from './pouch.js'
import { attachDemo } from './demo.js'
import './global.css'
import './elements/map-picker.js'
import './elements/waypoint-map.js'
import './elements/relative-time.js'
import './elements/tp-amount.js'

;(async function () {

  // ── Color scheme ──────────────────────────────────────────────────────
  function applyColorScheme(pref) {
    const sys = window.matchMedia('(prefers-color-scheme: dark)').matches
    const dark = pref === 'dark' || (pref !== 'light' && sys)
    document.documentElement.classList.toggle('dark', dark)
  }

  applyColorScheme(localStorage.getItem('color_scheme') || 'auto')

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
    const stored = localStorage.getItem('color_scheme')
    if (!stored || stored === 'auto') {
      document.documentElement.classList.toggle('dark', e.matches)
    }
  })

  // ── Nano-id (no dependency) ────────────────────────────────────────────
  const nanoid = (len = 8) =>
    crypto.getRandomValues(new Uint8Array(len))
      .reduce((s, b) => s + (b & 63).toString(36), '')

  // ── IndexedDB key/value store ──────────────────────────────────────────

  const IDB_NAME       = 'alaska-tracker'
  const IDB_VERSION    = 2
  const IDB_STORE      = 'kv'
  const IDB_SCAN_STORE = 'scanQueue'
  let _db = null

  // ── Safe IndexedDB open + migration (#371) ─────────────────────────────
  //
  // Migration flow — every branch matters because a botched upgrade bricks
  // `auth_creds` (→ everyone gets logged out):
  //
  //   onupgradeneeded: fired on a fresh DB (oldVersion 0) AND on a version
  //     bump (oldVersion 1 → newVersion 2). The store creation is GUARDED by
  //     `oldVersion` so it's idempotent: the old code did an unconditional
  //     `createObjectStore('kv')`, which throws `ConstraintError` the moment
  //     it re-runs against a DB that already has `kv` (i.e. every existing
  //     user). `if (oldVersion < 1)` creates `kv` only on a truly fresh DB;
  //     `if (oldVersion < 2)` adds `scanQueue` for both fresh and v1 DBs.
  //
  //   onblocked: the upgrade can't start because another tab still holds the
  //     DB open at v1. Without handling this the open promise never settles,
  //     `idbGet('auth_creds')` hangs forever, and boot stalls on a blank
  //     screen — indistinguishable from "logged out". We reject so the
  //     caller's try/catch degrades to "no creds" instead of hanging.
  //
  //   db.onversionchange (on the SUCCESSFULLY-opened connection): a *future*
  //     tab wants to upgrade and we're the one blocking it. Close our
  //     connection so that tab's `onblocked` clears and its upgrade proceeds —
  //     otherwise the second tab hangs (the mirror image of the case above).
  function openDB() {
    if (_db) return Promise.resolve(_db)
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(IDB_NAME, IDB_VERSION)
      req.onupgradeneeded = e => {
        const db = e.target.result
        if (e.oldVersion < 1 && !db.objectStoreNames.contains(IDB_STORE)) {
          db.createObjectStore(IDB_STORE)
        }
        if (e.oldVersion < 2 && !db.objectStoreNames.contains(IDB_SCAN_STORE)) {
          db.createObjectStore(IDB_SCAN_STORE)
        }
      }
      req.onsuccess = e => {
        _db = e.target.result
        // If another tab later requests a higher version, step aside so its
        // upgrade isn't blocked by this open connection.
        _db.onversionchange = () => { _db.close(); _db = null }
        resolve(_db)
      }
      req.onerror   = e => reject(e.target.error)
      req.onblocked = () => reject(new Error('IndexedDB upgrade blocked by another open tab'))
    })
  }

  async function idbGet(key) {
    const db = await openDB()
    return new Promise((resolve, reject) => {
      const req = db.transaction(IDB_STORE).objectStore(IDB_STORE).get(key)
      req.onsuccess = () => resolve(req.result ?? null)
      req.onerror   = () => reject(req.error)
    })
  }

  async function idbSet(key, value) {
    const db = await openDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(IDB_STORE, 'readwrite')
      tx.objectStore(IDB_STORE).put(value, key)
      tx.oncomplete = () => resolve()
      tx.onerror    = () => reject(tx.error)
    })
  }

  async function idbDel(...keys) {
    const db = await openDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(IDB_STORE, 'readwrite')
      keys.forEach(k => tx.objectStore(IDB_STORE).delete(k))
      tx.oncomplete = () => resolve()
      tx.onerror    = () => reject(tx.error)
    })
  }

  // ── Durable scan queue store (#371) ────────────────────────────────────
  //
  // Keyed by the scan id (`scan::<millis>::<seq>`) so a `put` of an item
  // already in the store overwrites in place. Each item is the
  // `scanItemEncoder` JSON Elm hands across `saveScanItem`.

  async function scanQueueGetAll() {
    const db = await openDB()
    return new Promise((resolve, reject) => {
      const req = db.transaction(IDB_SCAN_STORE).objectStore(IDB_SCAN_STORE).getAll()
      req.onsuccess = () => resolve(req.result || [])
      req.onerror   = () => reject(req.error)
    })
  }

  // Resolves on commit, rejects on error. The error is surfaced (not
  // swallowed like `idbSet`) so a `QuotaExceededError` reaches the Elm
  // `scanItemSaved` ack and flips `persistError`.
  async function scanQueuePut(item, id) {
    const db = await openDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(IDB_SCAN_STORE, 'readwrite')
      tx.objectStore(IDB_SCAN_STORE).put(item, id)
      tx.oncomplete = () => resolve()
      tx.onerror    = () => reject(tx.error)
      tx.onabort    = () => reject(tx.error || new Error('scanQueue put aborted'))
    })
  }

  // First Elm callers landed in #374 (the `ExpenseChanged` submit-clear echo,
  // the multi-receipt split source, and `ClearDoneItems`). The JS handler was
  // wired in #371 so those callers flipped it on without touching main.js's
  // IDB plumbing.
  async function scanQueueDelete(id) {
    const db = await openDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(IDB_SCAN_STORE, 'readwrite')
      tx.objectStore(IDB_SCAN_STORE).delete(id)
      tx.oncomplete = () => resolve()
      tx.onerror    = () => reject(tx.error)
    })
  }

  async function scanQueueClear() {
    const db = await openDB()
    // Guard for a DB still at v1 where the store doesn't exist yet (an upgrade
    // that hasn't run / was blocked). Nothing to clear → resolve.
    if (!db.objectStoreNames.contains(IDB_SCAN_STORE)) return
    return new Promise((resolve, reject) => {
      const tx = db.transaction(IDB_SCAN_STORE, 'readwrite')
      tx.objectStore(IDB_SCAN_STORE).clear()
      tx.oncomplete = () => resolve()
      tx.onerror    = () => reject(tx.error)
    })
  }

  // ── App keys for wipe ─────────────────────────────────────────────────
  const APP_KEYS = ['auth_creds', 'anthropic_key', 'pending_ref']

  // ── Referral attribution: read the `tp_ref` cookie set by the marketing
  // site (.ternpike.com scope), persist into IDB so it survives even if the
  // cookie expires before the user verifies their email. Cleared on signup
  // success by the server-side `referredBy` write; the client clears it
  // here on first read since once it's in IDB the cookie is redundant.
  const REF_RE = /^qr-user-[a-z0-9]{4}$/
  function readRefCookie() {
    const m = document.cookie.match(/(?:^|;\s*)tp_ref=([^;]+)/)
    if (!m) return null
    try {
      const v = decodeURIComponent(m[1])
      return REF_RE.test(v) ? v : null
    } catch {
      return null
    }
  }

  // ── Demo mode detection ───────────────────────────────────────────────
  //
  // /demo serves the same SPA bundle (root wrangler.jsonc is SPA mode) but
  // skips IndexedDB reads, skips PouchDB attach, and seeds movie road trips
  // into memory via attachDemo. The URL is rewritten to /trips so the Elm
  // router lands on RouteTrips without any Elm-side change.
  //
  // sessionStorage is what makes demo mode survive a refresh. The URL
  // rewrite above means subsequent loads see /trips (or any deeper
  // route after the user clicks around), so pathname alone can't be
  // trusted on refresh. The flag is tab-scoped — close the tab, lose
  // the demo — which is the right TTL.
  const isDemo =
    window.location.pathname.startsWith('/demo') ||
    sessionStorage.getItem('demo') === '1'
  if (isDemo) {
    sessionStorage.setItem('demo', '1')
    if (window.location.pathname.startsWith('/demo')) {
      window.history.replaceState(null, '', '/trips')
    }
  }

  // ── Load all persisted settings before starting Elm ───────────────────
  //
  // Wrapped in try/catch (#371): if the IndexedDB open/upgrade fails or is
  // blocked by another tab (see `openDB`'s onblocked/onversionchange notes),
  // we degrade to "no creds" and boot the guest UI rather than hanging on a
  // blank screen forever. The Elm router then shows the login screen — the
  // user re-authenticates rather than being stuck.
  let authCredsRaw = null
  let anthropicKey = null
  let pendingRefStored = null
  if (!isDemo) {
    try {
      ;[authCredsRaw, anthropicKey, pendingRefStored] = await Promise.all([
        idbGet('auth_creds'),
        idbGet('anthropic_key'),
        idbGet('pending_ref'),
      ])
    } catch (err) {
      console.error('[idb] boot read failed — degrading to no creds:', err)
    }
  }

  // Cookie → IDB promotion. The marketing site sets `tp_ref` on
  // `.ternpike.com`; we hoist it into IDB so it survives cookie expiry
  // and Safari ITP. IDB value wins if both are present.
  let pendingRef = pendingRefStored || null
  if (!isDemo) {
    const fromCookie = readRefCookie()
    if (fromCookie && !pendingRef) {
      pendingRef = fromCookie
      try {
        await idbSet('pending_ref', pendingRef)
      } catch (err) {
        console.warn('[ref] idb persist failed:', err)
      }
    }
  }

  let authCreds = null
  if (isDemo) {
    authCreds = {
      dbName: 'demo',
      email: 'demo@ternpike.com',
      password: 'demo',
      tier: 'osprey',
    }
  } else if (authCredsRaw) {
    try {
      authCreds = JSON.parse(authCredsRaw)
    } catch (_) {
      authCreds = null
    }
  }

  // The user's LOCAL calendar date — never UTC. `toISOString()` would hand
  // back the UTC day, which for any western offset rolls over hours early
  // (e.g. 6 PM PDT is already "tomorrow" in UTC), so an evening expense would
  // default to the wrong date. Elm refreshes this from `Time.here`/`Time.now`
  // on boot and whenever the app regains visibility (travel / crossing
  // midnight), so this flag only has to be right for the first paint.
  const localToday = (d =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  )(new Date())

  const flags = {
    authCreds:      authCreds,
    anthropicKey:   anthropicKey  || '',
    // Resolved at build time in `vite.config.js` — the single place an API
    // hostname is allowed to appear. `VITE_BACKEND_URL` still overrides it
    // (see docs/key-rotation.md §8 / `npm run dev:staging`), and CI branch
    // builds other than `main` bake staging.
    backendUrl:     __BACKEND_URL__,
    basePath:       import.meta.env.BASE_URL,
    colorScheme:    localStorage.getItem('color_scheme') || 'auto',
    demoMode:       isDemo,
    pendingRef:     pendingRef,
    today:          localToday,
    vapidPublicKey: import.meta.env.VITE_VAPID_PUBLIC_KEY || '',
    version:        __BUILD_SHA__,
  }


  // ── Start Elm ──────────────────────────────────────────────────────────

  const app = Elm.Main.init({ flags })

  // Test-only escape hatch. Lets the E2E harness push synthetic port
  // messages into Elm without standing up the whole CouchDB sync chain
  // (`couch.ternpike.com` is hard-coded in src/pouch.js and isn't
  // reachable in the test environment). Production code never reads
  // this — see `e2e/specs/create-flock.spec.ts` for the sole user.
  if (typeof window !== 'undefined') {
    /* eslint-disable no-underscore-dangle */
    window.__ternpikeTestApp = app
    /* eslint-enable no-underscore-dangle */
  }

  // /verify/:unit/:fixture mounts a seeded fixture model with no creds and no
  // sync. Skip attachPouch entirely so nothing reaches couch.ternpike.com —
  // these routes are hermetic and backend-free (mirrors the /demo guard above).
  const isVerify = /\/verify(\/|$)/.test(window.location.pathname)

  if (isDemo) {
    attachDemo(app)
  } else if (!isVerify) {
    attachPouch(app, { creds: authCreds })
  }

  // window.__verify: the agent/dashboard interface. Elm pushes the full
  // verification matrix (plus which unit/fixture is mounted) on a /verify boot;
  // we expose it as a small read API alongside the existing test hatch. current()
  // also re-reads the live data-verify-* attributes so the DOM tier can confirm
  // the rendered surface matches the pure-tier verdict.
  if (app.ports.verifyResults) {
    let snapshot = { mountedUnit: null, mountedFixture: null, results: [] }

    const domSurface = () => {
      // Select the *mounted* unit specifically — a page (e.g. Settings) can
      // render several verify units, so a bare [data-verify-unit] would grab
      // whichever comes first in the DOM.
      const el = snapshot.mountedUnit
        ? document.querySelector(`[data-verify-unit="${snapshot.mountedUnit}"]`)
        : document.querySelector('[data-verify-unit]')
      if (!el) return null
      const out = {}
      for (const attr of el.attributes) {
        if (attr.name.startsWith('data-verify-')) {
          out[attr.name.replace('data-verify-', '')] = attr.value
        }
      }
      return out
    }

    // Dev-only verification overlay: on /verify/:unit/:fixture, surface the
    // mounted unit's verdict + observed attrs on top of the real page, so a
    // human sees screen + attrs + PASS/FAIL together (matching the reference
    // dashboard). import.meta.env.DEV is false in `vite build`, so it never
    // appears in prod / the DOM-tier / visual goldens — those stay clean.
    const renderVerifyOverlay = () => {
      if (!snapshot.mountedFixture) return
      const result = snapshot.results.find(
        (r) => r.unit === snapshot.mountedUnit && r.fixture === snapshot.mountedFixture,
      )
      if (!result) return
      const pass = (result.verdict || '').startsWith('PASS')
      // Prefer the live DOM attrs; fall back to the matrix surface (pure-only
      // units like ScanRouting have no rendered element).
      const attrs = domSurface() || result.surface || {}
      const pairs = Object.entries(attrs)
        .filter(([k]) => k !== 'unit')
        .map(([k, v]) => `${k}=${v}`)
        .join('  ·  ')
      let el = document.getElementById('__verify_overlay')
      if (!el) {
        el = document.createElement('div')
        el.id = '__verify_overlay'
        document.body.appendChild(el)
      }
      el.style.cssText =
        'position:fixed;top:0;left:0;right:0;z-index:99999;font:12px/1.5 ui-monospace,monospace;' +
        `background:#1b1b1b;color:#eaeaea;padding:8px 14px;box-shadow:0 1px 6px rgba(0,0,0,.3);border-bottom:3px solid ${pass ? '#5aa469' : '#c8553d'};`
      el.innerHTML =
        `<b>${result.unit} / ${result.fixture}</b> ` +
        `<span style="color:${pass ? '#7fcf8f' : '#ff9b86'};font-weight:700">${result.verdict}</span>` +
        (pairs ? ` &nbsp;·&nbsp; ${pairs}` : '')
    }

    app.ports.verifyResults.subscribe((payload) => {
      snapshot = payload
      if (import.meta.env.DEV) requestAnimationFrame(renderVerifyOverlay)
    })

    /* eslint-disable no-underscore-dangle */
    window.__verify = {
      manifest: () =>
        snapshot.results.map((r) => ({ unit: r.unit, fixture: r.fixture, verdict: r.verdict })),
      runAll: () => snapshot.results,
      current: () => {
        const match = snapshot.results.find(
          (r) => r.unit === snapshot.mountedUnit && r.fixture === snapshot.mountedFixture,
        )
        return { ...(match || null), domSurface: domSurface() }
      },
    }
    /* eslint-enable no-underscore-dangle */
  }

  // ── Port handlers ──────────────────────────────────────────────────────

  app.ports.saveStorage.subscribe(async ({ key, value }) => {
    await idbSet(key, value)
    if (key === 'color_scheme') {
      localStorage.setItem('color_scheme', value)
      applyColorScheme(value)
    }
    // Keep the in-module `authCreds` in lockstep with the store (#371). The
    // CouchDB sync auth header (`basicAuthHeader`) reads `authCreds.email`
    // / `.password` directly. `value` is the SERIALIZED creds string, so a
    // raw `authCreds = value` would leave `.email` undefined → every synced
    // request 401s after an in-SPA re-login. Parse it, mirroring the
    // `color_scheme` special-case above.
    if (key === 'auth_creds') {
      try {
        authCreds = JSON.parse(value)
      } catch (err) {
        console.error('[auth] failed to parse saved auth_creds:', err)
      }
    }
  })

  // ── Durable scan queue: load / save / delete ports (#371) ──────────────
  //
  // Gated off /verify and /demo like the rest of the device-storage wiring —
  // those routes are hermetic and never touch the real IndexedDB.
  if (!isVerify && !isDemo) {
    // loadScanQueue → getAll → scanQueueLoaded. A read failure (Private
    // Browsing / Lockdown Mode) reports `available:false` via storageStatus
    // and hands Elm an empty array so hydration proceeds without erroring.
    if (app.ports.loadScanQueue) {
      app.ports.loadScanQueue.subscribe(async () => {
        try {
          const items = await scanQueueGetAll()
          if (app.ports.scanQueueLoaded) app.ports.scanQueueLoaded.send(items)
        } catch (err) {
          console.error('[scanQueue] load failed:', err)
          if (app.ports.scanQueueLoaded) app.ports.scanQueueLoaded.send([])
          if (app.ports.storageStatus) {
            const earlyInstalled =
              window.navigator.standalone === true ||
              (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
            const earlyIsIos =
              typeof window.navigator.standalone !== 'undefined' ||
              (/iPhone|iPad|iPod/.test(navigator.userAgent) && !window.MSStream)
            app.ports.storageStatus.send({ available: false, installed: earlyInstalled, isIos: earlyIsIos, persisted: false })
          }
        }
      })
    }

    // saveScanItem → put → scanItemSaved {id, ok, error}. The existing
    // `idbSet` swallows `QuotaExceededError`; this path surfaces it so Elm
    // flips `persistError` and never shows "Saved · will scan later" for an
    // item that didn't actually persist.
    if (app.ports.saveScanItem) {
      app.ports.saveScanItem.subscribe(async (item) => {
        const id = item && item.id
        try {
          await scanQueuePut(item, id)
          if (app.ports.scanItemSaved) {
            app.ports.scanItemSaved.send({ id, ok: true, error: '' })
          }
        } catch (err) {
          console.error('[scanQueue] save failed:', err)
          if (app.ports.scanItemSaved) {
            app.ports.scanItemSaved.send({
              id,
              ok: false,
              error: (err && err.name) || 'save failed',
            })
          }
        }
      })
    }

    // deleteScanItem: Elm port + callers landed in #374 (submit-clear echo,
    // split source, ClearDoneItems). Guarded so an older bundle without the
    // port can't throw.
    if (app.ports.deleteScanItem) {
      app.ports.deleteScanItem.subscribe(async (id) => {
        try {
          await scanQueueDelete(id)
        } catch (err) {
          console.error('[scanQueue] delete failed:', err)
        }
      })
    }

    // Boot storage probe + best-effort persistence (#371). Both run off the
    // critical path (never awaited before Elm starts). The probe does a
    // trivial read of `scanQueue`; if it throws (Private Browsing / Lockdown),
    // report unavailable so the capture hero can refuse the durability
    // promise. `navigator.storage.persist()` is feature-detected and its
    // rejection swallowed — it resolves `false` when the UA declines, which we
    // report honestly rather than overpromising.
    // `installed` detects whether the app is running as an installed PWA
    // (standalone mode, #377). iOS only grants persist() via the installed-app
    // heuristic, so the durability promise is only reliable in standalone.
    ;(async () => {
      let available = true
      try {
        await scanQueueGetAll()
      } catch (err) {
        console.error('[scanQueue] storage probe failed:', err)
        available = false
      }

      let persisted = false
      try {
        if (navigator.storage && navigator.storage.persisted) {
          persisted = await navigator.storage.persisted()
        }
        if (!persisted && navigator.storage && navigator.storage.persist) {
          persisted = await navigator.storage.persist()
        }
      } catch (_) {
        // best-effort: leave `persisted` as-is
      }

      // Detect standalone (installed PWA) mode. `navigator.standalone` is a
      // non-standard iOS Safari boolean; `display-mode: standalone` is the
      // standard equivalent supported by Chrome/Android and iOS 16.4+.
      const installed =
        window.navigator.standalone === true ||
        (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)

      // Detect iOS/iPadOS. `navigator.standalone` only exists on iOS; the
      // maxTouchPoints guard catches iPadOS 13+ where the UA drops "iPad".
      const isIos =
        typeof window.navigator.standalone !== 'undefined' ||
        (/iPhone|iPad|iPod/.test(navigator.userAgent) && !window.MSStream)

      if (app.ports.storageStatus) {
        app.ports.storageStatus.send({ available, installed, isIos, persisted })
      }
    })()
  }

  // ── Network status ─────────────────────────────────────────────────────
  if (app.ports.networkStatus) {
    // Send initial state (before the listeners are attached, so Elm has the truth from frame zero)
    app.ports.networkStatus.send(navigator.onLine)
    window.addEventListener('online',  () => app.ports.networkStatus.send(true))
    window.addEventListener('offline', () => app.ports.networkStatus.send(false))
  }

  // ── PWA install prompt ─────────────────────────────────────────────────
  let deferredInstallPrompt = null

  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault()
    deferredInstallPrompt = e
    if (app.ports.canInstall) app.ports.canInstall.send(true)
  })

  window.addEventListener('appinstalled', () => {
    deferredInstallPrompt = null
    if (app.ports.canInstall) app.ports.canInstall.send(false)
  })

  if (app.ports.triggerInstallPrompt) {
    app.ports.triggerInstallPrompt.subscribe(async () => {
      if (!deferredInstallPrompt) return
      deferredInstallPrompt.prompt()
      try { await deferredInstallPrompt.userChoice } catch (_) {}
      deferredInstallPrompt = null
      if (app.ports.canInstall) app.ports.canInstall.send(false)
    })
  }

  // ── iOS standalone viewport heal (floating bottom-nav fix) ─────────────
  //
  // In the installed (standalone) iOS web app, opening the software keyboard
  // shrinks the layout viewport — and iOS sometimes never grows it back after
  // the keyboard closes (observed through iOS 26.x). `window.innerHeight`
  // stays stuck at the shrunken value, so every `position: fixed` element
  // (the bottom nav) anchors to a phantom viewport bottom a keyboard-height
  // up the screen, and the `sticky` header drifts the same way. The only
  // user-side cure is force-quitting the app.
  //
  // The heal: remember the tallest innerHeight seen for the current
  // orientation; whenever the viewport is stuck short of it while no input
  // is focused (keyboard closed), force a full re-layout by toggling
  // `display` on <body> for one frame so WebKit re-measures the viewport and
  // snaps fixed/sticky elements back to the real screen edges. <body>'s own
  // style attribute is not managed by Elm (Browser.application patches only
  // its children), so the toggle can't fight the virtual DOM.
  const runningStandalone =
    window.navigator.standalone === true ||
    (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
  const onIosDevice =
    typeof window.navigator.standalone !== 'undefined' ||
    (/iPhone|iPad|iPod/.test(navigator.userAgent) && !window.MSStream)

  if (runningStandalone && onIosDevice) {
    let maxVH = window.innerHeight
    let baseVW = window.innerWidth

    const keyboardLikelyOpen = () => {
      const el = document.activeElement
      return !!el && /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)
    }

    const healViewport = () => {
      if (keyboardLikelyOpen()) return
      if (maxVH - window.innerHeight <= 4) return
      const y = window.scrollY
      document.body.style.display = 'none'
      void document.body.offsetHeight
      document.body.style.display = ''
      window.scrollTo(0, y)
    }

    window.addEventListener('resize', () => {
      if (window.innerWidth !== baseVW) {
        // Rotation: re-baseline instead of "healing" toward the other
        // orientation's taller height.
        baseVW = window.innerWidth
        maxVH = window.innerHeight
        return
      }
      maxVH = Math.max(maxVH, window.innerHeight)
    })

    // Keyboard dismissal lands as a focusout and the viewport settles a beat
    // later; keyboard animations report on visualViewport first. Returning
    // from the camera / app switcher (visibilitychange, pageshow) can land in
    // the stuck state too.
    const healSoon = () => setTimeout(healViewport, 250)
    document.addEventListener('focusout', healSoon)
    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', healSoon)
    }
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) healSoon()
    })
    window.addEventListener('pageshow', healSoon)
  }

  // Token-expiry logout: drop creds but LEAVE the durable scan queue intact
  // (#371) — an unsent receipt captured offline must survive a 401 so it's
  // still there after the user re-authenticates.
  app.ports.clearStorage.subscribe(() => {
    authCreds = null
    idbDel('auth_creds')
  })

  // Full reset (Settings → Reset, via `ResetSettingsClicked`): wipe the kv
  // keys AND explicitly clear the scanQueue store (#371). `scanQueueClear`
  // self-guards for a DB still at v1 where the store doesn't exist.
  app.ports.clearAllStorage.subscribe(async () => {
    authCreds = null
    await idbDel(...APP_KEYS)
    try {
      await scanQueueClear()
    } catch (err) {
      console.error('[scanQueue] clear failed:', err)
    }
  })

  app.ports.requestGeolocation.subscribe(() => {
    if (!('geolocation' in navigator)) {
      app.ports.gotGpsCoords.send({ lat: 0, lon: 0, denied: true })
      return
    }
    navigator.geolocation.getCurrentPosition(
      pos => app.ports.gotGpsCoords.send({ lat: pos.coords.latitude, lon: pos.coords.longitude, denied: false }),
      _err => app.ports.gotGpsCoords.send({ lat: 0, lon: 0, denied: true }),
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 }
    )
  })

  // Approximate decoded-byte length of a `data:image/...;base64,XXX` URL.
  // Each 4 base64 chars decode to 3 bytes, minus 1 byte per `=` padding char.
  function base64ByteLength(dataUrl) {
    if (typeof dataUrl !== 'string') return 0
    const comma = dataUrl.indexOf(',')
    const payload = comma >= 0 ? dataUrl.slice(comma + 1) : dataUrl
    const padding = payload.endsWith('==') ? 2 : payload.endsWith('=') ? 1 : 0
    return Math.max(0, Math.floor((payload.length * 3) / 4) - padding)
  }

  // Load a data URL into an HTMLImageElement, resolving once `onload` fires.
  function loadImage(dataUrl) {
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.onload = () => resolve(img)
      img.onerror = () => reject(new Error('image failed to decode'))
      img.src = dataUrl
    })
  }

  // ── OCR image prep: downscale + recompress before sending to Anthropic ──
  //
  // Anthropic's vision API caps base64 image payloads at 5 MiB. Phone JPEGs
  // routinely run 6–8 MB, so we'd 400 on most real-world receipt photos.
  // Elm has no Canvas, so the resize has to happen here: draw the image to
  // a canvas at max 1568px on the long edge (Claude's recommended size) and
  // re-encode JPEG, dropping quality and then dimensions until the base64
  // length fits the caller's budget.
  app.ports.prepareOcrImage.subscribe(async ({ id, dataUrl, maxBytes }) => {
    const send = (payload) => {
      if (app.ports.ocrImagePrepared) {
        app.ports.ocrImagePrepared.send(payload)
      }
    }

    const originalBytes = base64ByteLength(dataUrl)

    try {
      // Fast path: already small enough, ship as-is.
      if (originalBytes <= maxBytes) {
        send({ id, dataUrl, originalBytes, finalBytes: originalBytes, error: '' })
        return
      }

      const img = await loadImage(dataUrl)
      const maxDim = 1568

      let width = img.naturalWidth || img.width
      let height = img.naturalHeight || img.height
      const initialScale = Math.min(1, maxDim / Math.max(width, height))
      width = Math.max(1, Math.round(width * initialScale))
      height = Math.max(1, Math.round(height * initialScale))

      const canvas = document.createElement('canvas')
      const ctx = canvas.getContext('2d')

      const render = (w, h, quality) => {
        canvas.width = w
        canvas.height = h
        ctx.drawImage(img, 0, 0, w, h)
        return canvas.toDataURL('image/jpeg', quality)
      }

      // Quality ladder at the initial dimensions.
      const qualitySteps = [0.85, 0.75, 0.65, 0.55, 0.45]
      let result = null
      let finalBytes = Infinity

      for (const q of qualitySteps) {
        result = render(width, height, q)
        finalBytes = base64ByteLength(result)
        if (finalBytes <= maxBytes) break
      }

      // Still too big — shrink dimensions 20% at a time at quality 0.55.
      while (finalBytes > maxBytes && Math.max(width, height) > 600) {
        width = Math.max(1, Math.round(width * 0.8))
        height = Math.max(1, Math.round(height * 0.8))
        result = render(width, height, 0.55)
        finalBytes = base64ByteLength(result)
      }

      if (finalBytes > maxBytes) {
        send({
          id,
          dataUrl: '',
          originalBytes,
          finalBytes,
          error: `couldn't shrink image below ${maxBytes} bytes (got ${finalBytes})`,
        })
        return
      }

      send({ id, dataUrl: result, originalBytes, finalBytes, error: '' })
    } catch (err) {
      console.error('[ocr-resize] failed:', err)
      send({
        id,
        dataUrl: '',
        originalBytes,
        finalBytes: 0,
        error: String(err && err.message ? err.message : err),
      })
    }
  })

  // Proxy OCR through the Ternpike-hosted /scan Worker endpoint.
  // Uses Basic auth (same email:password as PouchDB sync) — Elm has no
  // built-in base64 encoder so this must go through JS. The Worker
  // returns Anthropic's /v1/messages response shape verbatim.
  app.ports.scanProxyOut.subscribe(async ({ backendUrl, body, itemId }) => {
    try {
      const auth = basicAuthHeader()
      if (!auth) {
        app.ports.scanProxyIn.send({ body: 'unauthorized', itemId, ok: false, status: 401 })
        return
      }
      const resp = await fetch(`${backendUrl}/scan`, {
        method: 'POST',
        headers: { Authorization: auth, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })
      const text = await resp.text()
      app.ports.scanProxyIn.send({ body: text, itemId, ok: resp.ok, status: resp.status })
    } catch (err) {
      app.ports.scanProxyIn.send({ body: String(err), itemId, ok: false, status: 0 })
    }
  })

  app.ports.extractExifGps.subscribe(async ({ id, dataUrl }) => {
    try {
      const res    = await fetch(dataUrl)
      const buffer = await res.arrayBuffer()
      const exif   = await exifr.parse(buffer, { gps: true, tiff: true, ifd0: true, exif: true })
      console.log('[exifr] parsed tags:', exif)
      const debug  = JSON.stringify(exif ?? null, null, 2)

      if (exif && typeof exif.latitude === 'number' && typeof exif.longitude === 'number') {
        console.log('[exifr] GPS found:', exif.latitude, exif.longitude)
        app.ports.gotExifResult.send({ id, lat: exif.latitude, lon: exif.longitude, hasGps: true, debug: '' })
      } else {
        console.log('[exifr] no GPS in image')
        app.ports.gotExifResult.send({ id, lat: 0, lon: 0, hasGps: false, debug })
      }
    } catch (err) {
      console.error('[exifr] parse error:', err)
      app.ports.gotExifResult.send({ id, lat: 0, lon: 0, hasGps: false, debug: String(err) })
    }
  })

  // ── PWA service worker + "New version available" toast (#477) ──────────
  //
  // `sw.js` no longer calls `skipWaiting()` in `install`, so a new worker
  // parks in `waiting` until the user taps Reload. This block is the other
  // half of that contract: notice the waiting worker, tell Elm, and reload
  // exactly once when it takes control.
  //
  // Gated behind `!isVerify` for the same reason `emitNotificationState()`
  // is: a real waiting worker during `npm run verify:dom` would flip the
  // seeded UpdateToast fixture and make the DOM tier nondeterministic.
  //
  // This is a SECOND, independent resume path from the iOS viewport heal
  // above. They stay separate; the heal's listeners are registered earlier in
  // this file, so for a shared event the heal runs first (heal-then-update),
  // and unlike the heal this block runs on every platform, not just
  // installed-iOS.
  if ('serviceWorker' in navigator && !isVerify) {
    const UPDATE_THROTTLE_MS = 5 * 60 * 1000
    const UPDATE_RACE_MS = 10000
    const ACTIVATION_FALLBACK_MS = 4000

    // Objects, not booleans. `controller` is null on a first-ever visit and
    // on any page a worker hasn't claimed; comparing IDENTITY later answers
    // "a *different* worker took over", which a boot-time boolean cannot.
    const bootController = navigator.serviceWorker.controller

    // `CACHE` in sw.js is stamped as `ternpike-<sha8>` (see vite.config.js),
    // while `__BUILD_SHA__` is the full sha — line them up before comparing.
    const runningCache = `ternpike-${String(__BUILD_SHA__).slice(0, 8)}`

    let bootActive = null
    let waitingWorker = null
    // Two INDEPENDENT flags. Sharing one (an "unrequested claim?" boolean
    // doubling as "did the user authorize this?") makes Reload a no-op in the
    // headline case: session starts uncontrolled → becomes controlled →
    // deploy → tap → suppressed.
    let userRequestedUpdate = false
    let reloading = false
    // `register()` below soft-updates already, so the window opens now.
    let lastUpdateCheck = Date.now()

    const notifyElm = (ready) => {
      if (app.ports.swUpdateReady) app.ports.swUpdateReady.send(ready)
    }

    const reloadOnce = () => {
      if (reloading) return
      reloading = true
      window.location.reload()
    }

    // Ask a worker which cache generation it would serve. Resolves `null`
    // when it doesn't answer within the budget (a wedged or older worker).
    const workerVersion = (worker) =>
      new Promise((resolve) => {
        let settled = false
        const done = (v) => {
          if (settled) return
          settled = true
          resolve(v)
        }
        try {
          const channel = new MessageChannel()
          channel.port1.onmessage = (e) => done((e.data && e.data.version) || null)
          worker.postMessage({ type: 'GET_VERSION' }, [channel.port2])
        } catch (err) {
          done(null)
        }
        setTimeout(() => done(null), 2000)
      })

    const retract = (worker) => {
      if (waitingWorker !== worker) return
      waitingWorker = null
      notifyElm(false)
    }

    const announce = async (worker) => {
      // The worker that was already active when this page booted is the one
      // serving it — never a reason to offer an update.
      if (worker === bootActive) return
      const version = await workerVersion(worker)
      // The fetch handler is network-first, so an ordinary refresh after a
      // deploy already runs the NEW bundle while the old worker still
      // controls the page — and that same navigation installs the new worker
      // → waiting → a toast on a page that IS the new version. Suppress
      // exactly that. A worker that doesn't answer (`null`) is announced: a
      // missing toast is a dead feature, a spurious one is only noise.
      if (version !== null && version === runningCache) return
      waitingWorker = worker
      notifyElm(true)
    }

    // Detection has to be exhaustive or the toast silently never appears for
    // the WHOLE session — a second `update()` does not re-fire `updatefound`
    // for a worker already parked in `waiting`.
    const track = (worker) => {
      if (!worker) return
      const evaluate = () => {
        if (worker.state === 'installed' || worker.state === 'activated') {
          // `installed` and `activated` are both "ready". Note there is no
          // `navigator.serviceWorker.controller` guard: on an UNCONTROLLED
          // page a new worker auto-activates with no client to wait for —
          // exactly the version-skew case the old condition hid.
          announce(worker)
        } else if (worker.state === 'redundant') {
          // A failed activation must not leave a permanent toast behind.
          retract(worker)
        }
      }
      // `statechange` never re-fires a transition that already happened, so
      // read the current state immediately as well as subscribing.
      evaluate()
      worker.addEventListener('statechange', evaluate)
    }

    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (reloading) return
      const claimedByNewWorker =
        bootController !== null && navigator.serviceWorker.controller !== bootController
      if (!userRequestedUpdate && !claimedByNewWorker) return
      // `controllerchange` fires in EVERY claimed client, so one tab's Reload
      // would otherwise discard another tab's half-typed expense.
      if (!userRequestedUpdate && !document.hidden) return
      reloadOnce()
    })

    if (app.ports.applySwUpdate) {
      app.ports.applySwUpdate.subscribe(async () => {
        userRequestedUpdate = true
        // Resolve the registration at TAP time. A `reg` closed over from boot
        // throws `InvalidStateError` once Safari/ITP has evicted it.
        let reg = null
        try {
          reg = await navigator.serviceWorker.getRegistration()
        } catch (err) {
          console.warn('[sw] getRegistration failed on apply:', err)
        }
        const waiting = (reg && reg.waiting) || waitingWorker
        if (!waiting) {
          // Network-first makes an unconditional reload always correct.
          reloadOnce()
          return
        }
        // The dangerous case is NOT "no waiting worker" — it's a waiting
        // worker that never activates (WebKit 199110 was open iOS 12.3 → 16).
        // This fallback closes the entire "Reload does nothing" class.
        setTimeout(reloadOnce, ACTIVATION_FALLBACK_MS)
        waiting.postMessage({ type: 'SKIP_WAITING' })
      })
    }

    const withTimeout = (promise, ms) =>
      Promise.race([promise, new Promise((resolve) => setTimeout(() => resolve(null), ms))])

    // Re-emit the held state on every tick. `Main.updateAuth` is only reached
    // from `AuthModel`: `( AuthMsg _, GuestModel gs )` DROPS the message. The
    // registration resolves within the first second of boot, so for a
    // logged-out user the notification would be discarded and never re-sent —
    // no toast for the rest of the session, precisely when the shipped fix
    // might be an auth fix. Holding the state here and re-emitting lets Elm
    // converge no matter which model was mounted when the worker landed.
    const reemit = () => {
      if (waitingWorker) notifyElm(true)
    }

    const onResume = async () => {
      // Deliberately NOT filtered on `document.hidden`: WebKit 202399 reports
      // the wrong visibility state in standalone. The throttle de-duplicates.
      if (navigator.onLine === false) return
      if (Date.now() - lastUpdateCheck < UPDATE_THROTTLE_MS) {
        reemit()
        return
      }
      let reg = null
      try {
        reg = await navigator.serviceWorker.getRegistration()
      } catch (err) {
        reg = null
      }
      if (!reg) {
        // Safari/ITP evicts registrations after ~7 days without interaction —
        // exactly this app's user. Re-register rather than give up.
        try {
          reg = await navigator.serviceWorker.register('/sw.js')
        } catch (err) {
          console.warn('[sw] re-register on resume failed:', err)
          return
        }
      }
      if (!reg) return
      // A wedged registration HANGS rather than rejecting, so try/catch alone
      // buys nothing — race it against a timeout.
      const settled = await withTimeout(
        reg.update().then(() => true).catch(() => null),
        UPDATE_RACE_MS,
      )
      // Throttle timestamp advances only on success.
      if (settled) lastUpdateCheck = Date.now()
      track(reg.waiting)
      track(reg.installing)
      reemit()
    }

    document.addEventListener('visibilitychange', onResume)
    window.addEventListener('pageshow', onResume)
    window.addEventListener('focus', onResume)
    window.addEventListener('online', onResume)

    navigator.serviceWorker.register('/sw.js')
      .then(reg => {
        bootActive = reg.active
        // Three call sites, one helper. A worker can already be parked in
        // `waiting` (or mid-`installing`) before this promise resolves.
        track(reg.waiting)
        track(reg.installing)
        reg.addEventListener('updatefound', () => {
          // `reg.installing` can already have advanced by the time this
          // fires; the old `const w = reg.installing; if (!w) return` bailed
          // silently and killed the toast for the whole session.
          track(reg.installing || reg.waiting)
        })
      })
      .catch(err => console.error('[sw] registration failed:', err))
  }

  // ── PWA notifications (push) ───────────────────────────────────────────
  //
  // Bridges Elm's `notificationState` / `pushSubscribeResult` ports to the
  // Web Push API. The Elm side stays purely declarative — it asks for
  // permission, asks to subscribe, asks to flip a pref — and the JS side
  // does the imperative browser work and reports the resulting state.
  //
  // Boot-time emit: feature-detect Notifications + PushManager + SW. If
  // missing, send one `{ permission: 'unsupported', ... }` event so Elm
  // can render the "not supported" UI and skip wiring further handlers.
  // If present, read the current Notification.permission, standalone
  // mode, and existing subscription state — then send that one combined
  // event before subscribing the outbound ports.
  //
  // The subscribe / preferences endpoints don't exist yet (server work
  // is filed under #179 / #180). subscribePush + savePushPrefs will 404
  // until those land — handlers tolerate it gracefully so the local UI
  // state stays consistent.

  // Convert a URL-safe base64 VAPID public key into the Uint8Array
  // pushManager.subscribe expects. Standard MDN snippet.
  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
    const raw = atob(base64)
    const out = new Uint8Array(raw.length)
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
    return out
  }

  // Build a Basic auth header from the cached auth_creds. Returns null
  // if the user isn't signed in (the notification endpoints are auth-
  // gated, so callers should bail in that case).
  function basicAuthHeader() {
    if (!authCreds || !authCreds.email || !authCreds.password) return null
    return 'Basic ' + btoa(`${authCreds.email}:${authCreds.password}`)
  }

  const notificationsSupported =
    typeof window !== 'undefined' &&
    'Notification' in window &&
    'PushManager' in window &&
    'serviceWorker' in navigator

  // Read the current per-device subscription (if any) and the persisted
  // server-side prefs, then emit a single `notificationState` event so
  // Elm hydrates `notificationPermission`, `notificationPrefs`,
  // `pushSubscribed`, and `standalone` from frame zero.
  async function emitNotificationState() {
    if (!notificationsSupported) {
      app.ports.notificationState.send({
        permission: 'unsupported',
        prefs: { weeklyScanReminder: false },
        standalone: false,
        subscribed: false,
      })
      return
    }
    const standalone =
      window.matchMedia('(display-mode: standalone)').matches ||
      window.navigator.standalone === true
    const permission = Notification.permission
    let subscribed = false
    let endpoint = null
    let prefs = { weeklyScanReminder: false }
    let sub = null
    try {
      const reg = await navigator.serviceWorker.ready
      sub = await reg.pushManager.getSubscription()
      if (sub) {
        subscribed = true
        endpoint = sub.endpoint
      }
    } catch (err) {
      console.error('[notifications] getSubscription failed:', err)
    }
    if (subscribed && endpoint) {
      const auth = basicAuthHeader()
      if (auth) {
        try {
          const res = await fetch(
            `${flags.backendUrl}/notifications/preferences?endpoint=${encodeURIComponent(endpoint)}`,
            { headers: { Authorization: auth } },
          )
          if (res.ok) {
            const body = await res.json()
            if (body && body.prefs && typeof body.prefs === 'object') {
              prefs = {
                weeklyScanReminder: body.prefs.weeklyScanReminder === true,
              }
            }
          }
        } catch (err) {
          console.error('[notifications] preferences fetch failed:', err)
        }
      }
    }
    // Self-heal: re-register this device's subscription with the server.
    // Idempotent — the server upserts by sha256(endpoint). Covers the
    // case where the original POST failed silently (e.g. the Worker
    // route wasn't deployed yet, network blip, transient 5xx), leaving
    // the browser with a local subscription but no server-side record.
    // Fire-and-forget so it doesn't delay the boot-time UI hydration.
    if (subscribed && endpoint) {
      const auth = basicAuthHeader()
      if (auth) {
        const raw = sub.toJSON ? sub.toJSON() : null
        const keys = raw && raw.keys ? raw.keys : null
        if (keys && keys.auth && keys.p256dh) {
          fetch(`${flags.backendUrl}/notifications/subscribe`, {
            method: 'POST',
            headers: {
              Authorization: auth,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              endpoint,
              keys: { auth: keys.auth, p256dh: keys.p256dh },
              subscriptions: prefs,
            }),
          })
            .then((res) => {
              if (!res.ok) {
                console.error('[notifications] self-heal POST returned', res.status)
              }
            })
            .catch((err) => {
              console.error('[notifications] self-heal POST failed:', err)
            })
        }
      }
    }
    app.ports.notificationState.send({ permission, prefs, standalone, subscribed })
  }

  // Fire-and-forget initial emit. The await chain is internal — we
  // don't gate the rest of init on it. Skipped on /verify routes so the
  // seeded fixture's notification/standalone state isn't clobbered by the
  // real device state (same reasoning as the attachPouch skip above).
  if (!isVerify) emitNotificationState()

  if (notificationsSupported && app.ports.subscribePush) {
    app.ports.subscribePush.subscribe(async ({ prefs, vapidPublicKey }) => {
      if (!vapidPublicKey) {
        app.ports.pushSubscribeResult.send({
          ok: false,
          error: 'VAPID public key not configured',
        })
        return
      }
      // iOS Safari (16.4+ PWA) requires Notification.permission to be
      // 'granted' BEFORE pushManager.subscribe is called, and the whole
      // chain must stay inside the user-gesture context that triggered
      // the port. So we await the prompt here (only when needed) rather
      // than letting Elm fire it in parallel via Cmd.batch.
      if (Notification.permission === 'default') {
        try {
          await Notification.requestPermission()
        } catch (err) {
          console.error('[notifications] requestPermission failed:', err)
        }
      }
      if (Notification.permission !== 'granted') {
        app.ports.pushSubscribeResult.send({
          ok: false,
          error: 'Notification permission not granted',
        })
        await emitNotificationState()
        return
      }
      try {
        const reg = await navigator.serviceWorker.ready
        const sub = await reg.pushManager.subscribe({
          applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
          userVisibleOnly: true,
        })
        const auth = basicAuthHeader()
        const raw = sub.toJSON ? sub.toJSON() : null
        const body = {
          endpoint: sub.endpoint,
          keys: raw && raw.keys ? raw.keys : {},
          subscriptions: prefs,
        }
        if (auth) {
          try {
            const res = await fetch(`${flags.backendUrl}/notifications/subscribe`, {
              method: 'POST',
              headers: {
                Authorization: auth,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify(body),
            })
            if (!res.ok) {
              console.error('[notifications] subscribe POST returned', res.status, await res.text().catch(() => ''))
            }
          } catch (err) {
            console.error('[notifications] subscribe POST failed:', err)
          }
        }
        app.ports.pushSubscribeResult.send({ ok: true, error: '' })
      } catch (err) {
        console.error('[notifications] pushManager.subscribe failed:', err)
        app.ports.pushSubscribeResult.send({
          ok: false,
          error: String(err && err.message ? err.message : err),
        })
      }
      await emitNotificationState()
    })
  }

  if (notificationsSupported && app.ports.unsubscribePush) {
    app.ports.unsubscribePush.subscribe(async () => {
      try {
        const reg = await navigator.serviceWorker.ready
        const sub = await reg.pushManager.getSubscription()
        if (sub) {
          const auth = basicAuthHeader()
          if (auth) {
            try {
              await fetch(`${flags.backendUrl}/notifications/subscribe`, {
                method: 'DELETE',
                headers: {
                  Authorization: auth,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({ endpoint: sub.endpoint }),
              })
            } catch (err) {
              console.error('[notifications] unsubscribe DELETE failed:', err)
            }
          }
          await sub.unsubscribe()
        }
      } catch (err) {
        console.error('[notifications] unsubscribe failed:', err)
      }
      await emitNotificationState()
    })
  }

  app.ports.nativeShare.subscribe(async ({ mode, title, text, url }) => {
    const send = (payload) => {
      if (app.ports.nativeShareResult) {
        app.ports.nativeShareResult.send(payload)
      }
    }
    const reportClipboard = async () => {
      try {
        await navigator.clipboard.writeText(url)
        send({ ok: true, reason: 'clipboard' })
      } catch {
        send({ ok: false, reason: 'unsupported' })
      }
    }
    if (mode === 'copy' || !navigator.share) {
      await reportClipboard()
      return
    }
    try {
      await navigator.share({ title, text, url })
      send({ ok: true, reason: 'native' })
    } catch (err) {
      if (err && err.name === 'AbortError') {
        send({ ok: false, reason: 'cancelled' })
      } else {
        await reportClipboard()
      }
    }
  })

  app.ports.downloadFile.subscribe(({ filename, content, mimeType }) => {
    const blob = new Blob([content], { type: mimeType })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    a.click()
    URL.revokeObjectURL(url)
  })

  if (notificationsSupported && app.ports.savePushPrefs) {
    app.ports.savePushPrefs.subscribe(async (prefs) => {
      try {
        const reg = await navigator.serviceWorker.ready
        const sub = await reg.pushManager.getSubscription()
        if (!sub) return
        const auth = basicAuthHeader()
        if (!auth) return
        await fetch(`${flags.backendUrl}/notifications/preferences`, {
          method: 'PUT',
          headers: {
            Authorization: auth,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ endpoint: sub.endpoint, prefs }),
        })
        // Tolerate failure silently — Elm state is the optimistic
        // source of truth, cron re-checks tier independently.
      } catch (err) {
        console.error('[notifications] savePushPrefs failed:', err)
      }
    })
  }

  // ── Nest funnel analytics (#340) ──────────────────────────────────────────
  // Fire-and-forget beacon to POST /invite/track. No auth, no PII — the
  // payload is { stage, flockId } only. Failures are swallowed silently so
  // a blocked beacon never disrupts the funnel UX.
  if (app.ports.trackFunnel) {
    app.ports.trackFunnel.subscribe(({ stage, flockId }) => {
      fetch(`${flags.backendUrl}/invite/track`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ flockId, stage }),
      }).catch(() => {
        // Beacon failures are intentionally swallowed — analytics must
        // never block or degrade the funnel.
      })
    })
  }

})()
