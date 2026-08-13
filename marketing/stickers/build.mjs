// Build the Ternpike sticker kit.
//
//   node marketing/stickers/build.mjs
//
// Two output profiles from one set of designs (see lib/profiles.mjs):
//
//   svg/<slug>.svg          colour die-cut vinyl — the deliverable
//   png/<slug>.png          the same at 300 DPI, for raster-only portals
//   sheets/print-sheet.svg  US Letter gang sheet with dashed cut guides
//   thermal/<slug>.svg      black-on-white, ganged onto a 4×6 label
//   thermal/<slug>.png      the same at 203 DPI, hard-thresholded to 1 bit
//                           — what a direct thermal head actually lays down
//   thermal/<slug>.pdf      that bitmap on an exactly-4×6 page — print THIS
//                           from an iPhone or iPad
//
// PNG output needs `sharp`, which is not a repo dependency — it pulls a
// platform binary and nothing else here rasterizes. Run
// `npm i --no-save sharp` first, or pass --no-png to emit vectors only.
// The SVGs are the real deliverable; the PNGs are a convenience.

import { mkdir, rm, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { KEYLINE, UNITS_PER_INCH } from './lib/shapes.mjs'
import {
  BRAND,
  bindingConstraint,
  colorProfile,
  minLegibleScale,
  monoProfile,
  thermalScale,
} from './lib/profiles.mjs'
import { qrAudit, resetQrAudit } from './lib/qr.mjs'
import { qrDestination, stickers } from './lib/stickers.mjs'
import { loadFonts, resetTypeAudit, round, text, typeAudit } from './lib/type.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = join(here, '..', '..')
const wantPng = !process.argv.includes('--no-png')

const inches = (units) => round(units / UNITS_PER_INCH)
// DM Mono has no U+2033 prime, so spell the unit out.
const label = (s) => `${inches(s.w)}in × ${inches(s.h)}in`

/**
 * Render one design's artwork, returning it alongside the type sizes it
 * used. The thermal profile needs the sizes to work out how far the design
 * must be scaled up; nothing else looks at them.
 */
function renderArt(sticker, fonts, profile, ctx = { scale: Infinity }) {
  resetTypeAudit()
  resetQrAudit()
  const body = sticker.art(fonts, sticker.cut, profile, ctx).trim()
  return { body, qr: qrAudit(), type: typeAudit() }
}

// ── One sticker (colour) ─────────────────────────────────────────────────

// width/height in inches so the file carries its physical size: dropped
// into Illustrator or a print portal it arrives at 1:1 rather than at
// whatever the importer guesses.
function stickerSvg(sticker, fonts) {
  const { body } = renderArt(sticker, fonts, colorProfile)
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${inches(sticker.w)}in" height="${inches(sticker.h)}in" viewBox="0 0 ${sticker.w} ${sticker.h}">
  <title>Ternpike — ${sticker.title}</title>
  <path d="${sticker.cut(0)}" fill="${colorProfile.keyline}"/>
  ${body}
</svg>
`
}

// ── Thermal 4×6 label ────────────────────────────────────────────────────

// 4×6in at 100 units/in, less the margin a thermal head can't reach.
const LABEL = { gap: 12, h: 600, margin: 14, w: 400 }

/**
 * Lay out as many copies of one design as fit on a 4×6 label, at the scale
 * its smallest type needs.
 *
 * Rotation is tried as well as the upright placement: a 3.2in-wide design
 * scaled 1.3× overflows a 4in label upright but fits comfortably turned
 * sideways, and a sideways sticker peels exactly the same.
 */
function planLabel(sticker, type) {
  const wanted = thermalScale(type)
  const availW = LABEL.w - LABEL.margin * 2
  const availH = LABEL.h - LABEL.margin * 2

  const fitAt = (scale, rotated) => {
    const w = (rotated ? sticker.h : sticker.w) * scale
    const h = (rotated ? sticker.w : sticker.h) * scale
    const cols = Math.floor((availW + LABEL.gap) / (w + LABEL.gap))
    const rows = Math.floor((availH + LABEL.gap) / (h + LABEL.gap))
    return { cols, count: cols * rows, h, rotated, rows, scale, w }
  }

  const options = [fitAt(wanted, false), fitAt(wanted, true)].filter((o) => o.count > 0)
  if (options.length > 0) {
    // Most copies per label wins; upright breaks the tie.
    options.sort((a, b) => b.count - a.count || Number(a.rotated) - Number(b.rotated))
    return { ...options[0], shortfall: null }
  }

  // Nothing fits even once at the legible scale. Fall back to the largest
  // scale that does fit and say so — a silently shrunk sticker is how you
  // end up with an unreadable URL.
  const capped = Math.min(
    availW / sticker.w,
    availH / sticker.h,
    availW / sticker.h,
    availH / sticker.w,
  )
  const rotated = sticker.w > availW * 0.999
  return { ...fitAt(capped, rotated), shortfall: { capped, wanted } }
}

function thermalSvg(sticker, fonts) {
  const { body, type } = renderArt(sticker, fonts, monoProfile)
  const plan = planLabel(sticker, type)

  const blockW = plan.cols * plan.w + (plan.cols - 1) * LABEL.gap
  const blockH = plan.rows * plan.h + (plan.rows - 1) * LABEL.gap
  const originX = (LABEL.w - blockW) / 2
  const originY = (LABEL.h - blockH) / 2
  plan.originX = originX
  plan.originY = originY

  const cells = []
  for (let r = 0; r < plan.rows; r++) {
    for (let c = 0; c < plan.cols; c++) {
      const x = round(originX + c * (plan.w + LABEL.gap))
      const y = round(originY + r * (plan.h + LABEL.gap))
      // Rotating clockwise about the cell: local (u,v) lands at
      // (x + h*scale - v*scale, y + u*scale), so the footprint is h×w.
      const transform = plan.rotated
        ? `translate(${round(x + plan.w)} ${y}) rotate(90) scale(${plan.scale})`
        : `translate(${x} ${y}) scale(${plan.scale})`
      cells.push(`  <g transform="${transform}">
    ${body}
    <path d="${sticker.cut(0)}" fill="none" stroke="#000000" stroke-width="${round(0.6 / plan.scale)}" stroke-dasharray="${round(5 / plan.scale)} ${round(4 / plan.scale)}"/>
  </g>`)
    }
  }

  return {
    plan,
    type,
    svg: `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="4in" height="6in" viewBox="0 0 ${LABEL.w} ${LABEL.h}">
  <title>Ternpike — ${sticker.title} — 4×6 thermal label</title>
  <rect width="${LABEL.w}" height="${LABEL.h}" fill="#ffffff"/>
${cells.join('\n')}
</svg>
`,
  }
}

// ── Size sheets: one design, N per label ─────────────────────────────────
//
// A label printer has one page size, so "print it bigger" has to mean
// "print fewer per page". These sheets are that dial: 1-up fills the
// label, 2-up is half each, 3-up a third, 4-up a quarter. Pick a design,
// pick a number, get that size.
//
// Not every step exists for every design. Scaling down eventually puts the
// smallest type under the 203 DPI floor or the QR under the size a phone
// resolves, and a sticker that prints but can't be read or scanned is
// worse than one that isn't offered — so unavailable steps are reported,
// not silently shrunk.

const SIZE_STEPS = [1, 2, 3, 4]

// Room at the bottom of every sheet for the caption strap. Outside the
// sticker area, so it's scrap once you've cut — but it's what tells you
// which sheet you're holding after a few come off the printer.
const CAPTION_BAND = 12

// A QR below this stops being something a phone picks up casually.
const MIN_QR_INCHES = 0.75

// Ways to divide a label into N cells. Which one wins depends on the
// sticker's aspect: a 2.5×1in strip wants four stacked rows, a 1.3in
// square wants a 2×2.
const GRIDS = {
  1: [[1, 1]],
  2: [[1, 2], [2, 1]],
  3: [[1, 3], [3, 1]],
  4: [[1, 4], [2, 2], [4, 1]],
}

/** The largest this design can print at, N to a label. */
function bestGrid(sticker, n) {
  const usableW = LABEL.w - LABEL.margin * 2
  const usableH = LABEL.h - LABEL.margin * 2 - CAPTION_BAND
  let best = null

  for (const [rows, cols] of GRIDS[n]) {
    const cellW = (usableW - (cols - 1) * LABEL.gap) / cols
    const cellH = (usableH - (rows - 1) * LABEL.gap) / rows
    for (const rotated of [false, true]) {
      const w = rotated ? sticker.h : sticker.w
      const h = rotated ? sticker.w : sticker.h
      const scale = Math.min(cellW / w, cellH / h)
      if (!best || scale > best.scale) {
        best = { cellH, cellW, cols, h, rotated, rows, scale, w }
      }
    }
  }
  return best
}

function sizeSheet(fonts, sticker, n, plan) {
  const { body } = renderArt(sticker, fonts, monoProfile, { scale: plan.scale })
  const usableW = LABEL.w - LABEL.margin * 2
  const usableH = LABEL.h - LABEL.margin * 2 - CAPTION_BAND
  const blockW = plan.cols * plan.cellW + (plan.cols - 1) * LABEL.gap
  const blockH = plan.rows * plan.cellH + (plan.rows - 1) * LABEL.gap
  const originX = LABEL.margin + (usableW - blockW) / 2
  const originY = LABEL.margin + (usableH - blockH) / 2

  const cells = []
  for (let r = 0; r < plan.rows; r++) {
    for (let c = 0; c < plan.cols; c++) {
      const w = plan.w * plan.scale
      const h = plan.h * plan.scale
      const x = originX + c * (plan.cellW + LABEL.gap) + (plan.cellW - w) / 2
      const y = originY + r * (plan.cellH + LABEL.gap) + (plan.cellH - h) / 2
      // Rotating clockwise about the cell: local (u,v) lands at
      // (x + w - v*scale, y + u*scale), so the footprint is h×w.
      const transform = plan.rotated
        ? `translate(${round(x + w)} ${round(y)}) rotate(90) scale(${round(plan.scale)})`
        : `translate(${round(x)} ${round(y)}) scale(${round(plan.scale)})`
      cells.push(`  <g transform="${transform}">
    ${body}
    <path d="${sticker.cut(0)}" fill="none" stroke="#000000" stroke-width="${round(0.6 / plan.scale)}" stroke-dasharray="${round(5 / plan.scale)} ${round(4 / plan.scale)}"/>
  </g>`)
    }
  }

  const size = `${inches(sticker.w * plan.scale)} x ${inches(sticker.h * plan.scale)}in`
  const strap = `${sticker.slug}  ·  ${n}-up  ·  ${size}  ·  print at 100%`

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="4in" height="6in" viewBox="0 0 ${LABEL.w} ${LABEL.h}">
  <title>Ternpike — ${sticker.title} — ${n} per 4×6 label</title>
  <rect width="${LABEL.w}" height="${LABEL.h}" fill="#ffffff"/>
${cells.join('\n')}
  <path d="${text(fonts['DMMono-Medium'], strap, {
    anchor: 'middle',
    letterSpacing: 0.04,
    size: 9,
    x: LABEL.w / 2,
    y: LABEL.h - 12,
  })}" fill="#000000"/>
</svg>
`
}

// ── Trip pack ────────────────────────────────────────────────────────────
//
// One file, one print job: the designs actually being taken on the road,
// each on its own 4×6 page at the count that yields the most stickers.
//
// The per-design labels in thermal/ scale a design UP to its legible size,
// which is right when you want it at full size and wrong when you want a
// lot of them — wordmark-rust is 2 per label there and 4 here, milepost the
// same. Only the badge can't improve: a 3in circle is one to a page however
// you turn it.

const TRIP_PACK = [
  ['badge-tern', 1],
  ['wordmark-rust', 4],
  ['milepost-zero', 4],
  ['cabin-or-truck', 3],
  ['receipt', 3],
]

// ── Gang sheet (colour, US Letter) ───────────────────────────────────────

const SHEET = { gap: 22, h: 1100, margin: 40, w: 850 }

// How many of each to gang up. Weighted toward the small ones — those are
// the ones that actually get handed out.
const POOL = [
  ['badge-tern', 1],
  ['milepost-zero', 1],
  ['receipt', 1],
  ['qr-trailhead', 1],
  ['orlando-juneau', 1],
  ['cabin-or-truck', 1],
  ['tern-mark', 2],
  ['wordmark-rust', 2],
  ['no-signal', 1],
]

/**
 * Shelf packing, tallest first, skipping anything that won't fit the
 * current shelf rather than breaking to a new one. Overflow starts another
 * sheet — better two honest pages than one page with a sticker clipped off
 * the edge.
 */
function pack(items) {
  const bySlug = new Map(stickers.map((s) => [s.slug, s]))
  const queue = []
  for (const [slug, count] of items) {
    const sticker = bySlug.get(slug)
    if (!sticker) throw new Error(`unknown sticker in POOL: ${slug}`)
    for (let i = 0; i < count; i++) queue.push(sticker)
  }
  queue.sort((a, b) => b.h - a.h || b.w - a.w)

  const right = SHEET.w - SHEET.margin
  const floor = SHEET.h - SHEET.margin - 24 // 24 leaves room for the slug line
  const sheets = []
  let remaining = queue

  while (remaining.length > 0) {
    const placed = []
    const leftovers = []
    let shelfY = SHEET.margin
    let shelfH = 0
    let x = SHEET.margin
    const pool = remaining

    while (pool.length > 0) {
      const idx = pool.findIndex((s) => x + s.w <= right && shelfY + s.h <= floor)
      if (idx === -1) {
        // Nothing fits this shelf. Drop to the next one, or give up on
        // this sheet if even the tallest remaining item won't clear.
        const nextY = shelfY + (shelfH === 0 ? 0 : shelfH + SHEET.gap)
        if (shelfH === 0 || !pool.some((s) => nextY + s.h <= floor)) {
          leftovers.push(...pool)
          break
        }
        shelfY = nextY
        shelfH = 0
        x = SHEET.margin
        continue
      }
      const [sticker] = pool.splice(idx, 1)
      placed.push({ sticker, x, y: shelfY })
      x += sticker.w + SHEET.gap
      shelfH = Math.max(shelfH, sticker.h)
    }

    if (placed.length === 0) throw new Error('sticker too large for the sheet')
    sheets.push(placed)
    remaining = leftovers
  }
  return sheets
}

function sheetSvg(placed, fonts, { index, total }) {
  const art = placed
    .map(
      ({ sticker, x, y }) => `  <g transform="translate(${x} ${y})">
    <path d="${sticker.cut(0)}" fill="${colorProfile.keyline}"/>
    ${renderArt(sticker, fonts, colorProfile).body}
  </g>`,
    )
    .join('\n')

  // Magenta dashed guides, on top of everything, in their own group so a
  // print shop can delete or remap the layer in one click.
  const guides = placed
    .map(
      ({ sticker, x, y }) =>
        `    <path transform="translate(${x} ${y})" d="${sticker.cut(0)}"/>`,
    )
    .join('\n')

  const slug = `Ternpike sticker sheet ${index}/${total} · US Letter · print at 100% (actual size) · magenta = cut guide, delete before printing`

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="8.5in" height="11in" viewBox="0 0 ${SHEET.w} ${SHEET.h}">
  <title>Ternpike sticker sheet ${index} of ${total}</title>
  <rect width="${SHEET.w}" height="${SHEET.h}" fill="${colorProfile.sheetBg}"/>
${art}
  <g id="cut-guides" fill="none" stroke="#ff00ff" stroke-width="0.6" stroke-dasharray="6 4">
${guides}
  </g>
  <path d="${text(fonts['DMMono-Regular'], slug, { size: 7.5, x: SHEET.margin, y: SHEET.h - 22 })}" fill="#b0b0a8"/>
</svg>
`
}

// ── Contact sheet (review image) ─────────────────────────────────────────

function contactSheet(fonts, { cols = 3, profile, subset, subtitle, title }) {
  const cellW = 420
  const cellH = 400
  const artW = 350
  const artH = 264
  const pad = 26
  const margin = 54
  const headerH = 190
  const rows = Math.ceil(subset.length / cols)
  const w = margin * 2 + cols * cellW + (cols - 1) * pad
  const h = headerH + rows * cellH + (rows - 1) * pad + margin
  const paper = profile.mono ? '#ffffff' : BRAND.cream
  const cellBg = profile.mono ? '#f4f4f4' : '#ffffff'
  const ink = profile.mono ? '#000000' : BRAND.forest
  const sub = profile.mono ? '#000000' : BRAND.moss
  const cap = profile.mono ? '#000000' : BRAND.rust

  const cells = subset
    .map((sticker, i) => {
      const col = i % cols
      const row = Math.floor(i / cols)
      const cx = margin + col * (cellW + pad)
      const cy = headerH + row * (cellH + pad)
      const scale = Math.min(artW / sticker.w, artH / sticker.h, 1.35)
      const sw = sticker.w * scale
      const sh = sticker.h * scale
      const ax = cx + (cellW - sw) / 2
      const ay = cy + (artH - sh) / 2 + 20

      return `  <g>
    <rect x="${cx}" y="${cy}" width="${cellW}" height="${cellH}" rx="18" fill="${cellBg}" opacity="0.55"/>
    <g transform="translate(${round(ax)} ${round(ay)}) scale(${round(scale)})">
      <path d="${sticker.cut(0)}" fill="${profile.keyline}"/>
      ${renderArt(sticker, fonts, profile).body}
    </g>
    <path d="${text(fonts['PlayfairDisplay-Bold'], sticker.title, {
      anchor: 'middle',
      size: 24,
      x: cx + cellW / 2,
      y: cy + artH + 74,
    })}" fill="${ink}"/>
    <path d="${text(fonts['DMMono-Regular'], label(sticker), {
      anchor: 'middle',
      letterSpacing: 0.12,
      size: 13,
      x: cx + cellW / 2,
      y: cy + artH + 100,
    })}" fill="${cap}"/>
  </g>`
    })
    .join('\n')

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <rect width="${w}" height="${h}" fill="${paper}"/>
  <path d="${text(fonts['PlayfairDisplay-Black'], title, { size: 62, x: margin, y: 96 })}" fill="${ink}"/>
  <path d="${text(fonts['PlayfairDisplay-Italic'], subtitle, {
    size: 26,
    x: margin + 4,
    y: 136,
  })}" fill="${sub}"/>
  <path d="M${margin} 158H${w - margin}" stroke="${cap}" stroke-width="2"/>
${cells}
</svg>
`
}

