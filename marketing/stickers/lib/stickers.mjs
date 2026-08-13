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
// **Designs may reflow for size.** `art` receives a `ctx` whose `scale` is
// the factor the sticker is about to print at. Most designs ignore it. One
// that carries a long line at a small size can't: "Track every turn of the
// road." needs ~2in of width at 11pt, so below a certain scale the choice
// is to set it on two lines at a larger size or not to offer that size at
// all. Reflowing is better than refusing.
//
// **Designs name roles, never colours.** `art` receives a profile `p` and
// paints with `p.dark` / `p.onDark` / `p.accent` and friends. That is what
// lets the identical design render as full-colour vinyl and as black-on-
// white thermal line art without two copies drifting apart. See
// `profiles.mjs`. If you find yourself reaching for a hex literal here,
// the role you want is missing — add it to both profiles instead.

import {
  KEYLINE,
  arrowSign,
  bird,
  circle,
  diamond,
  ellipse,
  milepost,
  mountains,
  noSignal,
  pin,
  receipt,
  arrowBoard,
  pawPrint,
  roundedRect,
  scanBrackets,
  shield,
  star5,
  sunburst,
} from './shapes.mjs'
import { COPY } from './copy.mjs'
import { qrCard, qrTarget } from './qr.mjs'
import { arcText, text } from './type.mjs'

// Thermal floors in design units, with a hair of slack for the 2dp scale
// rounding: 7pt for mono, 9pt for Playfair Bold.
const FLOOR_UNITS = 9.9
const SERIF_FLOOR_UNITS = 12.7
// Playfair Italic's hairlines fail earlier still: 11pt.
const ITALIC_FLOOR_UNITS = 15.3

/**
 * Size for a sticker's smallest line, given the scale it's about to print
 * at. `ctx.scale` is Infinity for a full-size render, so this is a no-op
 * unless something is deliberately printing the design small — in which
 * case the design-unit size grows to hold the physical size above the
 * 203 DPI floor. That's what lets a design offer a smaller print instead
 * of refusing one.
 */
const smallest = (ctx, base, floor = FLOOR_UNITS) =>
  Math.max(base, floor / Math.min(ctx.scale, 4))

/** Capitalise a fragment lifted from the middle of a sentence. */
const sentence = (s) => s.charAt(0).toUpperCase() + s.slice(1)

const line = (x1, y1, x2, y2, stroke, width = 1.4, extra = '') =>
  `<path d="M${x1} ${y1}H${x2}" stroke="${stroke}" stroke-width="${width}" stroke-linecap="round" ${extra}/>`

