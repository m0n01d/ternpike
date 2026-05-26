// Ternpike-branded QR sticker SVG.
//
// Layout target: Munbyn 2"x1" thermal label, landscape. QR on the left,
// brand chrome on the right. The SVG declares width/height in inches and
// uses a 200x100 viewBox so the proportions print at the intended physical
// size regardless of renderer.
//
// Three templates:
//   - trailhead — dark forest bg, cream QR card, cream brand text
//   - sign      — parchment bg, forest QR + text, rust accent
//   - minimal   — pure white, black QR, gray text (ultra-clean)
//
// QR is rendered as a single `<path>` of dark modules (~10x smaller SVG
// than one `<rect>` per module) at error-correction level Q (~25% recovery)
// so coffee splatter, scratches, and dim light don't kill the scan.

import qrcode from 'qrcode-generator'

const PALETTE = {
  forest: '#2d3a22',
  forestDeep: '#1a2412',
  cream: '#f2ede3',
  parchment: '#faf7f0',
  rust: '#b85c38',
  ink: '#1e2818',
  muted: '#8a8a78',
}

export const TEMPLATES = ['trailhead', 'sign', 'minimal', 'share']
export const DEFAULT_TEMPLATE = 'trailhead'

export const isValidTemplate = (t) => TEMPLATES.includes(t)

