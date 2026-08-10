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
  monoProfile,
  thermalScale,
} from './lib/profiles.mjs'
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
function renderArt(sticker, fonts, profile) {
  resetTypeAudit()
  const body = sticker.art(fonts, sticker.cut, profile).trim()
  return { body, type: typeAudit() }
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

function contactSheet(fonts, { profile, subtitle, title }) {
  const cols = 3
  const cellW = 420
  const cellH = 400
  const artW = 350
  const artH = 264
  const pad = 26
  const margin = 54
  const headerH = 190
  const rows = Math.ceil(stickers.length / cols)
  const w = margin * 2 + cols * cellW + (cols - 1) * pad
  const h = headerH + rows * cellH + (rows - 1) * pad + margin
  const paper = profile.mono ? '#ffffff' : BRAND.cream
  const cellBg = profile.mono ? '#f4f4f4' : '#ffffff'
  const ink = profile.mono ? '#000000' : BRAND.forest
  const sub = profile.mono ? '#000000' : BRAND.moss
  const cap = profile.mono ? '#000000' : BRAND.rust

  const cells = stickers
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
  if (!PDFDocument) return null
  const doc = await PDFDocument.create()
  doc.setTitle('Ternpike thermal label')
  doc.setCreator('Ternpike')
  const page = doc.addPage([288, 432]) // 4×6in at 72pt/in
  const image = await doc.embedPng(png)
  page.drawImage(image, { height: 432, width: 288, x: 0, y: 0 })
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

// Cell geometry so verify.mjs can decode ONE sticker per label. A ganged
// label holds several finder-pattern triples and jsQR resolves none of
// them — a decoder limitation, not a print defect, but the two look
// identical from a pass/fail line unless the check crops first.
await writeFile(
  join(thermalDir, 'plan.json'),
  `${JSON.stringify({ dpi: THERMAL_DPI, label: LABEL, designs: thermalPlans }, null, 2)}\n`,
)

await writeFile(
  join(sheetDir, 'contact-sheet.svg'),
  contactSheet(fonts, {
    profile: colorProfile,
    subtitle: 'Die-cut vinyl. Vector, outlined, print at actual size.',
    title: 'Ternpike sticker kit',
  }),
)
await raster(
  contactSheet(fonts, {
    profile: colorProfile,
    subtitle: 'Die-cut vinyl. Vector, outlined, print at actual size.',
    title: 'Ternpike sticker kit',
  }),
  join(shotDir, 'stickers-contact-sheet.png'),
  1,
)

const monoContact = contactSheet(fonts, {
  profile: monoProfile,
  subtitle: 'The same designs, black on white, for a thermal label printer.',
  title: 'Thermal profile',
})
await writeFile(join(sheetDir, 'contact-sheet-thermal.svg'), monoContact)
await raster(monoContact, join(shotDir, 'stickers-contact-sheet-thermal.png'), 1, {
  bilevel: true,
})

console.log(`\n${stickers.length} designs · 2 profiles · keyline ${KEYLINE / 100}in`)
