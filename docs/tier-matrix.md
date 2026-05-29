# Tier capability matrix — source of truth

This file is the **canonical map of what each tier actually unlocks**, derived
from the gating code (not from prose). The marketing pricing table
(`marketing/src/content.yaml` → `pricing.tiers`), the Terms "Tiers and billing"
section, and any in-app upgrade copy must agree with this table.

**Keep it current.** When you add, move, or remove a tier gate, update this
table AND `marketing/src/content.yaml` in the **same commit**. The guardrail
test `marketing/test/pricing.matrix.spec.mjs` pins the pricing copy against this
matrix and fails CI on drift. See the "Subscription tiers" section of
`CLAUDE.md`.

The authority is the code column. If a row here disagrees with the linked gate,
the code wins — fix the row (and the marketing copy), not the other way around.

## Matrix

| Capability | Tern (free) | Osprey | Trailblazer | Gate in code |
|---|:--:|:--:|:--:|---|
| Offline expense log | ✅ | ✅ | ✅ | ungated (PouchDB local-first, all tiers) |
| Manual entry — every field | ✅ | ✅ | ✅ | no field-level gate anywhere |
| Cross-device sync | ✅ | ✅ | ✅ | `Main.startSync` fires at login for every authed user |
| Stats dashboard | ✅ | ✅ | ✅ | `Pages.Stats` has no gate; `UI.Layout` shows the tab to all |
| Trip count | **≤ 3** | unlimited | unlimited | `Pages.Trips.atTripLimit` (`not isPaid && trips >= 3`) |
| BYO-key receipt scanning | ✅ | ✅ | ✅ | `Data.OcrPath.resolve` → `ByoPath` on any tier |
| Hosted scanning (no key needed) | ❌ | ✅ | ✅ | `Data.OcrPath.resolve` → `HostedPath` only when `isPaid` |
| Batch scanning | ❌ | ✅ | ✅ | `Data.Trip.canBatchScan` (`Tier.isPaid`) |
| GPS auto-location (geocoding) | ❌ | ✅ | ✅ | `Main.geocodeDispatch` (`Tier.isPaid`) |
| Nest — shared ledger | ❌ | ✅ | ✅ | `Pages.Settings.SharedTrips`, `UI.TripFormModal` (`Tier.isPaid`) |
| Push notifications | ❌ | ✅ | ✅ | `Data.Notifications.panelState` (`isPaid`) |
| CSV export | ❌ | ✅ | ✅ | `Pages.Ledger.viewActions` (`UI.Gate.requiresPaid`) |
| No recurring charge / permanent | — | ❌ | ✅ | billing mechanics — `Data.Tier` + server `UserRecord` |
| All 1.x updates + v2 loyalty discount | — | — | ✅ | product promise (Terms) |

Notes:

- **BYO keys are available on every tier** — paid is purely additive. A Tern
  user with their own Anthropic/OpenAI/Gemini key scans unlimited (browser →
  provider direct); a Tern user *without* a key cannot scan at all
  (`OcrPath.Unscannable`). There is **no "N scans / month" quota** anywhere in
  the app — the only rate limit is the marketing-site guest demo
  (`server/scanDemo.js`), which is not a tier.
- **"Full receipt details" is not a paid gate.** Merchant / date / notes come
  back from OCR on any tier and are editable by anyone. Only the **GPS
  auto-location** step (geocoding the receipt address) is paid-gated.
- Osprey and Trailblazer are **feature-equivalent**; the difference is billing
  mechanics (subscription vs one-time) and the permanent flag. Never write code
  that downgrades a Trailblazer.
