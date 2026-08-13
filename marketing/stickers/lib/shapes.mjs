// Die-cut silhouettes and the Ternpike bird mark.
//
// Every shape is a function of an `inset`, because each sticker is drawn
// twice: once at inset 0 as the parchment keyline (the white border that
// gives the cutter its tolerance) and once inset by KEYLINE as the artwork
// field. The same function also supplies the dashed cut guide on the
// print sheet, which is what keeps the guide and the border in agreement —
// they can't drift because there is only one definition.
//
// Units are 1/100 inch throughout: 100 units = 1in on paper.

import { round } from './type.mjs'

export const UNITS_PER_INCH = 100
export const KEYLINE = 7 // 0.07in white border

const r2 = round

export const roundedRect = (w, h, radius) => (inset) => {
  const x = inset
  const y = inset
  const rw = w - inset * 2
  const rh = h - inset * 2
  const rr = Math.max(0, Math.min(radius - inset, rw / 2, rh / 2))
  return `M${r2(x + rr)} ${r2(y)}h${r2(rw - rr * 2)}a${r2(rr)} ${r2(rr)} 0 0 1 ${r2(rr)} ${r2(rr)}v${r2(rh - rr * 2)}a${r2(rr)} ${r2(rr)} 0 0 1 ${r2(-rr)} ${r2(rr)}h${r2(-(rw - rr * 2))}a${r2(rr)} ${r2(rr)} 0 0 1 ${r2(-rr)} ${r2(-rr)}v${r2(-(rh - rr * 2))}a${r2(rr)} ${r2(rr)} 0 0 1 ${r2(rr)} ${r2(-rr)}z`
}

export const circle = (d) => (inset) => {
  const c = d / 2
  const rr = c - inset
  return `M${r2(c)} ${r2(c - rr)}a${r2(rr)} ${r2(rr)} 0 1 1 0 ${r2(rr * 2)}a${r2(rr)} ${r2(rr)} 0 1 1 0 ${r2(-rr * 2)}z`
}

export const ellipse = (w, h) => (inset) => {
  const cx = w / 2
  const cy = h / 2
  const rx = cx - inset
  const ry = cy - inset
  return `M${r2(cx)} ${r2(cy - ry)}a${r2(rx)} ${r2(ry)} 0 1 1 0 ${r2(ry * 2)}a${r2(rx)} ${r2(ry)} 0 1 1 0 ${r2(-ry * 2)}z`
}

/**
 * Thermal-receipt silhouette: square shoulders, torn zigzag along the
 * bottom. `teeth` counts the full V's; the inset shifts the whole tear up
 * with the rest of the outline so the keyline follows every point.
 */
export const receipt = (w, h, teeth) => (inset) => {
  const left = inset
  const right = w - inset
  const top = inset
  const bottom = h - inset
  const rr = Math.max(0, 4 - inset)
  const span = (right - left) / teeth
  const depth = 9

  const zig = []
  for (let i = 0; i < teeth; i++) {
    const midX = right - span * i - span / 2
    const endX = right - span * (i + 1)
    zig.push(`L${r2(midX)} ${r2(bottom - depth)}L${r2(endX)} ${r2(bottom)}`)
  }

  return `M${r2(left)} ${r2(top + rr)}a${r2(rr)} ${r2(rr)} 0 0 1 ${r2(rr)} ${r2(-rr)}h${r2(right - left - rr * 2)}a${r2(rr)} ${r2(rr)} 0 0 1 ${r2(rr)} ${r2(rr)}V${r2(bottom)}${zig.join('')}z`
}

/**
 * Highway milepost: a tall plate with a domed head, the shape the Alaska
 * Highway markers use. Radius on the head is half the width so the top is
 * a true semicircle at inset 0.
 */
export const milepost = (w, h) => (inset) => {
  const left = inset
  const right = w - inset
  const top = inset
  const bottom = h - inset
  const head = (right - left) / 2
  const foot = Math.max(0, 6 - inset)
  return `M${r2(left)} ${r2(top + head)}a${r2(head)} ${r2(head)} 0 0 1 ${r2(head * 2)} 0V${r2(bottom - foot)}a${r2(foot)} ${r2(foot)} 0 0 1 ${r2(-foot)} ${r2(foot)}h${r2(-(right - left - foot * 2))}a${r2(foot)} ${r2(foot)} 0 0 1 ${r2(-foot)} ${r2(-foot)}z`
}

