// Server-rendered 4x6 sticker PDF — pure black-and-white for thermal label
// printers (Munbyn RW403B et al). No background fill (the label IS white)
// and no cream QR card (the white margin around the QR is its quiet zone).
//
// Three sizes via `?size=large|medium|small`:
//   - large  → 1 full-label sticker (4×6) with tern + tagline + URL + slug
//   - medium → 2×3 grid of 6 stickers (~1.8" each) with tern + Ternpike wordmark
//   - small  → 3×4 grid of 12 stickers (~1.2" each) with QR + ternpike.com only
//
// Why this exists: iOS Safari's "Save to PDF" / "Print to PDF" silently
// ignores `@page size: 4in 6in` and renders the print page to whatever
// the system paper default is (US Letter). The Worker generates the PDF
// at exactly 4x6 inches using pdf-lib, so iOS / AirPrint / the Munbyn app
// all get a correctly-sized vector asset with no resizing.
//
// Fonts: Helvetica-Bold / Helvetica-Oblique / Courier are part of the PDF
// base-14 font set — every PDF viewer ships them, no embedding needed.

import { PDFDocument, StandardFonts, rgb } from 'pdf-lib'
import qrcode from 'qrcode-generator'

const BLACK = rgb(0, 0, 0)
const WHITE = rgb(1, 1, 1)

// 4x6 inches at 72pt/inch.
const PAGE_W = 288
const PAGE_H = 432

// Grid configuration per size. Gaps are between cells AND on outer
// margins, so cellW = (PAGE_W - (cols+1)*gap) / cols.
const LAYOUTS = {
  large: { cols: 1, rows: 1, gap: 0, render: renderCellLarge },
  medium: { cols: 2, rows: 3, gap: 10, render: renderCellMedium },
  small: { cols: 3, rows: 4, gap: 8, render: renderCellSmall },
}

export const SIZES = Object.keys(LAYOUTS)
export const DEFAULT_SIZE = 'large'

export async function renderStickerPdf({ dest, lat, lon, size = DEFAULT_SIZE, slug }) {
  const layout = LAYOUTS[size] || LAYOUTS[DEFAULT_SIZE]
  const pdfDoc = await PDFDocument.create()
  pdfDoc.setTitle(`Ternpike sticker · ${slug} · ${size}`)
  pdfDoc.setCreator('Ternpike')

  const page = pdfDoc.addPage([PAGE_W, PAGE_H])
  const fonts = {
    bold: await pdfDoc.embedFont(StandardFonts.HelveticaBold),
    italic: await pdfDoc.embedFont(StandardFonts.HelveticaOblique),
    mono: await pdfDoc.embedFont(StandardFonts.Courier),
  }

  // Encode the QR once and reuse the module matrix for every cell — same
  // slug → same QR.
  const qr = encodeQr(dest)

  // Coords are "where the print request came from" — stamped on every
  // sticker in the batch. Skipped when cf didn't provide lat/lon (local
  // dev without --remote).
  const coords = formatCoords(lat, lon)

  for (const box of layoutCells(layout)) {
    layout.render(page, { ...box, coords, dest, fonts, qr, slug })
  }

  return await pdfDoc.save()
}

// "44.052, -123.087" — three decimals matches cf's IP-based precision
// (~110m). Signed numbers so southern/western hemispheres read correctly
// without N/S/E/W tags eating space.
function formatCoords(lat, lon) {
  if (lat == null || lon == null) return null
  return `${lat.toFixed(3)}, ${lon.toFixed(3)}`
}

function layoutCells({ cols, gap, rows }) {
  const cellW = (PAGE_W - (cols + 1) * gap) / cols
  const cellH = (PAGE_H - (rows + 1) * gap) / rows
  const boxes = []
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      // PDF y is bottom-up; row 0 (visually top) is the highest y. The
      // y returned is the cell's bottom-left corner.
      const x = gap + c * (cellW + gap)
      const y = PAGE_H - gap - (r + 1) * cellH - r * gap
      boxes.push({ h: cellH, w: cellW, x, y })
    }
  }
  return boxes
}

// ── Cell renderers ─────────────────────────────────────────────────────────
//
// Each renderer receives a cell box (x, y, w, h in PDF coords, where x/y is
// the cell's bottom-left) plus the QR matrix, slug, dest, and font set. The
// design is laid out in cell-local top-down coords via the `localY` helper,
// which flips to PDF y for each draw call.

// Large: the original 4x6 single-sticker design — QR, tern mascot, Ternpike
// wordmark, italic tagline, URL, slug, edge-geo coords.
function renderCellLarge(page, { coords, dest, fonts, h, qr, slug, w, x, y }) {
  const cx = x + w / 2
  const top = y + h
  const localY = (td) => top - td
  // Scale factor maps the original 320×480 share-template viewBox into
  // whatever the actual cell is (typically PAGE_W × PAGE_H for `large`).
  const s = w / 320

  drawQrAt(page, { x: x + 40 * s, y: localY((28 + 240) * s), size: 240 * s, qr })
  drawTern(page, { centerX: cx, centerY: localY(305 * s), width: 80 * s })

  drawCenteredText(page, 'Ternpike', { font: fonts.bold, size: 38 * s, cx, baselineY: localY(355 * s) })
  drawCenteredText(page, 'Track every turn of the road.', { font: fonts.italic, size: 16 * s, cx, baselineY: localY(388 * s) })
  drawCenteredText(page, 'ternpike.com', { font: fonts.mono, size: 14 * s, cx, baselineY: localY(425 * s) })
  drawCenteredText(page, slug, { font: fonts.mono, size: 10 * s, cx, baselineY: localY(447 * s) })
  if (coords) {
    drawCenteredText(page, coords, { font: fonts.mono, size: 8 * s, cx, baselineY: localY(465 * s) })
  }
}

