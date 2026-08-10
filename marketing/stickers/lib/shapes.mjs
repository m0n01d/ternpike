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
