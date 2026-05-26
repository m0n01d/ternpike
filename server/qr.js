// QR-sticker redirect + counter + sticker generator.
//
// Sticker URLs are `https://ternpike.com/qr/<slug>` — short enough to print
// on a Munbyn label, dense scan-from-distance QR. Each request bumps a KV
// counter for the slug, rolls up the Cloudflare-edge country/region/city of
// the scanner, and 302s to the marketing site with a `?ref=qr-<slug>` tag
// for any downstream analytics.
//
// KV is eventually consistent across colos, so a simultaneous burst of scans
// from two regions can lose a count or two. That's fine for "did anyone
// scan" — we want order-of-magnitude, not audit-grade.
//
// Slugs are normalized to `[a-z0-9-]{1,32}`; anything else still redirects
// but isn't counted (no KV pollution from misreads or fat-fingered URLs).
//
// Sticker SVGs are public — knowing a slug doesn't reveal anything the QR
// itself doesn't already encode, and making generation public means the user
// can open a print URL on any device without juggling the admin secret.
// /admin/qr (counts read) remains gated.

import {
  DEFAULT_TEMPLATE,
  TEMPLATES,
  isValidTemplate,
  renderSticker,
} from './qrSvg.js'
import { renderStickerPdf } from './qrPdf.js'

const SLUG_RE = /^[a-z0-9-]{1,32}$/
const PUBLIC_BASE = 'https://ternpike.com'
const DEFAULT_DEST = `${PUBLIC_BASE}/`
const MAX_PRINT_SLUGS = 50

const nowIso = () => new Date().toISOString()

const normalizeSlug = (raw) => {
  if (typeof raw !== 'string') return null
  const s = raw.toLowerCase().trim()
  return SLUG_RE.test(s) ? s : null
}

const safeParse = (s) => {
  try {
    return JSON.parse(s)
  } catch {
    return null
  }
}

const stickerUrl = (slug) => `${PUBLIC_BASE}/qr/${slug}`

// Default page size per template. The 2x1 templates are designed for small
// Munbyn / Dymo label stock; the share template fills a 4x6 shipping label
// (its 4:5 viewBox letterboxes inside 4:6 with a thin white margin).
// Override with `?size=<W>x<H>` where W/H are inches.
const SIZE_FOR_TEMPLATE = {
  trailhead: { w: 2, h: 1 },
  sign: { w: 2, h: 1 },
  minimal: { w: 2, h: 1 },
  share: { w: 4, h: 6 },
}

const SIZE_RE = /^(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)$/

const pickSize = (raw, template) => {
  if (typeof raw === 'string') {
    const m = SIZE_RE.exec(raw.toLowerCase().trim())
    if (m) {
      const w = parseFloat(m[1])
      const h = parseFloat(m[2])
      if (w > 0 && h > 0 && w <= 20 && h <= 20) {
        return { w, h }
      }
    }
  }
  return SIZE_FOR_TEMPLATE[template] || SIZE_FOR_TEMPLATE.trailhead
}

const bumpCounter = async (kv, slug, loc) => {
  const raw = await kv.get(slug)
  const prev = raw ? safeParse(raw) : null
  const now = nowIso()
  const byCountry = { ...(prev?.byCountry || {}) }
  const byRegion = { ...(prev?.byRegion || {}) }
  const byCity = { ...(prev?.byCity || {}) }
  if (loc.country) {
    byCountry[loc.country] = (byCountry[loc.country] || 0) + 1
  }
  if (loc.country && loc.region) {
    const key = `${loc.country}-${loc.region}`
    byRegion[key] = (byRegion[key] || 0) + 1
  }
  if (loc.city) {
    byCity[loc.city] = (byCity[loc.city] || 0) + 1
  }
  const next = {
    count: (prev?.count ?? 0) + 1,
    firstAt: prev?.firstAt ?? now,
    lastAt: now,
    byCountry,
    byRegion,
    byCity,
  }
  await kv.put(slug, JSON.stringify(next))
}

