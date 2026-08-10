# Ternpike sticker kit

Nine die-cut stickers for handing out — trailhead kiosks, campground boards,
gas-pump tops, the back of a laptop at a coffee shop with wifi.

**Every sticker gets someone to the site.** All nine print `ternpike.com`;
three also carry a scannable QR. `verify.mjs` enforces both — it decodes each
QR back out of the rendered pixels and fails the build if a URL-only design
stops printing its URL.

![contact sheet](../../docs/screenshots/stickers-contact-sheet.png)

| Slug | Size | Gets you there via | What it is |
|---|---|---|---|
| `qr-trailhead` | 2 × 3in | 1.5in QR + URL | QR-first. Kiosk and bulletin boards. |
| `receipt` | 1.6 × 3.2in | 0.74in QR + URL | Die-cut receipt with a torn edge — the product as an object. |
| `orlando-juneau` | 3.2 × 1.6in | 0.84in QR + URL | The hero line, route plotted behind it. |
| `badge-tern` | 3 × 3in | URL | National-park badge. The flagship — arc-set type, tern, mile-0 line. |
| `wordmark-rust` | 3.2 × 1.1in | URL | Rust bar wordmark with the tern soaring off the end. Bumper/laptop edge. |
| `milepost-zero` | 1.4 × 3in | URL | Alaska Highway milepost. Every trip starts at mile zero. |
| `no-signal` | 2.6 × 1.2in | URL | "No signal, no problem." The offline-first pitch. |
| `cabin-or-truck` | 2.8 × 1.5in | URL | The joke sticker. The decision the app exists to inform. |
| `tern-mark` | 1.5 × 1.5in | URL | Mark plus URL, nothing else. The one you order 500 of. |

The six URL-only designs are the ones where a QR would either not scan or
would wreck the composition — `tern-mark` is 1.5in of bird, and a symbol big
enough to read would leave no bird. If you want one anyway, add
`qr: '<slug>'` to the design and a `qrCard({...})` call; `verify.mjs` will
tell you whether it survives at print size.

## What's in here

```
svg/<slug>.svg      colour, one sticker each — artwork only, no cut guides
png/<slug>.png      the same at 300 DPI, for portals that only take raster
sheets/print-sheet.svg    US Letter gang sheet, 11 stickers, dashed cut guides
thermal/<slug>.svg  black-on-white, ganged onto a 4×6 label — see below
thermal/<slug>.png  the same at 203 DPI, hard-thresholded to one bit
thermal/plan.json   per-design scale and cell geometry
sheets/contact-sheet.svg  the review image above
```

The **SVGs are the deliverable.** All type is outlined to paths, so a shop
opening the file without Playfair Display or DM Mono installed still gets the
right letterforms instead of a silent Helvetica substitution. Each file
declares its `width`/`height` in inches, so it imports at 1:1 rather than at
whatever the importer guesses.

## Printing

**Die-cut vinyl (a real print run).** Send `svg/<slug>.svg`. Every sticker's
silhouette *is* the cut line, and each carries a 0.07in parchment keyline
inside that edge — the white border you see is deliberate, and it's what gives
the cutter registration slop. Vendors that want a named spot-colour cut path
(`CutContour`) can duplicate the outermost path; it's the first element in the
file. Ask for **matte** vinyl: the palette is muted and gloss fights it.

**At home.** Print `sheets/print-sheet.svg` on 8.5 × 11 sticker paper at
**100% / actual size** — not "fit to page", which silently scales everything
down a few percent. Cut on the magenta dashed guides, then delete or ignore
the `#cut-guides` group if you'd rather cut by eye. The individual SVGs have
no guides at all.

**Minimum legible size.** The smallest type in the kit is 7pt-equivalent
(`ternpike.com` on `no-signal` and `wordmark-rust`). Don't scale any sticker
below 100% or that line closes up.

## Printing on a thermal label printer

`thermal/` is the same nine designs rendered for a direct thermal head
(Munbyn RW403B and friends): **pure black on white, one sticker design per
4 × 6 label, ganged to fill it.** Print the SVG (or the PNG) at 100%.

| Design | Scale | Per 4×6 label |
|---|---|---|
| `tern-mark` | 1.00× | 6 |
| `wordmark-rust` | 1.08× | 4 |
| `no-signal` | 1.30× | 3 |
| `milepost-zero` | 1.22× | 3 (rotated) |
| `cabin-or-truck` | 1.30× | 2 |
| `qr-trailhead` | 1.18× | 2 (rotated) |
| `badge-tern` | 1.14× | 1 |
| `receipt` | 1.50× | 1 |
| `orlando-juneau` | 1.30× | 1 (rotated) |

Three things drive that table, and none of them are stylistic:

- **Ink coverage.** A dark-field design printed as-is is a solid black slab:
  slow, smeary, and hard on the head. The mono profile turns every field
  white, so dark designs invert into line art. That's why the badge prints as
  an outlined ring rather than a filled disc.
