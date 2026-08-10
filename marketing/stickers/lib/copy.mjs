// Sticker copy, read from the marketing site's own content file.
//
// Not retyped. `marketing/src/content.yaml` is the source of truth for
// every word on ternpike.com, and a sticker quoting a line the site no
// longer says is worse than a sticker with no line at all — vinyl and
// thermal stock both outlive a copy edit.
//
// So every string here is pulled by path, and every shortened version is
// checked against the original. Rewrite `hero.headline` and this build
// FAILS rather than quietly shipping last season's headline. That's the
// same bargain `marketing/test/pricing.matrix.spec.mjs` makes for the
// pricing bullets.
//
// The one thing not sourced from here is "MILE 0" on the milepost sticker:
// that's a visual device (a highway marker needs a number), not a claim
// about the product.

import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { load } from 'js-yaml'

const here = dirname(dirname(fileURLToPath(import.meta.url)))
const contentPath = join(here, '..', 'src', 'content.yaml')

const content = load(await readFile(contentPath, 'utf8'))

/** Resolve a dotted path, insisting it exists and is a string. */
function at(path) {
  let node = content
  for (const key of path.split('.')) {
    node = node?.[Array.isArray(node) ? Number(key) : key]
  }
  if (typeof node !== 'string') {
    throw new Error(`content.yaml: ${path} is missing or not a string`)
  }
  return node
}

/** Collapse the site's `<br>`s and wrapped newlines into one clean line. */
const flatten = (s) =>
  s
    .replace(/<br\s*\/?>/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim()

/** A whole line, verbatim. */
export const line = (path) => flatten(at(path))

/**
 * A shorter line lifted out of a longer one.
 *
 * Throws unless `text` still appears in the source, so a reworded sentence
 * breaks the build instead of leaving a stale sticker in the repo. Matching
 * ignores case because sticker copy gets sentence- or title-cased.
 */
export function fragment(path, text) {
  if (!flatten(at(path)).toLowerCase().includes(text.toLowerCase())) {
    throw new Error(
      `content.yaml: ${path} no longer contains ${JSON.stringify(text)} — sticker copy is stale`,
    )
  }
  return text
}

/**
 * One line broken across several, for setting in a narrow column.
 *
 * The parts must rejoin into exactly the source line, which is what stops
 * a "line break" from quietly becoming a rewrite.
 */
export function split(path, parts) {
  const source = flatten(at(path))
  const rejoined = parts.join(' ')
  if (rejoined !== source) {
    throw new Error(
      `content.yaml: ${path} is ${JSON.stringify(source)} but the sticker sets ${JSON.stringify(rejoined)}`,
    )
  }
  return parts
}

/** Break an already-verified string across display lines. */
export function wrap(source, parts) {
  if (parts.join(' ') !== source) {
    throw new Error(
      `sticker copy: ${JSON.stringify(source)} does not rejoin from ${JSON.stringify(parts)}`,
    )
  }
  return parts
}

/** Break where the site breaks — on its own `<br>`. */
export const brLines = (path) =>
  at(path)
    .split(/<br\s*\/?>/i)
    .map((part) => part.replace(/\s+/g, ' ').trim())

const dropPeriod = (s) => s.replace(/\.$/, '')

export const COPY = {
  brand: line('brand.name'),

  /** "Track every turn of the road." */
  tagline: line('brand.tagline'),
  taglineCaps: dropPeriod(line('brand.tagline')).toUpperCase(),

  /** The tagline over two lines, for a narrow sticker. */
  taglineLines: wrap(line('brand.tagline'), ['Track every turn', 'of the road.']),

  /** "Every dollar, from Orlando to Juneau." — set as three lines. */
  heroLines: split('hero.headline', ['Every dollar,', 'from Orlando', 'to Juneau.']),

  /** From the footer's "© 2026 Ternpike. Made on the Alaska Highway." */
  madeOnCaps: fragment('footer.legal', 'Made on the Alaska Highway').toUpperCase(),
  alaskaHighwayCaps: fragment('footer.legal', 'Alaska Highway').toUpperCase(),

  /** The offline feature, by its own name on the site. */
  offline: line('features.items.0.title'),
  offlineCaps: line('features.items.0.title').toUpperCase(),
  offlineLines: split('features.items.0.title', ['Works without', 'signal']),

  /** "Stop doing math in your head." — broken where the site breaks it. */
  mathLines: brLines('emailCapture.headlineHtml'),

  /** The first question the origin story opens with. */
  spentLines: wrap(fragment('origin.paragraphs.0', 'How much have I spent?'), [
    'How much have',
    'I spent?',
  ]),

  /** Lifted from step three: "…splurge on a cabin or sleep in the truck." */
  cabin: fragment('howItWorks.steps.2.body', 'splurge on a cabin'),
  truck: fragment('howItWorks.steps.2.body', 'or sleep in the truck'),
}
