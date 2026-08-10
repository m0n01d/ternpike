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
svg/<slug>.svg      one sticker each — artwork only, no cut guides
png/<slug>.png      the same at 300 DPI, for portals that only take raster
sheets/print-sheet.svg    US Letter gang sheet, 11 stickers, dashed cut guides
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
from the rendered artwork at 300 DPI and again downscaled to 150 px-per-inch —
deliberately worse than a phone at arm's length. A quiet zone eaten by a
nudged coordinate produces a picture that looks like a QR and scans like a
smudge; this is the only check that catches it before the vinyl order.

Neither dependency is in any `package.json`. Nothing in CI runs this — the
generated files are committed, and the kit changes about as often as the logo
does. Fonts are fetched from Google Fonts on first run and cached in `.fonts/`
(gitignored); both families are SIL OFL 1.1, which permits outlining and
redistribution.

Designs live in `lib/stickers.mjs`, one object each. Coordinates are in
**1/100 inch**, so `y: 172` means "1.72 inches down" — the unit you actually
think in when deciding whether a line survives at 2 inches wide. `lib/shapes.mjs`
holds the silhouettes and the tern mark; `lib/type.mjs` does text→path.

Colours come from `src/theme.css` and are mirrored in `C` at the top of
`lib/stickers.mjs`. If the brand palette moves, move it there too — a sticker
in last season's green is worse than no sticker.

### Two traps worth knowing about

`opentype.js@2.0.0` cannot shape Playfair Display (it throws on the font's
`ccmp` lookup), and its path serializer rounds some coordinates to `NaN` —
which drops whole letters from the render with no error at all. `lib/type.mjs`
sidesteps both by laying glyphs out directly and serializing path data itself.
Don't "simplify" it back to `font.getPath(...).toPathData()`; the first
version of this kit shipped a badge reading `TRACK EVER TRN F THE RAD`.
