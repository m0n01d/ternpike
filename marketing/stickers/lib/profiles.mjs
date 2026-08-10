// Print profiles: the same nine designs, rendered for two very different
// output devices.
//
// Designs never name a colour. They name a ROLE — `field`, `ink`, `accent`
// — and a profile decides what that role is worth. That indirection is the
// only reason a thermal variant exists at all: mechanically recolouring
// finished artwork produces mush, whereas a design that already says "this
// is the field and that is the ink" inverts correctly for free.
//
// ── color ──
// Die-cut vinyl. Full brand palette, light-on-dark where the design wants
// it, soft opacities for hairlines.
//
// ── mono ──
// Direct thermal label printers (Munbyn RW403B and friends). Three hard
// constraints, none of them stylistic:
//
//   1. One bit per dot. There is no grey — a 40%-opacity hairline is
//      dithered into speckle, so every opacity collapses to 1.
//   2. Ink coverage costs. A 3in solid-black disc means the head holds full
//      power across the whole label: slow, smeary, and hard on the head. So
//      `field` becomes white and every dark-field design inverts into line
//      art rather than printing as a black slab.
//   3. 203 DPI has a legibility floor. Counters fill in below roughly 7pt
//      mono / 9pt Playfair Bold, and Playfair's hairline serifs drop out
//      entirely below ~11pt. Designs are scaled up per-design until their
//      smallest run clears it (see `thermalScale`).
//
// 203 DPI is the conservative assumption — it's what the common Munbyn
// models run. A 300 DPI head prints these strictly better.

const BLACK = '#000000'
const WHITE = '#ffffff'

// From src/theme.css.
export const BRAND = {
  cream: '#f2ede3',
  forest: '#2d3a22',
  forestDeep: '#1a2412',
  moss: '#6b7c58',
  muted: '#8a8a78',
  parchment: '#faf7f0',
  rust: '#b85c38',
  tan: '#d4c9a8',
}

/**
 * Roles a design may paint with.
 *
 * `field`/`ink` are per-design (a receipt is ink-on-light, a badge is
 * light-on-dark), so each design picks its own pair from the profile's
 * named surfaces rather than the profile dictating one.
 */
export const colorProfile = {
  name: 'color',
  mono: false,
  keyline: BRAND.parchment,
  sheetBg: '#ffffff',

  // Surfaces a design can choose as its field.
  dark: BRAND.forest,
  light: BRAND.cream,
  warm: BRAND.tan,
  green: BRAND.moss,
  brand: BRAND.rust,

  // Marks on those surfaces.
  onDark: BRAND.cream,
  onDarkSoft: BRAND.tan,
  onLight: BRAND.forest,
  onLightSoft: BRAND.muted,
  accent: BRAND.rust,

  // QR always needs a genuinely light card and genuinely dark modules.
  card: BRAND.cream,
  cardInk: BRAND.forestDeep,

  markDark: BRAND.forestDeep,

  /** Opacity for de-emphasised elements. */
  dim: (o) => o,
}

export const monoProfile = {
  name: 'mono',
  mono: true,
  keyline: WHITE,
  sheetBg: WHITE,

  // Every field goes white. Dark-field designs invert into line art; that
  // is the point, not a side effect.
  dark: WHITE,
  light: WHITE,
  warm: WHITE,
  green: WHITE,
  brand: WHITE,

  onDark: BLACK,
  onDarkSoft: BLACK,
  onLight: BLACK,
  onLightSoft: BLACK,
  accent: BLACK,

  card: WHITE,
  cardInk: BLACK,

  // The tern's cap and beak are drawn over its body. Same colour as the
  // body turns the whole bird into one clean silhouette; keeping them
  // white would punch a hole in a shape that is already only an outline.
  markDark: BLACK,

  dim: () => 1,
}

// ── Thermal legibility floor ─────────────────────────────────────────────

const UNITS_PER_POINT = 100 / 72

// Minimum rendered size, in points, below which a face stops surviving a
// 203 DPI thermal head. Playfair is split because its hairline serifs and
// high stroke contrast fail well before its counters do.
const FLOOR_PT = [
  [/Playfair.*(Italic|Regular)/, 11],
  [/Playfair/, 9],
  [/DM Mono/, 7],
]

const floorFor = (family) => (FLOOR_PT.find(([re]) => re.test(family)) ?? [null, 9])[1]

/**
 * How far a design must be scaled up before its smallest type clears the
 * thermal floor.
 *
 * Returns 1 when the design is already legible. Callers get a number to
 * multiply the whole sticker by — scaling uniformly keeps the composition
 * intact, where bumping individual runs would reflow it.
 */
export function thermalScale(entries) {
  let scale = 1
  for (const { family, size } of entries) {
    const needed = (floorFor(family) * UNITS_PER_POINT) / size
    if (needed > scale) scale = needed
  }
  return Math.round(scale * 100) / 100
}

/** The run that forced the scale — useful for explaining a big number. */
export function bindingConstraint(entries) {
  let worst = null
  for (const entry of entries) {
    const needed = (floorFor(entry.family) * UNITS_PER_POINT) / entry.size
    if (!worst || needed > worst.needed) worst = { ...entry, needed }
  }
  return worst
}