const constantTimeEqual = (a, b) => {
  let acc = 0
  const len = Math.min(a.length, b.length)
  for (let i = 0; i < len; i++) {
    acc |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return acc === 0 && a.length === b.length
}

// Cloudflare populates request.cf with edge geo data; absent on local
// `wrangler dev` without the --cf flag, hence the null-guarded reads.
const readLocation = (c) => {
  const cf = c.req.raw?.cf
  if (!cf) return { country: null, region: null, city: null }
  return {
    country: typeof cf.country === 'string' ? cf.country : null,
    region: typeof cf.regionCode === 'string' ? cf.regionCode : null,
    city: typeof cf.city === 'string' ? cf.city : null,
  }
}

const pickTemplate = (raw) =>
  isValidTemplate(raw) ? raw : DEFAULT_TEMPLATE

const stickerForSlug = (slug, template, label) =>
  renderSticker({
    dest: stickerUrl(slug),
    label,
    slug,
    template,
  })

export function registerQrRoutes(app) {
  // Register deeper / literal routes BEFORE the bare `/qr/:slug` redirect
  // so `/qr/print` and `/qr/<slug>/sticker.svg` don't get swallowed by it.

  // --- printable HTML (one or many slugs, one per page) -------------------

  app.get('/qr/print', (c) => {
    const slugsParam = c.req.query('slugs') || c.req.query('slug') || ''
    const slugs = slugsParam
      .split(',')
      .map(normalizeSlug)
      .filter(Boolean)
      .slice(0, MAX_PRINT_SLUGS)
    if (slugs.length === 0) {
      return c.text('no valid slugs (use ?slugs=a,b,c)', 400)
    }
    const template = pickTemplate(c.req.query('template'))
    const size = pickSize(c.req.query('size'), template)
    const label = c.req.query('label') || ''
    const stickers = slugs
      .map((slug) => {
        const svg = stickerForSlug(slug, template, label)
        return `<div class="sticker">${stripXmlDecl(svg)}</div>`
      })
      .join('\n')
    const html = printPage({ count: slugs.length, size, stickers, template })
    return new Response(html, {
      headers: {
        'Cache-Control': 'no-store',
        'Content-Type': 'text/html; charset=utf-8',
      },
    })
  })

  // --- sticker SVG (one slug, raw image) ----------------------------------

  app.get('/qr/:slug/sticker.svg', (c) => {
    const slug = normalizeSlug(c.req.param('slug'))
    if (!slug) {
      return c.text('invalid slug', 400)
    }
    const template = pickTemplate(c.req.query('template'))
    const label = c.req.query('label') || ''
    const svg = stickerForSlug(slug, template, label)
    return new Response(svg, {
      headers: {
        'Cache-Control': 'public, max-age=3600',
        'Content-Type': 'image/svg+xml; charset=utf-8',
      },
    })
  })

  // --- sticker PDF (one slug, 4x6 vector, label-printer ready) ------------
  //
  // Bypasses the browser print stack so iOS Safari "Save to PDF" doesn't
  // letterbox the sticker onto a Letter page. Currently the share template
  // at exactly 4x6 inches; size/template knobs are future work.

  app.get('/qr/:slug/sticker.pdf', async (c) => {
    const slug = normalizeSlug(c.req.param('slug'))
    if (!slug) {
      return c.text('invalid slug', 400)
    }
    const dest = stickerUrl(slug)
    const bytes = await renderStickerPdf({ dest, slug })
    return new Response(bytes, {
      headers: {
        'Cache-Control': 'public, max-age=3600',
        'Content-Disposition': `inline; filename="ternpike-${slug}.pdf"`,
        'Content-Type': 'application/pdf',
      },
    })
  })

  // --- scan redirect (the actual QR target) -------------------------------

  app.get('/qr/:slug', (c) => {
    const slug = normalizeSlug(c.req.param('slug'))
    const target = slug
      ? `${DEFAULT_DEST}?ref=qr-${slug}`
      : DEFAULT_DEST
    if (slug && c.env.QR_KV) {
      const loc = readLocation(c)
      c.executionCtx.waitUntil(bumpCounter(c.env.QR_KV, slug, loc))
    }
    return c.redirect(target, 302)
  })

  // --- admin: list slugs with counts + region rollup ----------------------

  app.get('/admin/qr', async (c) => {
    if (!c.env.ADMIN_SECRET) {
      return c.json({ error: 'admin_not_configured', ok: false }, 503)
    }
    const provided = c.req.header('x-admin-secret')
    if (!provided || !constantTimeEqual(provided, c.env.ADMIN_SECRET)) {
      return c.json({ error: 'unauthorized', ok: false }, 401)
    }
    if (!c.env.QR_KV) {
      return c.json({ ok: true, slugs: [] })
    }
    const slugs = []
    let cursor
    do {
      const page = await c.env.QR_KV.list({ cursor })
      for (const key of page.keys) {
        const raw = await c.env.QR_KV.get(key.name)
        const data = raw ? safeParse(raw) : null
        slugs.push({
          byCity: data?.byCity || {},
          byCountry: data?.byCountry || {},
          byRegion: data?.byRegion || {},
          count: data?.count ?? 0,
          firstAt: data?.firstAt ?? null,
          lastAt: data?.lastAt ?? null,
          slug: key.name,
        })
      }
      cursor = page.list_complete ? undefined : page.cursor
    } while (cursor)
    slugs.sort((a, b) => b.count - a.count)
    return c.json({ ok: true, slugs, templates: TEMPLATES })
  })
}

// ── HTML print page ─────────────────────────────────────────────────────────

// One sticker per page at exactly the requested `size` so browser print →
// AirPrint hands the printer a label-shaped page. `@page` size is honored
// by Chrome, Safari, and Firefox. The screen-rendered scale matches the
// physical dimensions for an honest preview.
//
// The sticker box scales the SVG to fill its width and height; the SVG's
// own viewBox + default preserveAspectRatio letterboxes inside that box
// when aspect ratios differ (e.g. share's 4:5 inside a 4:6 label leaves a
// thin white margin top/bottom). The .sticker background is white so the
// letterbox blends into the label.
function printPage({ count, size, stickers, template }) {
  const { w, h } = size
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Ternpike QR stickers (${count})</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Playfair+Display:ital,wght@0,700;1,400&display=swap" rel="stylesheet">
<style>
  @page { size: ${w}in ${h}in; margin: 0; }
  html, body { margin: 0; padding: 0; background: #2d3a22; font-family: -apple-system, system-ui, sans-serif; }
  .toolbar {
    color: #f2ede3; padding: 16px 20px; display: flex; gap: 12px; align-items: center;
    font-size: 14px; position: sticky; top: 0; background: #2d3a22; border-bottom: 1px solid #4a5e3a;
  }
  .toolbar button {
    background: #b85c38; color: #f2ede3; border: 0; border-radius: 6px;
    padding: 8px 14px; font: inherit; font-weight: 600; cursor: pointer;
  }
  .toolbar button:hover { background: #cc7050; }
  .sheet { padding: 24px; display: flex; flex-direction: column; gap: 16px; align-items: center; }
  /* Background matches the share/trailhead forest so any letterboxing
     from an aspect-mismatched template blends rather than showing as
     white bands. Pure-white templates (minimal) override it themselves. */
  .sticker {
    width: ${w}in; height: ${h}in; background: #2d3a22;
    box-shadow: 0 4px 16px rgb(0 0 0 / 0.3); overflow: hidden;
  }
  .sticker svg { display: block; width: 100%; height: 100%; }
  @media print {
    .toolbar { display: none; }
    .sheet { padding: 0; gap: 0; }
    .sticker { box-shadow: none; page-break-after: always; }
    .sticker:last-child { page-break-after: auto; }
    html, body { background: white; }
  }
</style>
</head>
<body>
  <div class="toolbar">
    <strong>${count} sticker${count === 1 ? '' : 's'}</strong>
    <span>${template} · ${w}×${h}in</span>
    <span style="flex:1"></span>
    <button onclick="window.print()">Print</button>
  </div>
  <div class="sheet">
    ${stickers}
  </div>
</body>
</html>`
}

function stripXmlDecl(svg) {
  return svg.replace(/^<\?xml[^?]*\?>\s*/, '')
}
