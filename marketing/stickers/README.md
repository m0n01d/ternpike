# Ternpike sticker kit

Eight die-cut stickers for handing out — trailhead kiosks, campground boards,
gas-pump tops, the back of a laptop at a coffee shop with wifi. Every one
carries `ternpike.com`, so the sticker *is* the funnel.

![contact sheet](../../docs/screenshots/stickers-contact-sheet.png)

| Slug | Size | What it is |
|---|---|---|
| `badge-tern` | 3 × 3in | National-park badge. The flagship — arc-set type, tern, mile-0 line. |
| `wordmark-rust` | 3.2 × 1.1in | Rust bar wordmark with the tern soaring off the end. Bumper/laptop edge. |
| `milepost-zero` | 1.4 × 3in | Alaska Highway milepost. Every trip starts at mile zero. |
| `no-signal` | 2.6 × 1.2in | "No signal, no problem." The offline-first pitch. |
| `receipt` | 1.6 × 2.6in | Die-cut receipt with a torn edge — the product as an object. |
| `orlando-juneau` | 3.2 × 1.6in | The hero line, route plotted behind it. |
| `cabin-or-truck` | 2.8 × 1.5in | The joke sticker. The decision the app exists to inform. |
| `tern-mark` | 1.5 × 1.5in | Mark plus URL, nothing else. The one you order 500 of. |

## What's in here

```
svg/<slug>.svg      one sticker each — artwork only, no cut guides
png/<slug>.png      the same at 300 DPI, for portals that only take raster
sheets/print-sheet.svg    US Letter gang sheet, 13 stickers, dashed cut guides
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

## Relationship to the QR stickers

Separate system, on purpose. `server/qrSvg.js` generates *scannable, tracked*
labels — `/qr/<slug>` counts every scan and redirects with `?ref=qr-<slug>`.
Those are 2 × 1in thermal-label stock and exist to measure.

These are swag. They're prettier, they're die-cut, and they carry a plain URL
with no attribution. Hand out both: a QR label on the thing you want to
measure, a vinyl sticker on the thing you want someone to keep.

## Regenerating

```sh
npm i --no-save opentype.js sharp
node marketing/stickers/build.mjs          # SVG + PNG + sheets
node marketing/stickers/build.mjs --no-png # vectors only, skips sharp
```

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
