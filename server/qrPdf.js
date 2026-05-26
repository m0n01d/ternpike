// Server-rendered 4x6 sticker PDF.
//
// Why this exists: iOS Safari's "Save to PDF" / "Print to PDF" silently
// ignores `@page size: 4in 6in` and renders the print page to whatever
// the system paper default is (US Letter). Users hitting that path end
// up with a tiny 4x6 island in the middle of an 8.5x11 sheet, useless
// on a 4x6 label printer like the Munbyn RW403B.
//
// This module side-steps the browser print stack entirely: the Worker
// generates the PDF at exactly 4x6 inches using pdf-lib, and the iOS
// PDF viewer (or AirPrint, or the Munbyn iOS app, or any other consumer)
// gets a correctly-sized vector asset with no resizing or aspect drift.
//
// Mirrors the visual design of the `share` SVG template — forest bg,
// cream QR card, Helvetica wordmark below (Playfair isn't a PDF
// standard font and embedding ~50KB of font binary isn't worth it for
// a label).

import { PDFDocument, StandardFonts, rgb } from 'pdf-lib'
import qrcode from 'qrcode-generator'

const PALETTE = {
  forest: rgb(45 / 255, 58 / 255, 34 / 255),
  forestDeep: rgb(26 / 255, 36 / 255, 18 / 255),
  cream: rgb(242 / 255, 237 / 255, 227 / 255),
}

// 4x6 inches at 72pt/inch. Matches the `share` template's 320x480
// viewBox at a 0.9pt-per-viewBox-unit scale.
const PAGE_W = 288
const PAGE_H = 432
const SVG_W = 320
const SVG_H = 480
const S = PAGE_W / SVG_W // 0.9

const scale = (v) => v * S

// SVG positions an element by its top-left and grows down. pdf-lib
// positions by bottom-left and grows up. svgYToPdf converts the SVG
// top-edge y of an element of height `h` into the PDF y of its bottom.
const svgYToPdf = (svgY, h = 0) => PAGE_H - (svgY + h) * S

export async function renderStickerPdf({ dest, slug }) {
  const pdfDoc = await PDFDocument.create()
  pdfDoc.setTitle(`Ternpike sticker · ${slug}`)
  pdfDoc.setCreator('Ternpike')

  const page = pdfDoc.addPage([PAGE_W, PAGE_H])
  const bold = await pdfDoc.embedFont(StandardFonts.HelveticaBold)
  const italic = await pdfDoc.embedFont(StandardFonts.HelveticaOblique)
  const mono = await pdfDoc.embedFont(StandardFonts.Courier)

  // Forest background — full bleed.
  page.drawRectangle({
    x: 0,
    y: 0,
    width: PAGE_W,
    height: PAGE_H,
    color: PALETTE.forest,
  })

  // Cream QR card — same coords as the `share` SVG template.
  // SVG: x=12, y=20, 296x296.
  page.drawRectangle({
    x: scale(12),
    y: svgYToPdf(20, 296),
    width: scale(296),
    height: scale(296),
    color: PALETTE.cream,
  })

  // QR modules — drawn as dark squares inside the cream card.
  const qrX = 20
  const qrY = 28
  const qrSize = 280
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
          color: PALETTE.forestDeep,
        })
      }
    }
  }

  // Brand chrome — text positions match the SVG template's baselines.
  drawCentered(page, 'Ternpike', bold, 38, 370, PALETTE.cream, 1)
  drawCentered(
    page,
    'Track every turn of the road.',
    italic,
    16,
    400,
    PALETTE.cream,
    0.85,
  )
  drawCentered(page, 'ternpike.com', mono, 14, 436, PALETTE.cream, 0.7)
  drawCentered(page, slug, mono, 11, 460, PALETTE.cream, 0.5)

  return await pdfDoc.save()
}

function drawCentered(page, text, font, sizeViewBox, svgBaselineY, color, opacity) {
  const size = scale(sizeViewBox)
  const w = font.widthOfTextAtSize(text, size)
  page.drawText(text, {
    x: scale(SVG_W / 2) - w / 2,
    y: PAGE_H - scale(svgBaselineY),
    font,
    size,
    color,
    opacity,
  })
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
