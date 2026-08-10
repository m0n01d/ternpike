// The sticker designs.
//
// Each entry is a die-cut sticker: a silhouette (`cut`) plus artwork drawn
// inside it. `cut(0)` is the outer trim; the artwork field is drawn at
// `cut(KEYLINE)` so every sticker carries the white border a die cutter
// needs for registration slop.
//
// Coordinates are 1/100 inch — the numbers in a design read as hundredths
// of an inch on the finished sticker, which is the unit you actually think
// in when you're deciding whether a line of type will survive at 2 inches
// wide.

import {
  KEYLINE,
  bird,
  circle,
  dottedRoute,
  ellipse,
  milepost,
  noSignal,
  receipt,
  roundedRect,
} from './shapes.mjs'
import { qrCard, qrTarget } from './qr.mjs'
import { arcText, text } from './type.mjs'

// Straight from src/theme.css — the sticker kit and the app must not drift
// into two different greens.
export const C = {
  cream: '#f2ede3',
  forest: '#2d3a22',
  forestDeep: '#1a2412',
  ink: '#1e2818',
  moss: '#6b7c58',
  muted: '#8a8a78',
  parchment: '#faf7f0',
  rust: '#b85c38',
  tan: '#d4c9a8',
}

const line = (x1, y1, x2, y2, stroke, width = 1.4, extra = '') =>
  `<path d="M${x1} ${y1}H${x2}" stroke="${stroke}" stroke-width="${width}" stroke-linecap="round" ${extra}/>`

