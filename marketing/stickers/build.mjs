// Build the Ternpike sticker kit.
//
//   node marketing/stickers/build.mjs
//
// Emits, from the designs in lib/stickers.mjs:
//   svg/<slug>.svg     one die-cut sticker each, artwork only, no guides
//   png/<slug>.png     the same at 300 DPI, for print portals that want raster
//   sheets/*.svg       US Letter gang sheets with dashed cut guides
//   ../../docs/screenshots/stickers-*.png   review images for the PR
//
// PNG output needs `sharp`, which is not a repo dependency — it pulls a
// platform binary and nothing else here rasterizes. Run
// `npm i --no-save sharp` first, or pass --no-png to emit vectors only.
// The SVGs are the real deliverable; the PNGs are a convenience.

import { mkdir, rm, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { KEYLINE, UNITS_PER_INCH } from './lib/shapes.mjs'
import { C, stickers } from './lib/stickers.mjs'
import { loadFonts, round, text } from './lib/type.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = join(here, '..', '..')
const wantPng = !process.argv.includes('--no-png')

const inches = (units) => round(units / UNITS_PER_INCH)
// DM Mono has no U+2033 prime, so spell the unit out.
const label = (s) => `${inches(s.w)}in × ${inches(s.h)}in`

// ── One sticker ──────────────────────────────────────────────────────────

// width/height in inches so the file carries its physical size: dropped
// into Illustrator or a print portal it arrives at 1:1 rather than at
// whatever the importer guesses.
function stickerSvg(sticker, fonts) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${inches(sticker.w)}in" height="${inches(sticker.h)}in" viewBox="0 0 ${sticker.w} ${sticker.h}">
  <title>Ternpike — ${sticker.title}</title>
  <path d="${sticker.cut(0)}" fill="${C.parchment}"/>
  ${sticker.art(fonts, sticker.cut).trim()}
</svg>
`
}

// ── Gang sheet ───────────────────────────────────────────────────────────

const SHEET = { gap: 22, h: 1100, margin: 40, w: 850 }

// How many of each to gang up. Weighted toward the small ones — those are
// the ones that actually get handed out.
const POOL = [
  ['badge-tern', 1],
  ['milepost-zero', 1],
  ['receipt', 1],
  ['orlando-juneau', 1],
  ['cabin-or-truck', 1],
  ['tern-mark', 4],
  ['wordmark-rust', 2],
  ['no-signal', 2],
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
    let pool = remaining

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
      pool = pool
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
    <path d="${sticker.cut(0)}" fill="${C.parchment}"/>
    ${sticker.art(fonts, sticker.cut).trim()}
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
  <rect width="${SHEET.w}" height="${SHEET.h}" fill="#ffffff"/>
${art}
  <g id="cut-guides" fill="none" stroke="#ff00ff" stroke-width="0.6" stroke-dasharray="6 4">
${guides}
  </g>
  <path d="${text(fonts['DMMono-Regular'], slug, { size: 7.5, x: SHEET.margin, y: SHEET.h - 22 })}" fill="#b0b0a8"/>
</svg>
`
}

// ── Contact sheet (review image) ─────────────────────────────────────────

function contactSheet(fonts) {
  const cols = 4
  const cellW = 345
  const cellH = 360
  const artW = 296
  const artH = 216
  const pad = 26
  const margin = 54
  const headerH = 190
  const rows = Math.ceil(stickers.length / cols)
  const w = margin * 2 + cols * cellW + (cols - 1) * pad
  const h = headerH + rows * cellH + (rows - 1) * pad + margin

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
    <rect x="${cx}" y="${cy}" width="${cellW}" height="${cellH}" rx="18" fill="#ffffff" opacity="0.55"/>
    <g transform="translate(${round(ax)} ${round(ay)}) scale(${round(scale)})">
      <path d="${sticker.cut(0)}" fill="${C.parchment}"/>
      ${sticker.art(fonts, sticker.cut).trim()}
    </g>
    <path d="${text(fonts['PlayfairDisplay-Bold'], sticker.title, {
      anchor: 'middle',
      size: 24,
      x: cx + cellW / 2,
      y: cy + artH + 74,
    })}" fill="${C.forest}"/>
    <path d="${text(fonts['DMMono-Regular'], label(sticker), {
      anchor: 'middle',
      letterSpacing: 0.12,
      size: 13,
      x: cx + cellW / 2,
      y: cy + artH + 100,
    })}" fill="${C.rust}"/>
  </g>`
    })
    .join('\n')

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <rect width="${w}" height="${h}" fill="${C.cream}"/>
  <path d="${text(fonts['PlayfairDisplay-Black'], 'Ternpike sticker kit', {
    size: 62,
    x: margin,
    y: 96,
  })}" fill="${C.forest}"/>
  <path d="${text(fonts['PlayfairDisplay-Italic'], 'Eight die-cut designs. Vector, outlined, print at actual size.', {
    size: 26,
    x: margin + 4,
    y: 136,
  })}" fill="${C.moss}"/>
  <path d="M${margin} 158H${w - margin}" stroke="${C.rust}" stroke-width="2"/>
${cells}
</svg>
`
}

// ── Run ──────────────────────────────────────────────────────────────────

const fonts = await loadFonts()

const svgDir = join(here, 'svg')
const pngDir = join(here, 'png')
const sheetDir = join(here, 'sheets')
const shotDir = join(repoRoot, 'docs', 'screenshots')

for (const dir of [svgDir, pngDir, sheetDir]) {
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

// 300 DPI: viewBox units are 1/100in, so 3 px per unit.
const raster = async (svg, out, pxPerUnit = 3) => {
  if (!sharp) return
  await sharp(Buffer.from(svg), { density: 96 * pxPerUnit })
    .resize({ width: Math.round(widthOf(svg) * pxPerUnit) })
    .png({ compressionLevel: 9 })
    .toFile(out)
}

const widthOf = (svg) => Number(/viewBox="0 0 ([\d.]+)/.exec(svg)[1])

for (const sticker of stickers) {
  const svg = stickerSvg(sticker, fonts)
  await writeFile(join(svgDir, `${sticker.slug}.svg`), svg)
  await raster(svg, join(pngDir, `${sticker.slug}.png`))
  console.log(`  ${sticker.slug.padEnd(16)} ${label(sticker)}`)
}

const sheets = pack(POOL)
for (const [i, placed] of sheets.entries()) {
  const svg = sheetSvg(placed, fonts, { index: i + 1, total: sheets.length })
  const name = sheets.length === 1 ? 'print-sheet' : `print-sheet-${i + 1}`
  await writeFile(join(sheetDir, `${name}.svg`), svg)
  await raster(svg, join(shotDir, `stickers-${name}.png`), 1.4)
  console.log(`  ${name.padEnd(16)} ${placed.length} stickers`)
}

const contact = contactSheet(fonts)
await writeFile(join(sheetDir, 'contact-sheet.svg'), contact)
await raster(contact, join(shotDir, 'stickers-contact-sheet.png'), 1)

console.log(`\n${stickers.length} stickers · ${sheets.length} gang sheet(s) · keyline ${KEYLINE / 100}in`)
