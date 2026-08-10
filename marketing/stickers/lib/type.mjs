// Text → outlined SVG paths.
//
// Every glyph in the sticker kit ships as path data, never as a `<text>`
// element. A print shop opening `svg/badge-tern.svg` in Illustrator has no
// Playfair Display or DM Mono installed, and a `<text>` node would silently
// fall back to Helvetica — the kind of failure you discover on the proof.
// Outlining is the only way to make the file mean the same thing everywhere.
//
// Fonts are fetched from Google Fonts on first build and cached in
// `.fonts/` (gitignored). Both families are SIL Open Font License 1.1,
// which permits embedding and redistribution.

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import opentype from 'opentype.js'

const here = dirname(dirname(fileURLToPath(import.meta.url)))
const fontDir = join(here, '.fonts')

// Pinned to the exact gstatic URLs the CSS API hands back for a
// non-woff2 user agent. Pinned rather than re-resolved each build so a
// Google-side font revision can't silently reflow every sticker.
const FONT_SOURCES = {
  'DMMono-Medium': 'https://fonts.gstatic.com/s/dmmono/v16/aFTR7PB1QTsUX8KYvumzIYQ.ttf',
  'DMMono-Regular': 'https://fonts.gstatic.com/s/dmmono/v16/aFTU7PB1QTsUX8KYhh0.ttf',
  'PlayfairDisplay-Black':
    'https://fonts.gstatic.com/s/playfairdisplay/v40/nuFvD-vYSZviVYUb_rj3ij__anPXJzDwcbmjWBN2PKfsukDQ.ttf',
  'PlayfairDisplay-Bold':
    'https://fonts.gstatic.com/s/playfairdisplay/v40/nuFvD-vYSZviVYUb_rj3ij__anPXJzDwcbmjWBN2PKeiukDQ.ttf',
  'PlayfairDisplay-BoldItalic':
    'https://fonts.gstatic.com/s/playfairdisplay/v40/nuFRD-vYSZviVYUb_rj3ij__anPXDTnCjmHKM4nYO7KN_naUbtY.ttf',
  'PlayfairDisplay-Italic':
    'https://fonts.gstatic.com/s/playfairdisplay/v40/nuFRD-vYSZviVYUb_rj3ij__anPXDTnCjmHKM4nYO7KN_qiTbtY.ttf',
}

export async function loadFonts() {
  await mkdir(fontDir, { recursive: true })
  const fonts = {}
  for (const [name, url] of Object.entries(FONT_SOURCES)) {
    const file = join(fontDir, `${name}.ttf`)
    if (!existsSync(file)) {
      const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/4.0' } })
      if (!res.ok) throw new Error(`font fetch failed: ${name} → ${res.status}`)
      await writeFile(file, Buffer.from(await res.arrayBuffer()))
    }
    const buf = await readFile(file)
    fonts[name] = opentype.parse(
      buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength),
    )
  }
  return fonts
}

const PLACES = 2
const FACTOR = 10 ** PLACES

const num = (v) => {
  const r = Math.round(v * FACTOR) / FACTOR
  return String(Object.is(r, -0) ? 0 : r)
}

// Numbers are space-separated except before a leading minus, which is its
// own delimiter — the usual SVG path shorthand.
const cmd = (letter, ...values) => {
  let out = letter
  for (let i = 0; i < values.length; i++) {
    const s = num(values[i])
    out += i > 0 && !s.startsWith('-') ? ` ${s}` : s
  }
  return out
}

/**
 * Serialize an opentype Path to SVG path data.
 *
 * Hand-rolled rather than `Path.toPathData()` because opentype 2.0.0's
 * rounder does `Math.round(decimalPart + "e+" + places)`. When a coordinate
 * lands a hair off an integer its fractional part stringifies in
 * exponential notation ("4.44e-16"), the concatenation becomes
 * "4.44e-16e+2", and the coordinate silently rounds to NaN. Whole letters
 * vanish from the render with no error — which is exactly the failure mode
 * a print asset must not have.
 */