/**
 * The tern from `marketing/src/favicon.svg`, redrawn as a reusable group.
 *
 * The favicon's raw drawing lives in a ~96×30 box with the body centred
 * near (60, 41). `scale` is relative to that box; `x`/`y` place the bird's
 * centre, not its corner, so callers can drop it on a layout axis without
 * arithmetic.
 */
export function bird({ dark, light, scale = 1, x, y }) {
  const tx = round(x - 48 * scale)
  const ty = round(y - 35 * scale)
  return `<g transform="translate(${tx} ${ty}) scale(${round(scale)})">
    <path d="M60 40 C40 26, 8 20, 0 29 C16 28, 38 34, 60 44Z" fill="${light}"/>
    <path d="M60 40 C80 26, 112 20, 120 29 C104 28, 82 34, 60 44Z" fill="${light}"/>
    <ellipse cx="60" cy="43" rx="20" ry="7" fill="${light}"/>
    <g transform="rotate(-12 42 43)">
      <path d="M42 43 L18 38" stroke="${light}" stroke-width="2.5" stroke-linecap="round"/>
      <path d="M42 43 L18 48" stroke="${light}" stroke-width="2" stroke-linecap="round"/>
    </g>
    <ellipse cx="76" cy="40" rx="9" ry="7" fill="${dark}"/>
    <path d="M84 40 L96 38.5 L84 42Z" fill="${dark}"/>
    <circle cx="79" cy="38.5" r="1.6" fill="${light}"/>
  </g>`
}

/** Concentric signal arcs with a slash through them. */
export function noSignal({ cx, cy, slash, stroke, weight = 3.4 }) {
  const arc = (r) => {
    const a = (140 * Math.PI) / 180
    const x1 = cx - r * Math.sin(a / 2)
    const x2 = cx + r * Math.sin(a / 2)
    const yy = cy - r * Math.cos(a / 2)
    return `<path d="M${r2(x1)} ${r2(yy)}A${r2(r)} ${r2(r)} 0 0 1 ${r2(x2)} ${r2(yy)}" fill="none" stroke="${stroke}" stroke-width="${weight}" stroke-linecap="round"/>`
  }
  return `<g>
    ${arc(20)}${arc(13)}${arc(6)}
    <circle cx="${r2(cx)}" cy="${r2(cy)}" r="2.6" fill="${stroke}"/>
    <path d="M${r2(cx - 18)} ${r2(cy + 12)}L${r2(cx + 18)} ${r2(cy - 22)}" stroke="${slash}" stroke-width="${weight + 0.6}" stroke-linecap="round"/>
  </g>`
}

/**
 * Viewfinder corner marks around a QR.
 *
 * A code sitting alone on white reads as decoration. Bracketing it is the
 * cheapest possible way to say "point your camera here" without spending a
 * word on it, and it survives 1-bit thermal at any size the QR does.
 */
export function scanBrackets({ h, len = 15, stroke, w, weight = 2.4, x, y }) {
  const corners = [
    `M${r2(x + len)} ${r2(y)}H${r2(x)}V${r2(y + len)}`,
    `M${r2(x + w - len)} ${r2(y)}H${r2(x + w)}V${r2(y + len)}`,
    `M${r2(x + len)} ${r2(y + h)}H${r2(x)}V${r2(y + h - len)}`,
    `M${r2(x + w - len)} ${r2(y + h)}H${r2(x + w)}V${r2(y + h - len)}`,
  ]
  return `<g fill="none" stroke="${stroke}" stroke-width="${weight}" stroke-linecap="square">${corners
    .map((d) => `<path d="${d}"/>`)
    .join('')}</g>`
}