- **No grey.** One bit per dot means a 35%-opacity hairline dithers into
  speckle. Every opacity collapses to 1, and decoration that relied on
  receding gets dropped — the route dots behind *Orlando to Juneau* cross the
  descenders at full black, so the mono profile omits them.
- **203 DPI has a legibility floor.** Counters fill in below ~7pt mono / 9pt
  Playfair Bold, and Playfair's hairline serifs vanish below ~11pt. Each
  design is scaled up until its *smallest* run clears that floor — uniformly,
  so the composition holds. That's the Scale column, and it's computed from
  the type actually drawn, not guessed.

203 DPI is the conservative assumption; a 300 DPI head prints these strictly
better. The dashed outline on each is a scissor guide — cut on it and it's
gone.

**For plain tracked QR labels, you may not want this kit at all.**
`server/qrPdf.js` already serves purpose-built 4×6 PDFs for this printer at
`https://ternpike.com/qr/<slug>/sticker.pdf?size=large|medium|small` — 1, 6,
or 12 per label, and PDF rather than SVG specifically because iOS Safari
ignores `@page size` and letterboxes onto US Letter. Use that when you want
cheap tracked labels; use `thermal/` when you want the actual designs.

## The QRs are tracked

Every QR points at `https://ternpike.com/qr/<slug>` — the existing redirect in
`server/qr.js`, not a bare link to the homepage. That route bumps a per-slug
counter in `QR_KV`, rolls up the scanner's Cloudflare edge geo, and 302s to
`ternpike.com/?ref=qr-<slug>`.

Each design has its own slug (`trailhead`, `receipt`, `route`), so
`GET /admin/qr` answers the question that justifies putting a QR on swag at
all: **which design actually gets scanned, and where.** Slugs need no
registration — an unseen slug is counted on first scan.

Change a slug in `lib/stickers.mjs` if you want per-batch attribution instead
of per-design (`ak24`, `booth-3`). Anything matching `[a-z0-9-]{1,32}` works.

This is the same machinery behind the 2 × 1in thermal labels
(`server/qrSvg.js`), which still exist and are still the right tool when you
want a cheap tracked label rather than a keepsake. Hand out both.

## Regenerating

```sh
npm i --no-save opentype.js sharp qrcode-generator jsqr
node marketing/stickers/build.mjs          # SVG + PNG + sheets
node marketing/stickers/build.mjs --no-png # vectors only, skips sharp
node marketing/stickers/verify.mjs         # decode every QR out of the PNGs
```

**Run `verify.mjs` after any layout change near a QR.** It decodes each symbol
three ways: from the colour artwork at 300 DPI, from the same downscaled to
150 px-per-inch (deliberately worse than a phone at arm's length), and from
the 1-bit thermal label. A quiet zone eaten by a nudged coordinate produces a
picture that looks like a QR and scans like a smudge; this is the only check
that catches it before the print run.

It crops to a single cell before decoding a thermal label, because a ganged
label carries several finder-pattern triples and jsQR resolves none of them.
That's a decoder limitation rather than a print defect — but the two are
indistinguishable from a pass/fail line, which is why the crop uses the real
cell geometry from `thermal/plan.json` instead of a guess.

Neither dependency is in any `package.json`. Nothing in CI runs this — the
generated files are committed, and the kit changes about as often as the logo
does. Fonts are fetched from Google Fonts on first run and cached in `.fonts/`
(gitignored); both families are SIL OFL 1.1, which permits outlining and
redistribution.

Designs live in `lib/stickers.mjs`, one object each. Coordinates are in
**1/100 inch**, so `y: 172` means "1.72 inches down" — the unit you actually
think in when deciding whether a line survives at 2 inches wide. `lib/shapes.mjs`
holds the silhouettes and the tern mark; `lib/type.mjs` does text→path.

**Designs name roles, never colours** — `p.dark`, `p.onDark`, `p.accent`. A
profile in `lib/profiles.mjs` decides what each role is worth, which is the
only reason one set of artwork can be both colour vinyl and thermal line art
without two copies drifting apart. Reaching for a hex literal in a design
means the role you want is missing; add it to both profiles instead.

Brand values come from `src/theme.css` and are mirrored in `BRAND` in
`lib/profiles.mjs`. If the palette moves, move it there too — a sticker in
last season's green is worse than no sticker.

### Two traps worth knowing about

`opentype.js@2.0.0` cannot shape Playfair Display (it throws on the font's
`ccmp` lookup), and its path serializer rounds some coordinates to `NaN` —
which drops whole letters from the render with no error at all. `lib/type.mjs`
sidesteps both by laying glyphs out directly and serializing path data itself.
Don't "simplify" it back to `font.getPath(...).toPathData()`; the first
version of this kit shipped a badge reading `TRACK EVER TRN F THE RAD`.