export const stickers = [
  // ── 1. Park badge ────────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '3in round. The flagship — national-park badge with a code in the field.',
    cut: circle(300),
    h: 300,
    qr: 'badge',
    slug: 'badge-tern',
    title: 'Tern badge',
    w: 300,
    art: (f, cut, p, ctx) => `
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
      ${bird({ dark: p.markDark, light: p.onDark, scale: 0.95, x: 150, y: 92 })}
      <path d="${text(f['PlayfairDisplay-Black'], COPY.brand, {
        anchor: 'middle',
        size: 32,
        x: 150,
        y: 140,
      })}" fill="${p.onDark}"/>
      ${line(112, 150, 188, 150, p.accent, 1.6)}
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 3, size: 80, slug: 'badge', x: 110, y: 160 })}
    `,
  },

  // ── 2. Wordmark bar ──────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '3.8 × 1.1in. Bumper wordmark, tern soaring off the end, code on the tail.',
    cut: roundedRect(380, 110, 20),
    h: 110,
    qr: 'bar',
    slug: 'wordmark-rust',
    title: 'Wordmark bar',
    w: 380,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.brand}"/>
      <path d="${cut(15)}" fill="none" stroke="${p.onDark}" stroke-width="1" opacity="${p.dim(0.45)}"/>
      <path d="${text(f['PlayfairDisplay-Black'], COPY.brand, { size: 38, x: 26, y: 60 })}" fill="${p.onDark}"/>
      <path d="${text(f['DMMono-Medium'], 'ternpike.com', {
        letterSpacing: 0.2,
        size: smallest(ctx, 9),
        x: 28,
        y: 84,
      })}" fill="${p.onDark}" opacity="${p.dim(0.85)}"/>
      ${bird({ dark: p.markDark, light: p.onDark, scale: 0.5, x: 242, y: 46 })}
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 3, size: 88, slug: 'bar', x: 276, y: 11 })}
    `,
  },

  // ── 3. Milepost ──────────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '1.4 × 3.2in. Highway milepost — every trip starts at mile zero.',
    cut: milepost(140, 320),
    h: 320,
    qr: 'mile',
    slug: 'milepost-zero',
    title: 'Milepost',
    w: 140,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.dark}"/>
      <path d="${cut(16)}" fill="none" stroke="${p.onDark}" stroke-width="1.1" opacity="${p.dim(0.35)}"/>
      ${bird({ dark: p.markDark, light: p.onDark, scale: 0.4, x: 70, y: 44 })}
      <path d="${text(f['DMMono-Medium'], 'MILE', {
        anchor: 'middle',
        letterSpacing: 0.34,
        size: 12,
        x: 73,
        y: 92,
      })}" fill="${p.onDarkSoft}"/>
      <path d="${text(f['PlayfairDisplay-Black'], '0', {
        anchor: 'middle',
        size: 66,
        x: 70,
        y: 158,
      })}" fill="${p.onDark}"/>
      ${line(42, 172, 98, 172, p.accent, 1.8)}
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 3, size: 92, slug: 'mile', x: 24, y: 182 })}
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: smallest(ctx, 8),
        x: 71,
        y: 298,
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
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      <path d="${cut(16)}" fill="none" stroke="${p.accent}" stroke-width="1.4"/>
      ${noSignal({ cx: 54, cy: 64, slash: p.accent, stroke: p.onLight })}
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.offlineLines[0], { size: 22, x: 90, y: 56 })}" fill="${p.onLight}"/>
      <path d="${text(f['PlayfairDisplay-Italic'], COPY.offlineLines[1], { size: 22, x: 90, y: 82 })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Medium'], 'ternpike.com', {
        letterSpacing: 0.2,
        size: smallest(ctx, 7.5),
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
    art: (f, cut, p, ctx) => {
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
        size: smallest(ctx, 6.5),
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
        size: smallest(ctx, 7),
        x: 81,
        y: 196,
      })}" fill="${p.accent}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, size: 74, slug: 'receipt', x: 43, y: 204 })}
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.14,
        size: smallest(ctx, 8),
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
    art: (f, cut, p, ctx) => `
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
        size: smallest(ctx, 7.5),
        x: 113,
        y: 130,
      })}" fill="${p.onDarkSoft}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, size: 84, slug: 'route', x: 218, y: 38 })}
    `,
  },

  // ── 7. Cabin or truck ────────────────────────────────────────────────
  {
    family: 'kit',
    blurb: '3.4 × 1.7in oval. The joke sticker — the decision the app exists to inform.',
    cut: ellipse(340, 170),
    h: 170,
    qr: 'cabin',
    slug: 'cabin-or-truck',
    title: 'Cabin or truck',
    w: 340,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.warm}"/>
      <path d="${cut(15)}" fill="none" stroke="${p.onLight}" stroke-width="1.1" opacity="${p.dim(0.5)}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 3, size: 84, slug: 'cabin', x: 36, y: 43 })}
      <path d="${text(f['PlayfairDisplay-Italic'], sentence(COPY.cabin), {
        anchor: 'middle',
        size: 20,
        x: 232,
        y: 68,
      })}" fill="${p.onLight}"/>
      ${line(178, 88, 204, 88, p.accent, 1.2)}
      <path d="${text(f['DMMono-Medium'], 'OR', {
        anchor: 'middle',
        letterSpacing: 0.3,
        size: smallest(ctx, 8),
        x: 233,
        y: 91,
      })}" fill="${p.accent}"/>
      ${line(260, 88, 286, 88, p.accent, 1.2)}
      <path d="${text(f['PlayfairDisplay-Italic'], COPY.truck.replace(/^or /, ''), {
        anchor: 'middle',
        size: 20,
        x: 232,
        y: 116,
      })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.16,
        size: smallest(ctx, 7.5),
        x: 233,
        y: 140,
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
    // Below ~1.05x the tagline can't hold one line at 11pt — it wants two
    // inches of width and the sticker is under two inches wide. So the
    // small layout sets it on two lines at a size that survives, drops the
    // rule for the room, and grows the URL to clear the floor too. Same
    // words either way; only the setting changes.
    art: (f, cut, p, ctx) =>
      ctx.scale < 1.05
        ? `
      <path d="${cut(KEYLINE)}" fill="${p.dark}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 6, size: 150, slug: 'trailhead', x: 25, y: 22 })}
      <path d="${text(f['PlayfairDisplay-Black'], COPY.brand, {
        anchor: 'middle',
        size: 28,
        x: 100,
        y: 205,
      })}" fill="${p.onDark}"/>
      ${COPY.taglineLines
        .map(
          (part, i) => `<path d="${text(f['PlayfairDisplay-Italic'], part, {
        anchor: 'middle',
        size: 18,
        x: 100,
        y: 230 + i * 21,
      })}" fill="${p.onDark}"/>`,
        )
        .join('\n      ')}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.16,
        size: 11.5,
        x: 101,
        y: 280,
      })}" fill="${p.onDarkSoft}"/>
    `
        : `
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
    blurb: '1.3in square. Bracketed code, 8 per 4×6 label — the workhorse.',
    cut: roundedRect(130, 130, 12),
    h: 130,
    qr: 'mini',
    slug: 'scan-mini',
    title: 'Scan mini',
    w: 130,
    art: (f, cut, p) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${scanBrackets({ h: 98, len: 14, stroke: p.accent, w: 98, weight: 2.2, x: 16, y: 8 })}
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

  // ── 15. Three steps ──────────────────────────────────────────────────
  {
    family: 'scan',
    blurb: '1.7 × 2.2in. The how-it-works headline, QR above it.',
    cut: roundedRect(170, 220, 12),
    h: 220,
    qr: 'sleep',
    slug: 'scan-sleep',
    title: 'Three steps',
    w: 170,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 116, slug: 'sleep', x: 27, y: 14 })}
      ${COPY.sleepLines
        .map(
          (part, i) => `<path d="${text(f['PlayfairDisplay-Bold'], part, {
        anchor: 'middle',
        size: smallest(ctx, 14, SERIF_FLOOR_UNITS),
        x: 85,
        y: 155 + i * 20,
      })}" fill="${p.onLight}"/>`,
        )
        .join('\n      ')}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: smallest(ctx, 10),
        x: 85,
        y: 200,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 16. Now I know ───────────────────────────────────────────────────
  //
  // The origin story's closing line and its shortest. Reads like something
  // a person said, which is rarer on a sticker than a slogan.
  {
    family: 'scan',
    blurb: '1.7 × 1.75in. The origin story in four words.',
    cut: roundedRect(170, 175, 12),
    h: 175,
    qr: 'know',
    slug: 'scan-know',
    title: 'Now I know',
    w: 170,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 100, slug: 'know', x: 35, y: 14 })}
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.know, {
        anchor: 'middle',
        size: smallest(ctx, 13, SERIF_FLOOR_UNITS),
        x: 85,
        y: 136,
      })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: smallest(ctx, 10),
        x: 85,
        y: 158,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 17. Actually free ────────────────────────────────────────────────
  {
    family: 'scan',
    blurb: '2.5 × 1.2in. The free-tier row from the comparison table.',
    cut: roundedRect(250, 120, 12),
    h: 120,
    qr: 'free',
    slug: 'scan-free',
    title: 'Actually free',
    w: 250,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 100, slug: 'free', x: 11, y: 10 })}
      ${COPY.freeLines
        .map(
          (part, i) => `<path d="${text(f['PlayfairDisplay-Bold'], part, {
        size: smallest(ctx, 13, SERIF_FLOOR_UNITS),
        x: 124,
        y: 44 + i * 20,
      })}" fill="${p.onLight}"/>`,
        )
        .join('\n      ')}
      ${line(124, 78, 190, 78, p.accent, 1.5)}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        letterSpacing: 0.08,
        size: smallest(ctx, 10),
        x: 124,
        y: 98,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 18. Join the waitlist ────────────────────────────────────────────
  //
  // The only design that asks for the thing directly. Everything else is a
  // hook or a mark; this one is the site's own button.
  {
    family: 'scan',
    blurb: '2.4 × 1in. The site\'s call to action, nothing else.',
    cut: roundedRect(240, 100, 12),
    h: 100,
    qr: 'join',
    slug: 'scan-waitlist',
    title: 'Join the waitlist',
    w: 240,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 80, slug: 'join', x: 11, y: 10 })}
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.waitlist, {
        size: smallest(ctx, 15, SERIF_FLOOR_UNITS),
        x: 102,
        y: 46,
      })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        letterSpacing: 0.12,
        size: smallest(ctx, 10),
        x: 102,
        y: 72,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 19. How much is left ─────────────────────────────────────────────
  {
    family: 'scan',
    blurb: '1.6 × 1.9in. The origin story\'s second question — pairs with scan-strip.',
    cut: roundedRect(160, 190, 12),
    h: 190,
    qr: 'left',
    slug: 'scan-left',
    title: 'How much is left',
    w: 160,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 100, slug: 'left', x: 30, y: 16 })}
      ${COPY.leftLines
        .map(
          (part, i) => `<path d="${text(f['PlayfairDisplay-Bold'], part, {
        anchor: 'middle',
        size: smallest(ctx, 14, SERIF_FLOOR_UNITS),
        x: 80,
        y: 140 + i * 18,
      })}" fill="${p.onLight}"/>`,
        )
        .join('\n      ')}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: smallest(ctx, 10),
        x: 80,
        y: 178,
      })}" fill="${p.onLight}"/>
    `,
  },
  // ── 20. Scan frame ───────────────────────────────────────────────────
  //
  // Tern on top, code in a viewfinder. No sentence at all — the brackets
  // do the asking, which is the one thing a plain code can't.
  {
    family: 'scan',
    blurb: '1.6 × 2in. Tern over a bracketed code. Brand-forward, wordless.',
    cut: roundedRect(160, 200, 12),
    h: 200,
    qr: 'frame',
    slug: 'scan-frame',
    title: 'Scan frame',
    w: 160,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${bird({ dark: p.markDark, light: p.onLight, scale: 0.46, x: 80, y: 22 })}
      ${scanBrackets({ h: 116, len: 17, stroke: p.accent, w: 116, weight: 2.6, x: 22, y: 40 })}
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 100, slug: 'frame', x: 30, y: 48 })}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: smallest(ctx, 10),
        x: 80,
        y: 180,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 21. Alaska range ─────────────────────────────────────────────────
  {
    family: 'scan',
    blurb: '1.7 × 2in. Mountain range over the code — the most place-specific one.',
    cut: roundedRect(170, 200, 12),
    h: 200,
    qr: 'peak',
    slug: 'scan-peak',
    title: 'Alaska range',
    w: 170,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${mountains({ fill: p.onLight, h: 42, w: 130, x: 20, y: 16 })}
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 100, slug: 'peak', x: 35, y: 68 })}
      <path d="${text(f['DMMono-Medium'], COPY.alaskaHighwayCaps, {
        anchor: 'middle',
        letterSpacing: 0.1,
        size: smallest(ctx, 10),
        x: 85,
        y: 188,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 22. GPS pin ──────────────────────────────────────────────────────
  {
    family: 'scan',
    blurb: '2.5 × 1.2in. Map pin and the GPS row from the comparison table.',
    cut: roundedRect(250, 120, 12),
    h: 120,
    qr: 'gps',
    slug: 'scan-pin',
    title: 'GPS pin',
    w: 250,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 104, slug: 'gps', x: 10, y: 8 })}
      ${pin({ cx: 134, cy: 44, fill: p.accent, hole: p.light, r: 10 })}
      ${COPY.gpsLines
        .map(
          (part, i) => `<path d="${text(f['PlayfairDisplay-Bold'], part, {
        size: smallest(ctx, 13, SERIF_FLOOR_UNITS),
        x: 154,
        y: 44 + i * 20,
      })}" fill="${p.onLight}"/>`,
        )
        .join('\n      ')}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        letterSpacing: 0.08,
        size: smallest(ctx, 10),
        x: 154,
        y: 98,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 23. No signal, with the icon ─────────────────────────────────────
  //
  // The kit sticker of the same name is 2.6in of type. This is the icon
  // doing the work at a size you can spare on a bin.
  {
    family: 'scan',
    blurb: '2.6 × 1.2in. The crossed-signal mark beside the code.',
    cut: roundedRect(260, 120, 12),
    h: 120,
    qr: 'offline',
    slug: 'scan-signal',
    title: 'No signal icon',
    w: 260,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 104, slug: 'offline', x: 10, y: 8 })}
      ${noSignal({ cx: 138, cy: 46, slash: p.accent, stroke: p.onLight, weight: 3 })}
      ${COPY.offlineLines
        .map(
          (part, i) => `<path d="${text(f['PlayfairDisplay-Bold'], part, {
        size: smallest(ctx, 13, SERIF_FLOOR_UNITS),
        x: 166,
        y: 44 + i * 20,
      })}" fill="${p.onLight}"/>`,
        )
        .join('\n      ')}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        letterSpacing: 0.08,
        size: smallest(ctx, 10),
        x: 166,
        y: 98,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ══ Roadside family ══════════════════════════════════════════════════
  //
  // Route 66 furniture: the shapes America already reads at a glance —
  // route shields, caution diamonds, license plates, googie arrows,
  // postcards. The die-cut silhouette carries the joke; the QR cashes it.

  // ── 24. Route shield ─────────────────────────────────────────────────
  {
    family: 'road',
    blurb: '2.2 × 2.4in. US route shield with the code where the number goes.',
    cut: shield(220, 240),
    h: 240,
    qr: 'shield',
    slug: 'route-shield',
    title: 'Route shield',
    w: 220,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      <path d="${cut(15)}" fill="none" stroke="${p.onLight}" stroke-width="3"/>
      <path d="${text(f['PlayfairDisplay-Bold'], COPY.brand, {
        anchor: 'middle',
        size: smallest(ctx, 24, SERIF_FLOOR_UNITS),
        x: 110,
        y: 56,
      })}" fill="${p.onLight}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 84, slug: 'shield', x: 68, y: 70 })}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.06,
        size: smallest(ctx, 10),
        x: 110,
        y: 178,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 25. Caution diamond ──────────────────────────────────────────────
  {
    family: 'road',
    blurb: '2.5in diamond. The offline feature as a road warning sign.',
    cut: diamond(250),
    h: 250,
    qr: 'caution',
    slug: 'caution-diamond',
    title: 'Caution diamond',
    w: 250,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.warm}"/>
      <path d="${cut(16)}" fill="none" stroke="${p.onLight}" stroke-width="3"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 80, slug: 'caution', x: 85, y: 52 })}
      <path d="${text(f['DMMono-Medium'], COPY.offlineCaps, {
        anchor: 'middle',
        letterSpacing: 0.06,
        size: smallest(ctx, 10),
        x: 125,
        y: 160,
      })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Regular'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.04,
        size: smallest(ctx, 10),
        x: 125,
        y: 182,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 26. License plate ────────────────────────────────────────────────
  //
  // The brand name is the plate number, the tagline is the state slogan,
  // and the registration sticker is a QR. Bolt holes included.
  {
    family: 'road',
    blurb: '3.6 × 1.8in. License plate — TERNPIKE as the number, QR as the tag.',
    cut: roundedRect(360, 180, 16),
    h: 180,
    qr: 'plate',
    slug: 'license-plate',
    title: 'License plate',
    w: 360,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      <path d="${cut(14)}" fill="none" stroke="${p.onLight}" stroke-width="2.4"/>
      <circle cx="38" cy="30" r="5" fill="none" stroke="${p.onLight}" stroke-width="1.8"/>
      <circle cx="326" cy="30" r="5" fill="none" stroke="${p.onLight}" stroke-width="1.8"/>
      <path d="${text(f['DMMono-Medium'], COPY.alaskaHighwayCaps, {
        anchor: 'middle',
        letterSpacing: 0.14,
        size: smallest(ctx, 10),
        x: 180,
        y: 40,
      })}" fill="${p.accent}"/>
      <path d="${text(f['DMMono-Medium'], COPY.brand.toUpperCase(), {
        anchor: 'middle',
        letterSpacing: 0.05,
        size: 34,
        x: 138,
        y: 112,
      })}" fill="${p.onLight}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 80, slug: 'plate', x: 248, y: 50 })}
      <path d="${text(f['DMMono-Medium'], COPY.taglineCaps, {
        anchor: 'middle',
        letterSpacing: 0.02,
        size: smallest(ctx, 10),
        x: 138,
        y: 158,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 27. Googie arrow ─────────────────────────────────────────────────
  //
  // Mid-century motel-sign arrow, bulbs and all. Stick it pointing at
  // something — the head is empty on purpose.
  {
    family: 'road',
    blurb: '3.4 × 1.4in. Motel-sign arrow with bulb dots. Point it at things.',
    cut: arrowSign(340, 140),
    h: 140,
    qr: 'arrow',
    slug: 'googie-arrow',
    title: 'Googie arrow',
    w: 340,
    art: (f, cut, p, ctx) => {
      const bulbs = [20, 120]
        .flatMap((y) => [28, 62, 96, 130, 164, 198, 232].map((x) => [x, y]))
        .concat([[262, 36], [262, 104], [288, 52], [288, 88], [308, 70]])
        .map(([x, y]) => `<circle cx="${x}" cy="${y}" r="3.4" fill="${p.onDark}"/>`)
        .join('')
      return `
      <path d="${cut(KEYLINE)}" fill="${p.brand}"/>
      <path d="${cut(13)}" fill="none" stroke="${p.onDark}" stroke-width="1.6" opacity="${p.dim(0.6)}"/>
      ${bulbs}
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 80, slug: 'arrow', x: 24, y: 30 })}
      <path d="${text(f['PlayfairDisplay-Black'], COPY.brand, {
        anchor: 'middle',
        size: smallest(ctx, 22, SERIF_FLOOR_UNITS),
        x: 176,
        y: 66,
      })}" fill="${p.onDark}"/>
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.06,
        size: smallest(ctx, 10),
        x: 176,
        y: 92,
      })}" fill="${p.onDark}"/>
    `
    },
  },

  // ── 28. Postcard ─────────────────────────────────────────────────────
  //
  // The hero headline as the message, Dwight's sign-off from the origin
  // story, and the QR where the stamp goes — postmark cancelling it.
  {
    family: 'road',
    blurb: '3.4 × 2.2in. Postcard — hero line as the message, QR as the stamp.',
    cut: roundedRect(340, 220, 10),
    h: 220,
    qr: 'postcard',
    slug: 'postcard',
    title: 'Postcard',
    w: 340,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      <path d="${cut(13)}" fill="none" stroke="${p.onLightSoft}" stroke-width="1" opacity="${p.dim(0.7)}"/>
      <path d="M204 20V202" stroke="${p.onLightSoft}" stroke-width="1.2" opacity="${p.dim(0.8)}"/>
      ${COPY.heroLines
        .map(
          (part, i) => `<path d="${text(f['PlayfairDisplay-Italic'], part, {
        anchor: 'middle',
        size: smallest(ctx, 17, ITALIC_FLOOR_UNITS),
        x: 106,
        y: 56 + i * 27,
      })}" fill="${p.onLight}"/>`,
        )
        .join('\n      ')}
      <path d="${text(f['PlayfairDisplay-Italic'], COPY.attribution, {
        anchor: 'end',
        size: smallest(ctx, 16, ITALIC_FLOOR_UNITS),
        x: 188,
        y: 160,
      })}" fill="${p.onLight}"/>
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        letterSpacing: 0.1,
        size: smallest(ctx, 10),
        x: 20,
        y: 200,
      })}" fill="${p.onLight}"/>
      <rect x="224" y="12" width="96" height="96" fill="none" stroke="${p.onLightSoft}"
            stroke-width="1.2" stroke-dasharray="4 3" opacity="${p.dim(0.8)}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 84, slug: 'postcard', x: 230, y: 18 })}
      <circle cx="238" cy="132" r="13" fill="none" stroke="${p.onLightSoft}" stroke-width="1.4" opacity="${p.dim(0.85)}"/>
      <g fill="none" stroke="${p.onLightSoft}" stroke-width="1.4" opacity="${p.dim(0.85)}">
        <path d="M258 126q8 -5 16 0t16 0t16 0"/>
        <path d="M258 133q8 -5 16 0t16 0t16 0"/>
        <path d="M258 140q8 -5 16 0t16 0t16 0"/>
      </g>
      <g stroke="${p.onLightSoft}" stroke-width="1.2" opacity="${p.dim(0.8)}">
        <path d="M214 162H322"/>
        <path d="M214 180H322"/>
        <path d="M214 198H322"/>
      </g>
    `,
  },

  // ══ Alaska family ════════════════════════════════════════════════════
  //
  // For the road the app was built on. The Big Dipper off the state flag,
  // a bear paw, the Watson Lake Sign Post Forest, the midnight sun — each
  // one something you'd actually see from the Alaska Highway.

  // ── 29. Big Dipper ───────────────────────────────────────────────────
  //
  // Eight stars of gold — the state flag's constellation, Polaris top
  // right. Star positions eyeballed from the flag, not surveyed.
  {
    family: 'alaska',
    blurb: '2.2 × 2.8in. The state flag constellation over the code.',
    cut: roundedRect(220, 280, 14),
    h: 280,
    qr: 'dipper',
    slug: 'big-dipper',
    title: 'Big Dipper',
    w: 220,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.dark}"/>
      ${[
        [38, 120, 9],
        [74, 102, 9],
        [44, 164, 9],
        [86, 142, 9],
        [112, 116, 9],
        [134, 88, 9],
        [158, 64, 9],
        [182, 32, 13],
      ]
        .map(([sx, sy, sr]) => star5({ cx: sx, cy: sy, fill: p.onDark, r: sr }))
        .join('')}
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 80, slug: 'dipper', x: 70, y: 182 })}
      <path d="${text(f['DMMono-Medium'], 'TERNPIKE.COM', {
        anchor: 'middle',
        letterSpacing: 0.06,
        size: smallest(ctx, 10),
        x: 110,
        y: 268,
      })}" fill="${p.onDarkSoft}"/>
    `,
  },

  // ── 30. Bear paw ─────────────────────────────────────────────────────
  {
    family: 'alaska',
    blurb: '2.1in round. Bear paw over the code — the polite kind of bear sign.',
    cut: circle(210),
    h: 210,
    qr: 'paw',
    slug: 'bear-paw',
    title: 'Bear paw',
    w: 210,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      <circle cx="105" cy="105" r="89" fill="none" stroke="${p.onLight}" stroke-width="1.4" opacity="${p.dim(0.5)}"/>
      ${pawPrint({ cx: 105, cy: 58, fill: p.onLight, scale: 0.92 })}
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 76, slug: 'paw', x: 67, y: 88 })}
      ${arcText(f['DMMono-Medium'], 'TERNPIKE.COM', {
        centerDeg: 180,
        cx: 105,
        cy: 105,
        fill: p.onLight,
        flip: true,
        letterSpacing: 0.14,
        r: 76,
        size: 10,
      })}
    `,
  },

  // ── 31. Sign Post Forest ─────────────────────────────────────────────
  //
  // Watson Lake's landmark, scaled to a sticker: boards pointing at the
  // hero headline's two endpoints, and one board that's a QR. The city
  // names are fragments of hero.headline, same guard as everything else.
  {
    family: 'alaska',
    blurb: '2.2 × 3in. The Sign Post Forest — Orlando one way, Juneau the other.',
    cut: roundedRect(220, 300, 14),
    h: 300,
    qr: 'forest',
    slug: 'sign-forest',
    title: 'Sign Post Forest',
    w: 220,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      <rect x="103" y="20" width="14" height="224" fill="${p.onLight}" opacity="${p.dim(0.85)}"/>
      <path d="${arrowBoard({ dir: 'right', h: 36, w: 166, x: 26, y: 30 })}" fill="${p.card}" stroke="${p.onLight}" stroke-width="2"/>
      <path d="${text(f['DMMono-Medium'], COPY.orlandoCaps, {
        anchor: 'middle',
        letterSpacing: 0.12,
        size: smallest(ctx, 12),
        x: 100,
        y: 54,
      })}" fill="${p.onLight}"/>
      <path d="${arrowBoard({ dir: 'left', h: 36, w: 166, x: 28, y: 82 })}" fill="${p.card}" stroke="${p.onLight}" stroke-width="2"/>
      <path d="${text(f['DMMono-Medium'], COPY.juneauCaps, {
        anchor: 'middle',
        letterSpacing: 0.12,
        size: smallest(ctx, 12),
        x: 120,
        y: 106,
      })}" fill="${p.onLight}"/>
      <rect x="60" y="134" width="100" height="100" fill="${p.card}" stroke="${p.onLight}" stroke-width="2"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 0, size: 84, slug: 'forest', x: 68, y: 142 })}
      <path d="${text(f['DMMono-Medium'], COPY.alaskaHighwayCaps, {
        anchor: 'middle',
        letterSpacing: 0.08,
        size: smallest(ctx, 10),
        x: 110,
        y: 262,
      })}" fill="${p.accent}"/>
      <path d="${text(f['DMMono-Regular'], 'ternpike.com', {
        anchor: 'middle',
        letterSpacing: 0.08,
        size: smallest(ctx, 10),
        x: 110,
        y: 284,
      })}" fill="${p.onLight}"/>
    `,
  },

  // ── 32. Midnight sun ─────────────────────────────────────────────────
  {
    family: 'alaska',
    blurb: '3.2 × 1.4in. Low sun over the range — June on the Alaska Highway.',
    cut: roundedRect(320, 140, 14),
    h: 140,
    qr: 'sun',
    slug: 'midnight-sun',
    title: 'Midnight sun',
    w: 320,
    art: (f, cut, p, ctx) => `
      <path d="${cut(KEYLINE)}" fill="${p.light}"/>
      ${sunburst({ cx: 58, cy: 46, r: 15, stroke: p.accent })}
      ${mountains({ fill: p.onLight, h: 44, w: 172, x: 22, y: 48 })}
      <path d="${text(f['DMMono-Medium'], COPY.madeOnCaps, {
        anchor: 'middle',
        letterSpacing: 0,
        size: smallest(ctx, 10),
        x: 107,
        y: 120,
      })}" fill="${p.onLight}"/>
      ${qrCard({ dark: p.cardInk, light: p.card, radius: 2, size: 104, slug: 'sun', x: 202, y: 18 })}
    `,
  },
]

/** Where a design's QR sends a scanner, or null if it carries only a URL. */
export const qrDestination = (sticker) => (sticker.qr ? qrTarget(sticker.qr) : null)