/** A three-peak range. Solid, because a 1-bit outline at this size fills in. */
export function mountains({ fill, h, w, x, y }) {
  const px = (t) => r2(x + w * t)
  const py = (t) => r2(y + h * t)
  return `<path d="M${r2(x)} ${py(1)}L${px(0.16)} ${py(0.42)}L${px(0.28)} ${py(0.66)}L${px(0.49)} ${py(0)}L${px(0.66)} ${py(0.48)}L${px(0.78)} ${py(0.26)}L${r2(x + w)} ${py(1)}Z" fill="${fill}"/>`
}

/**
 * Map pin, tip at (cx, cy).
 *
 * Junction points sit at a true 40° off horizontal from the head's centre,
 * so the body meets the circle tangentially instead of kinking — visible at
 * 1.5in even though it sounds like pedantry.
 */
export function pin({ cx, cy, fill, hole, r }) {
  const headY = cy - r * 1.7
  const jx = r * Math.cos((40 * Math.PI) / 180)
  const jy = r * Math.sin((40 * Math.PI) / 180)
  return `<g>
    <path d="M${r2(cx)} ${r2(cy)}L${r2(cx - jx)} ${r2(headY + jy)}A${r2(r)} ${r2(r)} 0 1 1 ${r2(cx + jx)} ${r2(headY + jy)}Z" fill="${fill}"/>
    <circle cx="${r2(cx)}" cy="${r2(headY)}" r="${r2(r * 0.38)}" fill="${hole}"/>
  </g>`
}

/**
 * US-route-style shield: flat top with rounded shoulders, sides tucking to
 * a soft point at the bottom. The controls all ride the inset-shifted box,
 * so the keyline tracks the silhouette closely enough for a cutter.
 */
export const shield = (w, h) => (inset) => {
  const l = inset
  const r = w - inset
  const t = inset
  const b = h - inset
  const cx = w / 2
  const cr = Math.max(0, 16 - inset)
  const waist = t + (b - t) * 0.45
  const bulge = waist + (b - waist) * 0.55
  return `M${r2(l + cr)} ${r2(t)}H${r2(r - cr)}Q${r2(r)} ${r2(t)} ${r2(r)} ${r2(t + cr)}V${r2(waist)}C${r2(r)} ${r2(bulge)} ${r2(cx + (r - cx) * 0.45)} ${r2(b - 18)} ${r2(cx + 7)} ${r2(b - 5)}Q${r2(cx)} ${r2(b)} ${r2(cx - 7)} ${r2(b - 5)}C${r2(cx - (cx - l) * 0.45)} ${r2(b - 18)} ${r2(l)} ${r2(bulge)} ${r2(l)} ${r2(waist)}V${r2(t + cr)}Q${r2(l)} ${r2(t)} ${r2(l + cr)} ${r2(t)}Z`
}

/**
 * Warning-sign diamond: a 45° square with softened tips. Offsetting a 45°
 * edge inward by `inset` moves each vertex inward by inset·√2 along its
 * axis, which is why the tips use that factor rather than the raw inset.
 */
export const diamond = (size) => (inset) => {
  const c = size / 2
  const eff = c - inset * Math.SQRT2
  const k = Math.max(0, 9 - inset) * Math.SQRT1_2
  return (
    `M${r2(c - k)} ${r2(c - eff + k)}` +
    `Q${r2(c)} ${r2(c - eff)} ${r2(c + k)} ${r2(c - eff + k)}` +
    `L${r2(c + eff - k)} ${r2(c - k)}` +
    `Q${r2(c + eff)} ${r2(c)} ${r2(c + eff - k)} ${r2(c + k)}` +
    `L${r2(c + k)} ${r2(c + eff - k)}` +
    `Q${r2(c)} ${r2(c + eff)} ${r2(c - k)} ${r2(c + eff - k)}` +
    `L${r2(c - eff + k)} ${r2(c + k)}` +
    `Q${r2(c - eff)} ${r2(c)} ${r2(c - eff + k)} ${r2(c - k)}` +
    `Z`
  )
}

/**
 * Googie arrow pointing right: rounded-corner body, pentagon head, soft
 * tip. The head slope's inward offset is approximated as 1.65× the inset
 * (1/sin of the slope angle for these proportions) — close enough for a
 * 0.07in keyline, nowhere near close enough for machining.
 */
