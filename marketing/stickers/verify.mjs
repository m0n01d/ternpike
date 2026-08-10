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
// Needs `npm i --no-save sharp jsqr`.

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

  const meta = await sharp(file).metadata()
  const full = await decode(file, meta.width)
  const small = await decode(file, Math.round((sticker.w / 100) * PHONE_PX_PER_INCH))

  const ok = full === expected && small === expected
  if (!ok) failures++
  console.log(
    `  ${sticker.slug.padEnd(16)} ${ok ? 'OK  ' : 'FAIL'} 300dpi=${full === expected ? 'yes' : JSON.stringify(full)} @${PHONE_PX_PER_INCH}dpi=${small === expected ? 'yes' : JSON.stringify(small)}`,
  )
}

const withQr = stickers.filter(qrDestination).length
console.log(
  `\n${stickers.length} stickers · ${withQr} with a QR · every one carries ternpike.com · ${failures} failing`,
)
process.exit(failures === 0 ? 0 : 1)
