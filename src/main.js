import { Elm } from './Main.elm'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
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

;(async function () {

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
    try { authCreds = JSON.parse(authCredsRaw) } catch (_) { authCreds = null }
  }

  const flags = {
    authCreds:    authCreds,
    anthropicKey: anthropicKey  || '',
    backendUrl:   'https://api.ternpike.com',
    basePath:     import.meta.env.BASE_URL,
    today:        new Date().toISOString().slice(0, 10),
    version:      __BUILD_SHA__,
  }

  // ── <map-picker> custom element ────────────────────────────────────────
  class MapPicker extends HTMLElement {
    connectedCallback() {
      this._overlay = document.createElement('div')
      Object.assign(this._overlay.style, {
        position: 'fixed', inset: '0', background: 'rgba(0,0,0,0.85)',
        zIndex: '9999', display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
      })

      const mapDiv = document.createElement('div')
      Object.assign(mapDiv.style, {
        width: 'min(460px,96vw)', height: '360px',
        borderRadius: '12px', overflow: 'hidden',
      })

      const toolbar = document.createElement('div')
      Object.assign(toolbar.style, {
        display: 'flex', gap: '12px', marginTop: '16px', width: 'min(460px,96vw)',
      })

      const confirmBtn = document.createElement('button')
      confirmBtn.textContent = 'Confirm location'
      Object.assign(confirmBtn.style, {
        flex: '1', background: '#e8a020', color: '#0d0f0e', border: 'none',
        borderRadius: '8px', padding: '14px', fontSize: '16px',
        fontWeight: '700', cursor: 'pointer', fontFamily: 'inherit',
      })

      const cancelBtn = document.createElement('button')
      cancelBtn.textContent = 'Cancel'
      Object.assign(cancelBtn.style, {
        background: 'none', border: '1px solid #3a4240', color: '#7a8a80',
        borderRadius: '8px', padding: '14px 20px', fontSize: '14px',
        cursor: 'pointer', fontFamily: 'inherit',
      })

      toolbar.append(confirmBtn, cancelBtn)
      this._overlay.append(mapDiv, toolbar)
      document.body.appendChild(this._overlay)

      const lat = parseFloat(this.getAttribute('lat') || '64.2008')
      const lon = parseFloat(this.getAttribute('lon') || '-153.4937')

      this._map = L.map(mapDiv).setView([lat, lon], 13)
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        maxZoom: 19,
      }).addTo(this._map)
      this._marker = L.marker([lat, lon], { draggable: true }).addTo(this._map)

      // Leaflet needs visible container before sizing correctly
      setTimeout(() => this._map && this._map.invalidateSize(), 100)

      confirmBtn.addEventListener('click', () => {
        const { lat: la, lng: lo } = this._marker.getLatLng()
        this.dispatchEvent(new CustomEvent('confirm', { detail: { lat: la, lon: lo }, bubbles: true }))
      })

      cancelBtn.addEventListener('click', () => {
        this.dispatchEvent(new CustomEvent('dismiss', { bubbles: true }))
      })
    }

    disconnectedCallback() {
      if (this._map) { this._map.remove(); this._map = null }
      if (this._overlay) { this._overlay.remove(); this._overlay = null }
    }

    attributeChangedCallback(name, _old, val) {
      if (!this._map || !this._marker) return
      if (name === 'lat' || name === 'lon') {
        const la = parseFloat(this.getAttribute('lat') || '64.2008')
        const lo = parseFloat(this.getAttribute('lon') || '-153.4937')
        this._map.setView([la, lo])
        this._marker.setLatLng([la, lo])
      }
    }

    static get observedAttributes() { return ['lat', 'lon'] }
  }

  customElements.define('map-picker', MapPicker)

  // ── <waypoint-map> custom element ──────────────────────────────────────
  class WaypointMap extends HTMLElement {
    connectedCallback() {
      this._map = L.map(this).setView([64.2008, -153.4937], 6)
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        maxZoom: 19,
      }).addTo(this._map)
      this._markers = []
      this._renderPoints(this.getAttribute('points'))
      setTimeout(() => this._map && this._map.invalidateSize(), 100)
    }

    disconnectedCallback() {
      if (this._map) { this._map.remove(); this._map = null }
      this._markers = []
    }

    _renderPoints(raw) {
      this._markers.forEach(m => m.remove())
      this._markers = []
      let pts; try { pts = JSON.parse(raw || '[]') } catch (_) { return }
      if (!pts.length) return
      const lls = []
      pts.forEach(p => {
        const m = L.marker([p.lat, p.lon]).addTo(this._map)
        if (p.label) m.bindPopup(p.label)
        this._markers.push(m)
        lls.push([p.lat, p.lon])
      })
      if (lls.length === 1) this._map.setView(lls[0], 13)
      else this._map.fitBounds(lls, { padding: [20, 20] })
    }

    attributeChangedCallback(name, _old, val) {
      if (name === 'points' && this._map) this._renderPoints(val)
    }

    static get observedAttributes() { return ['points'] }
  }

  customElements.define('waypoint-map', WaypointMap)

  // ── Start Elm ──────────────────────────────────────────────────────────

  const app = Elm.Main.init({ flags })

  attachPouch(app, { creds: authCreds })

  // ── Port handlers ──────────────────────────────────────────────────────

  app.ports.saveStorage.subscribe(async ({ key, value }) => {
    await idbSet(key, value)
  })

  // ── Network status ─────────────────────────────────────────────────────
  if (app.ports.networkStatus) {
    // Send initial state (before the listeners are attached, so Elm has the truth from frame zero)
    app.ports.networkStatus.send(navigator.onLine)
    window.addEventListener('online',  () => app.ports.networkStatus.send(true))
    window.addEventListener('offline', () => app.ports.networkStatus.send(false))
  }

  app.ports.clearStorage.subscribe(() => idbDel('auth_creds'))

  app.ports.clearAllStorage.subscribe(() => idbDel(...APP_KEYS))

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

})()