export const arrowSign = (w, h, head = 90) => (inset) => {
  const l = inset
  const t = inset
  const b = h - inset
  const r = w - inset * 1.65
  const cy = h / 2
  const nx = w - head
  const cr = Math.max(0, 12 - inset)
  const tipR = Math.max(0, 8 - inset)
  return `M${r2(l + cr)} ${r2(t)}H${r2(nx)}L${r2(r - tipR * 1.6)} ${r2(cy - tipR)}Q${r2(r)} ${r2(cy)} ${r2(r - tipR * 1.6)} ${r2(cy + tipR)}L${r2(nx)} ${r2(b)}H${r2(l + cr)}Q${r2(l)} ${r2(b)} ${r2(l)} ${r2(b - cr)}V${r2(t + cr)}Q${r2(l)} ${r2(t)} ${r2(l + cr)} ${r2(t)}Z`
}

/** Five-point star, point-up. The Alaska flag is eight of these. */
export function star5({ cx, cy, fill, r }) {
  const pts = []
  for (let i = 0; i < 10; i++) {
    const rad = (Math.PI / 5) * i - Math.PI / 2
    const rr = i % 2 === 0 ? r : r * 0.4
    pts.push(`${r2(cx + rr * Math.cos(rad))} ${r2(cy + rr * Math.sin(rad))}`)
  }
  return `<path d="M${pts.join('L')}Z" fill="${fill}"/>`
}

/**
 * Bear paw print: heel pad plus four toes. Filled shapes, not outlines —
 * at sticker scale the black areas are small enough that a thermal head
 * lays them down cleanly, and an outlined paw reads as a diagram.
 */
export function pawPrint({ cx, cy, fill, scale = 1 }) {
  const toe = (dx, dy, rot) =>
    `<ellipse cx="${r2(cx + dx * scale)}" cy="${r2(cy + dy * scale)}" rx="${r2(11 * scale)}" ry="${r2(14 * scale)}" transform="rotate(${rot} ${r2(cx + dx * scale)} ${r2(cy + dy * scale)})" fill="${fill}"/>`
  return `<g>
    <ellipse cx="${r2(cx)}" cy="${r2(cy)}" rx="${r2(27 * scale)}" ry="${r2(20 * scale)}" fill="${fill}"/>
    ${toe(-39, -20, -28)}${toe(-14, -31, -10)}${toe(14, -31, 10)}${toe(39, -20, 28)}
  </g>`
}

/** Low sun with rays — outlined, so it survives 1-bit next to solid hills. */
export function sunburst({ cx, cy, r, stroke, weight = 2.2 }) {
  const rays = []
  for (let i = 0; i < 8; i++) {
    const rad = (Math.PI / 4) * i
    const x1 = cx + (r + 5) * Math.cos(rad)
    const y1 = cy + (r + 5) * Math.sin(rad)
    const x2 = cx + (r + 12) * Math.cos(rad)
    const y2 = cy + (r + 12) * Math.sin(rad)
    rays.push(`<path d="M${r2(x1)} ${r2(y1)}L${r2(x2)} ${r2(y2)}"/>`)
  }
  return `<g fill="none" stroke="${stroke}" stroke-width="${weight}" stroke-linecap="round">
    <circle cx="${r2(cx)}" cy="${r2(cy)}" r="${r2(r)}"/>
    ${rays.join('')}
  </g>`
}

/** Direction-sign board with a pointed end, Sign Post Forest style. */
export function arrowBoard({ dir = 'right', h, w, x, y }) {
  const a = h * 0.45
  return dir === 'right'
    ? `M${r2(x)} ${r2(y)}H${r2(x + w - a)}L${r2(x + w)} ${r2(y + h / 2)}L${r2(x + w - a)} ${r2(y + h)}H${r2(x)}Z`
    : `M${r2(x + w)} ${r2(y)}H${r2(x + a)}L${r2(x)} ${r2(y + h / 2)}L${r2(x + a)} ${r2(y + h)}H${r2(x + w)}Z`
}

