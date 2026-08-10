// QR codes for the sticker kit.
//
// Every QR points at `https://ternpike.com/qr/<slug>`, not at the bare
// domain. That route is the existing tracked redirect in `server/qr.js`: it
// bumps a per-slug counter in QR_KV, rolls up the scanner's edge geo, and
// 302s to `ternpike.com/?ref=qr-<slug>`. Giving each sticker design its own
// slug means `GET /admin/qr` answers "which design actually gets scanned",
// which is the whole reason to put a QR on swag instead of just a URL.
//
// Verified live before baking into print: `curl -D- https://ternpike.com/qr/probe-test`
// returns 302 → `https://ternpike.com/?ref=qr-probe-test`. The route is
// `ternpike.com/qr/*` in `server/wrangler.toml`, pointed at the auth Worker.
// Unknown slugs redirect fine, so a design needs no registration step.

import qrcode from 'qrcode-generator'
import { round } from './type.mjs'

const BASE = 'https://ternpike.com/qr'

// Four modules of light margin on every side. The spec requires it and
// phone scanners genuinely fail without it — this is the one QR parameter
// you cannot eyeball on a proof, because it fails intermittently rather
// than obviously.
const QUIET = 4

// Error correction Q recovers ~25% of the symbol. On a sticker that will
// live on a bumper or a water bottle, that headroom is the difference
// between "scuffed" and "dead".
const EC = 'Q'

export const qrTarget = (slug) => `${BASE}/${slug}`

/**
 * A QR on a light card, sized to fill `size` INCLUDING its quiet zone.
 *
 * Sizing the card rather than the symbol is deliberate: it makes the quiet
 * zone structural instead of something a later layout tweak can eat.
 */
export function qrCard({ dark, light, radius = 3, size, slug, x, y }) {
  const qr = qrcode(0, EC)
  qr.addData(qrTarget(slug))
  qr.make()

  const n = qr.getModuleCount()
  const cell = size / (n + QUIET * 2)
  const cs = round(cell)
  const originX = x + cell * QUIET
  const originY = y + cell * QUIET

  const parts = []
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (!qr.isDark(r, c)) continue
      parts.push(`M${round(originX + c * cell)} ${round(originY + r * cell)}h${cs}v${cs}h-${cs}z`)
    }
  }

  return `<g shape-rendering="crispEdges">
    <rect x="${round(x)}" y="${round(y)}" width="${round(size)}" height="${round(size)}" rx="${radius}" fill="${light}"/>
    <path d="${parts.join('')}" fill="${dark}"/>
  </g>`
}
