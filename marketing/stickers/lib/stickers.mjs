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
//
// **Designs name roles, never colours.** `art` receives a profile `p` and
// paints with `p.dark` / `p.onDark` / `p.accent` and friends. That is what
// lets the identical design render as full-colour vinyl and as black-on-
// white thermal line art without two copies drifting apart. See
// `profiles.mjs`. If you find yourself reaching for a hex literal here,
// the role you want is missing — add it to both profiles instead.

import {
  KEYLINE,
  bird,
  circle,
  ellipse,
  milepost,
  noSignal,
  receipt,
  roundedRect,
} from './shapes.mjs'
import { COPY } from './copy.mjs'
import { qrCard, qrTarget } from './qr.mjs'
import { arcText, text } from './type.mjs'

/** Capitalise a fragment lifted from the middle of a sentence. */
const sentence = (s) => s.charAt(0).toUpperCase() + s.slice(1)

const line = (x1, y1, x2, y2, stroke, width = 1.4, extra = '') =>
  `<path d="M${x1} ${y1}H${x2}" stroke="${stroke}" stroke-width="${width}" stroke-linecap="round" ${extra}/>`

export const stickers = [
  // ── 1. Park badge ────────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '3in round. The flagship — national-park badge, arc-set type.',
    cut: circle(300),
    h: 300,
    slug: 'badge-tern',
    title: 'Tern badge',
    w: 300,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.dark}"/>
      <circle cx="150" cy="150" r="137" fill="none" stroke="${p.accent}" stroke-width="2.2"/>
      <circle cx="150" cy="150" r="102" fill="none" stroke="${p.onDark}" stroke-width="1.2" opacity="${p.dim(0.4)}"/>
      ${arcText(f['DMMono-Medium'], COPY.taglineCaps, {
        centerDeg: 0,
        cx: 150,
        cy: 150,
        fill: p.onDark,
        letterSpacing: 0.16,
        r: 110,
        size: 12,
      })}
      ${arcText(f['DMMono-Medium'], 'TERNPIKE.COM', {
        centerDeg: 180,
        cx: 150,
        cy: 150,
        fill: p.onDarkSoft,
        flip: true,
        letterSpacing: 0.34,
        r: 124,
        size: 11.5,
      })}
      <g fill="${p.accent}">
        <path d="M33 150l7-7 7 7-7 7z"/>
        <path d="M253 150l7-7 7 7-7 7z"/>
      </g>
      ${bird({ dark: p.markDark, light: p.onDark, scale: 1.2, x: 150, y: 112 })}
      <path d="${text(f['PlayfairDisplay-Black'], COPY.brand, {
        anchor: 'middle',
        size: 40,
        x: 150,
        y: 172,
      })}" fill="${p.onDark}"/>
      ${line(104, 184, 196, 184, p.accent, 1.6)}
      <path d="${text(f['DMMono-Medium'], COPY.madeOnCaps, {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: 8.5,
        x: 150,
        y: 200,
      })}" fill="${p.onDarkSoft}"/>
    `,
  },

  // ── 2. Wordmark bar ──────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '3.2 × 1.1in. Bumper/laptop-edge wordmark with the tern soaring off the end.',
    cut: roundedRect(320, 110, 20),
    h: 110,
    slug: 'wordmark-rust',
    title: 'Wordmark bar',
    w: 320,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.brand}"/>
      <path d="${cut(15)}" fill="none" stroke="${p.onDark}" stroke-width="1" opacity="${p.dim(0.45)}"/>
      <path d="${text(f['PlayfairDisplay-Black'], COPY.brand, { size: 46, x: 28, y: 64 })}" fill="${p.onDark}"/>
      <path d="${text(f['DMMono-Medium'], 'ternpike.com', {
        letterSpacing: 0.2,
        size: 9,
        x: 30,
        y: 86,
      })}" fill="${p.onDark}" opacity="${p.dim(0.85)}"/>
      ${bird({ dark: p.markDark, light: p.onDark, scale: 0.62, x: 268, y: 50 })}
    `,
  },

  // ── 3. Milepost ──────────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '1.4 × 3in. Highway milepost — every trip starts at mile zero.',
    cut: milepost(140, 300),
    h: 300,
    slug: 'milepost-zero',
    title: 'Milepost',
    w: 140,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.dark}"/>
      <path d="${cut(16)}" fill="none" stroke="${p.onDark}" stroke-width="1.1" opacity="${p.dim(0.35)}"/>
      ${bird({ dark: p.markDark, light: p.onDark, scale: 0.44, x: 70, y: 50 })}
      <path d="${text(f['DMMono-Medium'], 'MILE', {
        anchor: 'middle',
        letterSpacing: 0.34,
        size: 13,
        x: 74,
        y: 104,
      })}" fill="${p.onDarkSoft}"/>
      <path d="${text(f['PlayfairDisplay-Black'], '0', {
        anchor: 'middle',
        size: 82,
        x: 70,
        y: 186,
      })}" fill="${p.onDark}"/>
      ${line(42, 204, 98, 204, p.accent, 1.8)}
      <path d="${text(f['DMMono-Medium'], COPY.brand.toUpperCase(), {
        anchor: 'middle',
        letterSpacing: 0.26,
        size: 11,
        x: 74,
        y: 230,
      })}" fill="${p.onDark}"/>
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: 8,
        x: 71,
        y: 268,
      })}" fill="${p.onDark}" opacity="${p.dim(0.6)}"/>
    `,
  },

  // ── 4. No signal ─────────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '2.6 × 1.2in. The offline feature, by the name the site gives it.',
    cut: roundedRect(260, 120, 17),
    h: 120,
    slug: 'no-signal',
    title: 'Works without signal',
    w: 260,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      <path d="${cut(16)}" fill="none" stroke="${p.accent}" stroke-width="1.4"/>
      ${noSignal({ cx: 54, cy: 64, slash: p.accent, stroke: p.onLight })}
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.offlineLines[0], { size: 22, x: 90, y: 56 })}" fill="${p.onLight}"/>
      <path d="${text(f['PlayfairDisplay-Italic'], COPY.offlineLines[1], { size: 22, x: 90, y: 82 })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Medium'], 'ternpike.com', {
        letterSpacing: 0.2,
        size: 7.5,
        x: 91,
        y: 101,
      })}" fill="${p.accent}"/>
    `,
  },

  // ── 5. Receipt ───────────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '1.6 × 3.2in. Die-cut receipt with a torn edge — the product in one object.',
    cut: receipt(160, 320, 7),
    h: 320,
    qr: 'receipt',
    slug: 'receipt',
    title: 'Receipt',
    w: 160,
    art: (f, cut, p) => {
      const rows = [
        ['FUEL', '62.40'],
        ['CAMPGROUND', '28.00'],
        ['DINER', '19.75'],
        ['PIE', '6.50'],
      ]
      const body = rows
        .map(
          ([label, amount], i) => `
          <path d="${text(f['DMMono-Regular'], label, { size: 9.5, x: 20, y: 90 + i * 18 })}" fill="${p.onLight}"/>
          <path d="${text(f['DMMono-Regular'], amount, {
            anchor: 'end',
            size: 9.5,
            x: 140,
            y: 90 + i * 18,
          })}" fill="${p.onLight}"/>`,
        )
        .join('')
      return `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.brand, {
        anchor: 'middle',
        size: 21,
        x: 80,
        y: 44,
      })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Regular'], COPY.alaskaHighwayCaps, {
        anchor: 'middle',
        letterSpacing: 0.18,
        size: 6.5,
        x: 81,
        y: 58,
      })}" fill="${p.onLightSoft}"/>
      ${line(20, 70, 140, 70, p.onLightSoft, 1, `stroke-dasharray="3 3" opacity="${p.dim(0.8)}"`)}
      ${body}
      ${line(20, 158, 140, 158, p.onLightSoft, 1, `stroke-dasharray="3 3" opacity="${p.dim(0.8)}"`)}
      <path d="${text(f['DMMono-Medium'], 'TOTAL', { letterSpacing: 0.12, size: 10, x: 20, y: 178 })}" fill="${p.onLight}"/>
      <path d="${text(f['PlayfairDisplay-Bold'], '116.65', {
        anchor: 'end',
        size: 17,
        x: 140,
        y: 179,
      })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Medium'], COPY.offlineCaps, {
        anchor: 'middle',
        letterSpacing: 0.14,
        size: 7,
        x: 81,
        y: 196,
      })}" fill="${p.accent}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, size: 74, slug: 'receipt', x: 43, y: 204 })}
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.14,
        size: 8,
        x: 81,
        y: 296,
      })}" fill="${p.onLight}"/>
    `
    },
  },

  // ── 6. Orlando → Juneau ──────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '3.2 × 1.6in. The hero headline in full, QR on the right.',
    cut: roundedRect(320, 160, 18),
    h: 160,
    qr: 'route',
    slug: 'orlando-juneau',
    title: 'Orlando to Juneau',
    w: 320,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.dark}"/>
      ${COPY.heroLines
        .map(
          (heroLine, i) => `<path d="${text(f['PlayfairDisplay-Italic'], heroLine, {
        anchor: 'middle',
        size: 21,
        x: 112,
        y: 48 + i * 24,
      })}" fill="${p.onDark}"/>`,
        )
        .join('\n      ')}
      ${line(84, 112, 140, 112, p.accent, 1.5)}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.26,
        size: 7.5,
        x: 113,
        y: 130,
      })}" fill="${p.onDarkSoft}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, size: 84, slug: 'route', x: 218, y: 38 })}
    `,
  },

  // ── 7. Cabin or truck ────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '2.8 × 1.5in oval. The joke sticker — the decision the app exists to inform.',
    cut: ellipse(280, 150),
    h: 150,
    slug: 'cabin-or-truck',
    title: 'Cabin or truck',
    w: 280,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.warm}"/>
      <path d="${cut(15)}" fill="none" stroke="${p.onLight}" stroke-width="1.1" opacity="${p.dim(0.5)}"/>
      <path d="${text(f['PlayfairDisplay-Italic'], sentence(COPY.cabin), {
        anchor: 'middle',
        size: 22,
        x: 140,
        y: 62,
      })}" fill="${p.onLight}"/>
      ${line(96, 78, 122, 78, p.accent, 1.2)}
      <path d="${text(f['DMMono-Medium'], 'OR', {
        anchor: 'middle',
        letterSpacing: 0.3,
        size: 8,
        x: 141,
        y: 81,
      })}" fill="${p.accent}"/>
      ${line(158, 78, 184, 78, p.accent, 1.2)}
      <path d="${text(f['PlayfairDisplay-Italic'], COPY.truck.replace(/^or /, ''), {
        anchor: 'middle',
        size: 22,
        x: 140,
        y: 106,
      })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.16,
        size: 7.5,
        x: 141,
        y: 126,
      })}" fill="${p.onLight}" opacity="${p.dim(0.65)}"/>
    `,
  },

  // ── 8. Tern mark ─────────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '1.5in round. The smallest one — mark plus URL, nothing else.',
    cut: circle(150),
    h: 150,
    slug: 'tern-mark',
    title: 'Tern mark',
    w: 150,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.green}"/>
      <circle cx="75" cy="75" r="61" fill="none" stroke="${p.onDark}" stroke-width="1" opacity="${p.dim(0.35)}"/>
      ${bird({ dark: p.markDark, light: p.onDark, scale: 0.92, x: 75, y: 60 })}
      ${arcText(f['DMMono-Medium'], 'TERNPIKE.COM', {
        centerDeg: 180,
        cx: 75,
        cy: 75,
        fill: p.onDark,
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
    family: 'kit',
    blurb: '2 × 3in. QR-first — 1.5in symbol, for kiosk and bulletin boards.',
    cut: roundedRect(200, 300, 18),
    h: 300,
    qr: 'trailhead',
    slug: 'qr-trailhead',
    title: 'Trailhead scan card',
    w: 200,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.dark}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 6, size: 150, slug: 'trailhead', x: 25, y: 24 })}
      <path d="${text(f['PlayfairDisplay-Black'], COPY.brand, {
        anchor: 'middle',
        size: 32,
        x: 100,
        y: 212,
      })}" fill="${p.onDark}"/>
      <path d="${text(f['PlayfairDisplay-Italic'], COPY.tagline, {
        anchor: 'middle',
        size: 13,
        x: 100,
        y: 236,
      })}" fill="${p.onDark}" opacity="${p.dim(0.85)}"/>
      ${line(70, 250, 130, 250, p.accent, 1.5)}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.24,
        size: 9.5,
        x: 101,
        y: 272,
      })}" fill="${p.onDarkSoft}"/>
    `,
  },

  // ══ Scan family ══════════════════════════════════════════════════════
  //
  // Small, QR-dominant, high yield per label. These are for slapping on
  // things in the wild — the QR is the whole message and the type is a
  // caption, which is the inverse of the kit above.
  //
  // Three rules the kit designs don't follow:
  //
  //   - QR ≥ 0.78in, always. Below that a phone has to be deliberate
  //     about it, and nobody is deliberate about a sticker on a bin.
  //   - Type is authored at or above the 203 DPI thermal floor (mono ≥ 10
  //     units, Playfair Bold ≥ 13), so `thermalScale` stays 1.00× and the
  //     label gangs the maximum number of copies. Scaling a design up to
  //     make it legible costs stickers per label; designing above the
  //     floor costs nothing.
  //   - Light field. A utility sticker spends no ink on a background, and
  //     a light field means the colour and mono renders barely differ.

  // ── 10. Scan mini ────────────────────────────────────────────────────
  {
    family: 'scan',
    blurb: '1.3in square. Smallest useful scan target — 8 per 4×6 label.',
    cut: roundedRect(130, 130, 12),
    h: 130,
    qr: 'mini',
    slug: 'scan-mini',
    title: 'Scan mini',
    w: 130,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 88, slug: 'mini', x: 21, y: 13 })}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: 10,
        x: 65,
        y: 118,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 11. Scan dot ─────────────────────────────────────────────────────
  {
    family: 'scan',
    blurb: '1.7in round. Circles sit better on poles and bin lids than squares.',
    cut: circle(170),
    h: 170,
    qr: 'dot',
    slug: 'scan-dot',
    title: 'Scan dot',
    w: 170,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 84, slug: 'dot', x: 43, y: 24 })}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: 10,
        x: 85,
        y: 134,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 12. Scan hook ────────────────────────────────────────────────────
  //
  // A bare QR gets ignored; a QR with a reason gets scanned. The question
  // is doing the work here, not the mark.
  {
    family: 'scan',
    blurb: '2.4 × 1.3in. The waitlist headline beside the code — 4 per 4×6 label.',
    cut: roundedRect(240, 130, 12),
    h: 130,
    qr: 'hook',
    slug: 'scan-hook',
    title: 'Scan hook',
    w: 240,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 104, slug: 'hook', x: 13, y: 13 })}
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.mathLines[0], { size: 13, x: 128, y: 46 })}" fill="${p.onLight}"/>
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.mathLines[1], { size: 13, x: 128, y: 66 })}" fill="${p.onLight}"/>
      ${line(128, 82, 196, 82, p.accent, 1.6)}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        letterSpacing: 0.08,
        size: 10,
        x: 128,
        y: 102,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 13. Scan post ────────────────────────────────────────────────────
  {
    family: 'scan',
    blurb: '1.3 × 1.75in. Tall enough to read the mark, small enough for 6 per label.',
    cut: roundedRect(130, 175, 12),
    h: 175,
    qr: 'post',
    slug: 'scan-post',
    title: 'Scan post',
    w: 130,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${bird({ dark: p.markDark, light: p.onLight, scale: 0.46, x: 65, y: 26 })}
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 98, slug: 'post', x: 16, y: 42 })}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: 10,
        x: 65,
        y: 158,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 14. Scan strip ───────────────────────────────────────────────────
  {
    family: 'scan',
    blurb: '2.5 × 1in. Strip shape for bin rims, sign edges, pump handles.',
    cut: roundedRect(250, 100, 12),
    h: 100,
    qr: 'strip',
    slug: 'scan-strip',
    title: 'Scan strip',
    w: 250,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 80, slug: 'strip', x: 11, y: 10 })}
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.spentLines[0], { size: 13, x: 102, y: 40 })}" fill="${p.onLight}"/>
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.spentLines[1], { size: 13, x: 102, y: 58 })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        letterSpacing: 0.12,
        size: 10,
        x: 102,
        y: 82,
      })}" fill="${p.onLight}"/>
    `,
  },
]
/** Where a design's QR sends a scanner, or null if it carries only a URL. */
export const qrDestination = (sticker) => (sticker.qr ? qrTarget(sticker.qr) : null)