// ── Run ──────────────────────────────────────────────────────────────────

const fonts = await loadFonts()

const svgDir = join(here, 'svg')
const pngDir = join(here, 'png')
const sheetDir = join(here, 'sheets')
const thermalDir = join(here, 'thermal')
const sizesDir = join(thermalDir, 'sizes')
const shotDir = join(repoRoot, 'docs', 'screenshots')

for (const dir of [svgDir, pngDir, sheetDir, thermalDir]) {
  await rm(dir, { force: true, recursive: true })
  await mkdir(dir, { recursive: true })
}
await mkdir(shotDir, { recursive: true })

let sharp = null
if (wantPng) {
  try {
    ;({ default: sharp } = await import('sharp'))
  } catch {
    console.warn('! sharp not installed — skipping PNG output (npm i --no-save sharp)')
  }
}

const widthOf = (svg) => Number(/viewBox="0 0 ([\d.]+)/.exec(svg)[1])

// Fixed timestamp for PDF metadata — see thermalPdf.
const EPOCH = new Date(0)

let PDFDocument = null
try {
  ;({ PDFDocument } = await import('pdf-lib'))
} catch {
  console.warn('! pdf-lib not installed — skipping thermal PDFs (npm i --no-save pdf-lib)')
}

/**
 * Wrap a thermal bitmap in a PDF page that is exactly 4×6 inches.
 *
 * iOS Safari ignores `@page size` and renders any HTML/SVG print job onto
 * the system paper default, so an SVG label printed from an iPhone arrives
 * letterboxed on US Letter and comes out of the printer scaled down. A PDF
 * that already declares 288×432pt cannot be reinterpreted. This is the same
 * reason `server/qrPdf.js` exists — the constraint hasn't changed just
 * because these labels are generated ahead of time.
 *
 * The page embeds the already-thresholded bitmap rather than vector art:
 * the head is going to reduce everything to one bit at 203 DPI anyway, so
 * embedding the bilevel image is what makes the proof and the print the
 * same object.
 */
async function thermalPdf(png) {
  return thermalPdfPages([png], 'Ternpike thermal label')
}

/**
 * One PDF, one 4×6 page per bitmap.
 *
 * Multi-page matters for the trip pack: five separate files is five
 * separate print jobs to line up on a phone, where one file is a single
 * "print" with the whole set behind it.
 */
async function thermalPdfPages(pngs, title) {
  if (!PDFDocument) return null
  const doc = await PDFDocument.create()
  doc.setTitle(title)
  doc.setCreator('Ternpike')
  // pdf-lib stamps wall-clock creation/modification dates, which makes
  // every rebuild a diff even when no artwork changed. Pin them so the
  // committed PDFs are reproducible and a real change is visible as one.
  doc.setCreationDate(EPOCH)
  doc.setModificationDate(EPOCH)
  for (const png of pngs) {
    const page = doc.addPage([288, 432]) // 4×6in at 72pt/in
    const image = await doc.embedPng(png)
    page.drawImage(image, { height: 432, width: 288, x: 0, y: 0 })
  }
  return Buffer.from(await doc.save())
}

// Viewbox units are 1/100in, so pxPerUnit is DPI/100. `bilevel` reproduces
// what a thermal head does: no anti-aliasing, no grey, every dot on or off.
const rasterBuffer = async (svg, pxPerUnit, { bilevel = false } = {}) => {
  if (!sharp) return null
  let pipe = sharp(Buffer.from(svg), { density: 96 * pxPerUnit }).resize({
    width: Math.round(widthOf(svg) * pxPerUnit),
  })
  if (bilevel) pipe = pipe.greyscale().threshold(128)
  return await pipe.png({ compressionLevel: 9 }).toBuffer()
}

const raster = async (svg, out, pxPerUnit = 3, opts = {}) => {
  const buf = await rasterBuffer(svg, pxPerUnit, opts)
  if (buf) await writeFile(out, buf)
  return buf
}

console.log('colour (die-cut vinyl)')
for (const sticker of stickers) {
  const svg = stickerSvg(sticker, fonts)
  await writeFile(join(svgDir, `${sticker.slug}.svg`), svg)
  await raster(svg, join(pngDir, `${sticker.slug}.png`))
  const dest = qrDestination(sticker)
  console.log(
    `  ${sticker.slug.padEnd(16)} ${label(sticker).padEnd(14)} ${dest ? `QR → ${dest}` : 'url only'}`,
  )
}

const sheets = pack(POOL)
for (const [i, placed] of sheets.entries()) {
  const svg = sheetSvg(placed, fonts, { index: i + 1, total: sheets.length })
  const name = sheets.length === 1 ? 'print-sheet' : `print-sheet-${i + 1}`
  await writeFile(join(sheetDir, `${name}.svg`), svg)
  await raster(svg, join(shotDir, `stickers-${name}.png`), 1.4)
  console.log(`  ${name.padEnd(16)} ${placed.length} stickers, US Letter`)
}

// 203 DPI is the conservative Munbyn head resolution; a 300 DPI model
// prints these strictly better.
const THERMAL_DPI = 203

console.log('\nmono (4×6 thermal label, 203 DPI)')
const thermalPlans = []
for (const sticker of stickers) {
  const { plan, svg, type } = thermalSvg(sticker, fonts)
  await writeFile(join(thermalDir, `${sticker.slug}.svg`), svg)
  const png = await raster(svg, join(thermalDir, `${sticker.slug}.png`), THERMAL_DPI / 100, {
    bilevel: true,
  })
  if (png) {
    const pdf = await thermalPdf(png)
    if (pdf) await writeFile(join(thermalDir, `${sticker.slug}.pdf`), pdf)
  }
  const per = `${plan.count} per label`
  const geometry = `${plan.cols}×${plan.rows}${plan.rotated ? ' rotated' : ''}`
  let note = ''
  if (plan.shortfall) {
    const worst = bindingConstraint(type)
    note = ` — SHRUNK to ${plan.scale.toFixed(2)}× (needs ${plan.shortfall.wanted}×); "${worst?.family}" at ${worst?.size} will be marginal`
  }
  thermalPlans.push({ slug: sticker.slug, ...plan })
  console.log(
    `  ${sticker.slug.padEnd(16)} ${String(plan.scale.toFixed(2) + '×').padEnd(7)} ${per.padEnd(14)} ${geometry}${note}`,
  )
}

console.log('\nsize sheets — one design per label, N up (4×6)')
await mkdir(sizesDir, { recursive: true })
const sizeIndex = []
for (const sticker of stickers) {
  const { qr, type } = renderArt(sticker, fonts, monoProfile)
  const floorScale = thermalScale(type)
  const minQr = qr.length > 0 ? Math.min(...qr) : null
  const offered = []

  // Work out every step first, then drop the ones that aren't worth
  // offering. Three stacked rows and a 2×2 grid land at almost the same
  // scale for a square sticker, and when 3-up and 4-up print the same
  // size, 4-up is strictly better — one fewer choice, one more sticker.
  const steps = SIZE_STEPS.map((n) => {
    const plan = bestGrid(sticker, n)
    // Render AT the intended scale before judging it: a design that
    // reflows draws different type at 0.9x than at 1.4x, so the floor has
    // to be measured against what will actually print.
    const atScale = renderArt(sticker, fonts, monoProfile, { scale: plan.scale })
    // minLegibleScale, not thermalScale: a design may be perfectly readable
    // below 1×, and clamping there would refuse a print that works.
    const floorAtScale = minLegibleScale(atScale.type)
    const qrAtScale = atScale.qr.length > 0 ? Math.min(...atScale.qr) : null
    const reason =
      plan.scale < floorAtScale
        ? 'type'
        : qrAtScale !== null && (qrAtScale * plan.scale) / UNITS_PER_INCH < MIN_QR_INCHES
          ? 'qr'
          : null
    return { n, plan, reason }
  })
  for (let i = 0; i < steps.length - 1; i++) {
    const next = steps[i + 1]
    if (!steps[i].reason && !next.reason && steps[i].plan.scale < next.plan.scale * 1.08) {
      steps[i].reason = `=${next.n}up`
    }
  }

  for (const { n, plan, reason } of steps) {
    if (reason) {
      offered.push(`${n}:${reason}`)
      continue
    }
    const svg = sizeSheet(fonts, sticker, n, plan)
    const file = `${sticker.slug}-${n}up`
    // PDF only. A size sheet is the base design tiled and scaled, so its
    // SVG is 2.5MB of duplicated artwork that nothing prints — the vector
    // source lives in svg/ and thermal/<slug>.svg, and this regenerates.
    // SIZE_SVG=1 writes them anyway, for eyeballing a reflowed layout.
    if (process.env.SIZE_SVG) await writeFile(join(sizesDir, `${file}.svg`), svg)
    const png = await rasterBuffer(svg, THERMAL_DPI / 100, { bilevel: true })
    if (png) {
      const pdf = await thermalPdf(png)
      if (pdf) await writeFile(join(sizesDir, `${file}.pdf`), pdf)
    }
    offered.push(`${n}:${inches(sticker.w * plan.scale)}x${inches(sticker.h * plan.scale)}in`)
    sizeIndex.push({ file, n, slug: sticker.slug })
  }
  console.log(`  ${sticker.slug.padEnd(16)} ${offered.join('  ')}`)
}
await writeFile(
  join(sizesDir, 'index.json'),
  `${JSON.stringify({ minQrInches: MIN_QR_INCHES, sheets: sizeIndex }, null, 2)}\n`,
)

// Cell geometry so verify.mjs can decode ONE sticker per label. A ganged
// label holds several finder-pattern triples and jsQR resolves none of
// them — a decoder limitation, not a print defect, but the two look
// identical from a pass/fail line unless the check crops first.
await writeFile(
  join(thermalDir, 'plan.json'),
  `${JSON.stringify({ dpi: THERMAL_DPI, label: LABEL, designs: thermalPlans }, null, 2)}\n`,
)

const kit = stickers.filter((s) => s.family === 'kit')
const scan = stickers.filter((s) => s.family === 'scan')
const road = stickers.filter((s) => s.family === 'road')

// Built after the size sheets so it reuses their geometry exactly — the
// pack is the same pages, collated.
if (sharp) {
  const pages = []
  const manifest = []
  for (const [slug, step] of TRIP_PACK) {
    const sticker = stickers.find((x) => x.slug === slug)
    if (!sticker) throw new Error(`unknown sticker in TRIP_PACK: ${slug}`)
    const plan = bestGrid(sticker, step)
    const png = await rasterBuffer(sizeSheet(fonts, sticker, step, plan), THERMAL_DPI / 100, {
      bilevel: true,
    })
    pages.push(png)
    manifest.push(
      `${slug} ${step}-up ${inches(sticker.w * plan.scale)}x${inches(sticker.h * plan.scale)}in`,
    )
  }
  const pack = await thermalPdfPages(pages, 'Ternpike trip pack')
  if (pack) await writeFile(join(thermalDir, 'trip-pack.pdf'), pack)
  const total = TRIP_PACK.reduce((n, [, step]) => n + step, 0)
  console.log(`\ntrip pack · ${pages.length} pages · ${total} stickers`)
  for (const entry of manifest) console.log(`  ${entry}`)
}

const contacts = [
  {
    bilevel: false,
    file: 'contact-sheet',
    opts: {
      profile: colorProfile,
      subset: kit,
      subtitle: 'Die-cut vinyl. Vector, outlined, print at actual size.',
      title: 'Ternpike sticker kit',
    },
  },
  {
    bilevel: true,
    file: 'contact-sheet-thermal',
    opts: {
      profile: monoProfile,
      subset: kit,
      subtitle: 'The same designs, black on white, for a thermal label printer.',
      title: 'Thermal profile',
    },
  },
  {
    bilevel: true,
    file: 'contact-sheet-road',
    opts: {
      profile: monoProfile,
      subset: road,
      subtitle: 'Shields, signs, plates, arrows, postcards. Route 66 energy.',
      title: 'Roadside',
    },
  },
  {
    bilevel: true,
    file: 'contact-sheet-scan',
    opts: {
      cols: 3,
      profile: monoProfile,
      subset: scan,
      subtitle: 'Small, QR-first, many per label. For sticking on things out there.',
      title: 'Scan family',
    },
  },
]

for (const { bilevel, file, opts } of contacts) {
  const svg = contactSheet(fonts, opts)
  await writeFile(join(sheetDir, `${file}.svg`), svg)
  await raster(svg, join(shotDir, `stickers-${file}.png`), 1, { bilevel })
}

console.log(`\n${stickers.length} designs · 2 profiles · keyline ${KEYLINE / 100}in`)