const escapeXml = (s) =>
  String(s).replace(/[<>&"']/g, (c) =>
    c === '<' ? '&lt;'
    : c === '>' ? '&gt;'
    : c === '&' ? '&amp;'
    : c === '"' ? '&quot;'
    : '&apos;'
  )

// Each template fits the same 200x100 viewBox and exposes the same
// signature so the renderer can swap them by name.
const TEMPLATE_FNS = {
  trailhead: renderTrailhead,
  sign: renderSign,
  minimal: renderMinimal,
  share: renderShare,
}

export function renderSticker({ dest, label, slug, template }) {
  const fn = TEMPLATE_FNS[template] || TEMPLATE_FNS[DEFAULT_TEMPLATE]
  return fn({ dest, label: label || '', slug })
}

// ── Templates ──────────────────────────────────────────────────────────────

function renderTrailhead({ dest, label, slug }) {
  const qrSize = 80
  const qrOriginX = 10
  const qrOriginY = 10
  const cardPad = 4
  const path = renderQrAt(dest, qrOriginX, qrOriginY, qrSize)
  return baseSvg({
    bg: PALETTE.forest,
    body: `
      <rect x="${qrOriginX - cardPad}" y="${qrOriginY - cardPad}"
            width="${qrSize + cardPad * 2}" height="${qrSize + cardPad * 2}"
            rx="2" fill="${PALETTE.cream}"/>
      <path d="${path}" fill="${PALETTE.forestDeep}"/>
      <g fill="${PALETTE.cream}" font-family="Playfair Display, Georgia, serif">
        <text x="105" y="32" font-size="16" font-weight="700">Ternpike</text>
        <text x="105" y="50" font-size="7" font-style="italic" fill="${PALETTE.cream}" opacity="0.85">
          Track every turn of the road.
        </text>
        <text x="105" y="74" font-size="6" font-family="DM Mono, ui-monospace, monospace"
              opacity="0.7">ternpike.com</text>
        <text x="105" y="84" font-size="4" font-family="DM Mono, ui-monospace, monospace"
              opacity="0.5">${escapeXml(slug)}</text>
      </g>
      ${labelStrip(label, PALETTE.cream, 0.6)}
    `,
  })
}

function renderSign({ dest, label, slug }) {
  const qrSize = 80
  const qrOriginX = 10
  const qrOriginY = 10
  const path = renderQrAt(dest, qrOriginX, qrOriginY, qrSize)
  return baseSvg({
    bg: PALETTE.parchment,
    body: `
      <rect x="2" y="2" width="196" height="96" rx="3" fill="none"
            stroke="${PALETTE.rust}" stroke-width="1.2"/>
      <path d="${path}" fill="${PALETTE.forest}"/>
      <g fill="${PALETTE.forest}" font-family="Playfair Display, Georgia, serif">
        <text x="105" y="34" font-size="15" font-weight="700">Ternpike</text>
        <line x1="105" y1="40" x2="155" y2="40" stroke="${PALETTE.rust}" stroke-width="1"/>
        <text x="105" y="56" font-size="7" font-style="italic">
          Scan receipts.
        </text>
        <text x="105" y="65" font-size="7" font-style="italic">
          See your trip.
        </text>
        <text x="105" y="80" font-size="6" font-family="DM Mono, ui-monospace, monospace"
              fill="${PALETTE.rust}">ternpike.com</text>
        <text x="105" y="89" font-size="4" font-family="DM Mono, ui-monospace, monospace"
              fill="${PALETTE.muted}">${escapeXml(slug)}</text>
      </g>
      ${labelStrip(label, PALETTE.forest, 0.45)}
    `,
  })
}

// Full-bleed 4:6 portrait — matches a standard 4x6 shipping label so the
// QR fills the whole sticker when printed on a Munbyn / Rollo / Dymo /
// etc, and matches the modal's `<img>` aspect ratio for an honest preview.
// QR card is centered horizontally, brand stack below.
function renderShare({ dest, slug }) {
  const qrSize = 280
  const qrX = 20
  const qrY = 28
  const cardPad = 8
  const path = renderQrAt(dest, qrX, qrY, qrSize)
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 480" shape-rendering="crispEdges">
  <rect width="320" height="480" fill="${PALETTE.forest}"/>
  <rect x="${qrX - cardPad}" y="${qrY - cardPad}"
        width="${qrSize + cardPad * 2}" height="${qrSize + cardPad * 2}"
        rx="10" fill="${PALETTE.cream}"/>
  <path d="${path}" fill="${PALETTE.forestDeep}"/>
  <g fill="${PALETTE.cream}" font-family="Playfair Display, Georgia, serif" text-anchor="middle">
    <text x="160" y="370" font-size="38" font-weight="700">Ternpike</text>
    <text x="160" y="400" font-size="16" font-style="italic" opacity="0.85">Track every turn of the road.</text>
  </g>
  <g fill="${PALETTE.cream}" font-family="DM Mono, ui-monospace, monospace" text-anchor="middle">
    <text x="160" y="436" font-size="14" opacity="0.7">ternpike.com</text>
    <text x="160" y="460" font-size="11" opacity="0.5">${escapeXml(slug)}</text>
  </g>
</svg>`
}

function renderMinimal({ dest, label, slug }) {
  const qrSize = 80
  const qrOriginX = 10
  const qrOriginY = 10
  const path = renderQrAt(dest, qrOriginX, qrOriginY, qrSize)
  return baseSvg({
    bg: '#ffffff',
    body: `
      <path d="${path}" fill="#000000"/>
      <g fill="#1a1a1a" font-family="Helvetica, Arial, sans-serif">
        <text x="105" y="40" font-size="13" font-weight="700">Ternpike</text>
        <text x="105" y="56" font-size="6" font-family="ui-monospace, Menlo, monospace">
          ternpike.com
        </text>
        <text x="105" y="68" font-size="4" font-family="ui-monospace, Menlo, monospace"
              fill="#666666">${escapeXml(slug)}</text>
      </g>
      ${labelStrip(label, '#666666', 0.5)}
    `,
  })
}

// ── Helpers ────────────────────────────────────────────────────────────────

// Encode once; module count is content-length-dependent, so size/n gives
// the cell size that fits `size` exactly. Error correction Q (~25% recovery)
// leaves headroom for sticker grime without blowing up module count.
// Path coordinates are rounded to 2 decimals — QR scanners and SVG
// rasterizers don't need 16-digit precision, and the rounding cuts SVG
// size by ~70% (from ~50KB to ~15KB for a typical URL).
function renderQrAt(text, x, y, size) {
  const qr = qrcode(0, 'Q')
  qr.addData(text)
  qr.make()
  const n = qr.getModuleCount()
  const cellSize = size / n
  const cs = round2(cellSize)
  const parts = []
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (qr.isDark(r, c)) {
        const px = round2(x + c * cellSize)
        const py = round2(y + r * cellSize)
        parts.push(`M${px} ${py}h${cs}v${cs}h-${cs}z`)
      }
    }
  }
  return parts.join('')
}

const round2 = (n) => Math.round(n * 100) / 100

// Optional human-readable label across the bottom, under the brand chrome.
// Skipped when label is empty so single-purpose stickers stay clean.
function labelStrip(label, fill, opacity) {
  if (!label) return ''
  return `
    <text x="105" y="96" font-size="3.5" font-family="DM Mono, ui-monospace, monospace"
          fill="${fill}" opacity="${opacity}">${escapeXml(label)}</text>
  `
}

// No `width`/`height` attrs — the SVG scales to whatever physical size
// the consumer (printable HTML, an `<img>` in the share modal, etc.) sets
// via CSS. viewBox + the default preserveAspectRatio="xMidYMid meet"
// keeps the aspect locked, letterboxing inside non-matching containers.
function baseSvg({ bg, body }) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100" shape-rendering="crispEdges">
  <rect width="200" height="100" fill="${bg}"/>
  ${body}
</svg>`
}
