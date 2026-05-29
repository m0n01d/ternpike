// Guardrail: the marketing pricing table must stay consistent with the real
// tier gates in the app. Each assertion is tied to the code that enforces (or
// doesn't enforce) the capability — see docs/tier-matrix.md. When a gate moves,
// update content.yaml + the matrix doc, then this test goes green again.
//
// Run: npm test   (from marketing/) — plain node:test, no browser, no server.

import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import yaml from 'js-yaml'

const here = dirname(fileURLToPath(import.meta.url))
const content = yaml.load(await readFile(join(here, '..', 'src', 'content.yaml'), 'utf8'))

const tierById = Object.fromEntries(content.pricing.tiers.map((t) => [t.id, t]))
const tern = tierById.fledgling
const osprey = tierById.fly
const trailblazer = tierById.trailblazer

// Join a tier's feature bullets into one lowercased haystack for substring checks.
const blob = (tier) => tier.features.join(' \n ').toLowerCase()

test('all three tiers are present and named correctly', () => {
  assert.equal(tern?.name, 'Tern')
  assert.equal(osprey?.name, 'Osprey')
  assert.equal(trailblazer?.name, 'Trailblazer')
})

test('Tern: no per-month scan quota — scanning is BYO-key, not metered', () => {
  // Data.OcrPath.resolve: Tern is ByoPath (with a key) or Unscannable (without).
  // There is no N-scans/month counter anywhere in the app.
  assert.doesNotMatch(blob(tern), /scans?\s*\/\s*month|per month|\d+\s+scans/)
})

test('Tern: must not claim unlimited trips — free is capped at 3', () => {
  // Pages.Trips.atTripLimit: not isPaid && trips >= 3.
  assert.doesNotMatch(blob(tern), /unlimited trips/)
  assert.match(blob(tern), /3 trips/)
})

test('Tern: must not claim full receipt details are gated away', () => {
  // No field-level gate exists; merchant/date/notes are available on any tier.
  assert.doesNotMatch(blob(tern), /amount and category only|category only/)
})

test('Tern includes the capabilities that are genuinely ungated', () => {
  // Cross-device sync: Main.startSync fires for every authed user.
  // Stats dashboard: Pages.Stats / UI.Layout have no tier gate.
  assert.match(blob(tern), /sync/)
  assert.match(blob(tern), /stats/)
})

test('Osprey must not advertise sync or stats as paid-exclusive', () => {
  // Both are available to Tern; listing them under Osprey overstates the gate.
  // "Everything in Tern" already implies they carry up.
  assert.doesNotMatch(blob(osprey), /cross-device sync/)
  assert.doesNotMatch(blob(osprey), /stats dashboard/)
})

test('Osprey advertises the actually-paid capabilities', () => {
  const b = blob(osprey)
  assert.match(b, /everything in tern/) //                      additive stacking
  assert.match(b, /unlimited trips/) //                         Pages.Trips.atTripLimit
  assert.match(b, /no api key needed|hosted/) //                OcrPath.HostedPath
  assert.match(b, /batch/) //                                   Trip.canBatchScan
  assert.match(b, /gps/) //                                     Main.geocodeDispatch
  assert.match(b, /shared ledger|nest/) //                      SharedTrips / TripFormModal
  assert.match(b, /csv/) //                                     Ledger.viewActions requiresPaid
})

test('Trailblazer is the additive, permanent tier', () => {
  const b = blob(trailblazer)
  assert.match(b, /everything in osprey/)
  assert.match(b, /no recurring|one time|forever|ever/)
})
