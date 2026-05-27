// <waypoint-map> — Leaflet map that renders the encoded list of points
// from `Helpers.encodeWaypoints`. Lifted from the IIFE in src/main.js
// (#38, section 0). Side-effect import: importing this file registers the
// custom element via customElements.define.
//
// Attributes:
//   points='[{"lat":..,"lon":..,"label":"..","date":"..","dayLabel":"..","isDayBoundary":..}, ...]'
//     JSON-encoded array of waypoints. Re-render fires on attribute change.

import L from 'leaflet'
import 'leaflet.markercluster'

// Leaflet's marker DOM lives outside Tailwind's tree-shake reach, so
// these icons inline-style their HTML (same pattern as MapPicker).
function stopDotIcon() {
  return L.divIcon({
    className: 'tp-stop-dot',
    html: '<span style="display:block;width:10px;height:10px;border-radius:9999px;background:#9a4426;border:2px solid #f5efe2;box-shadow:0 0 0 1px #9a4426;"></span>',
    iconSize: [14, 14],
    iconAnchor: [7, 7],
  })
}

function dayPillIcon(label) {
  const safe = String(label || '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
  )
  return L.divIcon({
    className: 'tp-day-pill',
    html:
      '<span style="display:inline-block;background:#9a4426;color:#f5efe2;font:600 11px/1.4 system-ui,-apple-system,sans-serif;padding:3px 8px;border-radius:9999px;white-space:nowrap;box-shadow:0 1px 2px rgba(0,0,0,0.25);">' +
      safe +
      '</span>',
    iconSize: null,
    iconAnchor: [0, 0],
  })
}

// Cluster icon for the per-stop / per-day marker group. The icon
// reads the date range of its children — same-day clusters render as
// "Jun 10 · 5" (solves the day-pill / count-badge overlap), multi-day
// clusters render as "Jun 1–Jun 7 · 23" (the "bin days to weeks"
// behavior at low zoom). Pure-dot clusters with no day metadata fall
// back to a plain numeric badge.
function rangeClusterIcon(cluster) {
  const children = cluster.getAllChildMarkers()
  const dateToLabel = new Map()
  children.forEach(m => {
    const d = m.tpData
    if (d && d.date) dateToLabel.set(d.date, d.dayLabel || '')
  })
  const sortedDates = [...dateToLabel.keys()].sort()
  const labels = sortedDates.map(d => dateToLabel.get(d))
  const count = children.length
  const safe = s => String(s || '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
  )
  let labelText = ''
  if (labels.length === 1) {
    labelText = safe(labels[0])
  } else if (labels.length > 1) {
    labelText = safe(labels[0]) + '–' + safe(labels[labels.length - 1])
  }
  const inner = labelText
    ? labelText + '<span style="opacity:.6;margin:0 4px">·</span>' + count
    : String(count)
  return L.divIcon({
    className: 'tp-cluster-pill',
    html:
      '<span style="display:inline-flex;align-items:center;background:#9a4426;color:#f5efe2;font:600 11px/1.2 system-ui,-apple-system,sans-serif;padding:4px 10px;border-radius:9999px;white-space:nowrap;box-shadow:0 1px 2px rgba(0,0,0,0.25);">' +
      inner +
      '</span>',
    iconSize: null,
    iconAnchor: [0, 0],
  })
}

class WaypointMap extends HTMLElement {
  connectedCallback() {
    this._map = L.map(this).setView([64.2008, -153.4937], 6)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
    }).addTo(this._map)
    this._markers = []
    this._polyline = null
    this._clusters = null
    this._renderPoints(this.getAttribute('points'))
    setTimeout(() => this._map && this._map.invalidateSize(), 100)
    // Re-invalidate whenever the container resizes — the Ledger
    // small ⇄ expanded toggle flips a Tailwind height class, and
    // Leaflet's viewport otherwise stays stale until the next pan.
    this._resizeObserver = new ResizeObserver(() => {
      if (this._map) this._map.invalidateSize()
    })
    this._resizeObserver.observe(this)
  }

  disconnectedCallback() {
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
      this._resizeObserver = null
    }
    if (this._map) { this._map.remove(); this._map = null }
    this._markers = []
    this._polyline = null
    this._clusters = null
  }

  _renderPoints(raw) {
    this._markers.forEach(m => m.remove())
    this._markers = []
    if (this._polyline) { this._polyline.remove(); this._polyline = null }
    if (this._clusters) { this._clusters.remove(); this._clusters = null }
    let pts; try { pts = JSON.parse(raw || '[]') } catch (_) { return }
    if (!pts.length) return
    const lls = pts.map(p => [p.lat, p.lon])
    if (lls.length >= 2) {
      this._polyline = L.polyline(lls, {
        color: '#9a4426',
        weight: 3,
        opacity: 0.85,
      }).addTo(this._map)
    }
    // Every marker — day-boundary pills AND stop dots — goes into
    // the cluster group. The cluster icon (rangeClusterIcon) reads
    // each child's tpData.date / dayLabel to build a date-range
    // label, which (a) fixes the date-marker / count-badge overlap
    // when same-day stops cluster, and (b) bins days into ranges at
    // low zoom levels. maxClusterRadius tightens with zoom so
    // clicking a cluster zooms into real geographic positions
    // instead of a radial spiderfy; disableClusteringAtZoom forces
    // individual markers at street zoom.
    this._clusters = L.markerClusterGroup({
      disableClusteringAtZoom: 14,
      iconCreateFunction: rangeClusterIcon,
      maxClusterRadius: zoom =>
        zoom < 8 ? 60 : zoom < 12 ? 30 : 15,
      showCoverageOnHover: false,
      spiderfyOnMaxZoom: false,
    })
    pts.forEach(p => {
      const icon = p.isDayBoundary ? dayPillIcon(p.dayLabel) : stopDotIcon()
      const marker = L.marker([p.lat, p.lon], { icon })
      marker.tpData = p
      if (p.label) marker.bindPopup(p.label)
      this._clusters.addLayer(marker)
    })
    this._map.addLayer(this._clusters)
    if (lls.length === 1) this._map.setView(lls[0], 13)
    else this._map.fitBounds(lls, { padding: [40, 40] })
  }

  attributeChangedCallback(name, _old, val) {
    if (name === 'points' && this._map) this._renderPoints(val)
  }

  static get observedAttributes() { return ['points'] }
}

customElements.define('waypoint-map', WaypointMap)
