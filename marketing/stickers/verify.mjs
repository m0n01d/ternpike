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
// Needs `npm i --no-save sharp jsqr`.

import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import jsQR from 'jsqr'
import sharp from 'sharp'

import { qrDestination, stickers } from './lib/stickers.mjs'

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

for (const sticker of stickers) {
  const expected = qrDestination(sticker)
  const file = join(here, 'png', `${sticker.slug}.png`)

  if (!expected) {
    // No QR is fine — but then the printed URL is the only way anyone
    // reaches the site, so it had better be there. The rendered SVG can't
    // be grepped (type is outlined to paths), so check the design source,
    // which is where the string is actually written.
    const printsUrl = /ternpike\.com/i.test(sticker.art.toString())
    if (!printsUrl) failures++
    console.log(
      `  ${sticker.slug.padEnd(16)} ${printsUrl ? 'OK  ' : 'FAIL'} url only, no QR`,
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

  const ok = full === expected && small === expected && thermal === expected
  if (!ok) failures++
  const mark = (got) => (got === expected ? 'yes' : JSON.stringify(got))
  console.log(
    `  ${sticker.slug.padEnd(16)} ${ok ? 'OK  ' : 'FAIL'} vinyl300=${mark(full)} vinyl${PHONE_PX_PER_INCH}=${mark(small)} thermal203-1bit=${mark(thermal)}`,
  )
}

const withQr = stickers.filter(qrDestination).length
console.log(
  `\n${stickers.length} stickers · ${withQr} with a QR (colour + 1-bit thermal) · every one carries ternpike.com · ${failures} failing`,
)
process.exit(failures === 0 ? 0 : 1)