// Medium: QR fills most of the cell, small tern below, "Ternpike" wordmark
// then coords at the bottom. URL omitted — the QR is the URL.
function renderCellMedium(page, { coords, fonts, h, qr, w, x, y }) {
  const cx = x + w / 2
  const top = y + h
  const localY = (td) => top - td

  // Reserve bottom strip for tern + wordmark + coords.
  const bottomStrip = coords ? 36 : 26
  const qrSize = Math.min(w - 8, h - 4 - bottomStrip)
  drawQrAt(page, { x: cx - qrSize / 2, y: localY(4 + qrSize), size: qrSize, qr })

  drawTern(page, { centerX: cx, centerY: localY(4 + qrSize + 7), width: 24 })

  // Wordmark sits below tern; coords (if present) sit below wordmark.
  const wordBaseline = coords ? h - 13 : h - 4
  drawCenteredText(page, 'Ternpike', {
    font: fonts.bold, size: 10,
    cx, baselineY: localY(wordBaseline),
  })
  if (coords) {
    drawCenteredText(page, coords, {
      font: fonts.mono, size: 5,
      cx, baselineY: localY(h - 4),
    })
  }
}

// Small: QR + tern + lat/lon coords. Wordmark omitted (no room for legible
// "Ternpike" type) and "ternpike.com" URL too (encoded in the QR anyway —
// coords are the more interesting stamp here).
function renderCellSmall(page, { coords, fonts, h, qr, w, x, y }) {
  const cx = x + w / 2
  const top = y + h
  const localY = (td) => top - td

  // Reserve bottom strip for tern + coords text. When coords are absent
  // (local dev with no cf), fall back to "ternpike.com" so the cell isn't
  // missing its caption.
  const bottomStrip = 20
  const qrTop = 3
  const qrSize = Math.min(w - 4, h - qrTop - bottomStrip)
  drawQrAt(page, { x: cx - qrSize / 2, y: localY(qrTop + qrSize), size: qrSize, qr })

  drawTern(page, {
    centerX: cx,
    centerY: localY(qrTop + qrSize + 5),
    width: 14,
  })

  drawCenteredText(page, coords || 'ternpike.com', {
    font: fonts.mono, size: coords ? 4.5 : 5,
    cx, baselineY: localY(h - 3),
  })
}

// ── Drawing helpers ────────────────────────────────────────────────────────

// Draw the QR matrix as black squares anchored at (x, y) = bottom-left of
// the QR, with overall size × size pt. QR rows render top-down within that
// bounding box.
function drawQrAt(page, { qr, size, x, y }) {
  const { modules, size: n } = qr
  const cell = size / n
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (modules[r][c]) {
        page.drawRectangle({
          x: round2(x + c * cell),
          y: round2(y + size - (r + 1) * cell),
          width: round2(cell),
          height: round2(cell),
          color: BLACK,
        })
      }
    }
  }
}

function drawCenteredText(page, text, { baselineY, cx, font, size }) {
  const tw = font.widthOfTextAtSize(text, size)
  page.drawText(text, {
    x: cx - tw / 2,
    y: baselineY,
    font,
    size,
    color: BLACK,
  })
}

// Tern mascot mirroring public/favicon.svg, all-black silhouette with a
// white eye dot. The favicon's wing/body/head shapes are defined in a
// local 120×~30 coord box; we draw at the requested PDF size by scaling.
// pdf-lib's drawSvgPath flips Y internally (negative-Y scale matrix), so
// the (x, y) it takes are the PDF coords where the local SVG (0, 0)
// lands; positive local Y goes down on the page from there.
function drawTern(page, { centerX, centerY, width }) {
  const ts = width / 120
  const xOff = centerX - 60 * ts
  const yOff = centerY + 35 * ts // tern's local vertical center is ~35
  const localToPdf = (lx, ly) => ({
    x: xOff + lx * ts,
    y: yOff - ly * ts,
  })

  page.drawSvgPath('M60 40 C40 26, 8 20, 0 29 C16 28, 38 34, 60 44Z', {
    x: xOff, y: yOff, scale: ts, color: BLACK,
  })
  page.drawSvgPath('M60 40 C80 26, 112 20, 120 29 C104 28, 82 34, 60 44Z', {
    x: xOff, y: yOff, scale: ts, color: BLACK,
  })

  const body = localToPdf(60, 43)
  page.drawEllipse({
    x: body.x, y: body.y, xScale: 20 * ts, yScale: 7 * ts, color: BLACK,
  })
  const head = localToPdf(76, 40)
  page.drawEllipse({
    x: head.x, y: head.y, xScale: 9 * ts, yScale: 7 * ts, color: BLACK,
  })

  page.drawSvgPath('M84 40 L96 38.5 L84 42Z', {
    x: xOff, y: yOff, scale: ts, color: BLACK,
  })

  // The white eye is the only highlight on the otherwise-uniform black
  // silhouette — without it the tern reads as an undifferentiated blob.
  // Skipped at very small tern widths where it'd be sub-pixel.
  if (width >= 18) {
    const eye = localToPdf(79, 38.5)
    page.drawCircle({ x: eye.x, y: eye.y, size: 1.6 * ts, color: WHITE })
  }
}

function encodeQr(text) {
  const qr = qrcode(0, 'Q')
  qr.addData(text)
  qr.make()
  const n = qr.getModuleCount()
  const modules = []
  for (let r = 0; r < n; r++) {
    const row = []
    for (let c = 0; c < n; c++) {
      row.push(qr.isDark(r, c))
    }
    modules.push(row)
  }
  return { modules, size: n }
}

const round2 = (n) => Math.round(n * 100) / 100
