// Decode every QR back out of the rendered artwork.
//
//   node marketing/stickers/verify.mjs
//
// Generating a QR and rendering a QR are different things: a quiet zone
// eaten by a layout tweak, a light/dark pair without enough contrast, or a
// symbol scaled below its module resolution all produce a picture that
// looks like a QR and scans like a smudge. The only honest check is to
// point a decoder at the actual pixels.
//
// Each QR is decoded twice — once at 300 DPI (print truth) and once
// downscaled to roughly what a phone camera resolves from a foot away — so
// a symbol that only survives at full resolution fails here rather than in
// someone's hand.
//
// Both profiles are checked. The thermal pass is the harsher one: those
// PNGs are already hard-thresholded to one bit at 203 DPI, so a symbol
// that only survives with anti-aliased edges fails here — which is exactly
// what would happen coming off the label printer.
//
// The thermal PDFs are checked too — not their contents, but their page
// geometry. A label PDF that isn't exactly 4×6 gets scaled to fit by the
// print path, which is the whole failure this format exists to avoid.
//
// Needs `npm i --no-save sharp jsqr pdf-lib`.

import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import jsQR from 'jsqr'
import { PDFDocument } from 'pdf-lib'
import sharp from 'sharp'

import { bindingConstraint, monoProfile, thermalScale } from './lib/profiles.mjs'
import { qrDestination, stickers } from './lib/stickers.mjs'
import { loadFonts, resetTypeAudit, typeAudit } from './lib/type.mjs'

const here = dirname(fileURLToPath(import.meta.url))

// ~150 px across a 1in sticker: a deliberately unkind resolution, well
// below what a modern phone resolves at arm's length.
const PHONE_PX_PER_INCH = 150

const decode = async (file, width) => {
  const { data, info } = await sharp(file)
    .resize({ width })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true })
  return jsQR(new Uint8ClampedArray(data), info.width, info.height)?.data ?? null
}

const widthOf = async (file) => (await sharp(file).metadata()).width

const plans = JSON.parse(await readFile(join(here, 'thermal', 'plan.json'), 'utf8'))
const planFor = (slug) => plans.designs.find((d) => d.slug === slug)

/**
 * Decode one cell of a ganged thermal label.
 *
 * A 4×6 label carrying six stickers carries six QRs, and jsQR resolves
 * none of them — competing finder patterns, not a bad symbol. Cropping to
 * a single cell asks the question a phone would actually be asked.
 */
const decodeThermalCell = async (file, plan) => {
  const px = plans.dpi / 100
  const buf = await sharp(file)
    .extract({
      height: Math.round(plan.h * px),
      left: Math.round(plan.originX * px),
      top: Math.round(plan.originY * px),
      width: Math.round(plan.w * px),
    })
    .toBuffer()
  const { data, info } = await sharp(buf).ensureAlpha().raw().toBuffer({ resolveWithObject: true })
  return jsQR(new Uint8ClampedArray(data), info.width, info.height)?.data ?? null
}

let failures = 0

const fonts = await loadFonts()
const UNITS_PER_POINT = 100 / 72

/**
 * The whole point of `thermalScale` is that a design's smallest line clears
 * the 203 DPI legibility floor once scaled. Assert it actually does, rather
 * than trusting the arithmetic — the first version rounded to nearest and
 * put two designs a hundredth of a point under.
 */
const checkFloor = (sticker) => {
  resetTypeAudit()
  sticker.art(fonts, sticker.cut, monoProfile)
  const audit = typeAudit()
  const worst = bindingConstraint(audit)
  const rendered = (worst.size * thermalScale(audit)) / UNITS_PER_POINT
  const floor = (worst.needed * worst.size) / UNITS_PER_POINT
  return rendered + 1e-9 >= floor
    ? null
    : `${worst.family} at ${rendered.toFixed(2)}pt < ${floor}pt`
}

/** Exactly 4×6in at 72pt/in, one page. Anything else will be rescaled. */
const checkPdf = async (file) => {
  const doc = await PDFDocument.load(await readFile(join(here, 'thermal', `${file}.pdf`)))
  const pages = doc.getPages()
  if (pages.length !== 1) return `${pages.length} pages`
  const { height, width } = pages[0].getSize()
  return width === 288 && height === 432
    ? null
    : `${(width / 72).toFixed(2)}×${(height / 72).toFixed(2)}in`
}

for (const sticker of stickers) {
  const expected = qrDestination(sticker)
  const file = join(here, 'png', `${sticker.slug}.png`)

  if (!expected) {
    // No QR is fine — but then the printed URL is the only way anyone
    // reaches the site, so it had better be there. The rendered SVG can't
    // be grepped (type is outlined to paths), so check the design source,
    // which is where the string is actually written.
    const printsUrl = /ternpike\.com/i.test(sticker.art.toString())
    const pdf = await checkPdf(sticker.slug)
    const floor = checkFloor(sticker)
    const ok = printsUrl && !pdf && !floor
    if (!ok) failures++
    console.log(
      `  ${sticker.slug.padEnd(16)} ${ok ? 'OK  ' : 'FAIL'} url only, no QR${pdf ? ` — pdf ${pdf}` : ''}${floor ? ` — ${floor}` : ''}`,
    )
    continue
  }

  const full = await decode(file, await widthOf(file))
  const small = await decode(file, Math.round((sticker.w / 100) * PHONE_PX_PER_INCH))

  // The thermal label is already 1-bit at 203 DPI; decode one cell of it.
  const thermal = await decodeThermalCell(
    join(here, 'thermal', `${sticker.slug}.png`),
    planFor(sticker.slug),
  )

  const pdf = await checkPdf(sticker.slug)
  const floor = checkFloor(sticker)
  const ok = full === expected && small === expected && thermal === expected && !pdf && !floor
  if (!ok) failures++
  const mark = (got) => (got === expected ? 'yes' : JSON.stringify(got))
  console.log(
    `  ${sticker.slug.padEnd(16)} ${ok ? 'OK  ' : 'FAIL'} vinyl300=${mark(full)} vinyl${PHONE_PX_PER_INCH}=${mark(small)} thermal203-1bit=${mark(thermal)} pdf4x6=${pdf ? pdf : 'yes'}${floor ? ` FLOOR ${floor}` : ''}`,
  )
}

// The numbered sheets aren't designs, so the per-design loop misses them —
// and they're the ones most likely to actually get printed.
for (const file of ['1-small', '2-round', '3-tall', '4-large']) {
  const bad = await checkPdf(join('sheets', file))
  if (bad) failures++
  console.log(`  ${`sheet ${file}`.padEnd(16)} ${bad ? `FAIL pdf ${bad}` : 'OK   4x6 sheet, pdf4x6=yes'}`)
}

const withQr = stickers.filter(qrDestination).length
console.log(
  `\n${stickers.length} stickers · ${withQr} with a QR (colour + 1-bit thermal) · every one carries ternpike.com · all thermal PDFs exactly 4×6in · ${failures} failing`,
)
process.exit(failures === 0 ? 0 : 1)
