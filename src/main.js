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

  const IDB_NAME  = 'alaska-tracker'
  const IDB_STORE = 'kv'
  let _db = null

  function openDB() {
    if (_db) return Promise.resolve(_db)
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(IDB_NAME, 1)
      req.onupgradeneeded = e => e.target.result.createObjectStore(IDB_STORE)
      req.onsuccess  = e => { _db = e.target.result; resolve(_db) }
      req.onerror    = e => reject(e.target.error)
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

  // ── App keys for wipe ─────────────────────────────────────────────────
  const APP_KEYS = ['auth_creds', 'anthropic_key']

  // ── Load all persisted settings before starting Elm ───────────────────

  const [authCredsRaw, anthropicKey] = await Promise.all([
    idbGet('auth_creds'),
    idbGet('anthropic_key'),
  ])

  let authCreds = null
  if (authCredsRaw) {
    try {
      authCreds = JSON.parse(authCredsRaw)
    } catch (_) {
      authCreds = null
    }
  }

  const flags = {
    authCreds:      authCreds,
    anthropicKey:   anthropicKey  || '',
    backendUrl:     'https://api.ternpike.com',
    basePath:       import.meta.env.BASE_URL,
    colorScheme:    localStorage.getItem('color_scheme') || 'auto',
    today:          new Date().toISOString().slice(0, 10),
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

  attachPouch(app, { creds: authCreds })

  // ── Port handlers ──────────────────────────────────────────────────────

  app.ports.saveStorage.subscribe(async ({ key, value }) => {
    await idbSet(key, value)
    if (key === 'color_scheme') {
      localStorage.setItem('color_scheme', value)
      applyColorScheme(value)
    }
  })

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

  app.ports.clearStorage.subscribe(() => idbDel('auth_creds'))

  app.ports.clearAllStorage.subscribe(() => idbDel(...APP_KEYS))

  if (app.ports.printShareQr) {
    app.ports.printShareQr.subscribe(() => {
      // body.printing-share-qr flips a print-only stylesheet (global.css)
      // that hides everything except .print-share-qr. After the print
      // dialog closes (whether confirmed or cancelled), strip the class.
      document.body.classList.add('printing-share-qr')
      const cleanup = () => {
        document.body.classList.remove('printing-share-qr')
        window.removeEventListener('afterprint', cleanup)
      }
      window.addEventListener('afterprint', cleanup)
      window.print()
    })
  }

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

  // ── PWA service worker ─────────────────────────────────────────────────
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js')
      .then(reg => {
        reg.addEventListener('updatefound', () => {
          const newWorker = reg.installing
          if (!newWorker) return
          newWorker.addEventListener('statechange', () => {
            if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
              // New SW ready — tell it to activate immediately.
              newWorker.postMessage({ type: 'SKIP_WAITING' })
            }
          })
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
  // don't gate the rest of init on it.
  emitNotificationState()

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

})()
