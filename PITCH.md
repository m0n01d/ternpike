# Alaska Tracker — Product Pitch

## What It Is

Alaska Tracker is a mobile-first progressive web app for road trip expense tracking. You snap a photo of a receipt, AI reads it, and your expense is logged — with GPS coordinates, a category, a short note, and a detailed description — all stored in a Google Sheet you own. No subscription, no vendor lock-in, no data handed to a third party.

The app was built for a specific trip up the Alaska Highway and is designed for the realities of remote travel: intermittent connectivity, bulk receipt scanning at the end of a long driving day, and the need to see a live spending picture while you're still on the road.

---

## Core Value Proposition

**For the traveler:** "Scan your receipts at camp, know exactly where your budget stands before you pull out tomorrow morning."

**For the privacy-conscious user:** Your data lives in your own Google Sheet. You can download it, query it, or delete it anytime. The app is a UI layer, not a data silo.

**For the gear-head:** Open source, runs offline-capable as a PWA, no account creation required beyond a Google login.

---

## Feature Set

### AI Receipt Scanning
- Photograph one or multiple receipts at once; the queue processes in parallel
- Claude (Anthropic) reads each receipt and extracts: **amount, merchant, date, category, short note (50 chars), and a detailed long note (280 chars)** covering what was purchased, where, and any relevant context
- Scanned image stays visible on the form screen so you can cross-check fields without switching tabs
- Results are editable before submission — AI is a starting point, not the final word
- Works without an API key: photos queue and you fill fields manually

### GPS Location Logging
- **Three sources:** EXIF GPS from the receipt photo itself, browser geolocation, or a manual map pin
- Custom interactive map picker centered on Alaska by default; drag to set coordinates anywhere
- Every expense with coordinates is plotted on a **waypoint map** in the ledger — your spending trail across the trip rendered visually
- Location is optional and skippable per entry

### Ledger
- Expenses grouped by date with daily subtotals
- Per-entry display: category icon, merchant, short note, long note (2-line preview), amount, GPS indicator
- Inline edit and delete
- Toggle a full-route waypoint map at the top of the ledger
- Manual refresh to sync with the sheet

### Stats Dashboard
Ten live metrics calculated from your entries:
- Total spent, number of entries, days on road
- Average per day, average per entry, median entry
- Top spending category, biggest single day
- Days into trip, projected 30-day spend

Three charts:
- **By Category** — color-coded bar chart across all 11 categories
- **Daily Spending** — bar chart by calendar date
- **Cumulative Spend** — line chart showing total growth over time

Top 5 largest purchases ranked with category, note, date, and amount.

### 11 Expense Categories
Fuel ⛽ · Food 🍔 · Camp ⛺ · Ferry ⛴ · Gear 🔧 · Lodging 🏨 · Activities 🎯 · Shopping 🛍 · Medical 💊 · Transport 🚌 · Misc 📦

Broad enough to cover a multi-month road trip; specific enough to produce meaningful category breakdowns.

### Data Ownership via Google Sheets
- One Google Sheet is the entire database (columns A–J: id, date, amount, category, note, merchant, createdAt, lat, lon, longNote)
- Read and write via Google Sheets REST API using the user's own OAuth token
- User can open the sheet directly, filter, export to CSV, run their own formulas, or connect it to other tools (Looker Studio, Notion, etc.)
- No server, no database, no monthly hosting bill

### Auth & Session Management
- Google OAuth sign-in — no password, no account creation
- Session expires gracefully: 401 from any API call signs you out and shows a clear "Session expired" message rather than silently failing
- Settings (Sheet ID, Client ID, API key, trip start date) persist in local storage and survive sign-out

---

## Technical Snapshot

| Layer | Choice |
|---|---|
| Language | Elm 0.19.1 — no runtime exceptions |
| UI | Single-file SPA, Tailwind CSS via CDN |
| Backend | Google Sheets REST API (user-owned) |
| AI | Anthropic Claude (receipt OCR) |
| Maps | Custom web components (`waypoint-map`, `map-picker`) |
| Auth | Google OAuth 2.0 |
| Hosting | GitHub Pages (zero cost) |
| Storage | Browser local storage (config), Google Sheets (data) |

**PWA:** Installable on iOS and Android home screen, works offline for viewing cached data.

---

## Who It's For

**Primary:** Road trippers, overlanders, van-lifers, RV travelers — anyone spending across many categories over days or weeks away from home.

**Secondary:** Budget backpackers, international travelers, anyone who hates manually entering receipts and wants AI to do the tedious part.

**Technical affinity:** The current setup (bring your own Google Sheet and API keys) suits technically comfortable users. A hosted/managed version would open it to a broader audience.

---

## Monetization Angles

### Near-term (low friction)
1. **Managed hosting with onboarding** — remove the "bring your own Sheet ID and Client ID" setup friction. User signs in with Google, app provisions their Sheet automatically. Charge $3–5/month or a one-time fee.
2. **Trip report export** — one-tap PDF or shareable web summary of the trip: total spend, category breakdown, map of the route, top moments. Charge per export or as a premium feature.
3. **AI budget coaching** — after the trip, Claude analyzes spending patterns and generates a personalized debrief ("you spent 34% on fuel, here's how that compares to similar routes"). Upsell on top of base product.

### Medium-term
4. **Team/shared trips** — couples and groups traveling together both logging to the same sheet. Multi-user auth layer + conflict resolution.
5. **White-label for travel brands** — tour operators, overlanding clubs, van-life communities could offer branded versions to their audience.
6. **Integration marketplace** — YNAB sync, Splitwise, travel booking platforms (pull in flight/hotel costs automatically).

### Long-term
7. **Aggregated travel spending insights** — opt-in anonymized data → "what does the average Alaska Highway trip cost?" — valuable to tourism boards, gear brands, travel media.
8. **Affiliate partnerships** — campground bookings, gear recommendations, fuel price data surfaced contextually while the user is logging expenses.

---

## Competitive Landscape

| App | Strength | Gap vs. Alaska Tracker |
|---|---|---|
| Trail Wallet | Simple, mobile | No AI scanning, no maps, no Sheets export |
| TravelSpend | Travel-focused | No receipt scanning, subscription-only |
| Splitwise | Group expenses | Not designed for solo logging, no receipt OCR |
| Expensify | Enterprise receipt scanning | Overkill for personal travel, expensive, data silo |
| Google Sheets (manual) | Free, flexible | No UI, no scanning, no stats |

Alaska Tracker's differentiation: **AI scanning + GPS logging + user-owned data + zero subscription cost** — no other app in the travel budget category combines all four.

---

## Current Status

- Fully functional PWA deployed on GitHub Pages
- Used in production on an Alaska road trip
- Single-file Elm codebase (~3,000 lines), clean architecture, compiler-enforced correctness
- Ready for UX polish, onboarding flow, and productization

---

## What We Need

1. **Brand identity** — name, logo, App Store presence (currently "Alaska Tracker" but can be generalized to any road trip)
2. **Landing page** — explain the value prop, show the scan-to-entry demo, drive sign-ups
3. **Managed backend** — auto-provision Google Sheets, remove technical setup barrier
4. **Distribution** — travel communities (Reddit r/overlanding, r/vandwellers, iOverlander), gear brand partnerships, outdoor media coverage