function pathData(path) {
  const out = []
  for (const c of path.commands) {
    if (c.type === 'M') out.push(cmd('M', c.x, c.y))
    else if (c.type === 'L') out.push(cmd('L', c.x, c.y))
    else if (c.type === 'C') out.push(cmd('C', c.x1, c.y1, c.x2, c.y2, c.x, c.y))
    else if (c.type === 'Q') out.push(cmd('Q', c.x1, c.y1, c.x, c.y))
    else if (c.type === 'Z') out.push('Z')
  }
  return out.join('')
}

/**
 * Lay a string out glyph by glyph.
 *
 * Deliberately NOT `font.forEachGlyph`: that routes through opentype's Bidi
 * shaper, which throws on Playfair Display's `ccmp` lookup
 * ("substFormat: 2 is not yet supported"). None of the copy here is
 * bidirectional or needs ligature substitution, so direct
 * `charToGlyph` + kern-pair layout gives the same result and actually runs.
 *
 * Returns per-glyph pen positions plus the run width with any trailing
 * letter-space trimmed off, so centring is honest.
 */
function layout(font, str, size, letterSpacing) {
  try {
    font.position.init()
  } catch {
    // No GPOS on this face; getKerningValue falls back to the kern table.
  }
  const items = []
  let pen = 0
  let prev = null
  for (const ch of str) {
    const glyph = font.charToGlyph(ch)
    // A missing glyph renders as tofu (or as nothing) on a sticker nobody
    // proofreads at 300 DPI. Fail the build instead.
    if (glyph.index === 0) {
      throw new Error(`${font.names.fullName?.en || 'font'} has no glyph for ${JSON.stringify(ch)} (in ${JSON.stringify(str)})`)
    }
    if (prev) pen += (font.getKerningValue(prev, glyph) / font.unitsPerEm) * size
    const advance = (glyph.advanceWidth / font.unitsPerEm) * size
    items.push({ advance, glyph, x: pen })
    pen += advance + letterSpacing * size
    prev = glyph
  }
  return { items, width: pen - (str.length ? letterSpacing * size : 0) }
}

const originFor = (anchor, x, width) =>
  anchor === 'middle' ? x - width / 2 : anchor === 'end' ? x - width : x

/** Advance width of `str`, in the same units as `size`. */
export function measure(font, str, size, { letterSpacing = 0 } = {}) {
  return layout(font, str, size, letterSpacing).width
}

/**
 * A single run of outlined text, returned as one path's `d`.
 *
 * `y` is the BASELINE, not the top of the box — the usual SVG text
 * convention. `anchor` is 'start' | 'middle' | 'end'.
 */
export function text(font, str, { anchor = 'start', letterSpacing = 0, size, x, y }) {
  const { items, width } = layout(font, str, size, letterSpacing)
  const ox = originFor(anchor, x, width)
  return items
    .map(({ glyph, x: gx }) => pathData(glyph.getPath(ox + gx, y, size)))
    .join('')
}

/**
 * Text set along a circular arc, one `<path>` per glyph.
 *
 * `centerDeg` is measured clockwise from 12 o'clock, so 0 centers the run
 * at the top of the circle and 180 at the bottom. Bottom runs pass
 * `flip: true`, which reverses the sweep and rotates each glyph 180° so the
 * line still reads left-to-right right-way-up.
 */
export function arcText(
  font,
  str,
  { centerDeg, cx, cy, fill, letterSpacing = 0, r, size, flip = false },
) {
  const { items, width } = layout(font, str, size, letterSpacing)

  const parts = []
  for (const { advance, glyph, x: gx } of items) {
    if (!glyph.unicode || glyph.unicode === 32) continue

    // Arc length from the run's midpoint to this glyph's midpoint.
    const offset = gx + advance / 2 - width / 2
    const sweep = ((offset / r) * 180) / Math.PI
    const deg = flip ? centerDeg - sweep : centerDeg + sweep
    const rad = (deg * Math.PI) / 180
    const px = cx + r * Math.sin(rad)
    const py = cy - r * Math.cos(rad)
    const rotation = flip ? deg + 180 : deg

    const d = pathData(glyph.getPath(-advance / 2, 0, size))
    parts.push(
      `<path transform="translate(${round(px)} ${round(py)}) rotate(${round(rotation)})" d="${d}"/>`,
    )
  }
  return `<g fill="${fill}">${parts.join('')}</g>`
}

export const round = (n) => Math.round(n * 100) / 100
