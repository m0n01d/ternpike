// <map-picker> — full-screen Leaflet picker for selecting a lat/lon.
//
// Lifted from the IIFE in src/main.js (#38, section 0). Side-effect import:
// importing this file registers the custom element via customElements.define.
//
// Attributes:
//   lat="64.2008"   initial latitude
//   lon="-153.4937" initial longitude
//
// Events dispatched (bubbling):
//   confirm: { detail: { lat, lon } }  user tapped "Confirm location"
//   dismiss                            user tapped "Cancel"

import L from 'leaflet'

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