export const stickers = [
  // ── 1. Park badge ────────────────────────────────────────────────────
  {
    blurb: '3in round. The flagship — national-park badge, arc-set type.',
    cut: circle(300),
    h: 300,
    slug: 'badge-tern',
    title: 'Tern badge',
    w: 300,
    art: (f, cut) => `
      <path d="${cut(KEYLINE)}" fill="${C.forest}"/>
      <circle cx="150" cy="150" r="137" fill="none" stroke="${C.rust}" stroke-width="2.2"/>
      <circle cx="150" cy="150" r="102" fill="none" stroke="${C.cream}" stroke-width="1.2" opacity="0.4"/>
      ${arcText(f['DMMono-Medium'], 'TRACK EVERY TURN OF THE ROAD', {
        centerDeg: 0,
        cx: 150,
        cy: 150,
        fill: C.cream,
        letterSpacing: 0.16,
        r: 110,
        size: 12,
      })}
      ${arcText(f['DMMono-Medium'], 'TERNPIKE.COM', {
        centerDeg: 180,
        cx: 150,
        cy: 150,
        fill: C.tan,
        flip: true,
        letterSpacing: 0.34,
        r: 124,
        size: 11.5,
      })}
      <g fill="${C.rust}">
        <path d="M33 150l7-7 7 7-7 7z"/>
        <path d="M253 150l7-7 7 7-7 7z"/>
      </g>
      ${bird({ dark: C.forestDeep, light: C.cream, scale: 1.2, x: 150, y: 112 })}
      <path d="${text(f['PlayfairDisplay-Black'], 'Ternpike', {
        anchor: 'middle',
        size: 40,
        x: 150,
        y: 172,
      })}" fill="${C.cream}"/>
      ${line(104, 184, 196, 184, C.rust, 1.6)}
      <path d="${text(f['DMMono-Medium'], 'ALASKA HIGHWAY · MILE 0', {
        anchor: 'middle',
        letterSpacing: 0.14,
        size: 8.5,
        x: 150,
        y: 200,
      })}" fill="${C.tan}"/>
    `,
  },

  // ── 2. Wordmark bar ──────────────────────────────────────────────────
  {
    blurb: '3.2 × 1.1in. Bumper/laptop-edge wordmark with the tern soaring off the end.',
    cut: roundedRect(320, 110, 20),
    h: 110,
    slug: 'wordmark-rust',
    title: 'Wordmark bar',
    w: 320,
    art: (f, cut) => `
      <path d="${cut(KEYLINE)}" fill="${C.rust}"/>
      <path d="${cut(15)}" fill="none" stroke="${C.cream}" stroke-width="1" opacity="0.45"/>
      <path d="${text(f['PlayfairDisplay-Black'], 'Ternpike', { size: 46, x: 28, y: 64 })}" fill="${C.cream}"/>
      <path d="${text(f['DMMono-Medium'], 'ternpike.com', {
        letterSpacing: 0.2,
        size: 9,
        x: 30,
        y: 86,
      })}" fill="${C.cream}" opacity="0.85"/>
      ${bird({ dark: C.forestDeep, light: C.cream, scale: 0.62, x: 268, y: 50 })}
    `,
  },

  // ── 3. Milepost ──────────────────────────────────────────────────────
  {
    blurb: '1.4 × 3in. Highway milepost — every trip starts at mile zero.',
    cut: milepost(140, 300),
    h: 300,
    slug: 'milepost-zero',
    title: 'Milepost',
    w: 140,
    art: (f, cut) => `
      <path d="${cut(KEYLINE)}" fill="${C.forest}"/>
      <path d="${cut(16)}" fill="none" stroke="${C.cream}" stroke-width="1.1" opacity="0.35"/>
      ${bird({ dark: C.forestDeep, light: C.cream, scale: 0.44, x: 70, y: 50 })}
      <path d="${text(f['DMMono-Medium'], 'MILE', {
        anchor: 'middle',
        letterSpacing: 0.34,
        size: 13,
        x: 74,
        y: 104,
      })}" fill="${C.tan}"/>
      <path d="${text(f['PlayfairDisplay-Black'], '0', {
        anchor: 'middle',
        size: 82,
        x: 70,
        y: 186,
      })}" fill="${C.cream}"/>
      ${line(42, 204, 98, 204, C.rust, 1.8)}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE', {
        anchor: 'middle',
        letterSpacing: 0.26,
        size: 11,
        x: 74,
        y: 230,
      })}" fill="${C.cream}"/>
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: 8,
        x: 71,
        y: 268,
      })}" fill="${C.cream}" opacity="0.6"/>
    `,
  },

  // ── 4. No signal ─────────────────────────────────────────────────────
  {
    blurb: '2.6 × 1.2in. The offline-first pitch as a one-liner.',
    cut: roundedRect(260, 120, 17),
    h: 120,
    slug: 'no-signal',
    title: 'No signal, no problem',
    w: 260,
    art: (f, cut) => `
      <path d="${cut(KEYLINE)}" fill="${C.cream}"/>
      <path d="${cut(16)}" fill="none" stroke="${C.rust}" stroke-width="1.4"/>
      ${noSignal({ cx: 54, cy: 64, slash: C.rust, stroke: C.forest })}
      <path d="${text(f['PlayfairDisplay-Bold'], 'No signal,', { size: 26, x: 90, y: 56 })}" fill="${C.forest}"/>
      <path d="${text(f['PlayfairDisplay-Italic'], 'no problem.', { size: 26, x: 90, y: 82 })}" fill="${C.forest}"/>
      <path d="${text(f['DMMono-Medium'], 'ternpike.com', {
        letterSpacing: 0.2,
        size: 7.5,
        x: 91,
        y: 101,
      })}" fill="${C.rust}"/>
    `,
  },

  // ── 5. Receipt ───────────────────────────────────────────────────────
  {
    blurb: '1.6 × 3.2in. Die-cut receipt with a torn edge — the product in one object.',
    cut: receipt(160, 320, 7),
    h: 320,
    qr: 'receipt',
    slug: 'receipt',
    title: 'Receipt',
    w: 160,
    art: (f, cut) => {
      const rows = [
        ['FUEL', '62.40'],
        ['CAMPGROUND', '28.00'],
        ['DINER', '19.75'],
        ['PIE', '6.50'],
      ]
      const body = rows
        .map(
          ([label, amount], i) => `
          <path d="${text(f['DMMono-Regular'], label, { size: 9.5, x: 20, y: 90 + i * 18 })}" fill="${C.forest}"/>
          <path d="${text(f['DMMono-Regular'], amount, {
            anchor: 'end',
            size: 9.5,
            x: 140,
            y: 90 + i * 18,
          })}" fill="${C.forest}"/>`,
        )
        .join('')
      return `
      <path d="${cut(KEYLINE)}" fill="${C.cream}"/>
      <path d="${text(f['PlayfairDisplay-Bold'], 'Ternpike', {
        anchor: 'middle',
        size: 21,
        x: 80,
        y: 44,
      })}" fill="${C.forest}"/>
      <path d="${text(f['DMMono-Regular'], 'ALASKA HIGHWAY', {
        anchor: 'middle',
        letterSpacing: 0.18,
        size: 6.5,
        x: 81,
        y: 58,
      })}" fill="${C.muted}"/>
      ${line(20, 70, 140, 70, C.muted, 1, 'stroke-dasharray="3 3" opacity="0.8"')}
      ${body}
      ${line(20, 158, 140, 158, C.muted, 1, 'stroke-dasharray="3 3" opacity="0.8"')}
      <path d="${text(f['DMMono-Medium'], 'TOTAL', { letterSpacing: 0.12, size: 10, x: 20, y: 178 })}" fill="${C.forest}"/>
      <path d="${text(f['PlayfairDisplay-Bold'], '116.65', {
        anchor: 'end',
        size: 17,
        x: 140,
        y: 179,
      })}" fill="${C.forest}"/>
      <path d="${text(f['DMMono-Medium'], 'LOGGED OFFLINE', {
        anchor: 'middle',
        letterSpacing: 0.2,
        size: 7,
        x: 81,
        y: 196,
      })}" fill="${C.rust}"/>
      ${qrCard({ dark: C.forest, light: C.cream, size: 74, slug: 'receipt', x: 43, y: 204 })}
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.14,
        size: 8,
        x: 81,
        y: 296,
      })}" fill="${C.forest}"/>
    `
    },
  },

  // ── 6. Orlando → Juneau ──────────────────────────────────────────────
  {
    blurb: '3.2 × 1.6in. The hero line, route plotted behind it, QR on the right.',
    cut: roundedRect(320, 160, 18),
    h: 160,
    qr: 'route',
    slug: 'orlando-juneau',
    title: 'Orlando to Juneau',
    w: 320,
    art: (f, cut) => `
      <path d="${cut(KEYLINE)}" fill="${C.forest}"/>
      ${dottedRoute({ bend: 42, fill: C.moss, from: [36, 128], opacity: 0.5, to: [190, 42] })}
      <circle cx="36" cy="128" r="3.5" fill="${C.cream}" opacity="0.7"/>
      <circle cx="190" cy="42" r="5" fill="${C.rust}"/>
      <path d="${text(f['PlayfairDisplay-Italic'], 'Every dollar,', {
        anchor: 'middle',
        size: 24,
        x: 112,
        y: 66,
      })}" fill="${C.cream}"/>
      <path d="${text(f['PlayfairDisplay-Italic'], 'Orlando to Juneau.', {
        anchor: 'middle',
        size: 24,
        x: 112,
        y: 94,
      })}" fill="${C.cream}"/>
      ${line(84, 110, 140, 110, C.rust, 1.5)}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.26,
        size: 7.5,
        x: 113,
        y: 128,
      })}" fill="${C.tan}"/>
      ${qrCard({ dark: C.forestDeep, light: C.cream, size: 84, slug: 'route', x: 218, y: 38 })}
    `,
  },

  // ── 7. Cabin or truck ────────────────────────────────────────────────
  {
    blurb: '2.8 × 1.5in oval. The joke sticker — the decision the app exists to inform.',
    cut: ellipse(280, 150),
    h: 150,
    slug: 'cabin-or-truck',
    title: 'Cabin or truck',
    w: 280,
    art: (f, cut) => `
      <path d="${cut(KEYLINE)}" fill="${C.tan}"/>
      <path d="${cut(15)}" fill="none" stroke="${C.forest}" stroke-width="1.1" opacity="0.5"/>
      <path d="${text(f['PlayfairDisplay-Italic'], 'Splurge on the cabin', {
        anchor: 'middle',
        size: 22,
        x: 140,
        y: 62,
      })}" fill="${C.forest}"/>
      ${line(96, 78, 122, 78, C.rust, 1.2)}
      <path d="${text(f['DMMono-Medium'], 'OR', {
        anchor: 'middle',
        letterSpacing: 0.3,
        size: 8,
        x: 141,
        y: 81,
      })}" fill="${C.rust}"/>
      ${line(158, 78, 184, 78, C.rust, 1.2)}
      <path d="${text(f['PlayfairDisplay-Italic'], 'sleep in the truck.', {
        anchor: 'middle',
        size: 22,
        x: 140,
        y: 106,
      })}" fill="${C.forest}"/>
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.16,
        size: 7.5,
        x: 141,
        y: 126,
      })}" fill="${C.forest}" opacity="0.65"/>
    `,
  },

  // ── 8. Tern mark ─────────────────────────────────────────────────────
  {
    blurb: '1.5in round. The smallest one — mark plus URL, nothing else.',
    cut: circle(150),
    h: 150,
    slug: 'tern-mark',
    title: 'Tern mark',
    w: 150,
    art: (f, cut) => `
      <path d="${cut(KEYLINE)}" fill="${C.moss}"/>
      <circle cx="75" cy="75" r="61" fill="none" stroke="${C.cream}" stroke-width="1" opacity="0.35"/>
      ${bird({ dark: C.forestDeep, light: C.cream, scale: 0.92, x: 75, y: 60 })}
      ${arcText(f['DMMono-Medium'], 'TERNPIKE.COM', {
        centerDeg: 180,
        cx: 75,
        cy: 75,
        fill: C.cream,
        flip: true,
        letterSpacing: 0.22,
        r: 52,
        size: 10.5,
      })}
    `,
  },

  // ── 9. Trailhead scan card ───────────────────────────────────────────
  //
  // The one whose entire job is the scan: kiosk boards, campground
  // bulletin boards, the back of a gas pump. Everything else in the kit
  // is a brand object that happens to carry a URL; this is a call to
  // action that happens to be pretty.
  {
    blurb: '2 × 3in. QR-first — 1.5in symbol, for kiosk and bulletin boards.',
    cut: roundedRect(200, 300, 18),
    h: 300,
    qr: 'trailhead',
    slug: 'qr-trailhead',
    title: 'Trailhead scan card',
    w: 200,
    art: (f, cut) => `
      <path d="${cut(KEYLINE)}" fill="${C.forest}"/>
      ${qrCard({ dark: C.forestDeep, light: C.cream, radius: 6, size: 150, slug: 'trailhead', x: 25, y: 24 })}
      <path d="${text(f['PlayfairDisplay-Black'], 'Ternpike', {
        anchor: 'middle',
        size: 32,
        x: 100,
        y: 212,
      })}" fill="${C.cream}"/>
      <path d="${text(f['PlayfairDisplay-Italic'], 'Track every turn of the road.', {
        anchor: 'middle',
        size: 13,
        x: 100,
        y: 236,
      })}" fill="${C.cream}" opacity="0.85"/>
      ${line(70, 250, 130, 250, C.rust, 1.5)}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.24,
        size: 9.5,
        x: 101,
        y: 272,
      })}" fill="${C.tan}"/>
    `,
  },
]

/** Where a design's QR sends a scanner, or null if it carries only a URL. */
export const qrDestination = (sticker) => (sticker.qr ? qrTarget(sticker.qr) : null)
