// Server-rendered 4x6 sticker PDF — pure black-and-white for thermal label
// printers (Munbyn RW403B et al). No background fill (the label IS white)
// and no cream QR card (the white margin around the QR is its quiet zone).
// Includes a small tern mascot above the wordmark.
//
// Why this exists: iOS Safari's "Save to PDF" / "Print to PDF" silently
// ignores `@page size: 4in 6in` and renders the print page to whatever
// the system paper default is (US Letter). The Worker generates the PDF
// at exactly 4x6 inches using pdf-lib, so iOS / AirPrint / the Munbyn app
// all get a correctly-sized vector asset with no resizing.
//
// Fonts: Helvetica-Bold / Helvetica-Oblique / Courier are part of the PDF
// base-14 font set — every PDF viewer ships them, no embedding needed.
// Playfair (the brand display font) would add ~50KB of font binary and
// isn't worth it on a small label.

import { PDFDocument, StandardFonts, rgb } from 'pdf-lib'
import qrcode from 'qrcode-generator'

const BLACK = rgb(0, 0, 0)
const WHITE = rgb(1, 1, 1)

// 4x6 inches at 72pt/inch. Matches the `share` template's 320x480
// viewBox at a 0.9pt-per-viewBox-unit scale, so layout coords below
// can be reasoned about in viewBox space and converted at draw time.
const PAGE_W = 288
const PAGE_H = 432
const SVG_W = 320
const S = PAGE_W / SVG_W // 0.9

const scale = (v) => v * S
const svgYToPdf = (svgY, h = 0) => PAGE_H - (svgY + h) * S

export async function renderStickerPdf({ dest, slug }) {
  const pdfDoc = await PDFDocument.create()
  pdfDoc.setTitle(`Ternpike sticker · ${slug}`)
  pdfDoc.setCreator('Ternpike')

  const page = pdfDoc.addPage([PAGE_W, PAGE_H])
  const bold = await pdfDoc.embedFont(StandardFonts.HelveticaBold)
  const italic = await pdfDoc.embedFont(StandardFonts.HelveticaOblique)
  const mono = await pdfDoc.embedFont(StandardFonts.Courier)

  // White background isn't explicitly drawn — PDF pages default to white,
  // and on a thermal printer "white" is the unburned label substrate, so
  // not painting a fill saves ink/heat across the whole sheet.

  // QR modules. SVG-space: (40, 28), 240×240. Each module ~7.3pt at the
  // typical 33-module count.
  const qrX = 40
  const qrY = 28
  const qrSize = 240
  const { modules, size: n } = encodeQr(dest)
  const cell = qrSize / n
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (modules[r][c]) {
        page.drawRectangle({
          x: scale(qrX + c * cell),
          y: svgYToPdf(qrY + r * cell, cell),
          width: scale(cell),
          height: scale(cell),
          color: BLACK,
        })
      }
    }
  }

  // Tern mascot centered between QR and wordmark.
  drawTern(page, { centerX: scale(160), centerY: svgYToPdf(305), width: scale(80) })

  // Brand stack.
  drawCentered(page, 'Ternpike', bold, 38, 355, BLACK)
  drawCentered(page, 'Track every turn of the road.', italic, 16, 388, BLACK)
  drawCentered(page, 'ternpike.com', mono, 14, 430, BLACK)
  drawCentered(page, slug, mono, 11, 458, BLACK)

  return await pdfDoc.save()
}

function drawCentered(page, text, font, sizeViewBox, svgBaselineY, color) {
  const size = scale(sizeViewBox)
  const w = font.widthOfTextAtSize(text, size)
  page.drawText(text, {
    x: scale(SVG_W / 2) - w / 2,
    y: PAGE_H - scale(svgBaselineY),
    font,
    size,
    color,
  })
}

// Tern mascot mirroring public/favicon.svg, all-black silhouette with a
// white eye dot. The favicon's wing/body/head shapes are defined in a
// local 120×~30 coord box; we draw at the requested PDF size by scaling.
// pdf-lib's drawSvgPath flips Y internally (negative-Y scale matrix), so
// the (x, y) it takes are the PDF coords where the local SVG (0, 0)
// lands; positive local Y goes down on the page from there.
function drawTern(page, { centerX, centerY, width }) {
  const ternScale = width / 120
  const xOff = centerX - 60 * ternScale
  const yOff = centerY + 35 * ternScale // tern's local vertical center is ~35
  const localToPdf = (lx, ly) => ({
    x: xOff + lx * ternScale,
    y: yOff - ly * ternScale,
  })

  // Wings (mirrored cubic-bezier sweeps).
  page.drawSvgPath('M60 40 C40 26, 8 20, 0 29 C16 28, 38 34, 60 44Z', {
    x: xOff, y: yOff, scale: ternScale, color: BLACK,
  })
  page.drawSvgPath('M60 40 C80 26, 112 20, 120 29 C104 28, 82 34, 60 44Z', {
    x: xOff, y: yOff, scale: ternScale, color: BLACK,
  })

  // Body + head (same fill in B&W — they merge into a single silhouette).
  const body = localToPdf(60, 43)
  page.drawEllipse({
    x: body.x, y: body.y, xScale: 20 * ternScale, yScale: 7 * ternScale, color: BLACK,
  })
  const head = localToPdf(76, 40)
  page.drawEllipse({
    x: head.x, y: head.y, xScale: 9 * ternScale, yScale: 7 * ternScale, color: BLACK,
  })

  // Beak.
  page.drawSvgPath('M84 40 L96 38.5 L84 42Z', {
    x: xOff, y: yOff, scale: ternScale, color: BLACK,
  })

  // Eye — small white dot on the black head, the only highlight in the
  // silhouette. Without it the tern reads as an undifferentiated blob.
  const eye = localToPdf(79, 38.5)
  page.drawCircle({ x: eye.x, y: eye.y, size: 1.6 * ternScale, color: WHITE })
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
